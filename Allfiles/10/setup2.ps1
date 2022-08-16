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

$subscription = Get-AzSubscription -SubscriptionId $SubscriptionId
if ($null -eq $subscription) {
    throw "Error setting Azure context. Subscription not found."
}

$azContext = Set-AzContext -TenantId $subscription.TenantId -SubscriptionId $subscription.Id

$resourceGroup = Get-AzResourceGroup -ResourceGroupName $ResourceGroupName
if ($null -eq $resourceGroup) {
    throw "Resource group not found in subscription $($subscription.Name)"
}

$location = $resourceGroup.Location

$storageName = ('dp500sa' + (Get-Random -Minimum 0 -Maximum 999999 ).ToString('000000')).ToLower()
$ServerName = ('dp500server-' + (Get-Random -Minimum 0 -Maximum 999999 ).ToString('000000')).ToLower()

#Create storage accountadmin

$StorageHT = @{  
     ResourceGroupName = $ResourceGroupName
     Name              = $storageName 
     SkuName           = 'Standard_LRS'  
     Location          = $location
}
$StorageAccount = New-AzStorageAccount @StorageHT

Start-Sleep -s 120

#Upload .bacpac file to storage account

$SA = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName  -Name $storageName
$Context = $SA.Context
$ContainerName = 'dp500'
New-AzStorageContainer -Name $ContainerName -Context $Context -Permission Blob  

Start-Sleep -s 5

$bacpakPath = Join-Path (Resolve-Path '../') '00-Setup\DatabaseBackup\AdventureWorksDW2022-DP500.bacpac'

$Blob1HT = @{  
    File             = $bacpakPath
    Container        = $ContainerName  
    Blob             = "AdventureWorksDW2022-DP500.bacpac"  
    Context          = $Context  
    StandardBlobTier = 'Hot'
}

Set-AzStorageBlobContent @Blob1HT 

#Create SQL Database server

$sqlSecurePassword = ConvertTo-SecureString -String $SqlPassword -AsPlainText -Force
$SQLCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList 'sqladmin',$sqlSecurePassword

New-AzSqlServer -ServerName $ServerName -ResourceGroupName $ResourceGroupName -Location $Location -SqlAdministratorCredentials $SQLCredential
Start-Sleep -s 5

New-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $ServerName -AllowAllAzureIPs
Start-Sleep -s 5

#Import .bacpac file

New-AzSqlDatabaseImport -ResourceGroupName $ResourceGroupName -ServerName $ServerName -DatabaseName "AdventureWorksDW2022-DP500" -DatabaseMaxSizeBytes 5368709120  -StorageKeyType "StorageAccessKey" -StorageKey $(Get-AzStorageAccountKey -ResourceGroupName $ResourceGroupName -StorageAccountName $storageName).Value[0] -StorageUri "https://$($storageName).blob.core.windows.net/dp500/AdventureWorksDW2022-DP500.bacpac" -Edition "Standard" -ServiceObjectiveName "S2" -AdministratorLogin "sqladmin" -AdministratorLoginPassword $sqlSecurePassword

Start-Sleep -s 300

Write-Host "Finishing setup script at $(Get-Date)"
