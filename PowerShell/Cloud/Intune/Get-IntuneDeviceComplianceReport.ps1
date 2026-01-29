<
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
Requires Microsoft.Graph module with DeviceManagementManagedDevices.Read.All.
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
