<#
Copyright (c) 2018-2026 Luis Ramirez. All rights reserved.
GitHub: https://github.com/MiloGoodbarrel/automation-portfolio

.SYNOPSIS
Create a new shared mailbox or convert an existing mailbox to shared.

.DESCRIPTION
Creates a shared mailbox in Exchange Online and optionally assigns owners and members.
Can also convert an existing mailbox to shared.

.PARAMETER DisplayName
Display name for the shared mailbox.

.PARAMETER Alias
Mailbox alias.

.PARAMETER PrimarySmtpAddress
Primary SMTP address for the shared mailbox.

.PARAMETER Owners
Owners to grant Full Access and Send As.

.PARAMETER Members
Members to grant Full Access and Send As.

.PARAMETER ConvertExisting
Convert an existing mailbox to shared instead of creating a new one.

.PARAMETER ExistingUserPrincipalName
UPN of the mailbox to convert to shared.

.PARAMETER HideFromAddressLists
Hide mailbox from the GAL.

.PARAMETER Connect
Connect to Exchange Online before running.

.EXAMPLE
New-EXOSharedMailbox.ps1 -DisplayName "IT Helpdesk" -Alias "it-help" -PrimarySmtpAddress "it-help@contoso.com" -Owners "alex@contoso.com" -Members "helpdesk1@contoso.com","helpdesk2@contoso.com"

.EXAMPLE
New-EXOSharedMailbox.ps1 -ConvertExisting -ExistingUserPrincipalName "oldshared@contoso.com" -Owners "manager@contoso.com"

.NOTES
Author: Luis Ramirez
Requires ExchangeOnlineManagement module.

Author: Luis Ramirez
#>
#Requires -Modules ExchangeOnlineManagement

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$DisplayName,

    [Parameter(Mandatory = $false)]
    [string]$Alias,

    [Parameter(Mandatory = $false)]
    [string]$PrimarySmtpAddress,

    [Parameter(Mandatory = $false)]
    [string[]]$Owners,

    [Parameter(Mandatory = $false)]
    [string[]]$Members,

    [Parameter(Mandatory = $false)]
    [switch]$ConvertExisting,

    [Parameter(Mandatory = $false)]
    [string]$ExistingUserPrincipalName,

    [Parameter(Mandatory = $false)]
    [switch]$HideFromAddressLists,

    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-ExchangeOnline -ShowBanner:$false
}

if ($ConvertExisting) {
    if ([string]::IsNullOrWhiteSpace($ExistingUserPrincipalName)) {
        throw "ExistingUserPrincipalName is required when ConvertExisting is specified."
    }
    if ($PSCmdlet.ShouldProcess($ExistingUserPrincipalName, "Convert to shared mailbox")) {
        Set-Mailbox -Identity $ExistingUserPrincipalName -Type Shared
    }
    $mailboxIdentity = $ExistingUserPrincipalName
}
else {
    foreach ($required in @($DisplayName, $Alias, $PrimarySmtpAddress)) {
        if ([string]::IsNullOrWhiteSpace($required)) {
            throw "DisplayName, Alias, and PrimarySmtpAddress are required when creating a new shared mailbox."
        }
    }
    if ($PSCmdlet.ShouldProcess($PrimarySmtpAddress, "Create shared mailbox")) {
        New-Mailbox -Shared -Name $DisplayName -DisplayName $DisplayName -Alias $Alias -PrimarySmtpAddress $PrimarySmtpAddress | Out-Null
    }
    $mailboxIdentity = $PrimarySmtpAddress
}

if ($HideFromAddressLists) {
    if ($PSCmdlet.ShouldProcess($mailboxIdentity, "Hide from address lists")) {
        Set-Mailbox -Identity $mailboxIdentity -HiddenFromAddressListsEnabled $true
    }
}

foreach ($owner in ($Owners | Where-Object { $_ })) {
    if ($PSCmdlet.ShouldProcess($mailboxIdentity, "Grant FullAccess + SendAs to owner $owner")) {
        Add-MailboxPermission -Identity $mailboxIdentity -User $owner -AccessRights FullAccess -AutoMapping:$true -InheritanceType All
        Add-RecipientPermission -Identity $mailboxIdentity -Trustee $owner -AccessRights SendAs -Confirm:$false
    }
}

foreach ($member in ($Members | Where-Object { $_ })) {
    if ($PSCmdlet.ShouldProcess($mailboxIdentity, "Grant FullAccess + SendAs to member $member")) {
        Add-MailboxPermission -Identity $mailboxIdentity -User $member -AccessRights FullAccess -AutoMapping:$true -InheritanceType All
        Add-RecipientPermission -Identity $mailboxIdentity -Trustee $member -AccessRights SendAs -Confirm:$false
    }
}
