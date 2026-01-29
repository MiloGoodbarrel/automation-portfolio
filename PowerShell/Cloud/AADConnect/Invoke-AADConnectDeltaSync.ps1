<#
Copyright (c) 2018-2026 Luis Ramirez. All rights reserved.
GitHub: https://github.com/MiloGoodbarrel/automation-portfolio

.SYNOPSIS
Trigger Azure AD Connect sync cycle.

.DESCRIPTION
Runs a Delta or Initial sync cycle on the Azure AD Connect server.

.PARAMETER PolicyType
Delta (default) or Initial.

.EXAMPLE
Invoke-AADConnectDeltaSync.ps1 -PolicyType Delta

.NOTES
Author: Luis Ramirez
Requires ADSync module (Azure AD Connect server only).

Author: Luis Ramirez
#>
#Requires -Modules ADSync

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Delta", "Initial")]
    [string]$PolicyType = "Delta"
)

if ($PSCmdlet.ShouldProcess("Azure AD Connect", "Start $PolicyType sync")) {
    Start-ADSyncSyncCycle -PolicyType $PolicyType
}
