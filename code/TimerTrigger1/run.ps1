# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()
# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

# Build out required Functions
Function getBearerToken ($ClientId,$ClientSecret,$TenantId) {

    Try {
        
        ## Generate the Auth Token Payload ##
        $body = @{}
        $body.Add("grant_type", "client_credentials")
        $body.Add("client_id", $ClientId)
        $body.Add("client_secret", $ClientSecret)
        $body.Add("resource", "https://management.core.windows.net/")

        ## Politely Request the Bearer Token ##
        $bearerToken = Invoke-RestMethod `
            -Method "Post" `
            -Uri "https://login.microsoftonline.com/$tenantId/oauth2/token"`
            -Body $body `
            -ContentType 'application/x-www-form-urlencoded'



    } catch [System.SystemException] {

        ## Used to Capture Standard Exceptions and Throw to Error Log ##
        Write-Error -Message $_.Exception  
        throw $_.Exception

    }

    # return the $bearerToken Object from function#
    return $bearerToken
}

function getResourceHealth ($resourceId,$bearerToken) {

    Try {

        ## Generate header with bearerToken
        $Headers = @{}
        $Headers.Add("Authorization","$($bearerToken.token_type) "+ " " + "$($bearerToken.access_token)")

        # call Resource Health API and return results
        $resourceHealthAPIreturn = Invoke-WebRequest `
            -Method "Get" `
            -Uri "https://management.azure.com/$resourceId/providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2022-05-01" `
            -Headers $Headers 

    } catch [System.SystemException] {
        
        ## Used to Capture Generic Exceptions and Throw to Error Output ##
        Write-Error -Message $_.Exception  
        throw $_.Exception
    }
    ## Return resourceHealthAPIretun object from function ##
    return $resourceHealthAPIreturn
}

function getResourceIds {
    
    Try {

        ## Auth Token Generation
        $resourceURI = "https://database.windows.net/"
        $tokenAuthURI = $env:MSI_ENDPOINT + "?resource=$resourceURI&api-version=2017-09-01"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"="$env:MSI_SECRET"} -Uri $tokenAuthURI
        $accessToken = $tokenResponse.access_token

        ## Build out sqlConnection
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = "Data Source=cglabs-fordpoc-sqlserver.database.windows.net;Initial Catalog=cglabs-fordpoc-db"
        $SqlConnection.AccessToken = $accessToken


        ## Convert dataSet Object to INSERT T-SQL Command 
        $query = "SELECT resourceId FROM resourceIds"
        
        ## Build sqlCmd Object and collect return
        $sqlCmd = new-object system.data.sqlclient.sqldataadapter ($query, $SqlConnection)
        $resIds = new-object system.data.datatable
        $sqlCmd.Fill($resIds) | out-null

    } catch [System.SystemException] {

        ## Used to Capture Standard Exceptions and Throw to Error Log ##
        Write-Error -Message $_.Exception  
        throw $_.Exception

    }

    ## Return dataObject from Function 
    return $resIds.resourceId

}

function sendToDatabase ($dataSet,$resourceId) {

    Try {

        $resourceURI = "https://database.windows.net/"
        $tokenAuthURI = $env:MSI_ENDPOINT + "?resource=$resourceURI&api-version=2017-09-01"
        $tokenResponse = Invoke-RestMethod -Method Get -Headers @{"Secret"="$env:MSI_SECRET"} -Uri $tokenAuthURI
        $accessToken = $tokenResponse.access_token

        ## Build out sqlConnection
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
        $SqlConnection.ConnectionString = "Data Source=cglabs-fordpoc-sqlserver.database.windows.net;Initial Catalog=cglabs-fordpoc-db"
        $SqlConnection.AccessToken = $accessToken
        $SqlConnection.Open()

        ## Convert dataSet Object to INSERT T-SQL Command 
        $sqlInsert = "INSERT dbo.pocTable( ResourceId , availabilityState , title , summary , occuredTime , reasonChronicity , reportedTime ) `
        VALUES( '" `
        + ($resourceId) `
        + "' , '" `
        + ($responseBodyJson.properties.availabilityState) `
        + "' , '" `
        + ($responseBodyJson.properties.title) `
        + "' , '" `
        + ($responseBodyJson.properties.summary).replace( "'" , "''" ) `
        + "' , '" `
        + ($responseBodyJson.properties.occuredTime).ToString("yyyy-MM-ddThh:mm:ss") `
        + "' , '" `
        + ($responseBodyJson.properties.reasonChronicity) `
        + "' , '" `
        + ($responseBodyJson.properties.reportedTime).ToString("yyyy-MM-ddThh:mm:ss") `
        + "' )"
        
        ## Build out SQL Command to send data..
        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.CommandText = $sqlInsert
        $SqlCmd.Connection = $SqlConnection
        $sqlcmd.ExecuteNonQuery()

    } catch [System.SystemException] {
        
        Write-Error -Message $_.Exception  
        throw $_.Exception

    }
}

<# __main__ code below this point #>
Try {

    # Set Subscription to where the Keyvault is stored #
    [void](Set-AzContext -Subscription 'e56b7094-826f-412e-bf37-0f13a1f872cc')

    # Populating the required variables with Secrets from Keyvault. #
    $TenantId = $(Get-AzKeyVaultSecret -VaultName cglabs-fordpoc-kv -Name tenantId -AsPlainText)
    $ClientId = $(Get-AzKeyVaultSecret -VaultName cglabs-fordpoc-kv -Name clientId -AsPlainText)
    $ClientSecret = $(Get-AzKeyVaultSecret -VaultName cglabs-fordpoc-kv -Name clientSecret -AsPlainText)

    # Get ResourceId ArrayList #
    $resourceIds = $(getResourceIds)
    
    # Cycle through each Canary Resource #
    foreach ($resourceId in $resourceIds) {

        # Get Bearer Token
        $authToken = $(getBearerToken -ClientId $ClientId -TenantId $TenantId -ClientSecret $ClientSecret)

        # Get ResourceHealth Response
        $response = $(getResourceHealth -resourceId $resourceId -bearerToken $authToken)
    
        if ($response.statusCode -eq '200') {

            # Convert Response Body to Object from JSON
            $responseBodyJson = $(ConvertFrom-Json($response.content))

            # Feed data into Database
            $sqlResponse = $(sendToDatabase -dataSet $responseBodyJson.properties -resourceId $resourceId) 

            Write-Output $sqlResponse
        } 
    }

} catch [System.SystemException] {
        
    ## Used to Capture Generic Exceptions and Throw to Error Output ##
    Write-Error -Message $_.Exception  
    throw $_.Exception

}