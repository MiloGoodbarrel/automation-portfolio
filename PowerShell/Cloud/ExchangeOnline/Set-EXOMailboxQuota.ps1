<#
.SYNOPSIS
Set Exchange Online mailbox quotas.

.DESCRIPTION
Sets IssueWarningQuota, ProhibitSendQuota, and ProhibitSendReceiveQuota for a mailbox.

.PARAMETER Identity
Mailbox identity (UPN, alias, or SMTP address).

.PARAMETER IssueWarningQuota
Warning threshold (e.g., 45GB).

.PARAMETER ProhibitSendQuota
Send prohibited threshold (e.g., 49GB).

.PARAMETER ProhibitSendReceiveQuota
Send/receive prohibited threshold (e.g., 50GB).

.PARAMETER Connect
Connect to Exchange Online before running.

.EXAMPLE
Set-EXOMailboxQuota.ps1 -Identity "user@contoso.com" -IssueWarningQuota 45GB -ProhibitSendQuota 49GB -ProhibitSendReceiveQuota 50GB

.NOTES
Requires ExchangeOnlineManagement module.
#>
#Requires -Modules ExchangeOnlineManagement

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Identity,

    [Parameter(Mandatory = $false)]
    [string]$IssueWarningQuota,

    [Parameter(Mandatory = $false)]
    [string]$ProhibitSendQuota,

    [Parameter(Mandatory = $false)]
    [string]$ProhibitSendReceiveQuota,

    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-ExchangeOnline -ShowBanner:$false
}

$setParams = @{}
if ($IssueWarningQuota) { $setParams.IssueWarningQuota = $IssueWarningQuota }
if ($ProhibitSendQuota) { $setParams.ProhibitSendQuota = $ProhibitSendQuota }
if ($ProhibitSendReceiveQuota) { $setParams.ProhibitSendReceiveQuota = $ProhibitSendReceiveQuota }

if ($setParams.Count -eq 0) {
    throw "Specify at least one quota parameter."
}

if ($PSCmdlet.ShouldProcess($Identity, "Set mailbox quotas")) {
    Set-Mailbox -Identity $Identity @setParams
}
