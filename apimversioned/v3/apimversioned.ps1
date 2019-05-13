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
    
    $arm = Get-VstsInput -Name ConnectedServiceNameARM
    $Endpoint = Get-VstsEndpoint -Name $arm -Require	
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
    $DisplayName=Get-VstsInput -Name DisplayName
    if($newapi.startswith("/subscriptions"))
    {
        $newapi=$newapi.substring($newapi.indexOf("/apis")+6)
    }
    if([string]::IsNullOrEmpty($DisplayName))
    {
        $DisplayName=$newapi
    }
    $v=Get-VstsInput -Name version
    $apiVersionIdentifier="${newapi}${v}" -replace '.','-'
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
    if($SelectedTemplate -eq "Custom")
    {
        $PolicyContent = Get-VstsInput -Name Custom
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
    $targeturl="$($baseurl)/apis/$($newapi)?api-version=$($MicrosoftApiManagementAPIVersion)"	
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
            $versionseturl="$($baseurl)/api-version-sets/$($version)?api-version=$($MicrosoftApiManagementAPIVersion)"
            $json='{"id":"/api-version-sets/'+$($version)+'","name":"'+$($newapi)+'",'+$($scheme)+'}'
            Write-Host "Creating version set using $($versionseturl) using $($json)"
            Invoke-WebRequest -UseBasicParsing -Uri $versionseturl  -Body $json -ContentType "application/json" -Headers $headers -Method Put
            $apiurl="$($baseurl)/apis/$($newapi)?api-version=$($MicrosoftApiManagementAPIVersion)"
            $json = '{
                "id":"/apis/'+$($newapi)+'",
                "name":"'+$($newapi)+'",
                "properties":
                { 
                    "displayName":"'+$($DisplayName)+'",'+$AuthorizationBits+',
                    "path":"'+$($path)+'",
                    "protocols":["https"],
                    "apiVersion":"'+$($v)+'",
                    "apiVersionSet":{
                        "id":"/api-version-sets/'+$($version)+'",
                        "name":"'+$($newapi)+'",'+$($scheme)+'					   
                    },
                    "apiVersionSetId":"/api-version-sets/'+$version+'"
                }
            }'
            Write-Host "Creating API using $($apiurl) and $($json)"
            Invoke-WebRequest -UseBasicParsing -Uri $apiurl  -Body $json -ContentType "application/json" -Headers $headers -Method Put
            $headers.Add("If-Match","*")
            $importurl="$($baseurl)/apis/$($newapi)?import=true&api-version=$($MicrosoftApiManagementAPIVersion)"
            
            Write-Host "Importing Swagger definition to API using $($importurl)"
            #to change
            if($OpenAPISpec -eq "v2")
            {
                Invoke-WebRequest -UseBasicParsing $importurl -Method Put -ContentType "application/vnd.swagger.doc+json" -Body $swagger -Headers $headers
            }
            else {
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
            #the api already exists, only a new version must be created.
            $newversionurl="$($baseurl)/apis/$apiVersionIdentifier;rev=1?api-version=$($MicrosoftApiManagementAPIVersion)"
            $headers = @{
                Authorization = "Bearer $($resp.access_token)"        
            }				
            $json='{"sourceApiId":"/apis/'+$($newapi)+'","apiVersionName":"'+$($v)+'","apiVersionSet":{'+$($scheme)+'}}'
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
                $importurl="$($baseurl)/apis/$apiVersionIdentifier?import=true&api-version=$($MicrosoftApiManagementAPIVersion)"
                $authurl = "$($baseurl)/apis/$apiVersionIdentifier?api-version=2018-01-01"
            }		
            else
            {
                $importurl="$($baseurl)/apis/$($newapi)?import=true&api-version=$($MicrosoftApiManagementAPIVersion)"
                if($currentversion -ne $v)
                {
                    $authurl = "$($baseurl)/apis/$apiVersionIdentifier?api-version=2018-01-01"
                }
                else {
                    $authurl = "$($baseurl)/apis/$($newapi)?api-version=2018-01-01"
                }
                
            }
            $headers.Add("If-Match","*")	
            Write-Host "applying authorization"				
            
            $json='{"name":"'+$newapi+'","properties":{'+$AuthorizationBits+',"apiVersion":"'+$v+'"}}'
            Write-Host "Authorization json $($json)"
            Write-Host "endpoint is $($authurl) headers are $($headers)"
            Invoke-WebRequest -UseBasicParsing -Uri $authurl -Headers $headers -Method "PATCH" -ContentType "application/json" -Body $json
            Write-Host "applied authorization"
            #reapplying swagger
            
            Write-Host "Importing swagger $($importurl) spec is $($OpenAPISpec) format is $($Format)"
            
            if($OpenAPISpec -eq "v2")
            {
                Invoke-WebRequest -UseBasicParsing $importurl -Method Put -ContentType "application/vnd.swagger.doc+json" -Body $swagger -Headers $headers	
            }
            else {
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
    
    if($newversionurl -eq $null -or $newversionurl -eq "" -or ($currentversion -eq $v))
    {
        $apimv="$($newapi)"
    }
    else
    {
        $apimv=$apiVersionIdentifier
    }
    
    foreach ($product in $products)
    {
        if($product -ne $null -and $product -ne "")
        {
            $productapiurl=	"$($baseurl)/products/$($product)/apis/$($apimv)?api-version=$($MicrosoftApiManagementAPIVersion)"
            
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
            $policyapiurl=	"$($baseurl)/apis/$($apimv)/policies/policy?api-version=$($MicrosoftApiManagementAPIVersion)"
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
    Write-Host "Setting up authorization"
    
    Write-Host $rep
    
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}