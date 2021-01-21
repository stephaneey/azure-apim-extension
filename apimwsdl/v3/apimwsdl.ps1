[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
try {
	Import-Module $PSScriptRoot\ps_modules\Share\functions.psm1

	$arm = Get-VstsInput -Name ConnectedServiceNameARM
	$Endpoint = Get-VstsEndpoint -Name $arm -Require
	$newapi= Get-Slug $(Get-VstsInput -Name targetapi)
	$description=Get-VstsInput -Name Description
	$path = Get-VstsInput -Name pathapi
	$soapApiType = Get-VstsInput -Name soapApiType
	$portal = Get-VstsInput -Name ApiPortalName
	$rg = Get-VstsInput -Name ResourceGroupName
	$MicrosoftApiManagementAPIVersion = Get-VstsInput -Name MicrosoftApiManagementAPIVersion
	$wsdllocation = Get-VstsInput -Name wsdllocation
	$wsdlServiceName = Get-VstsInput -Name wsdlServiceName
	$wsdlEndpointName = Get-VstsInput -Name wsdlEndpointName
	$products = $(Get-VstsInput -Name product1).Split([Environment]::NewLine)
	$UseProductCreatedByPreviousTask = Get-VstsInput -Name UseProductCreatedByPreviousTask
	$SelectedTemplate = Get-VstsInput -Name TemplateSelector

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
	if($SelectedTemplate -eq "CacheLookup")
	{
		$PolicyContent = Get-VstsInput -Name CacheLookup
	}
	if($SelectedTemplate -eq "CORS")
	{
		$PolicyContent = Get-VstsInput -Name CORS
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
		#getting ARM token
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

	$headers = @{
		Authorization = "Bearer $($resp.access_token)"
	}
	$json = '{
		"properties": {
			"contentFormat": "wsdl-link",
			"wsdlSelector" : {
				"wsdlEndpointName": "' + $($wsdlEndpointName) + '",
				"wsdlServiceName": "' + $($wsdlServiceName) + '"
			},
			"apiType": "'+$($soapApiType)+'",
			"contentValue": "'+$($wsdllocation)+'",
			"displayName": "'+$($newapi)+'",
			"description": "'+$description+'",
			"path": "'+$($path)+'",
			"protocols": ["https"]
		}
	}'

	write-host $json
	$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)"
	$targeturl="$($baseurl)/apis/$($newapi)?api-version=$($MicrosoftApiManagementAPIVersion)"
	Write-Host "Creating or updating API $($targeturl)"

	try
	{
		Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers -Body $json -Method Put -ContentType "application/json"
	}
	catch [System.Net.WebException]
	{
		$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
		Write-Host $er.error.details
		throw
	}

	if($UseProductCreatedByPreviousTask -eq $true)
	{
		if ($null -eq $env:NewUpdatedProduct)
		{
			throw "There was no product created by a previous task"
		}
		
		$products = $env:NewUpdatedProduct.Split(";")

		if ($products.Length -le 0)
		{
			$products = $env:NewUpdatedProduct
		}

		Write-Host "Number of products created by a previous task(s): $($products.Length)"
	}

	foreach ($product in $products)
	{
		if($product -ne $null -and $product -ne "")
		{
			$productapiurl=	"$($baseurl)/products/$($product)/apis/$($newapi)?api-version=$($MicrosoftApiManagementAPIVersion)"

			try
			{
				Write-Host "Linking API to product $($productapiurl)"
				Invoke-WebRequest -UseBasicParsing -Uri $productapiurl -Headers $headers -Method Put 
			}
			catch [System.Net.WebException] 
			{
				$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
				Write-Host $er.error.details
				throw
			}
		}
	}

	#Policy content should never be null or empty. The 'none' policy will always apply if nothing is specified.
	if($PolicyContent -ne $null -and $PolicyContent -ne "")
	{
		try
		{
			$policyapiurl=	"$($baseurl)/apis/$($newapi)/policies/policy?api-version=$($MicrosoftApiManagementAPIVersion)"
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

	Write-Host $rep

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}