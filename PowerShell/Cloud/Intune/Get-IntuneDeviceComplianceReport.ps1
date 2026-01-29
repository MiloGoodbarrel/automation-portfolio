<#
Copyright (c) 2018-2026 Luis Ramirez. All rights reserved.
GitHub: https://github.com/MiloGoodbarrel/automation-portfolio

.SYNOPSIS
Report Intune managed device compliance.

.DESCRIPTION
Uses Microsoft Graph to list managed devices and their compliance state.

.PARAMETER Connect
Connect to Microsoft Graph before running.

.EXAMPLE
.
Get-IntuneDeviceComplianceReport.ps1

.NOTES
Author: Luis Ramirez
Requires Microsoft.Graph module with DeviceManagementManagedDevices.Read.All.

Author: Luis Ramirez
#>
#Requires -Modules Microsoft.Graph

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All"
}

Get-MgDeviceManagementManagedDevice -All | Select-Object \
    DeviceName,
    UserPrincipalName,
    OperatingSystem,
    OSVersion,
    ComplianceState,
    LastSyncDateTime,
    ManagementAgent,
    ManagedDeviceOwnerType
