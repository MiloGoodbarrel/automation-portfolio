################################################
# Author: Luis Ramirez                         #
# Created: 5-27-2021                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# This script checks if specified domain groups/users are members of the local    #
# Administrators group and adds any that are missing. Useful for maintaining      #
# consistent admin access across multiple servers without duplicating entries.    #
#                                                                                  #
# Parameters:                                                                      #
#   -RequiredAdmins: Array of groups/users that should be in local Admins         #
#   -Domain: The domain name (NetBIOS format). Defaults to current domain         #
#                                                                                  #
# Example: .\Ensure-RequiredLocalAdmins.ps1                                       #
# Example: .\Ensure-RequiredLocalAdmins.ps1 -Domain "CONTOSO"                     #
####################################################################################>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RequiredAdmins,

    [Parameter(Mandatory = $false)]
    [string]$Domain = $env:USERDOMAIN
)

# Example usage:
# .\Ensure-RequiredLocalAdmins.ps1 -RequiredAdmins "Domain Admins","IT Support"

# Verify running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

try {
    # Get current local administrators
    Write-Verbose "Retrieving current local Administrators group members..."
    $currentAdmins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop | Select-Object -ExpandProperty Name
    
    Write-Host "Current Administrators:" -ForegroundColor Cyan
    $currentAdmins | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    Write-Host ""

    # Check each required admin
    foreach ($admin in $RequiredAdmins) {
        $fullName = "$Domain\$admin"
        
        if ($currentAdmins -contains $fullName) {
            Write-Host "[EXISTS] $fullName" -ForegroundColor Green
        }
        else {
            try {
                Add-LocalGroupMember -Group "Administrators" -Member $fullName -ErrorAction Stop
                Write-Host "[ADDED] $fullName" -ForegroundColor Yellow
            }
            catch {
                Write-Warning "Failed to add $fullName : $_"
            }
        }
    }

    Write-Host "`nLocal Administrators group updated successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to process local Administrators group: $_"
    exit 1
}
