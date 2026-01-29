<#
Copyright (c) 2018-2026 Luis Ramirez. All rights reserved.
GitHub: https://github.com/MiloGoodbarrel/automation-portfolio

.SYNOPSIS
Report Entra ID PIM eligible and active role assignments.

.DESCRIPTION
Uses Microsoft Graph to list active and eligible PIM role assignments.
You can filter by user UPN and/or role display name.

.PARAMETER UserPrincipalName
Filter results to a specific user.

.PARAMETER RoleDisplayName
Filter results to a specific role (e.g., Global Administrator).

.PARAMETER IncludeEligible
Include eligible assignments (default: on).

.PARAMETER IncludeActive
Include active assignments (default: on).

.PARAMETER Connect
Connect to Microsoft Graph before running.

.EXAMPLE
Get-EntraPIMAssignments.ps1 -UserPrincipalName "alex@contoso.com"

.EXAMPLE
Get-EntraPIMAssignments.ps1 -RoleDisplayName "Privileged Role Administrator" -IncludeEligible

.NOTES
Author: Luis Ramirez
Requires Microsoft.Graph modules and RoleManagement.Read.Directory permission.

Author: Luis Ramirez
#>
#Requires -Modules Microsoft.Graph

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserPrincipalName,

    [Parameter(Mandatory = $false)]
    [string]$RoleDisplayName,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeEligible = $true,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeActive = $true,

    [Parameter(Mandatory = $false)]
    [switch]$Connect
)

if ($Connect) {
    Connect-MgGraph -Scopes "RoleManagement.Read.Directory","Directory.Read.All"
}

$principalId = $null
if ($UserPrincipalName) {
    $user = Get-MgUser -UserId $UserPrincipalName -ErrorAction Stop
    $principalId = $user.Id
}

$roleDefinitionId = $null
if ($RoleDisplayName) {
    $roleDef = Get-MgRoleManagementDirectoryRoleDefinition -Filter "displayName eq '$RoleDisplayName'" -ErrorAction Stop
    if ($roleDef.Count -eq 0) {
        throw "Role not found: $RoleDisplayName"
    }
    $roleDefinitionId = $roleDef[0].Id
}

$results = @()

if ($IncludeActive) {
    $active = Get-MgRoleManagementDirectoryRoleAssignmentScheduleInstance -All
    if ($principalId) { $active = $active | Where-Object { $_.PrincipalId -eq $principalId } }
    if ($roleDefinitionId) { $active = $active | Where-Object { $_.RoleDefinitionId -eq $roleDefinitionId } }
    $results += $active | ForEach-Object {
        [pscustomobject]@{
            AssignmentType = "Active"
            RoleDefinitionId = $_.RoleDefinitionId
            PrincipalId = $_.PrincipalId
            DirectoryScopeId = $_.DirectoryScopeId
            StartDateTime = $_.StartDateTime
            EndDateTime = $_.EndDateTime
        }
    }
}

if ($IncludeEligible) {
    $eligible = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -All
    if ($principalId) { $eligible = $eligible | Where-Object { $_.PrincipalId -eq $principalId } }
    if ($roleDefinitionId) { $eligible = $eligible | Where-Object { $_.RoleDefinitionId -eq $roleDefinitionId } }
    $results += $eligible | ForEach-Object {
        [pscustomobject]@{
            AssignmentType = "Eligible"
            RoleDefinitionId = $_.RoleDefinitionId
            PrincipalId = $_.PrincipalId
            DirectoryScopeId = $_.DirectoryScopeId
            StartDateTime = $_.StartDateTime
            EndDateTime = $_.EndDateTime
        }
    }
}

$results | Sort-Object AssignmentType, RoleDefinitionId, PrincipalId
