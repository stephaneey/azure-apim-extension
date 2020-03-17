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
    $apimVersion = Get-VstsInput -Name MicrosoftApiManagementAPIVersion

    $Endpoint = Get-VstsEndpoint -Name $subscription -Require

    $apiVersionIdentifier = "$($targetAPI)$($targetAPIVersion)" -replace '\.', '-'

    $client = $Endpoint.Auth.Parameters.ServicePrincipalId
    $secret = [System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
    $tenant = $Endpoint.Auth.Parameters.TenantId		
    $body = "resource=https%3A%2F%2Fmanagement.azure.com%2F" +
    "&client_id=$($client)" +
    "&grant_type=client_credentials" +
    "&client_secret=$($secret)"

    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri "$($cloudEnv)/$($tenant)/oauth2/token" `
            -Method POST `
            -Body $body | ConvertFrom-Json    

        $headers = @{ Authorization = "Bearer $($resp.access_token)" }		
    } catch [System.Net.WebException] {
        $er = $_.ErrorDetails.Message.ToString() | ConvertFrom-Json
        write-host $er.error.details
        throw
    }	

    $baseurl = "$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($resourceGroupName)/providers/Microsoft.ApiManagement/service/$($apiPortalName)"
    $targeturl = "$($baseurl)/apis/$($apiVersionIdentifier)?api-version=$($apimVersion)"	

    try {			
        Write-Host "Checking if exists: $($targeturl)"
        Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers | ConvertFrom-Json
        Write-Host "API exists"        
    } catch [System.Net.WebException] {
        Write-Host "API not found"
        throw
    }

    if ($revisionSelectPolicy -eq "Newest") {
        Write-Host "Getting list of revisions"

        $revisionList = Invoke-WebRequest -UseBasicParsing -Uri "$($baseurl)/apis/$($apiVersionIdentifier)/revisions?api-version=$($apimVersion)" -Headers $headers | ConvertFrom-Json
        $revisionList = $revisionList.value | Sort-Object -Property "updatedDateTime" -Descending

        if ($revisionList[-1].isCurrent) {
            Write-Host "Newest revision is current revision."
            return;
        }

        $revision = $revisionList[-1].apiRevision
        Write-Host "Newest revision: $($revision)";
    }

    Write-Host "Setting revision $($revision) to current";

    $releaseId = [guid]::NewGuid()
    $currentRevReleaseBody = '{"properties":{"apiId":"/apis/' + $($apiVersionIdentifier) + ';rev=' + $($revision) + '","notes":"' + $revisionReleaseNotes + '"}}'
    $currentRevisionUrl = "$($baseurl)/apis/$($apiVersionIdentifier);rev=$($revision)/releases/$($releaseId)?api-version=$($apimVersion)"

    Write-Host $currentRevisionUrl
    Write-Host $currentRevReleaseBody

    resp = Invoke-WebRequest -ContentType "application/json" `
        -UseBasicParsing -Uri $currentRevisionUrl `
        -Headers $headers `
        -Method Put `
        -Body $currentRevReleaseBody

    Write-Host resp    

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}