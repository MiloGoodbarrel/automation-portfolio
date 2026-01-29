################################################
# Author: Luis Ramirez                         #
# Created: 5-27-2021                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# This script adds a list of domain groups and users to the local Administrators  #
# group on the current machine. Useful for ensuring consistent admin access       #
# across servers.                                                                  #
#                                                                                  #
# Parameters:                                                                      #
#   -DomainGroups: Array of domain groups/users to add                            #
#   -Domain: The domain name (NetBIOS format). Defaults to current domain         #
#                                                                                  #
# Example: .\Add-DomainGroupsToLocalAdmin.ps1                                     #
###################################################################################
.NOTES
Author: Luis Ramirez
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$DomainGroups,

    [Parameter(Mandatory = $false)]
    [string]$Domain = $env:USERDOMAIN
)

# Example usage:
# .\Add-DomainGroupsToLocalAdmin.ps1 -DomainGroups "Domain Admins","IT Support","svc-account"

# Verify running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

# Build full domain\group names and add to local Administrators
foreach ($group in $DomainGroups) {
    $fullName = "$Domain\$group"
    try {
        Add-LocalGroupMember -Group "Administrators" -Member $fullName -ErrorAction Stop
        Write-Host "Successfully added: $fullName" -ForegroundColor Green
    }
    catch [Microsoft.PowerShell.Commands.MemberExistsException] {
        Write-Host "Already exists: $fullName" -ForegroundColor Yellow
    }
    catch {
        Write-Warning "Failed to add $fullName : $_"
    }
}
