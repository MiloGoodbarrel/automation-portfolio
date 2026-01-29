<#
Copyright (c) 2018-2026 Luis Ramirez. All rights reserved.
GitHub: https://github.com/MiloGoodbarrel/automation-portfolio

.SYNOPSIS
Report Microsoft 365 license usage and assignments.

.DESCRIPTION
Uses Microsoft Graph to list subscribed SKUs and users with assigned licenses.
Outputs per-SKU consumption and optional user-level details.

.PARAMETER IncludeUserDetails
Include user-level license assignments.

.PARAMETER Connect
Connect to Microsoft Graph before running.

.EXAMPLE
.
Get-M365LicenseReport.ps1

.EXAMPLE
.
Get-M365LicenseReport.ps1 -IncludeUserDetails

.NOTES
Author: Luis Ramirez
Requires Microsoft.Graph module with Organization.Read.All, User.Read.All.

Author: Luis Ramirez
#>
#Requires -Modules Microsoft.Graph

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$IncludeUserDetails,

    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-MgGraph -Scopes "Organization.Read.All","User.Read.All"
}

$skus = Get-MgSubscribedSku -All

$skuReport = $skus | ForEach-Object {
    [pscustomobject]@{
        SkuPartNumber   = $_.SkuPartNumber
        SkuId           = $_.SkuId
        EnabledUnits    = $_.PrepaidUnits.Enabled
        ConsumedUnits   = $_.ConsumedUnits
        SuspendedUnits  = $_.PrepaidUnits.Suspended
        WarningUnits    = $_.PrepaidUnits.Warning
        AvailableUnits  = ($_.PrepaidUnits.Enabled - $_.ConsumedUnits)
    }
}

$skuReport

if ($IncludeUserDetails) {
    $users = Get-MgUser -All -Property Id,DisplayName,UserPrincipalName,AssignedLicenses
    $users | Where-Object { $_.AssignedLicenses.Count -gt 0 } | ForEach-Object {
        [pscustomobject]@{
            DisplayName = $_.DisplayName
            UserPrincipalName = $_.UserPrincipalName
            SkuIds = ($_.AssignedLicenses | ForEach-Object { $_.SkuId }) -join ";"
        }
    }
}
