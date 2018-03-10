[CmdletBinding()]
param()
Trace-VstsEnteringInvocation $MyInvocation
try {        
<#  
Warning: this code is provided as-is with no warranty of any kind. I do this during my free time.
This task checks whether all the endpoints of a backend API are secured.
Prerequisite to using this task: the VSTS agent must be able to connect to the backend API targeted by the security check. If the Swagger file
is also secured, make sure the VSTS agent can still connect to it (using a code in the URL for instance similarly to Azure Functions)
#>	
    $swaggerlocation=Get-VstsInput -Name swaggerlocation    
    $cli=[System.Net.WebClient]::new()
    $swagger=$cli.DownloadString($swaggerlocation) | ConvertFrom-Json
    $cli.Dispose()
    $baseurl=$swaggerlocation.substring(0,$swaggerlocation.indexof("swagger")-1)
    $props=Get-Member -InputObject $swagger.paths
    $TaskError=$false
    $props|%{
     if($_.Name.StartsWith("/"))
     {        
        $PathToPing = "$($baseurl)$($_.Name)"
        $QueryString ="?"
        $PostBody=""
        $parameters={}
        $method=""                
        if($swagger.paths.$($_.Name).get -ne $null)
        {            
            $parameters=$swagger.paths.$($_.Name).get.parameters
            $method="get"
        }    
        if($swagger.paths.$($_.Name).post -ne $null)
        {  
            $parameters=$swagger.paths.$($_.Name).post.parameters
            $method="post"
        }    
        if($swagger.paths.$($_.Name).put -ne $null)
        {  
            $parameters=$swagger.paths.$($_.Name).put.parameters
            $method="put"
        }    
        if($swagger.paths.$($_.Name).delete -ne $null)
        {            
            $parameters=$swagger.paths.$($_.Name).delete.parameters
            $method="delete"
        }    
        if($swagger.paths.$($_.Name).merge -ne $null)
        {            
            $parameters=$swagger.paths.$($_.Name).merge.parameters
            $method="merge"
        }    
            
        foreach($param in $parameters)
        {
            if($param.in -eq "query")
            {                       
                $QueryString +="$($param.Name)=1&"                                           
            }                    
            if($param.in -eq "path")
            {
                $PathToPing = $PathToPing.Replace("{$($param.name)}","1")
            }
            if($param.in -eq "body")
            {
                $PostBody+="$($param.Name)=1&"  
            }
        }        

        try
        {
            write-host -Message s "attempting to call $($PathToPing)$($QueryString) using method $($method)"
            if($PostBody -eq "")
            {
               $resp=Invoke-WebRequest -UseBasicParsing -Uri "$($PathToPing)$($QueryString)" -Method "$($method)" -MaximumRedirection 0 -ErrorAction SilentlyContinue               
            }
            else
            {
               $resp=Invoke-WebRequest -UseBasicParsing -Uri "$($PathToPing)$($QueryString)" -Method "$($method)" -Body "$($PostBody)" -MaximumRedirection 0 -ErrorAction SilentlyContinue
               
            }
			#that trick is only valid for Azure Active Directory kind of redirection.
            if($resp.StatusCode -eq 302 -and $resp.Headers.Location.StartsWith("https://login"))
            {
                Write-host "$($PathToPing)$($QueryString) returned 302 to login page so it is secured"
            }
            else
            {
                Write-Warning "$($PathToPing)$($QueryString) returned 200"
                $TaskError=$true
            }
        }
        catch [System.Net.WebException] {
            $status = ($_.Exception.Response.StatusCode.value__ ).ToString().Trim();
            if($status -ne "401")
            {            
                Write-Warning "$($PathToPing)$($QueryString) returned $($status)"
                $TaskError=$true
            }
        }            
        
     }    
    }
    if($TaskError -eq $true)
    {
        throw "Some endpoints are not secure, please review the logs"
    }       
    
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}