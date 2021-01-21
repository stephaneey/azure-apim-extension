[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
try {        
<#  
Warning: this code is provided as-is with no warranty of any kind. I do this during my free time.
This task creates a Gateway API against an Azure Function set.
Prerequisite to using this task: VSTS agents must be able to connect to both the functions & APIM through ARM.
#>			
	    $arm=Get-VstsInput -Name ConnectedServiceNameARM
		$Endpoint = Get-VstsEndpoint -Name $arm -Require	
		$newapi=Get-VstsInput -Name targetapi	
		if($newapi -ne $null -and $newapi.indexOf("/apis/")-ne -1)
		{
			$newapi=$newapi.Substring($newapi.indexOf("/apis")+6)
		}
		$v=Get-VstsInput -Name version
		$portal=Get-VstsInput -Name ApiPortalName
		$rg=Get-VstsInput -Name APIResourceGroupName 
		$functiongroup=Get-VstsInput -Name ResourceGroupName 		
		$functionsite=Get-VstsInput -Name HostingWebSite
		$products = $(Get-VstsInput -Name product1).Split([Environment]::NewLine) 
		$path = Get-VstsInput -Name pathapi
		$UseProductCreatedByPreviousTask=Get-VstsInput -Name UseProductCreatedByPreviousTask

		$SelectedTemplate=Get-VstsInput -Name TemplateSelector
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
		
		$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)"
		$functionbaseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($functiongroup)/providers/Microsoft.Web/sites/$($functionsite)"
		$client=$Endpoint.Auth.Parameters.ServicePrincipalId
		$secret=[System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
		$tenant=$Endpoint.Auth.Parameters.TenantId		
		$body="resource=https%3A%2F%2Fmanagement.azure.com%2F"+
        "&client_id=$($client)"+
        "&grant_type=client_credentials"+
        "&client_secret=$($secret)"

		$bodyadmin="resource=https%3A%2F%2Fmanagement.core.windows.net%2F"+
        "&client_id=$($client)"+
        "&grant_type=client_credentials"+
        "&client_secret=$($secret)"
	    try
		{
			$resp=Invoke-WebRequest -UseBasicParsing -Uri "https://login.windows.net/$($tenant)/oauth2/token" `
				-Method POST `
				-Body $body| ConvertFrom-Json    
			$coremgt=Invoke-WebRequest -UseBasicParsing -Uri "https://login.windows.net/$($tenant)/oauth2/token" `
				-Method POST `
				-Body $bodyadmin| ConvertFrom-Json    

		
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
		$adminscmheaders = @{
		 Authorization = "Bearer $($coremgt.access_token)"        
		}
	    $adminresp=Invoke-WebRequest -UseBasicParsing -Uri "$($functionbaseurl)/functions/admin/token?api-version=2016-08-01" -Headers $headers
		$admintoken=$adminresp.Content|ConvertFrom-Json
		$adminheaders = @{
		 Authorization = "Bearer $($admintoken)"        
		}
		$json='{"swagger":{"enabled":true}}'
		Write-Host "Enabling Swagger for the target function set"
		Invoke-WebRequest -Body $json -UseBasicParsing "https://$($functionsite).scm.azurewebsites.net/api/functions/config" -Headers $adminscmheaders -Method Put -ContentType "application/json"
		#generating swagger key
		Write-Host "generating swagger key"
		$key=Invoke-WebRequest -UseBasicParsing -Uri "https://$($functionsite).azurewebsites.net/admin/host/systemkeys/swaggerdocumentationkey" -Method Post -Headers $adminheaders
		$keyjson=$key.Content|ConvertFrom-Json
		#noticed that calling the swagger definition too fast after getting a new key causes a 500 exception
		Start-Sleep -Seconds 2
		#non default swagger			
		
		
		write-host $json
		$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)"
		$targeturl="$($baseurl)/apis/$($newapi)?api-version=2017-03-01"	
		#checking whether the API already exists or not. If not, a versionset must be created.
		#NotFound
		try
		{			
			$cur=Invoke-WebRequest -UseBasicParsing -Uri $targeturl -Headers $headers|ConvertFrom-Json
			$currentversion=$cur.properties.apiVersion
			$apiexists=$true
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
			Write-Host "downloading swagger definition https://$($functionsite).azurewebsites.net/admin/host/swagger/default?code=$($keyjson.value)"
			$cli=[System.Net.WebClient]::new()
			$swagger=$cli.DownloadString("https://$($functionsite).azurewebsites.net/admin/host/swagger/default?code=$($keyjson.value)")				
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
					 "path":"'+$($path)+'",
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
				#the apis already exists, only a new version must be created.
				
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
				
				if($currentversion -ne $v -and $versionexists -eq $false)
				{
					Write-Host "Creating a new version $($newversionurl) with $($json)"
					Invoke-WebRequest -UseBasicParsing $newversionurl -Method Put -ContentType "application/vnd.ms-azure-apim.revisioninfo+json" -Body $json -Headers $headers					
					$importurl="$($baseurl)/apis/$($newapi)$($v)?import=true&api-version=2017-03-01"					
				}				
				else
				{
					$importurl="$($baseurl)/apis/$($newapi)?import=true&api-version=2017-03-01"
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

		if($newversionurl -eq $null -or $newversionurl -eq "" -or ($currentversion -eq $v))
		{
			$apimv="$($newapi)"
		}
		else
		{
			$apimv="$($newapi)$($v)"
		}

		foreach ($product in $products)
		{
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
		}
		
		if($PolicyContent -ne $null -and $PolicyContent -ne "")
		{
			try
			{
				$policyapiurl=	"$($baseurl)/apis/$apimv/policies/policy?api-version=2017-03-01"
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

		

		Write-Host "iterating through operations $($baseurl)/apis/$($apimv)/operations?api-version=2017-03-01"
		$operationresponse=Invoke-WebRequest -UseBasicParsing "$($baseurl)/apis/$($apimv)/operations?api-version=2017-03-01" -Headers $headers		
		$operations = $operationresponse.Content|ConvertFrom-Json
		$ops = @{}
		$operations.value|%{
			$ops.Add($_.properties.displayName,$_.name)
		}
		Write-Host "iterating through fucntions $($functionbaseurl)/functions?api-version=2016-08-01"
		$resp=Invoke-WebRequest -UseBasicParsing -Uri "$($functionbaseurl)/functions?api-version=2016-08-01"  -Headers $headers 
		$functions = $resp.Content|ConvertFrom-Json		
		
		$functions.value|% {
		$fname=$_.name.Substring($_.name.IndexOf("/")+1)
		Write-Host "Getting function keys https://$($functionsite).azurewebsites.net/admin/functions/$($fname)/keys"
		$keys=Invoke-WebRequest -UseBasicParsing -Uri "https://$($functionsite).azurewebsites.net/admin/functions/$($fname)/keys" -Headers $adminheaders
		$keys=$keys.Content|ConvertFrom-Json
		$thekey=$keys.keys[0].value
		$ops.Keys|%{
		if($_.ToString().indexOf("$fname/") -ne -1)
        {
            $targetfname=$ops[$_.ToString()]
            $json = "<policies>
    <inbound>        
        <set-query-parameter name='code' exists-action='skip'><value>"+$thekey+"</value></set-query-parameter>
        <base />
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>"
			Write-Host "setting operation policy $($baseurl)/apis/$($apimv)/operations/$($targetfname)/policy?api-version=2017-03-01"
            Invoke-WebRequest -Headers $headers -UseBasicParsing -Uri "$($baseurl)/apis/$($apimv)/operations/$($targetfname)/policy?api-version=2017-03-01" -Method Put -Body $json -ContentType "application/vnd.ms-azure-apim.policy.raw+xml"            
        }
    }

}

} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}