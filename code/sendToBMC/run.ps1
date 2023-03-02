# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()
# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}

Function getBearerTokenBMC ($ClientId,$ClientSecret) {

    Try {
        
        ## Generate the Auth Token Payload ##
        $body = @{}
        $body.Add("grant_type", "client_credentials")
        $body.Add("client_id", $ClientId)
        $body.Add("client_secret", $ClientSecret)
        $body.Add("scope", "api://4baf82f3-cbec-4c28-9b7d-0166c43a8f86/.default")

        ## Politely Request the Bearer Token ##
        $bearerToken = Invoke-RestMethod `
            -Method "Post" `
            -Uri "https://login.microsoftonline.com/azureford.onmicrosoft.com/oauth2/v2.0/token"`
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

function checkBMCForRecord ($ticket) {

    Try {

        ## Create BearerToken for API Call to BMC
        $bearerToken = $(getBearerTokenBMC -ClientId $ClientId -ClientSecret $ClientSecret)
        
        ## Format URL Query Object
        $queryUrl = ("https://api.qa01e.gcp.ford.com/itconnect/incident/v1/ticket-info?q=(" + "'" + "Description" + "'" + "=" + '"' + $ticket.name + '")')

        
        ## Generate header with bearerToken
        $Headers = @{}
        $Headers.Add("Authorization","$($bearerToken.token_type) "+ " " + "$($bearerToken.access_token)")

        $searchResult = Invoke-RestMethod `
                    -Method "Get" `
                    -Uri $queryUrl `
                    -ContentType 'application/json' `
                    -Headers $Headers

    } catch [System.SystemException] {
        
        Write-Error -Message $_.Exception  
        throw $_.Exception

    }

    return $($searchResult.entries)
}

function createBMCRecord ($ticket) {

    Try {

## Create Fake Ticket Fields
$detailedDescriptionValue = (@"
    Subscription Id: $(($ticket.id).Split('/')[2])
    Support Ticket#: $($ticket.Name)
    Owner Email: $($ticket.ContactDetail.PrimaryEmailAddress)

    MSFT Ticket Description:
    $($ticket.Description)
"@).Replace("`n","\n")

## Create Ticket Body
$createTicketBody = @"
    {
    "values" : {
    "Login_ID" : "ANOTIFIE",
    "Direct Contact LoginID": "ANOTIFIE",
    "Description" : "$($ticket.Name)",
    "Impact":"4-Minor/Localized",
    "Urgency":"4-Low",
    "Status" : "Assigned" ,
    "Reported Source" : "Direct Input" ,
    "Detailed_Decription": "$($detailedDescriptionValue)",
    "Service_Type" : "User Service Restoration" ,
    "Categorization Tier 1": "Break/Fix",
    "Categorization Tier 2": "Service Availability" ,
    "Categorization Tier 3": "Link Failed" ,
    "Product Categorization Tier 1":"Software" ,
    "Product Categorization Tier 2":"Application",
    "Product Categorization Tier 3":"IT",
    "Assigned Group": "Global Cloud Operations",
    "Assigned Support Organization": "Cloud Operations",
    "Assigned Support Company": "Ford Motor Company",
    "ServiceCI": "Azure",
    "z1D_Action" : "CREATE"
    } 
    }
"@

        ## Fetch bearerToken for API Call to BMC
        $bearerToken = $(getBearerTokenBMC -ClientId $ClientId -ClientSecret $ClientSecret)

        ## Generate header with bearerToken
        $Headers = @{}
        $Headers.Add("Authorization","$($bearerToken.token_type) "+ " " + "$($bearerToken.access_token)")

        ## Call BMC API to CREATE new Incident
        $createBMCTicketResults = Invoke-RestMethod `
                    -Method "Post" `
                    -Uri "https://api.qa01e.gcp.ford.com/itconnect/incident/v1/incident" `
                    -Body $createTicketBody `
                    -ContentType 'application/json' `
                    -Headers $Headers

        ## Return the New Incident Number from BMC as the Response (this can be used for logging or other automation activities if desired)
        return $($createBMCTicketResults.values.'Incident Number')

    } catch [System.SystemException] {
        
        Write-Error -Message $_.Exception  
        throw $_.Exception

        ## Return Exception Message to FunctionCall
        return $('Ticket Creation Failed: ' + $_.Exception.Message)

    }
}

<# __main__ code below this point #>
Try {

    ## Set Subscription to where the Keyvault is stored 
    [void](Set-AzContext -Subscription 'YOURSUBID')

    ## Populating the required variables with Secrets from Keyvault. 
    $ClientId = $(Get-AzKeyVaultSecret -VaultName 'ms-SevA-case-keyvault' -Name 'clientd' -AsPlainText)
    $ClientSecret = $(Get-AzKeyVaultSecret -VaultName 'ms-SevA-case-keyvault' -Name 'secret' -AsPlainText)

    
    $subscriptions = $(Get-AzSubscription)

    foreach ($subscription in $subscriptions) {

        ## Set Working Context to current Subscription
        [void](Set-AzContext -Subscription $subscriptions.Id)

        ## Capture SupportTickets and filter by Severity = 'Critical' and Status = 'Open'
        $supportTickets = $($supportTickets | Where-Object {$_.Severity -like 'Critical' -and $_.Status -like 'open'})

        ## ForEach through any SEV A tickets we get back
        foreach ($ticket in $supportTickets) {
            
            ## Call checkBMCForRecord Function and Log to Information Output
            If (checkBMCForRecord -ticket $ticket) {
                
                Write-Information ('Ticket Found: ' + $ticketCheck + ' - SKIPPING!')

            } else {

                ## Call createBMCRecord Function
                $createIncidentResponse = $(createBMCRecord -ticket $ticket) 
                
                ## Handling the Results of Call to createBMCRecord 
                If ($createIncidentResponse -like "Ticket Creation Failed:*"){

                    ## If Incident Creation Failed write Exception Message to Information Output
                    Write-Information ($createIncidentResponse + ' - Please check Error Output for detailed Exception Information.')

                } else {

                    ## Write BMC Incident Number to Information Output
                    Write-Information ('BMC Incident Number: ' + $createIncidentResponse)

                }                  
            }
        }
    }

} catch [System.SystemException] {
        
    ## Used to Capture Generic Exceptions and Throw to Error Output ##
    Write-Error -Message $_.Exception  
    throw $_.Exception

}