<#
Copyright (c) 2018-2026 Luis Ramirez. All rights reserved.
GitHub: https://github.com/MiloGoodbarrel/automation-portfolio

.SYNOPSIS
Report MFA registration status for users.

.DESCRIPTION
Uses Microsoft Graph Reports to list user MFA registration details.

.PARAMETER Connect
Connect to Microsoft Graph before running.

.EXAMPLE
.
Get-EntraMFARegistrationReport.ps1

.NOTES
Author: Luis Ramirez
Requires Microsoft.Graph module with Reports.Read.All.

Author: Luis Ramirez
#>
#Requires -Modules Microsoft.Graph

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-MgGraph -Scopes "Reports.Read.All"
}

Get-MgReportAuthenticationMethodsUserRegistrationDetail -All | Select-Object \
    UserDisplayName,
    UserPrincipalName,
    IsMfaRegistered,
    IsMfaCapable,
    IsPasswordlessCapable,
    IsSsprCapable,
    IsSsprEnabled,
    DefaultMfaMethod,
    MethodsRegistered,
    LastUpdatedDateTime
