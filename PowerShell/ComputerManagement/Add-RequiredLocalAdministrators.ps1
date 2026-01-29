################################################
# Author: Luis Ramirez                         #
# Created: 5-27-2021                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# This script ensures that required domain groups and service accounts are added  #
# to the local Administrators group. It checks existing members and only adds     #
# those that are missing to prevent duplicates.                                   #
#                                                                                  #
# Parameters:                                                                      #
#   -RequiredAdmins: Array of domain groups/users that should be local admins     #
#   -Domain: The domain name (NetBIOS format). Defaults to current domain         #
#                                                                                  #
# Example: .\Add-RequiredLocalAdministrators.ps1                                  #
# Example: .\Add-RequiredLocalAdministrators.ps1 -Domain "CONTOSO"                #
###################################################################################
.NOTES
Author: Luis Ramirez
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$RequiredAdmins,

    [Parameter(Mandatory = $false)]
    [string]$Domain = $env:USERDOMAIN
)

# Example usage:
# .\Add-RequiredLocalAdministrators.ps1 -RequiredAdmins "Domain Admins","IT Support","svc-account"

# Verify running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

try {
    # Get current local administrators
    Write-Host "Retrieving current local Administrators group members..." -ForegroundColor Cyan
    $currentAdmins = Get-LocalGroupMember -Group "Administrators" -ErrorAction Stop | Select-Object -ExpandProperty Name
    
    Write-Host "`nCurrent Administrators:" -ForegroundColor Yellow
    $currentAdmins | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    Write-Host ""

    $addedMembers = @()
    $existingMembers = @()

    # Check each required admin
    foreach ($admin in $RequiredAdmins) {
        $fullName = "$Domain\$admin"
        
        if ($currentAdmins -contains $fullName) {
            Write-Host "[EXISTS] $fullName" -ForegroundColor Green
            $existingMembers += $fullName
        }
        else {
            try {
                Add-LocalGroupMember -Group "Administrators" -Member $fullName -ErrorAction Stop
                Write-Host "[ADDED] $fullName" -ForegroundColor Yellow
                $addedMembers += $fullName
            }
            catch {
                Write-Warning "Failed to add $fullName : $_"
            }
        }
    }

    # Summary
    Write-Host "`n========== SUMMARY ==========" -ForegroundColor Cyan
    Write-Host "Already existed: $($existingMembers.Count)" -ForegroundColor Green
    Write-Host "Newly added:     $($addedMembers.Count)" -ForegroundColor Yellow
    
    if ($addedMembers.Count -gt 0) {
        Write-Host "`nNewly added members:" -ForegroundColor Yellow
        $addedMembers | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }

    Write-Host "`nLocal Administrators group updated successfully" -ForegroundColor Green
}
catch {
    Write-Error "Failed to process local Administrators group: $_"
    exit 1
}
