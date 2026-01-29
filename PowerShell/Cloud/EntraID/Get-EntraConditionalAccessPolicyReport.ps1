<
.SYNOPSIS
Report Entra ID Conditional Access policies.

.DESCRIPTION
Uses Microsoft Graph to export Conditional Access policy settings.

.PARAMETER Connect
Connect to Microsoft Graph before running.

.EXAMPLE
.
Get-EntraConditionalAccessPolicyReport.ps1

.NOTES
Author: Luis Ramirez
Requires Microsoft.Graph module with Policy.Read.All.

Author: Luis Ramirez
#>
#Requires -Modules Microsoft.Graph

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-MgGraph -Scopes "Policy.Read.All"
}

Get-MgIdentityConditionalAccessPolicy -All | ForEach-Object {
    [pscustomobject]@{
        DisplayName   = $_.DisplayName
        State         = $_.State
        CreatedDateTime = $_.CreatedDateTime
        ModifiedDateTime = $_.ModifiedDateTime
        Conditions    = ($_.Conditions | ConvertTo-Json -Depth 6)
        GrantControls = ($_.GrantControls | ConvertTo-Json -Depth 6)
        SessionControls = ($_.SessionControls | ConvertTo-Json -Depth 6)
    }
}
