<
.SYNOPSIS
Trigger Azure AD Connect sync cycle.

.DESCRIPTION
Runs a Delta or Initial sync cycle on the Azure AD Connect server.

.PARAMETER PolicyType
Delta (default) or Initial.

.EXAMPLE
.
Invoke-AADConnectDeltaSync.ps1 -PolicyType Delta

.NOTES
Requires ADSync module (Azure AD Connect server only).
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
