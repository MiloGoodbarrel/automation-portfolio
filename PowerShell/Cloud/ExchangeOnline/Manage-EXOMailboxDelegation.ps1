<#
Copyright (c) 2018-2026 Luis Ramirez. All rights reserved.
GitHub: https://github.com/MiloGoodbarrel/automation-portfolio

.SYNOPSIS
Add, remove, or report Exchange Online mailbox delegation.

.DESCRIPTION
Manages Full Access, Send As, and Send on Behalf permissions for a mailbox.
Supports reporting without changes.

.PARAMETER Mailbox
Target mailbox (UPN, alias, or SMTP address).

.PARAMETER User
User to grant or remove delegation for.

.PARAMETER Permission
Delegation type: FullAccess, SendAs, or SendOnBehalf.

.PARAMETER Action
Add, Remove, or Report.

.PARAMETER AutoMapping
Enable or disable AutoMapping for FullAccess permissions.

.PARAMETER Connect
Connect to Exchange Online before running.

.EXAMPLE
Manage-EXOMailboxDelegation.ps1 -Mailbox "shared@contoso.com" -User "alex@contoso.com" -Permission FullAccess -Action Add -AutoMapping

.EXAMPLE
Manage-EXOMailboxDelegation.ps1 -Mailbox "shared@contoso.com" -Permission SendAs -Action Report

.NOTES
Author: Luis Ramirez
Requires ExchangeOnlineManagement module.

Author: Luis Ramirez
#>
#Requires -Modules ExchangeOnlineManagement

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$Mailbox,

    [Parameter(Mandatory = $false)]
    [string]$User,

    [Parameter(Mandatory = $true)]
    [ValidateSet("FullAccess", "SendAs", "SendOnBehalf")]
    [string]$Permission,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Add", "Remove", "Report")]
    [string]$Action = "Report",

    [Parameter(Mandatory = $false)]
    [switch]$AutoMapping,

    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-ExchangeOnline -ShowBanner:$false
}

if ($Action -ne "Report" -and [string]::IsNullOrWhiteSpace($User)) {
    throw "User is required when Action is Add or Remove."
}

switch ($Action) {
    "Report" {
        switch ($Permission) {
            "FullAccess" {
                Get-MailboxPermission -Identity $Mailbox | Where-Object {
                    $_.AccessRights -contains "FullAccess" -and $_.IsInherited -eq $false
                } | Select-Object Identity, User, AccessRights, IsInherited
            }
            "SendAs" {
                Get-RecipientPermission -Identity $Mailbox | Where-Object {
                    $_.AccessRights -contains "SendAs"
                } | Select-Object Identity, Trustee, AccessRights, IsInherited
            }
            "SendOnBehalf" {
                Get-Mailbox -Identity $Mailbox | Select-Object -ExpandProperty GrantSendOnBehalfTo
            }
        }
    }
    "Add" {
        switch ($Permission) {
            "FullAccess" {
                if ($PSCmdlet.ShouldProcess("$Mailbox", "Add FullAccess for $User")) {
                    Add-MailboxPermission -Identity $Mailbox -User $User -AccessRights FullAccess -AutoMapping:$AutoMapping -InheritanceType All
                }
            }
            "SendAs" {
                if ($PSCmdlet.ShouldProcess("$Mailbox", "Add SendAs for $User")) {
                    Add-RecipientPermission -Identity $Mailbox -Trustee $User -AccessRights SendAs -Confirm:$false
                }
            }
            "SendOnBehalf" {
                if ($PSCmdlet.ShouldProcess("$Mailbox", "Add SendOnBehalf for $User")) {
                    Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Add = $User}
                }
            }
        }
    }
    "Remove" {
        switch ($Permission) {
            "FullAccess" {
                if ($PSCmdlet.ShouldProcess("$Mailbox", "Remove FullAccess for $User")) {
                    Remove-MailboxPermission -Identity $Mailbox -User $User -AccessRights FullAccess -InheritanceType All -Confirm:$false
                }
            }
            "SendAs" {
                if ($PSCmdlet.ShouldProcess("$Mailbox", "Remove SendAs for $User")) {
                    Remove-RecipientPermission -Identity $Mailbox -Trustee $User -AccessRights SendAs -Confirm:$false
                }
            }
            "SendOnBehalf" {
                if ($PSCmdlet.ShouldProcess("$Mailbox", "Remove SendOnBehalf for $User")) {
                    Set-Mailbox -Identity $Mailbox -GrantSendOnBehalfTo @{Remove = $User}
                }
            }
        }
    }
}
