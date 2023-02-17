# Setup Notes #

## Required Components/Configuration ##
There are some requirements that must be meant before using this code both locally and within Azure. 
- System Managed Identity associated with Azure Function and Rights with Azure SQL Db to write to the tables
- Azure SQL Database (10 DTU is what I'm testing with - can scale up if needed)
- Azure Function (with Time based Trigger set to every Minute)
- Target resources with 'canary = true' tag (this can be skipped if planning on manually or hardcoding canary resource IDs)


## Local Development ##
Install Required Tools on local development workstation:
``` powershell
# Visual Studio Code
choco install vscode

# .Net Core SDK (64-Bit)
choco install dotnetcore-sdk

## Validate .netcore install was successful | 
┏[bemitchell][fordPoC]
┖[~\repos\cglabs\scripts]> dotnet --info
.NET SDK:
 Version:   7.0.102
 Commit:    4bbdd14480

Runtime Environment:
 OS Name:     Windows
 OS Version:  10.0.22621
 OS Platform: Windows
 RID:         win10-x64
 Base Path:   C:\Program Files\dotnet\sdk\7.0.102\

Host:
  Version:      7.0.2
  Architecture: x64
  Commit:       d037e070eb

.NET SDKs installed:
  3.1.426 [C:\Program Files\dotnet\sdk]
  7.0.102 [C:\Program Files\dotnet\sdk]


# Azure Function Core Tools
choco install azure-functions-core-tools

# Validate Azure Function Core Tools is installed |
┏[bemitchell][fordPoC]
┖[~\repos\cglabs\scripts]> func

                  %%%%%%
                 %%%%%%
            @   %%%%%%    @
          @@   %%%%%%      @@
       @@@    %%%%%%%%%%%    @@@
     @@      %%%%%%%%%%        @@
       @@         %%%%       @@
         @@      %%%       @@
           @@    %%      @@
                %%
                %


Azure Functions Core Tools
Core Tools Version:       4.0.4915 Commit hash: N/A  (32-bit)
Function Runtime Version: 4.14.0.19631

Usage: func [context] [context] <action> [-/--options]

# VS Code Azure Function Extension
code --install-extension ms-azuretools.vscode-azurefunctions
```

## Setting up MS SQL DB ##

1. Configure Local Security User with Managed Identity and grant db_datareader & db_datawriter (either SSMS or Query Editor via Portal will work)
```sql
  CREATE USER [cglabs-fordpoc-func] FROM EXTERNAL PROVIDER;
  GO
  ALTER ROLE db_datareader ADD MEMBER [cglabs-fordpoc-func];
  ALTER ROLE db_datawriter ADD MEMBER [cglabs-fordpoc-func];
  GRANT EXECUTE TO [cglabs-fordpoc-func]
  GO
```

2. Configure Table for PoC
```sql
  CREATE TABLE pocTable (
    availabilityState	varchar(50),
    title				varchar(50),
    summary				varchar(255),
    occuredTime			datetime2,
    reasonChronicity	varchar(50),
    reportedTime		datetime2,
  )
```

3. Add additional table for resourceIds
```sql
  CREATE TABLE resourceIds(
  id INT NOT NULL UNIQUE PRIMARY KEY,
  resourceId varchar(255)
  );

  INSERT INTO [dbo].[resourceIds] (id,resourceId) VALUES
  ('0','subscriptions/e56b7094-826f-412e-bf37-0f13a1f872cc/resourceGroups/FordLoggingPoc/providers/Microsoft.Devices/IotHubs/cglabs-fordpoc-iot'),
  ('1','subscriptions/e56b7094-826f-412e-bf37-0f13a1f872cc/resourceGroups/FordLoggingPoc/providers/Microsoft.DocumentDb/databaseAccounts/cglabs-fordpoc-cosmo'),
  ('2','subscriptions/e56b7094-826f-412e-bf37-0f13a1f872cc/resourceGroups/FordLoggingPoc/providers/Microsoft.EventHub/namespaces/cglabs-fordpoc'),
  ('3','subscriptions/e56b7094-826f-412e-bf37-0f13a1f872cc/resourceGroups/FordLoggingPoc/providers/Microsoft.ServiceBus/namespaces/cglabs-fordpoc-bus'),
  ('4','subscriptions/e56b7094-826f-412e-bf37-0f13a1f872cc/resourceGroups/FordLoggingPoc/providers/Microsoft.Sql/servers/cglabs-fordpoc-sqlserver/databases/cglabs-fordpoc-db');

  SELECT * FROM resourceIds
```


## Setting up Service Principal for GitHub Actions ##

While best practice is providing only the access required to perform a function via RBAC, there isn't a dedicate "out the box" role for Azure Functions. You would either need to give Contributor or create a custom role with desired permissions. For example: microsoft.web/sites/functions/read role allows you to get Web Apps Functions. microsoft.web/sites/functions/write role allows you to update Web Apps Functions, and give this to the Service Principal.

```powershell
## Build out Expected Variables (This can be prestaged)
$appName = "azureGitHubDemo-app"
$subId= "MSDN Platforms"

## Set SubscriptionId
Set-AzContext $Subscription.Id

$svcPrincipal = New-AzADServicePrincipal -DisplayName $SPName
$spObject = [PSCustomObject]@{
    clientId = $Principal.ApplicationId
    clientSecret = ($Principal.Secret | ConvertFrom-SecureString -AsPlainText)
    subscriptionId = $Subscription.Id
    tenantId = $Subscription.TenantId
}
$spObject | ConvertTo-Json

## or use AZ CLI
 az ad sp create-for-rbac --name 'GitHubActionApp' --role 'contributor' --scopes /subscriptions/e56b7094-826f-412e-bf37-0f13a1f872cc --sdk-auth

## Sample Output for $spObject
{
"clientId": "12345678-1234-abcd-1234-12345678abcd",
"clientSecret": "abcdefghijklmnopqrstuwvxyz1234567890=",
"subscriptionId": "12345678-1234-abcd-1234-12345678abcd",
"tenantId": "12345678-1234-abcd-1234-12345678abcd"
"activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
"resourceManagerEndpointUrl": "https://management.azure.com/",
"activeDirectoryGraphResourceId": "https://graph.windows.net/",
"sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
"galleryEndpointUrl": "https://gallery.azure.com/",
"managementEndpointUrl": "https://management.core.windows.net/"
}
```

## Setting up the Action YAML File ##

Documentation used in setting things up: 
- [GitHub Action: azure-login](https://github.com/marketplace/actions/azure-login)
- [GitHub Action: azure-function-action](https://github.com/marketplace/actions/azure-functions-action)
- [GitHub Action WorkFlow Samples](https://github.com/Azure/actions-workflow-samples/blob/master/FunctionApp/windows-dotnet-functionapp-on-azure-rbac.yml)
- [GitHub Action Workflow Secrets](https://github.com/Azure/actions-workflow-samples/blob/master/assets/create-secrets-for-GitHub-workflows.md)
- [Learn MSFT Connect GitHub to Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-portal%2Cwindows)
- [Learn MSFT Function References](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell?tabs=portal#configure-function-scriptfile)

```yaml
name: DeployPSFunctionPoC

on:
  pull_request:
    branches: [ "main" ]
  workflow_dispatch:

env:
  FUNCTION_NAME: 'cglabs-fordpoc-func'
  SCRIPT_PATH: '.'
  RESOURCE_GROUP: 'FordLoggingPoc'
  LOCATION: 'eastus'

jobs:
  build:
    runs-on: windows-latest
    steps:
      - name: 'Checkout Github Action'
        uses: actions/checkout@v3

      - name: 'Login Azure via SP'
        uses: Azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDS }}
          enable-AzPSSession: true

      - name: 'Deploy Function'
        uses: Azure/functions-action@v1
        id: fa
        with:
          app-name: ${{ env.FUNCTION_NAME }}
          package: ${{ env.SCRIPT_PATH}}
          publish-profile: ${{ secrets.AZURE_FUNCTIONAPP_PUBLISH_PROFILE }}

```

** Make sure that you enable Public Network Access in the SQL Server Firewall and "Allow Azure Services and Resources to access this server". This is acceptable for the PoC.. But would configure this to Private Endpoints or Dedicated App Service Plan (so you can whitelist Outbound Public IP). 


## Random Thoughts and Notes ##

1. Since getting back the HTTP Status code is a requirement for this solution. You need to use Invoke-WebRequest vs Invoke-RestMethod for the ServiceHealth API Call. This requires that you then use ConvertFrom-JSON against the [Content] that is returned by the IWR call. 

2. Connecting to the ServiceHealth API via Enterprise App (ie Service Principal) requires that you 'Grant' Microsoft Graph access for 'ServiceHealth.Read.All' permissions. This will require somebody with suitable permissions within AAD (such as Global Admin).  

3. Configure FunctionApp to use System Managed Identity.. Just easier to work with.
    1. System Managed Identity Needs to have */READ at sufficient SCOPE (Subscription/Tenant/Management Group) to allow it to query all targetted resources for the "canary" tag. 
    2. This is not required if you plan to manually pass in or feed the ResourceIds to the Code. So consider this requirement vs the ease of scaling it. 
    3. Configure SMI with Keyvault Secrets User Role (or add via Access Policy if not using RBAC)

4. When setting up SQL to use the "System Managed Identity" - the SMI will be the same name as the FunctionApp name. 


