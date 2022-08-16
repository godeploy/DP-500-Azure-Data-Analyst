param(
    [Parameter(Mandatory=$true)]
    [string]
    $SubscriptionId,
    [Parameter(Mandatory=$true)]
    [string]
    $ResourceGroupName,
    [Parameter(Mandatory=$true)]
    [string]
    $SqlPassword
)

$ErrorActionPreference = 'Stop'

write-host "Starting script at $(Get-Date)"

$azContext = Get-AzContext -ErrorAction 'Stop'

Import-Module ../dp500.psm1 -Force

$subscription = Get-AzSubscription -SubscriptionId $SubscriptionId
if ($null -eq $subscription) {
    throw "Error setting Azure context. Subscription not found."
}

$azContext = Set-AzContext -TenantId $subscription.TenantId -SubscriptionId $subscription.Id

$resourceGroup = Get-AzResourceGroup -ResourceGroupName $ResourceGroupName
if ($null -eq $resourceGroup) {
    throw "Resource group not found in subscription $($subscription.Name)"
}

# Choose a random region
Write-Host "Finding an available region. This may take several minutes...";

$preferredLocations = "australiaeast","centralus","southcentralus","eastus2","northeurope","southeastasia","uksouth","westeurope","westus","westus2"
$requiredResourceProviders = "Microsoft.Synapse","Microsoft.Sql","Microsoft.Storage","Microsoft.Compute"

# Fetch locations with matching resource providers from our list of preferred locations
$locations = Get-GdAzLocationSupportingResource -RequiredResourceProvider $requiredResourceProviders -PreferredLocation $preferredLocations
Write-Host "$($locations.count)/$($preferredLocations.count) support the required resources."

# Randomise the list
$locations = $locations | Sort-Object {Get-Random}

# Get the first location with availability for SQL
$location = Get-GdAzLocationWithSqlAvailability -Locations $locations
Write-Host "Selected location $($location.Location)"

# Generate unique random suffix
$suffix = New-GdRandomString -Length 7

$sqlDatabaseName = "sqldw"
$sqlUser = "SQLUser"

# Create Synapse workspace
$synapseWorkspace = "synapsews$suffix"

write-host "Creating $synapseWorkspace Synapse Analytics workspace in $ResourceGroupName resource group..."
New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName `
  -TemplateFile "setup.json" `
  -Mode Complete `
  -workspaceName $synapseWorkspace `
  -uniqueSuffix $suffix `
  -sqlDatabaseName $sqlDatabaseName `
  -sqlUser $sqlUser `
  -sqlPassword $SqlPassword `
  -Force

# Make the current user and the Synapse service principal owners of the data lake blob store
write-host "Granting permissions on the $dataLakeAccountName storage account..."
write-host "(you can ignore any warnings!)"
$username = $azContext.Account.Id
$id = (Get-AzADServicePrincipal -DisplayName $synapseWorkspace).id
New-AzRoleAssignment -Objectid $id -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue;
New-AzRoleAssignment -SignInName $userName -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue;

# Create database
write-host "Creating the $sqlDatabaseName database..."
sqlcmd -S "$synapseWorkspace.sql.azuresynapse.net" -U $sqlUser -P $SqlPassword -d $sqlDatabaseName -I -i setup.sql

# Load data
write-host "Loading data..."
Get-ChildItem "./data/*.txt" -File | Foreach-Object {
    write-host ""
    $file = $_.FullName
    Write-Host "$file"
    $table = $_.Name.Replace(".txt","")
    bcp dbo.$table in $file -S "$synapseWorkspace.sql.azuresynapse.net" -U $sqlUser -P $SqlPassword -d $sqlDatabaseName -f $file.Replace("txt", "fmt") -q -k -E -b 5000
}

# Pause SQL Pool
write-host "Pausing the $sqlDatabaseName SQL Pool..."
Suspend-AzSynapseSqlPool -WorkspaceName $synapseWorkspace -Name $sqlDatabaseName

write-host "Script completed at $(Get-Date)"
