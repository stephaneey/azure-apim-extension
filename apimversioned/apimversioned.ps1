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

	    $arm=Get-VstsInput -Name ConnectedServiceNameARM
		$Endpoint = Get-VstsEndpoint -Name $arm -Require	
		$newapi=Get-VstsInput -Name targetapi
		if($newapi.startswith("/subscriptions"))
		{
			$newapi=$newapi.substring($newapi.indexOf("/apis")+6)
		}
		$v=Get-VstsInput -Name version
		$portal=Get-VstsInput -Name ApiPortalName
		$rg=Get-VstsInput -Name ResourceGroupName 
		$swaggerlocation=Get-VstsInput -Name swaggerlocation
		$product=Get-VstsInput -Name product1 
		$UseProductCreatedByPreviousTask=Get-VstsInput -Name UseProductCreatedByPreviousTask
		$SelectedTemplate=Get-VstsInput -Name TemplateSelector
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
		if($PolicyContent -ne $null -and $PolicyContent -ne "")
		{
			$PolicyContent = $PolicyContent.replace("`"","`'")
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
		
		$headers = @{
			Authorization = "Bearer $($resp.access_token)"        
		}
		
		write-host $json
		$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)"
		$targeturl="$($baseurl)/apis/$($newapi)?api-version=2017-03-01"	
		#checking whether the API already exists or not. If not, a versionset must be created.
		#NotFound
		try
		{			
			Write-Host "checking whether $($targeturl) exists"
			$cur=Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers|ConvertFrom-Json
			$currentversion=$cur.properties.apiVersion
			$apiexists=$true
			Write-Host "found api"
		}
		catch [System.Net.WebException] 
		{
			if($_.Exception.Response.StatusCode -eq "NotFound")
            {
				$apiexists=$false
			}
            else
            {
			    throw
            }
		}
		
		try
		{
			#downloading swagger for later import
			$cli=[System.Net.WebClient]::new()
			$swagger=$cli.DownloadString($swaggerlocation)				
			$cli.Dispose()

			if($apiexists -eq $false)
			{
				Write-Host "Creating new API from scratch"
				#creating the api version set, the api and importing the swagger definition into it
				$version="$($newapi)versionset"
				$versionseturl="$($baseurl)/api-version-sets/$($version)?api-version=2017-03-01"
				$json='{"id":"/api-version-sets/'+$($version)+'","name":"'+$($newapi)+'","versioningScheme":"Segment"}'
				Write-Host "Creating version set using $($versionseturl) using $($json)"
				Invoke-WebRequest -UseBasicParsing -Uri $versionseturl  -Body $json -ContentType "application/json" -Headers $headers -Method Put
				$apiurl="$($baseurl)/apis/$($newapi)?api-version=2017-03-01"
				$json = '{
				  "id":"/apis/'+$($newapi)+'",
				  "name":"'+$($newapi)+'",
				  "properties":
				  { 
					"displayName":"'+$($newapi)+'",
					 "path":"'+$($newapi)+'",
					 "protocols":["https"],
					 "apiVersion":"v1",
					 "apiVersionSet":{
					   "id":"/api-version-sets/'+$($version)+'",
					   "name":"'+$($newapi)+'",
					   "versioningScheme":"Segment"
					  },
					  "apiVersionSetId":"/api-version-sets/'+$version+'"
				  }
				}'
				Write-Host "Creating API using $($apiurl) and $($json)"
				Invoke-WebRequest -UseBasicParsing -Uri $apiurl  -Body $json -ContentType "application/json" -Headers $headers -Method Put
				$headers.Add("If-Match","*")
				$importurl="$($baseurl)/apis/$($newapi)?import=true&api-version=2017-03-01"
				
				Write-Host "Importing Swagger definition to API using $($importurl)"
				Invoke-WebRequest -UseBasicParsing $importurl -Method Put -ContentType "application/vnd.swagger.doc+json" -Body $swagger -Headers $headers
			}
			else
			{
				#the api already exists, only a new version must be created.
				$newversionurl="$($baseurl)/apis/$($newapi)$($v);rev=1?api-version=2017-03-01"
				$headers = @{
				 Authorization = "Bearer $($resp.access_token)"        
				}				
				$json='{"sourceApiId":"/apis/'+$($newapi)+'","apiVersionName":"'+$($v)+'","apiVersionSet":{"versioningScheme":"Segment"}}'
				try
				{			
					Invoke-WebRequest -UseBasicParsing -Uri $newversionurl -Headers $headers
					$versionexists=$true
				}
				catch [System.Net.WebException] 
				{
					if($_.Exception.Response.StatusCode -eq "NotFound")
					{
						$versionexists=$false
					}
					else
					{
						throw
					}
				}
				Write-Host "current version $($currentversion), version is $($v), version exists $($versionexists)"
				if($currentversion -ne $v -and $versionexists -eq $false)
				{
					Write-Host "Creating a new version $($newversionurl) with $($json)"
					Invoke-WebRequest -UseBasicParsing $newversionurl -Method Put -ContentType "application/vnd.ms-azure-apim.revisioninfo+json" -Body $json -Headers $headers
					$importurl="$($baseurl)/apis/$($newapi)$($v)?import=true&api-version=2017-03-01"
				}		
				else
				{
					$importurl="$($baseurl)/apis/$($newapi)$($v)?import=true&api-version=2017-03-01"
				}
				$headers.Add("If-Match","*")		
				#reapplying swagger
				
				Write-Host "Importing swagger $($importurl)"
				Invoke-WebRequest -UseBasicParsing $importurl -Method Put -ContentType "application/vnd.swagger.doc+json" -Body $swagger -Headers $headers
			}
			
		}
		catch [System.Net.WebException] 
		{
			$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
			Write-Host $er.error.details
			throw
		}
		
		if($UseProductCreatedByPreviousTask -eq $true)
		{
			$product = $env:NewUpdatedProduct
			if($product -eq $null -or $product -eq "")
			{
				throw "There was no product created by a previous task"
			}
		}
		if($newversionurl -eq $null -or $newversionurl -eq "" -or ($currentversion -eq $v))
		{
			$apimv="$($newapi)"
		}
		else
		{
			$apimv="$($newapi)$($v)"
		}
		if($product -ne $null -and $product -ne "")
		{
			$productapiurl=	"$($baseurl)/products/$($product)/apis/$($apimv)?api-version=2017-03-01"
			
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
		if($PolicyContent -ne $null -and $PolicyContent -ne "")
		{
			try
			{
				$policyapiurl=	"$($baseurl)/apis/$($apimv)/policies/policy?api-version=2017-03-01"
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
