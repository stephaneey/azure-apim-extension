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
		$Cloud= Get-VstsInput -Name CloudEnvironment
		$NewRevision=Get-VstsInput -Name NewRevision
		$MakeNewRevisionCurrent=Get-VstsInput -Name MakeNewRevisionCurrent
		$CurrentRevisionNotes=Get-VstsInput -Name CurrentRevisionNotes
		$currentRevision=1
		$subscriptionRequired=Get-VstsInput -Name subscriptionRequired
		$apiRevisionDescription=Get-VstsInput -Name apiRevisionDescription
        $VersionHeader= Get-VstsInput -Name VersionHeader
		$QueryParam = get-VstsInput -Name QueryParam
		$VersionScheme = Get-VstsInput -Name scheme 
		$MicrosoftApiManagementAPIVersion = Get-VstsInput -Name MicrosoftApiManagementAPIVersion
        switch($VersionScheme)
		{
			"Path" {$scheme='"versioningScheme":"Segment"'}
			"Query" {$scheme='"versioningScheme":"Query","versionQueryName":"'+$($QueryParam)+'"'}
			"Header" {$scheme='"versioningScheme":"Header","versionHeaderName":"'+$($VersionHeader)+'"'}
		}
		$newapi=Get-VstsInput -Name targetapi
		
		if($newapi.startswith("/subscriptions"))
		{
			$newapi=$newapi.substring($newapi.indexOf("/apis")+6)
		}
		#this will be overwritten by the OpenAPI definition's title property
		$DisplayName=$newapi
		$v=Get-VstsInput -Name version
		$apiVersionIdentifier="$($newapi)$($v)" -replace '\.','-'
		$portal=Get-VstsInput -Name ApiPortalName
		$rg=Get-VstsInput -Name ResourceGroupName 
		$SwaggerPicker = Get-VstsInput -Name SwaggerPicker 
		$swaggerlocation=Get-VstsInput -Name swaggerlocation
		$swaggercode=Get-VstsInput -Name swaggercode 		
		$swaggerartifact = Get-VstsInput -Name swaggerartifact
		$products = $(Get-VstsInput -Name product1).Split([Environment]::NewLine)
		$UseProductCreatedByPreviousTask=Get-VstsInput -Name UseProductCreatedByPreviousTask
		$path = Get-VstsInput -Name pathapi
		$Authorization = Get-VstsInput -Name Authorization
		$oid = Get-VstsInput -Name oid
		$oauth = Get-VstsInput -Name oauth
		$OpenAPISpec=Get-VstsInput -Name OpenAPISpec
		$Format=Get-VstsInput -Name Format
		$AuthorizationBits='"authenticationSettings":null'
		Write-Host "Preparing API publishing in $($OpenAPISpec) format $($Format) using Azure API $($MicrosoftApiManagementAPIVersion)"
		switch($Authorization)
		{
			'OAuth' {$AuthorizationBits='"authenticationSettings":{"oAuth2":{"authorizationServerId":"'+$oauth+'","scope":null}}'}
			'OpenID' {$AuthorizationBits='"authenticationSettings":{"openid":{"openidProviderId":"'+$oid+'"}}'}
			
		}
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
			
		
		$client=$Endpoint.Auth.Parameters.ServicePrincipalId
		$secret=[System.Web.HttpUtility]::UrlEncode($Endpoint.Auth.Parameters.ServicePrincipalKey)
		$tenant=$Endpoint.Auth.Parameters.TenantId		
		$body="resource=https%3A%2F%2Fmanagement.azure.com%2F"+
        "&client_id=$($client)"+
        "&grant_type=client_credentials"+
        "&client_secret=$($secret)"
	    try
		{
			$resp=Invoke-WebRequest -UseBasicParsing -Uri "$($Cloud)/$($tenant)/oauth2/token" `
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
		$targeturl="$($baseurl)/apis/$($apiVersionIdentifier)?api-version=$($MicrosoftApiManagementAPIVersion)"	
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
			switch($SwaggerPicker)
			{
				"Url" {
					$cli=[System.Net.WebClient]::new()
					$swagger=$cli.DownloadString($swaggerlocation)				
					$cli.Dispose()
					
				}
				"Artifact" {
					try {
 						Assert-VstsPath -LiteralPath $swaggerartifact -PathType Leaf
						 $swagger = Get-Content "$($swaggerartifact)" -Raw
					} catch {
  						Write-Error "Invalid file location $($swaggerartifact)"
					}
				}
				"Code" {
					$swagger=$swaggercode
				}
				default {Write-Error "Invalid swagger definition"}
			}	
			if($OpenAPISpec -eq "v3")
			{
				Add-Type -AssemblyName System.Web
				$swagger=$swagger.Replace("`r`n","`n")
				$swagger =[System.Web.HttpUtility]::JavaScriptStringEncode($swagger)
			}			

			if($apiexists -eq $false)
			{				
				Write-Host "Creating new API from scratch"
				#creating the api version set, the api and importing the swagger definition into it
				$version="$($newapi)versionset"
				$versionseturl="$($baseurl)/apiVersionSets/$($version)?api-version=$($MicrosoftApiManagementAPIVersion)"
				$json='{"id":"/apiVersionSets/'+$($version)+'","properties":{"name":"'+$($newapi)+'",'+$($scheme)+'}}'
				Write-Host "Creating version set using $($versionseturl) using $($json)"
				Invoke-WebRequest -UseBasicParsing -Uri $versionseturl  -Body $json -ContentType "application/json" -Headers $headers -Method Put
				$apiurl="$($baseurl)/apis/$($apiVersionIdentifier)?api-version=$($MicrosoftApiManagementAPIVersion)"
				$json = '{
				  "id":"/apis/'+$($newapi)+'",
				  "name":"'+$($newapi)+'",
				  "properties":
				  { '+$AuthorizationBits+',
				     "displayName":"'+$($DisplayName)+'",
					 "path":"'+$($path)+'",
					 "protocols":["https"],
					 "subscriptionRequired":"'+$($subscriptionRequired)+'",
					 "apiVersion":"'+$($v)+'",
					 "apiVersionSet":{
					   "id":"/apiVersionSets/'+$($version)+'",
					   "name":"'+$($apiVersionIdentifier)+'",'+$($scheme)+'					   
					  },
					  "apiVersionSetId":"/apiVersionSets/'+$version+'"
				  }
				}'
				$headers.Add("If-Match","*")
				Write-Host "Creating API using $($apiurl) and $($json)"
				Invoke-WebRequest -UseBasicParsing -Uri $apiurl  -Body $json -ContentType "application/json" -Headers $headers -Method Put
				
				$importurl="$($baseurl)/apis/$($apiVersionIdentifier)?import=true&api-version=$($MicrosoftApiManagementAPIVersion)"
				
				Write-Host "Importing Swagger definition to API using $($importurl)"
				#to change
				if($OpenAPISpec -eq "v2")
				{
					Invoke-WebRequest -UseBasicParsing $importurl -Method Patch -ContentType "application/vnd.swagger.doc+json" -Body $swagger -Headers $headers
				}
				else {
					$importurl=$importurl.Substring(0,$importurl.IndexOf("api-version"))+"api-version=2018-06-01-preview"
					if($Format -eq 'json')
					{
						$contentFormat="openapi+json"
					}else{
						$contentFormat="openapi"
					}				
					$openAPIBody='{"contentFormat":"'+$contentFormat+'","contentValue":"'+$swagger+'"}'
					Write-Host "OpenAPI body is $($openAPIBdoy)"
					Invoke-WebRequest -UseBasicParsing $importurl -Method Put -ContentType "application/json" -Body $openAPIBody -Headers $headers
				}
				
			}
			else
			{
				$rev=1;
				#the api already exists, only a new version or revision must be created.
				$newversionurl="$($baseurl)/apis/$($apiVersionIdentifier);rev=1?api-version=$($MicrosoftApiManagementAPIVersion)"
				$headers = @{
				 Authorization = "Bearer $($resp.access_token)"        
				}				
				
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
				$headers.Add("If-Match","*")	
				
				Write-Host "current version $($currentversion), version is $($v), version exists $($versionexists)"
				if($currentversion -ne $v -and $versionexists -eq $false)
				{
					#SEY
					$json='{"properties":{"name":"'+$newapi+'","displayName":"'+$DisplayName+'","sourceApiId":"/apis/'+$($newapi)+'","apiVersion":"'+$($v)+'","apiVersionSetId":"/apiversionsets/'+$newapi+'versionset"}}'			
					Write-Host "Creating a new version $($newversionurl) with $($json)"
					Invoke-WebRequest -UseBasicParsing $newversionurl -Method Put -ContentType "application/json" -Body $json -Headers $headers									
				}		
				else
				{
					Write-Host "Getting list of revisions"
					$revisions=Invoke-WebRequest -UseBasicParsing -Uri "$($baseurl)/apis/$($apiVersionIdentifier)/revisions?api-version=$($MicrosoftApiManagementAPIVersion)" -Headers $headers|ConvertFrom-Json
					
                    $revisions|% {
						$_.value|%{
							if($_.isCurrent -eq $true)
							{
							$currentRevision=$_.apiRevision                             
							}
						}
					}
					$revisions = $revisions.value | Sort-Object -Property "createdDateTime" -Descending  

					Write-Host "Current revision is $($currentRevision)"
                    if($NewRevision -eq $true)
                    {						
						$rev=([int]$revisions[0].apiRevision)+1;
						Write-Host "New revision is $($rev)"						
						$revJson='{"properties":{"sourceApiId":"'+$($baseurl)+'/apis/'+$($apiVersionIdentifier)+';rev='+$($currentRevision)+'","apiRevisionDescription":"'+$($apiRevisionDescription)+'"}}'
						Write-Host "New revision body is $($revJson)"
                        Invoke-WebRequest -ContentType "application/json" -UseBasicParsing -Uri "$($baseurl)/apis/$($apiVersionIdentifier);rev=$($rev)?api-version=$($MicrosoftApiManagementAPIVersion)" -Headers $headers -Method Put -Body $revJson
						Write-Host "Revision $($rev) created"
						if($MakeNewRevisionCurrent -eq $true)
						{
							Write-Host "Making new revision current"
							$releaseId=[guid]::NewGuid()
							$currentRevReleaseBody='{"properties":{"apiId":"/apis/'+$($apiVersionIdentifier)+';rev='+$($rev)+'","notes":"'+$CurrentRevisionNotes+'"}}'
							$currentRevisionUrl="$($baseurl)/apis/$($apiVersionIdentifier);rev=$($rev)/releases/$($releaseId)?api-version=$($MicrosoftApiManagementAPIVersion)"
							Write-Host $currentRevisionUrl
							Write-Host $currentRevReleaseBody
							$resp=Invoke-WebRequest -ContentType "application/json" -UseBasicParsing -Uri $currentRevisionUrl -Headers $headers -Method Put -Body $currentRevReleaseBody
							Write-Host $resp
						}
                    }
					else
                    {
                       $rev=$currentRevision;
                    }
				}
				$authurl = "$($baseurl)/apis/$($apiVersionIdentifier);rev=$($rev)?api-version=$($MicrosoftApiManagementAPIVersion)"		
				$importurl="$($baseurl)/apis/$($apiVersionIdentifier);rev=$($rev)?import=true&api-version=$($MicrosoftApiManagementAPIVersion)"											
				
				Write-Host "applying authorization"				
				
				$json='{"name":"'+$apiVersionIdentifier+'","properties":{'+$AuthorizationBits+',"ApiVersionSetId":"/apiVersionSets/'+$($newapi)+'versionset","apiVersion":"'+$v+'"}}'
				Write-Host "Authorization json $($json)"
				Write-Host "endpoint is $($authurl) headers are $($headers)"
				Invoke-WebRequest -UseBasicParsing -Uri $authurl -Headers $headers -Method "PATCH" -ContentType "application/json" -Body $json
				Write-Host "applied authorization"
				#reapplying swagger
				
				Write-Host "Importing swagger $($importurl) spec is $($OpenAPISpec) format is $($Format)"
				Write-Host "Applying $($swagger)"	
				if($OpenAPISpec -eq "v2")
				{
					Invoke-WebRequest -UseBasicParsing $importurl -Method Patch -ContentType "application/vnd.swagger.doc+json" -Body $swagger -Headers $headers	
				}
				else {
					$importurl=$importurl.Substring(0,$importurl.IndexOf("api-version"))+"api-version=2018-06-01-preview"
					if($Format -eq 'json')
					{
						$contentFormat="openapi+json"
					}else{
						$contentFormat="openapi"
					}				
					$openAPIBody='{"contentFormat":"'+$contentFormat+'","contentValue":"'+$swagger+'"}'
					Write-Host "API Body is $($openAPIBody)"
					Invoke-WebRequest -UseBasicParsing $importurl -Method Put -ContentType "application/json" -Body $openAPIBody -Headers $headers

				}
				
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

		foreach ($product in $products)
		{
			if($product -ne $null -and $product -ne "")
			{
				$productapiurl=	"$($baseurl)/products/$($product)/apis/$($apiVersionIdentifier)?api-version=$($MicrosoftApiManagementAPIVersion)"
				
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
				$policyapiurl=	"$($baseurl)/apis/$($apiVersionIdentifier);rev=$($rev)/policies/policy?api-version=$($MicrosoftApiManagementAPIVersion)"
				$JsonPolicies = "{
				  `"properties`": {					
					`"format`":`"rawxml`",  
					`"value`":`""+$PolicyContent+"`"
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