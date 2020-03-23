[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation

try {     
    <#  
    Warning: this code is provided as-is with no warranty of any kind. I do this during my free time.
    This task creates a versioned Gateway API against a backend API using the backend's swagger definition. 
    Prerequisite to using this task: the API Gateway requires connectivity to the backend, so make sure these are either public, either part of a
    shared VNET
    #>	

    $subscription = Get-VstsInput -Name ConnectedServiceNameARM
    $cloudEnv = Get-VstsInput -Name CloudEnvironment
    $resourceGroupName = Get-VstsInput -Name ResourceGroupName
    $apiPortalName = Get-VstsInput -Name ApiPortalName
    $targetAPI = Get-VstsInput -Name TargetAPI
    $targetAPIVersion = Get-VstsInput -Name TargetAPIVersion
    $revisionSelectPolicy = Get-VstsInput -Name RevisionSelectPolicy
    $revision = Get-VstsInput -Name Revision    
    $revisionReleaseNotes = Get-VstsInput -Name RevisionReleaseNotes    
    $oldRevisionPolicy = Get-VstsInput -Name OldRevisionPolicy
    $apimVersion = Get-VstsInput -Name MicrosoftApiManagementAPIVersion

    $Endpoint = Get-VstsEndpoint -Name $subscription -Require

    # Output variables for Debug purposes
    Write-Host "-----------Variables-----------"
    Write-Host "API Management Resource group: $($resourceGroupName)"
    Write-Host "API Management instance: $($apiPortalName)"
    Write-Host "API Management version: $($apimVersion)"
    Write-Host "API Name: $($targetAPI)"
    if ($null -ne $targetAPIVersion) {
        Write-Host "API Version: $($targetAPIVersion)"
    } else {
        Write-Host "API Version: N/A"
    }
    Write-Host "Revision select policy: $($revisionSelectPolicy)"
    Write-Host "Specified revision: $($revision)"
    Write-Host "Revision release notes: $($revisionReleaseNotes)"
    Write-Host "What to do with old revisions?: $($oldRevisionPolicy)"

    Write-Host "-----------Preparations-----------"

    $apiVersionIdentifier = "$($targetAPI)$($targetAPIVersion)" -replace '\.', '-'

    $client = $Endpoint.Auth.Parameters.ServicePrincipalId
    $secret = [System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
    $tenant = $Endpoint.Auth.Parameters.TenantId		
    $body = "resource=https%3A%2F%2Fmanagement.azure.com%2F" +
    "&client_id=$($client)" +
    "&grant_type=client_credentials" +
    "&client_secret=$($secret)"

    try {
        Write-Host "Authenticating"
        $resp = Invoke-WebRequest -UseBasicParsing -Uri "$($cloudEnv)/$($tenant)/oauth2/token" -Method POST -Body $body | ConvertFrom-Json
        $headers = @{ Authorization = "Bearer $($resp.access_token)" }
        Write-Host "Auth success"
    } catch [System.Net.WebException] {
        $er = $_.ErrorDetails.Message.ToString() | ConvertFrom-Json
        write-host $er.error.details
        throw
    }	

    $baseurl = "$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($resourceGroupName)/providers/Microsoft.ApiManagement/service/$($apiPortalName)"
    $targeturl = "$($baseurl)/apis/$($apiVersionIdentifier)?api-version=$($apimVersion)"	

    try {			
        Write-Host "Checking if exists: $($targeturl)"
        $resp = Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers | ConvertFrom-Json
        Write-Host "API exists"
    } catch [System.Net.WebException] {
        Write-Host "API not found"
        throw
    }

    $isNewestCurrent = $false
    if ($revisionSelectPolicy -eq "Newest") {        
        Write-Host "-----------Resolving newest revision-----------"

        $revisionList = Invoke-WebRequest -UseBasicParsing -Uri "$($baseurl)/apis/$($apiVersionIdentifier)/revisions?api-version=$($apimVersion)" -Headers $headers | ConvertFrom-Json;
        $revisionList = $revisionList.value | Sort-Object -Property "createdDateTime" -Descending        

        Write-Host "Current revisions:";
        $revisionList | Format-Table apiRevision, createdDateTime, isOnline, isCurrent;

        if ($revisionList[0].isCurrent) {
            Write-Host "Newest revision is current revision. Revision: $($revisionList[0].apiRevision)"
            $isNewestCurrent = $true
        } else {
            $revision = $revisionList[0].apiRevision
            Write-Host "Newest revision: $($revision)";    
        }
    }

    if ($isNewestCurrent -eq $false) {    
        Write-Host "-----------Setting current revision to $($revision)-----------"

        $releaseId = [guid]::NewGuid()
        $currentRevReleaseBody = '{"properties":{"apiId":"/apis/' + $($apiVersionIdentifier) + ';rev=' + $($revision) + '","notes":"' + $revisionReleaseNotes + '"}}'
        $currentRevisionUrl = "$($baseurl)/apis/$($apiVersionIdentifier);rev=$($revision)/releases/$($releaseId)?api-version=$($apimVersion)"
    
        Write-Host "Url: $($currentRevisionUrl)";
        Write-Host "Body: $($currentRevReleaseBody)";
    
        $resp = Invoke-WebRequest -ContentType "application/json" -UseBasicParsing -Uri $currentRevisionUrl -Headers $headers -Method Put -Body $currentRevReleaseBody;

        $resp | Format-List;

        Write-Host "----------Current Revision set to $($revision)----------" -ForegroundColor Green
    }

    if ($oldRevisionPolicy -ne "Nothing") {
        Write-Host "-----------Old Revisions-----------"
        Write-Host "Getting list of revisions"

        $revisionList = Invoke-WebRequest -UseBasicParsing -Uri "$($baseurl)/apis/$($apiVersionIdentifier)/revisions?api-version=$($apimVersion)" -Headers $headers | ConvertFrom-Json;
        $revisionList = $revisionList.value | Sort-Object -Property "createdDateTime" -Descending;

        $headers["If-match"] = "*"

        $revisionList | Where-Object { $_.isCurrent -eq $false } | ForEach-Object {     
            $revisionId = $_.apiRevision;
            if ($oldRevisionPolicy -eq "Offline") {
                if ($_.isOnline -eq $true) {
                    # 2020-03 newest version do not have this functionality yet
                    $resp = Invoke-WebRequest -UseBasicParsing -Uri "$($baseurl)/apis/$($apiVersionIdentifier);rev=$($revisionId)?api-version=2018-06-01-preview" -Method Patch -ContentType "application/json" -Headers $headers -Body '{"isOnline":false}';
                    Write-Host "Revision put offline: $($revisionId)"
                } else {
                    Write-Host "Revision is offline: $($revisionId)"
                }
            } elseif ($oldRevisionPolicy -eq "Delete") {
                $resp = Invoke-WebRequest -UseBasicParsing -Uri "$($baseurl)/apis/$($apiVersionIdentifier);rev=$($revisionId)?api-version=$($apimVersion)" -Method Delete -Headers $headers;
                Write-Host "Revision deleted: $($revisionId)"
            }
        }
        Write-Host "-----------Finished-----------"
    }
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}