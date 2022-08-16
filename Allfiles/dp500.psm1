function Get-GdAzLocationSupportingResource {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string[]]
        $PreferredLocations,
        [Parameter(Mandatory=$true)]
        [string[]]
        $RequiredResourceProviders
    )
    process {
        $locations = Get-AzLocation
        $matchingLocations = @()
        foreach ($location in $locations) {
            if ($location.Location -notin $PreferredLocations) {
                continue
            }
            $totalMatching = 0
            foreach ($provider in $location.Providers) {
                if ($provider -in $RequiredResourceProviders) {
                    $totalMatching++
                }
            }
            if ($totalMatching = $RequiredResourceProviders.Count) {
                $matchingLocations = $matchingLocations + @($location)
            } else {
                Write-Warning "Location $($location.Location) excluded, not all resource providers are available"
            }
        }

        return $matchingLocations
    }
}

function Get-GdAzLocationWithSqlAvailability {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResourceProviderLocation[]]
        $Locations
    )
    process {
        foreach ($location in $Locations) {
            $capability = Get-AzSqlCapability -LocationName $location.Location
            if ($null -eq $capability) {
                continue
            }
            if ($capability.Status -eq "Available") {
                return $location
            }
        }

        throw "None of the given locations have SQL availability."
    }
}

function New-GdRandomString {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [int]
        $Length
    )
    process {
        return -join ((48..57) + (97..122) | Get-Random -Count $Length | ForEach-Object {[char]$_})
    }
}
