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

## Setting up GitHub ##

### Links/Docs ###
Documentation used in setting things up: 
- [GitHub Action: azure-login](https://github.com/marketplace/actions/azure-login)
- [GitHub Action: azure-function-action](https://github.com/marketplace/actions/azure-functions-action)
- [GitHub Action WorkFlow Samples](https://github.com/Azure/actions-workflow-samples/blob/master/FunctionApp/windows-dotnet-functionapp-on-azure-rbac.yml)
- [GitHub Action Workflow Secrets](https://github.com/Azure/actions-workflow-samples/blob/master/assets/create-secrets-for-GitHub-workflows.md)
- [Learn MSFT Connect GitHub to Azure](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure?tabs=azure-portal%2Cwindows)
- [Learn MSFT Function References](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-powershell?tabs=portal#configure-function-scriptfile)
- [GitHub Action Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [Events that Trigger Workflows](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows)


### Setting up Service Principal for GitHub Actions ###

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

### Setup Branch Protection ###

You can create a branch protection rule to enforce certain workflows for one or more branches, such as requiring an approving review or passing status checks for all pull requests merged into the protected branch. This is strongly recommended for [MAIN]; not allowing direct push/merge without PR and approvals.

[About Protected Branch Rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches#require-pull-request-reviews-before-merging)

1. Goto Settings - Branches - Branch Protection Rule
2. Require a PR before merging - require approvals (number)
3. Also check "Do not allow bypassing the above settings" so that admins can't bypass the PR requirement

Results in this Output:
```powershell
┏[bemitchell][main]
┖[~\repos\cglabs\azureFunctionAppPoC]> git push
Enumerating objects: 5, done.
Counting objects: 100% (5/5), done.
Delta compression using up to 8 threads
Compressing objects: 100% (3/3), done.
Writing objects: 100% (3/3), 1.32 KiB | 1.32 MiB/s, done.
Total 3 (delta 2), reused 0 (delta 0), pack-reused 0
remote: Resolving deltas: 100% (2/2), completed with 2 local objects.
remote: error: GH006: Protected branch update failed for refs/heads/main.
remote: error: Changes must be made through a pull request.
To github.com:cloudgeeklabs/azureFunctionAppPoC.git
 ! [remote rejected] main -> main (protected branch hook declined)
error: failed to push some refs to 'github.com:cloudgeeklabs/azureFunctionAppPoC.git'
```

### Workflows ###
- Workflows: Workflows are defined by a YAML file checked in to your repo and will run when triggered by a specific event. Workflows are defined in the .github/workflows directory in a repository, and a repository can have multiple workflows, each of which can perform a different set of tasks. For example, you can have one workflow to build and test pull requests, another workflow to deploy your application every time a release is created, and still another workflow that adds a label every time someone opens a new issue.
- Runner: A runner is a server that runs your workflows when they're triggered. Each runner can run a single job at a time.
- Events: An event is a specific activity in a repository that triggers a workflow run. (Such as Pull Request or Push)
- Jobs: A job is a set of steps in a workflow that execute on the same runner. You can configure a job's dependencies with other jobs; by default, jobs have no dependencies and run in parallel with each other. Jobs execute on different runners. 
- Actions: You can configure a job's dependencies with other jobs; by default, jobs have no dependencies and run in parallel with each other.


```yaml
# This is the Name of the Workflow and is displayed in GH Actions. Should be meaningful to the work being performed
name: WorkFlowName

# GitHub displays the workflow run name in the list of workflow runs on your repository's "Actions" tab. If run-name is omitted or is only whitespace, then the run name is set to event-specific information for the workflow run. For example, for a workflow triggered by a push or pull_request event, it is set as the commit message. (I kinda prefer the committed message)
run-name: deployTheCode

# You can define single or multiple events that can trigger a workflow, or set a time schedule. You can also restrict the execution of a workflow to only occur for specific files, tags, or branch changes.
on:
  push:
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

Events that can Trigger Actions: Pull Request (good for tests before merge/deploy), Push (brach/merge), Issue (open/close etc). Events are workflows and thus require One or More Jobs that are broken down into invdividual steps. 


** Make sure that you enable Public Network Access in the SQL Server Firewall and "Allow Azure Services and Resources to access this server". This is acceptable for the PoC.. But would configure this to Private Endpoints or Dedicated App Service Plan (so you can whitelist Outbound Public IP). 


## Random Thoughts and Notes ##

1. Since getting back the HTTP Status code is a requirement for this solution. You need to use Invoke-WebRequest vs Invoke-RestMethod for the ServiceHealth API Call. This requires that you then use ConvertFrom-JSON against the [Content] that is returned by the IWR call. 

2. Connecting to the ServiceHealth API via Enterprise App (ie Service Principal) requires that you 'Grant' Microsoft Graph access for 'ServiceHealth.Read.All' permissions. This will require somebody with suitable permissions within AAD (such as Global Admin).  

3. Configure FunctionApp to use System Managed Identity.. Just easier to work with.
    1. System Managed Identity Needs to have */READ at sufficient SCOPE (Subscription/Tenant/Management Group) to allow it to query all targetted resources for the "canary" tag. 
    2. This is not required if you plan to manually pass in or feed the ResourceIds to the Code. So consider this requirement vs the ease of scaling it. 
    3. Configure SMI with Keyvault Secrets User Role (or add via Access Policy if not using RBAC)

4. When setting up SQL to use the "System Managed Identity" - the SMI will be the same name as the FunctionApp name. 

5. With what this FunctionApp is doing - would look at creating an Alert to notify team if it is down or has stopped feeding telemtry data. 
