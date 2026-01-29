<#
.SYNOPSIS
Get Azure AD Connect sync scheduler status.

.DESCRIPTION
Reports Azure AD Connect scheduler status, last/next sync times, and sync cycle settings.
Must run on the Azure AD Connect server.

.EXAMPLE
Get-AADConnectSyncStatus.ps1

.NOTES
Requires ADSync module (Azure AD Connect server only).

Author: Luis Ramirez
#>
#Requires -Modules ADSync

[CmdletBinding()]
param()

$scheduler = Get-ADSyncScheduler

[pscustomobject]@{
    SyncCycleEnabled           = $scheduler.SyncCycleEnabled
    NextSyncCyclePolicyType    = $scheduler.NextSyncCyclePolicyType
    NextSyncCycleStartTimeInUTC = $scheduler.NextSyncCycleStartTimeInUTC
    LastSyncCycleStartTimeInUTC = $scheduler.LastSyncCycleStartTimeInUTC
    LastSyncCycleEndTimeInUTC   = $scheduler.LastSyncCycleEndTimeInUTC
    StagingMode                 = $scheduler.StagingMode
    PurgeRunHistoryInterval     = $scheduler.PurgeRunHistoryInterval
}

if (Get-Command -Name Get-ADSyncConnectorRunStatus -ErrorAction SilentlyContinue) {
    Get-ADSyncConnectorRunStatus | Select-Object ConnectorName, RunStatus, LastRunTime, LastRunStatus
}
