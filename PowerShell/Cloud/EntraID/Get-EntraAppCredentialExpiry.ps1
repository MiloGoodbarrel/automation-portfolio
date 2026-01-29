<#
.SYNOPSIS
Report expiring app registration credentials.

.DESCRIPTION
Uses Microsoft Graph to list app registration secrets/certificates and flags expirations.

.PARAMETER DaysThreshold
Only show credentials expiring within this many days.

.PARAMETER Connect
Connect to Microsoft Graph before running.

.EXAMPLE
Get-EntraAppCredentialExpiry.ps1 -DaysThreshold 30

.NOTES
Author: Luis Ramirez
Requires Microsoft.Graph module with Application.Read.All.

Author: Luis Ramirez
#>
#Requires -Modules Microsoft.Graph

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [int]$DaysThreshold = 60,

    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-MgGraph -Scopes "Application.Read.All"
}

$now = Get-Date
$apps = Get-MgApplication -All

$apps | ForEach-Object {
    $app = $_
    foreach ($pw in $app.PasswordCredentials) {
        $daysLeft = ([datetime]$pw.EndDateTime - $now).Days
        if ($daysLeft -le $DaysThreshold) {
            [pscustomobject]@{
                AppDisplayName = $app.DisplayName
                AppId = $app.AppId
                CredentialType = "ClientSecret"
                CredentialName = $pw.DisplayName
                EndDateTime = $pw.EndDateTime
                DaysRemaining = $daysLeft
            }
        }
    }
    foreach ($key in $app.KeyCredentials) {
        $daysLeft = ([datetime]$key.EndDateTime - $now).Days
        if ($daysLeft -le $DaysThreshold) {
            [pscustomobject]@{
                AppDisplayName = $app.DisplayName
                AppId = $app.AppId
                CredentialType = "Certificate"
                CredentialName = $key.DisplayName
                EndDateTime = $key.EndDateTime
                DaysRemaining = $daysLeft
            }
        }
    }
}
