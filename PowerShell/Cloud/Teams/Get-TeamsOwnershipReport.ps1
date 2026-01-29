<
.SYNOPSIS
Report Microsoft Teams ownership and member counts.

.DESCRIPTION
Uses Microsoft Graph to list Teams (Microsoft 365 groups) and their owners.

.PARAMETER Connect
Connect to Microsoft Graph before running.

.EXAMPLE
.
Get-TeamsOwnershipReport.ps1

.NOTES
Author: Luis Ramirez
Requires Microsoft.Graph module with Group.Read.All.

Author: Luis Ramirez
#>
#Requires -Modules Microsoft.Graph

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-MgGraph -Scopes "Group.Read.All"
}

$teams = Get-MgGroup -All -Filter "resourceProvisioningOptions/Any(x:x eq 'Team')" -Property Id,DisplayName

$teams | ForEach-Object {
    $owners = Get-MgGroupOwner -GroupId $_.Id -All | Select-Object -ExpandProperty UserPrincipalName
    $members = Get-MgGroupMember -GroupId $_.Id -All

    [pscustomobject]@{
        TeamName = $_.DisplayName
        OwnerUPNs = ($owners -join ";")
        MemberCount = $members.Count
    }
}
