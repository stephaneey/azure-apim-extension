[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
try {        
<#  
Warning: this code is provided as-is with no warranty of any kind. I do this during my free time.
This task creates an APIM product. 
#>			
	$arm=Get-VstsInput -Name ConnectedServiceNameARM		
	$Endpoint = Get-VstsEndpoint -Name $arm -Require			
	$portal=Get-VstsInput -Name ApiPortalName
	$rg=Get-VstsInput -Name ResourceGroupName
	$api=Get-VstsInput -Name ApiName
	$operation=Get-VstsInput -Name OperationName
	$SelectedTemplate=Get-VstsInput -Name TemplateSelector
	$CurrentRevision=Get-VstsInput -Name CurrentRevision
	
	if($SelectedTemplate -eq "Artifact")
	{
		$policyPath = Get-VstsInput -Name policyArtifact
		try {
			Assert-VstsPath -LiteralPath $policyPath -PathType Leaf
			$PolicyContent = Get-Content "$($policyPath)" -Raw
		} catch {
		Write-Error "Invalid file location $($policyPath)"
		  }
	}
	if($SelectedTemplate -eq "RateAndQuota")
	{
		$PolicyContent = Get-VstsInput -Name RateAndQuota
	}
	if($SelectedTemplate -eq "None")
	{
		$PolicyContent = Get-VstsInput -Name None
	}
	if($SelectedTemplate -eq "Basic")
	{
		$PolicyContent = Get-VstsInput -Name Basic
	}
	if($SelectedTemplate -eq "JWT")
	{
		$PolicyContent = Get-VstsInput -Name JWT
	}
	if($SelectedTemplate -eq "IP")
	{
		$PolicyContent = Get-VstsInput -Name IP
	}
	if($SelectedTemplate -eq "RateByKey")
	{
		$PolicyContent = Get-VstsInput -Name RateByKey
	}
	if($SelectedTemplate -eq "QuotaByKey")
	{
		$PolicyContent = Get-VstsInput -Name QuotaByKey
	}
	if($SelectedTemplate -eq "HeaderCheck")
	{
		$PolicyContent = Get-VstsInput -Name HeaderCheck
	}
	if($SelectedTemplate -eq "Custom")
	{
		$PolicyContent = Get-VstsInput -Name Custom
	}
	if($PolicyContent -ne $null -and $PolicyContent -ne "")
	{
		$PolicyContent = $PolicyContent.replace("`"","`\`"")
	}		
	$client=$Endpoint.Auth.Parameters.ServicePrincipalId
	$secret=[System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
	$tenant=$Endpoint.Auth.Parameters.TenantId
	$body="resource=https%3A%2F%2Fmanagement.azure.com%2F"+
	"&client_id=$($client)"+
	"&grant_type=client_credentials"+
	"&client_secret=$($secret)"
	try
	{
		$resp=Invoke-WebRequest -UseBasicParsing -Uri "https://login.windows.net/$($tenant)/oauth2/token" `
		-Method POST `
		-Body $body| ConvertFrom-Json    
	
	}
	catch [System.Net.WebException] 
	{
		$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
		write-host $er.error.details
		throw
	}

	$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)"
	
	$headers = @{
		Authorization = "Bearer $($resp.access_token)"        
	}

	if($PolicyContent -ne $null -and $PolicyContent -ne "")
	{		
		try
		{
			$RevisionUrl="$($baseurl)/apis/$($api)/revisions?api-version=2019-01-01"
			Write-Host "Revision Url is $($RevisionUrl)"
			$revisions=Invoke-WebRequest -UseBasicParsing -Uri $RevisionUrl -Headers $headers|ConvertFrom-Json
			if($CurrentRevision -eq $true)
			{
				
            	$revisions|% {
					$_.value|%{
						if($_.isCurrent -eq $true)
						{
							$rev=$_.apiRevision                             
						}
					}
				}
			}
			else {
				$rev=$revisions.count
			}
			Write-Host "Revision to patch is $($rev)"
			$policyapiurl=	"$($baseurl)/apis/$($api);rev=$($rev)/operations/$($operation)/policies/policy?api-version=2017-03-01"
			$JsonPolicies = "{
				`"properties`": {					
				`"policyContent`":`""+$PolicyContent+"`"
				}
			}"
			Write-Host "Linking policy to API USING $($policyapiurl)"
			Write-Host $JsonPolicies
			Invoke-WebRequest -UseBasicParsing -Uri $policyapiurl -Headers $headers -Method Put -Body $JsonPolicies -ContentType "application/json"
		}
		catch [System.Net.WebException] 
		{
			$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
			Write-Host $er.error.details
			throw
		}
	}

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}