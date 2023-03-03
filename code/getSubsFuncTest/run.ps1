# Input bindings are passed in via param block.
param($Timer)

# Get the current universal time in the default string format
$currentUTCtime = (Get-Date).ToUniversalTime()
# The 'IsPastDue' property is 'true' when the current function invocation is later than scheduled.
if ($Timer.IsPastDue) {
    Write-Host "PowerShell timer is running late!"
}


<# __main__ code below this point #>
Try {

    ## Get all the Subs
    $Subs = $(Get-AzSubscription)
    Write-Output $subs.Name

    
    ## Testing AzConnect using User Managed Identity
    [void](Connect-AzAccount -Identity -AccountId 'bc646341-f8b7-4413-993d-623be46336d5' -ErrorAction SilentlyContinue)


} catch [System.SystemException] {
        
    ## Used to Capture Generic Exceptions and Throw to Error Output ##
    Write-Error -Message $_.Exception  
    throw $_.Exception

}