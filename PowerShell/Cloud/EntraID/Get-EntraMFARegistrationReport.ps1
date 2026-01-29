<
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
Requires Microsoft.Graph module with Reports.Read.All.
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
