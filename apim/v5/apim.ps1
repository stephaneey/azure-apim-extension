[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
try {
<#  
Warning: this code is provided as-is with no warranty of any kind. I do this during my free time.
This task creates a Gateway API against a backend API using the backend's swagger definition. 
Prerequisite to using this task: the API Gateway requires connectivity to the backend, so make sure these are either public, either part of a
shared VNET
#>	
	#getting inputs
	    $arm=Get-VstsInput -Name ConnectedServiceNameARM
		$Endpoint = Get-VstsEndpoint -Name $arm -Require	
		$newapi=Get-VstsInput -Name targetapi
		$DisplayName=Get-VstsInput -Name DisplayName
		if([string]::IsNullOrEmpty($DisplayName))
				{
					$DisplayName=$newapi
				}
		$portal=Get-VstsInput -Name ApiPortalName
		$rg=Get-VstsInput -Name ResourceGroupName 
		$SwaggerPicker = Get-VstsInput -Name SwaggerPicker 
		$swaggerlocation=Get-VstsInput -Name swaggerlocation
		$swaggercode=Get-VstsInput -Name swaggercode		
		$swaggerartifact=Get-VstsInput -Name swaggerartifact
		$products = $(Get-VstsInput -Name product1).Split([Environment]::NewLine)
		$UseProductCreatedByPreviousTask=Get-VstsInput -Name UseProductCreatedByPreviousTask
		$SelectedTemplate=Get-VstsInput -Name TemplateSelector
		$path = Get-VstsInput -Name pathapi
		$MicrosoftApiManagementAPIVersion = Get-VstsInput -Name MicrosoftApiManagementAPIVersion
		$Authorization = Get-VstsInput -Name Authorization
		$oid = Get-VstsInput -Name oid
		$oauth = Get-VstsInput -Name oauth
		$AuthorizationBits='"authenticationSettings":null'
		$subscriptionRequired=Get-VstsInput -Name subscriptionRequired
		$OpenAPISpec=Get-VstsInput -Name OpenAPISpec
		$Format=Get-VstsInput -Name Format
		Add-Type -AssemblyName System.Web
		switch($Authorization)
		{
			'OAuth' {$AuthorizationBits='"authenticationSettings":{"oAuth2":{"authorizationServerId":"'+$oauth+'","scope":null}}'}
			'OpenID' {$AuthorizationBits='"authenticationSettings":{"openid":{"openidProviderId":"'+$oid+'"}}'}
			
		}
		
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
		

	#preparing endpoints	
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
		$json = ""
		switch($SwaggerPicker)
			{
				"Url" {
					if($OpenAPISpec -eq "v2")
					{
						$json = '{
"name": "'+$($newapi)+'",
"id": "/apis/'+$($newapi)+'",
							"properties": {
							"contentFormat": "swagger-link-json",
							"contentValue": "'+$($SwaggerLocation)+'",
							"displayName": "'+$($DisplayName)+'",
							"path": "'+$($path)+'",
							"protocols":["https"],
							"subscriptionRequired":"'+$($subscriptionRequired)+'"
						}
						}'
					}
					else {
						$json = '{
"name": "'+$($newapi)+'",
"id": "/apis/'+$($newapi)+'",
							"properties": {
"displayName": "'+$($DisplayName)+'",
							"contentFormat": "openapi-link",
							"contentValue": "'+$($SwaggerLocation)+'",							
							"path": "'+$($path)+'",
							"protocols":["https"],
							"subscriptionRequired":"'+$($subscriptionRequired)+'"
						}
						}'
					}					
				}
				"Artifact" {
					try {
						 Assert-VstsPath -LiteralPath $swaggerartifact -PathType Leaf
						 
						 $swaggercode = Get-Content "$($swaggerartifact)" -Raw
						 
						 if($OpenAPISpec -eq "v2")
						 {							 
							$json = '{
"name": "'+$($newapi)+'",
"id": "/apis/'+$($newapi)+'",
								"properties": {
								"contentFormat": "swagger-json",
								"contentValue": "'+$($swaggercode).Replace('"','\"')+'",
								"displayName": "'+$($DisplayName)+'",
								"path": "'+$($path)+'",
								"protocols":["https"],
								"subscriptionRequired":"'+$($subscriptionRequired)+'"
							}
							}'
						 } else{
							$swaggercode=$swaggercode.Replace("`r`n","`n")
							$swaggercode =[System.Web.HttpUtility]::JavaScriptStringEncode($swaggercode)
							 if($Format -eq 'json')
							 {
								 $contentFormat="openapi+json"
							 }else{
								$contentFormat="openapi"
							 }								 
							 $json = '{
"name": "'+$($newapi)+'",
"id": "/apis/'+$($newapi)+'",
								"properties": {
								"contentFormat": "'+$($contentFormat)+'",
								"contentValue": "'+$($swaggercode)+'",
								"displayName": "'+$($DisplayName)+'",
								"path": "'+$($path)+'",
								"protocols":["https"],
								"subscriptionRequired":"'+$($subscriptionRequired)+'"
							}
							}'
						 }
						 
 						
					} catch {
  						Write-Error "Invalid file location $($swaggerartifact)"
					}
				}
				"Code" {		
					if($OpenAPISpec -eq "v2")
					{
						$json = '{
"name": "'+$($newapi)+'",
"id": "/apis/'+$($newapi)+'",
							"properties": {
							"contentFormat": "swagger-json",
							"contentValue": "'+$($swaggercode).Replace('"','\"')+'",
							"displayName": "'+$($DisplayName)+'",
							"path": "'+$($path)+'",
							"subscriptionRequired":"'+$($subscriptionRequired)+'"
						 }
						}'
					}	
					else {						
						$swaggercode=$swaggercode.Replace("`r`n","`n")
						$swaggercode =[System.Web.HttpUtility]::JavaScriptStringEncode($swaggercode)
						if($Format -eq 'json')
							 {
								$contentFormat="openapi+json"
							 }else{
								$contentFormat="openapi"
							 }								 
							 $json = '{
"name": "'+$($newapi)+'",
"id": "/apis/'+$($newapi)+'",
								"properties": {
"displayName": "'+$($DisplayName)+'",
								"contentFormat": "'+$($contentFormat)+'",
								"contentValue": "'+$($swaggercode)+'",								
								"path": "'+$($path)+'",
								"protocols":["https"],
								"subscriptionRequired":"'+$($subscriptionRequired)+'"
							}
							}'
					}		
					
				}
				default {Write-Error "Invalid swagger definition"}
			}		
		
		
		write-host $json
		$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)"
		$targeturl="$($baseurl)/apis/$($newapi)?api-version=$($MicrosoftApiManagementAPIVersion)"	
		Write-Host "Creating or updating API $($targeturl)"
		try
		{
			Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers -Body $json -Method Put -ContentType "application/json"
			$json = '{
"id": "/apis/'+$($newapi)+'",
"name": "'+$($newapi)+'",
				"properties": {		
"displayName": "'+$($DisplayName)+'",
				"protocols":["https"],						
				"path": "'+$($path)+'",'+$AuthorizationBits+'
			 }
			}'
			Write-Host "Updating with authorization information"
			Write-Host $json
			Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers -Body $json -Method Patch -ContentType "application/json"
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