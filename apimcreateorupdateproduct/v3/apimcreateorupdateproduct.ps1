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
		$displayName=Get-VstsInput -Name DisplayName
		$product=Get-VstsInput -Name product		
		$state=Get-VstsInput -Name state
		$groups = $(Get-VstsInput -Name groups).Split([Environment]::NewLine)

		if($state -eq $true)
		{
			$state="published"
		}
		else
		{
			$state="notPUblished"
		}
		$subscriptionRequired=Get-VstsInput -Name subscriptionRequired
		$subscriptionRequired=$subscriptionRequired.ToString().ToLowerInvariant()
		$approvalRequired=Get-VstsInput -Name approvalRequired		
		$approvalRequired=$approvalRequired.ToString().ToLowerInvariant()
		$subscriptionsLimit=Get-VstsInput -Name subscriptionsLimit
		if($subscriptionsLimit -eq $null -or $subscriptionsLimit -eq "")
		{
			$subscriptionsLimit='null'
		}
		$SelectedTemplate=Get-VstsInput -Name TemplateSelector
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

		
		$headers = @{
			Authorization = "Bearer $($resp.access_token)"        
		}
		
		if($product.startswith("/subscriptions"))
		{
			$product=$product.substring($product.indexOf("/products")+10)
		}
		Write-Host "Product is $($product)"
		$baseurl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)"
		$producturl="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)/products/$($product)?api-version=2017-03-01"
		Write-Host $producturl
		if($displayName -eq $null -or $displayName -eq "")
		{
			$displayName=$product
		}

		Write-Host "DisplayName is $($displayName)"
		if ($subscriptionRequired -eq 'true')
		{
			$json = '{
			"properties": {
				"displayName": "'+$displayName+'",
				"subscriptionRequired": '+$subscriptionRequired+',
			"approvalRequired": '+$approvalRequired+',
			"subscriptionsLimit":'+$subscriptionsLimit+',
			"state":"'+$state+'",
			}
		   }'	
		}
		else
		{
			$json = '{
			"properties": {
				"displayName": "'+$displayName+'",
				"subscriptionRequired": '+$subscriptionRequired+',			
				"state":"'+$state+'",
				}
		   }'
		}
				
		
		Write-Host $json
		try
		{
			Invoke-WebRequest -UseBasicParsing -Uri $producturl -Headers $headers -Method Put -Body $json -ContentType "application/json"
			Write-Host ("##vso[task.setvariable variable=NewUpdatedProduct;]$product")
		}
		catch [System.Net.WebException] 
		{
			$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
			write-host $er.error.details
			throw
		}
		#checking whether the provided groups exist or not
		$odataFilter="("
		foreach($group in $groups)
		{
			$odataFilter+="name%20eq%20'"+$group+"'%20or%20"
		}
		$odataFilter=$odataFilter.Substring(0,$odataFilter.Length-8)
		$odataFilter+=")"
		$existingGroupsUri="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)/groups?api-version=2017-03-01&"+'$filter='+"$($odataFilter)"
		$existingProductGroupsUri="$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)/products/$($product)/groups?api-version=2018-01-01"
		$existingProductGroups=Invoke-WebRequest -UseBasicParsing -Uri $existingProductGroupsUri -Headers $headers|ConvertFrom-Json
		Write-Host "getting existing groups $($existingGroupsUri)"
		$existingGroups=Invoke-WebRequest -UseBasicParsing -Uri $existingGroupsUri -Headers $headers|ConvertFrom-Json
		
		foreach ($group in $groups)
		{
			try
			{
				if($null -eq ($g=$existingGroups.value|where {$_.name -eq $group}))
				{
					write-host "creating group $($group)"
					$groupBody="{'properties':{'displayName':'$($group)'}}"
					Invoke-WebRequest -UseBasicParsing -Uri "$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)/groups/$($group)?api-version=2017-03-01" -Method Put -ContentType application/json -Body $groupBody -Headers $headers
				}
				$groupapiurl = "$($baseurl)/products/$($product)/groups/$($group)?api-version=2018-01-01"
				Write-Host "Adding group to product $($groupapiurl)"
				Invoke-WebRequest -UseBasicParsing -Uri $groupapiurl -Headers $headers -Method Put -Body $JsonPolicies -ContentType "application/json"
			}
			catch [System.Net.WebException] 
			{
				$er=$_.ErrorDetails.Message.ToString()|ConvertFrom-Json
				Write-Host $er.error.details
				throw
			}
		}
		foreach($existingProductGroup in $existingProductGroups.value)
		{

			if($null -eq ($g=$groups|where {$_ -eq $existingProductGroup.name}))
			{
				write-host "deleting product group $($existingProductGroup.name)"
				Invoke-Webrequest -UseBasicParsing -Uri "$($Endpoint.Url)subscriptions/$($Endpoint.Data.SubscriptionId)/resourceGroups/$($rg)/providers/Microsoft.ApiManagement/service/$($portal)/products/$($product)/groups/$($existingProductGroup.name)?api-version=2017-03-01" -Method Delete -Headers $headers
			}
		}

		if($PolicyContent -ne $null -and $PolicyContent -ne "")
		{
			try
			{
				$policyapiurl=	"$($baseurl)/products/$($product)/policies/policy?api-version=2017-03-01"
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