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

$azContext = Get-AzContext -ErrorAction 'Stop'

write-host "Starting script at $(Get-Date)"

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

$sqlUser = "SQLUser"

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
Write-Host "Your randomly-generated suffix for Azure resources is $suffix"

# Create Synapse workspace
$synapseWorkspace = "synapse$suffix"
$dataLakeAccountName = "datalake$suffix"

write-host "Creating $synapseWorkspace Synapse Analytics workspace in $resourceGroupName resource group..."
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
  -TemplateFile "setup.json" `
  -Mode Complete `
  -workspaceName $synapseWorkspace `
  -dataLakeAccountName $dataLakeAccountName `
  -sqlUser $sqlUser `
  -sqlPassword $sqlPassword `
  -uniqueSuffix $suffix `
  -Force

# Make the current user and the Synapse service principal owners of the data lake blob store
write-host "Granting permissions on the $dataLakeAccountName storage account..."
write-host "(you can ignore any warnings!)"
$userName = $azContext.Account.Id
$id = (Get-AzADServicePrincipal -DisplayName $synapseWorkspace).id
New-AzRoleAssignment -Objectid $id -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$SubscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue;
New-AzRoleAssignment -SignInName $userName -RoleDefinitionName "Storage Blob Data Owner" -Scope "/subscriptions/$SubscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.Storage/storageAccounts/$dataLakeAccountName" -ErrorAction SilentlyContinue;

# Upload files
write-host "Loading data..."
$storageAccount = Get-AzStorageAccount -ResourceGroupName $resourceGroupName -Name $dataLakeAccountName
$storageContext = $storageAccount.Context
Get-ChildItem "./data/*.csv" -File | Foreach-Object {
    write-host ""
    $file = $_.Name
    Write-Host $file
    $blobPath = "sales/csv/$file"
    Set-AzStorageBlobContent -File $_.FullName -Container "files" -Blob $blobPath -Context $storageContext
}

Get-ChildItem "./data/*.parquet" -File | Foreach-Object {
    write-host ""
    Write-Host $_.Name
    $folder = $_.Name.Replace(".snappy.parquet", "")
    $file = $_.Name.Replace($folder, "orders")
    $blobPath = "sales/parquet/year=$folder/$file"
    Set-AzStorageBlobContent -File $_.FullName -Container "files" -Blob $blobPath -Context $storageContext
}

Get-ChildItem "./data/*.json" -File | Foreach-Object {
    write-host ""
    $file = $_.Name
    Write-Host $file
    $blobPath = "sales/json/$file"
    Set-AzStorageBlobContent -File $_.FullName -Container "files" -Blob $blobPath -Context $storageContext
}

write-host "Script completed at $(Get-Date)"
