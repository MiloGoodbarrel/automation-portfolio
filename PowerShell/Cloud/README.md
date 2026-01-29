# Cloud Automation (Microsoft 365 / Entra ID / Azure AD Connect)

This folder contains PowerShell automation for Microsoft 365 (Exchange Online), Entra ID (Azure AD), and Azure AD Connect. These scripts are designed for enterprise use with safe defaults, detailed logging, and clear prerequisites.

## 📁 Folder Structure

```
Cloud/
├── ExchangeOnline/   # Mailboxes, delegation, shared mailbox automation
├── EntraID/          # Microsoft Graph and PIM reporting
├── Intune/           # Device compliance reporting
├── Teams/            # Team ownership and membership reporting
├── SharePoint/       # External sharing audits
└── AADConnect/       # Azure AD Connect sync status and sync triggers
```

## ✅ Included Scripts

### Exchange Online
- **Manage-EXOMailboxDelegation.ps1**
  Adds/removes/reports mailbox delegation (Full Access, Send As, Send on Behalf).

- **New-EXOSharedMailbox.ps1**
  Creates a new shared mailbox or converts an existing mailbox to shared, then assigns owners/members.

- **Set-EXOMailboxQuota.ps1**
  Sets mailbox quota limits (warning, prohibit send, prohibit send/receive).

### Entra ID / Microsoft Graph
- **Get-EntraPIMAssignments.ps1**
  Reports eligible and active PIM role assignments for a user or role.

- **Get-M365LicenseReport.ps1**
  Reports Microsoft 365 license availability and assignments.

- **Get-EntraConditionalAccessPolicyReport.ps1**
  Exports Conditional Access policy settings.

- **Get-EntraMFARegistrationReport.ps1**
  Reports MFA registration and authentication method readiness.

- **Get-EntraAppCredentialExpiry.ps1**
  Flags app registration secrets/certificates expiring soon.

### Intune
- **Get-IntuneDeviceComplianceReport.ps1**
  Reports device compliance and last sync status.

### Teams
- **Get-TeamsOwnershipReport.ps1**
  Reports Team ownership and member counts.

### SharePoint Online
- **Get-SPOExternalSharingReport.ps1**
  Reports site-level external sharing settings.

### Azure AD Connect
- **Get-AADConnectSyncStatus.ps1**
  Reports sync scheduler status and last/next sync times.

- **Invoke-AADConnectDeltaSync.ps1**
  Triggers a Delta or Initial Azure AD Connect sync cycle.

## 🔐 Authentication & Modules

These scripts require one or more of the following modules:
- **ExchangeOnlineManagement**
- **Microsoft.Graph**
- **ADSync** (Azure AD Connect server only)

Install modules as needed:
```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module Microsoft.Graph -Scope CurrentUser
```

## ⚠️ Notes

- Azure AD Connect scripts must run **on the AAD Connect server**.
- Microsoft Graph scripts require delegated permissions like `RoleManagement.Read.Directory`.
- Always test with `-WhatIf` when available.
