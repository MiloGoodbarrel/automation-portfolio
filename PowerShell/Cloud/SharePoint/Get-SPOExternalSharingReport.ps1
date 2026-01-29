<#
Copyright (c) 2018-2026 Luis Ramirez. All rights reserved.
GitHub: https://github.com/MiloGoodbarrel/automation-portfolio

.SYNOPSIS
Report SharePoint Online external sharing settings by site.

.DESCRIPTION
Uses SharePoint Online Management Shell to list site sharing capabilities.

.PARAMETER AdminUrl
SharePoint admin URL (e.g., https://contoso-admin.sharepoint.com).

.PARAMETER Connect
Connect to SharePoint Online before running.

.EXAMPLE
.
Get-SPOExternalSharingReport.ps1 -AdminUrl "https://contoso-admin.sharepoint.com" -Connect

.NOTES
Author: Luis Ramirez
Requires Microsoft.Online.SharePoint.PowerShell module.

Author: Luis Ramirez
#>
#Requires -Modules Microsoft.Online.SharePoint.PowerShell

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AdminUrl,

    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-SPOService -Url $AdminUrl
}

Get-SPOSite -Limit All | Select-Object \
    Url,
    Title,
    Template,
    SharingCapability,
    ExternalSharingEnabled,
    Owner
