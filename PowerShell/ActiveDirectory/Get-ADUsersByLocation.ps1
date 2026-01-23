################################################
# Author: Luis Ramirez                         #
# Created: 5-27-2021                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# This script queries Active Directory for enabled users in specific geographic   #
# OUs and exports their details to a log file. Useful for auditing user accounts  #
# across multiple international locations.                                        #
#                                                                                  #
# Parameters:                                                                      #
#   -Locations: Array of location names to query (must match OU names)            #
#   -SearchBase: Base OU path for searches. Use {0} as placeholder for location   #
#   -OutputFile: Path to output log file (default: Documents folder)              #
#   -Properties: Array of AD user properties to retrieve                          #
#                                                                                  #
# Example: .\Get-ADUsersByLocation.ps1                                            #
# Example: .\Get-ADUsersByLocation.ps1 -Locations "Australia","Canada"            #
####################################################################################>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Locations,

    [Parameter(Mandatory = $true)]
    [string]$SearchBase,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "$env:USERPROFILE\Documents\ADUsersByLocation.log",

    [Parameter(Mandatory = $false)]
    [string[]]$Properties = @(
        "GivenName", "Surname", "UserPrincipalName", "sAMAccountName",
        "physicalDeliveryOfficeName", "ou", "manager", "title"
    )
)

# Example usage:
# .\Get-ADUsersByLocation.ps1 -Locations "New York","London","Tokyo" -SearchBase "OU={0},OU=Users,DC=contoso,DC=com"

# Import Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "Failed to load ActiveDirectory module. Ensure RSAT tools are installed."
    exit 1
}

# Clear existing log file
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile -Force
    Write-Host "Cleared existing log file: $OutputFile" -ForegroundColor Yellow
}

Write-Host "Querying AD users from $($Locations.Count) location(s)..." -ForegroundColor Cyan
Write-Host "Output file: $OutputFile`n" -ForegroundColor Gray

$totalUsers = 0

foreach ($location in $Locations) {
    $searchOU = $SearchBase -f $location
    
    Write-Host "Processing: $location" -ForegroundColor Green
    Write-Verbose "Search Base: $searchOU"
    
    try {
        $users = Get-ADUser -Filter { Enabled -eq $true } `
            -Properties * `
            -SearchBase $searchOU `
            -SearchScope 2 `
            -ErrorAction Stop |
            Select-Object $Properties |
            Sort-Object GivenName
        
        if ($users) {
            $userCount = ($users | Measure-Object).Count
            $totalUsers += $userCount
            
            # Add location header to log
            "`n========== $location ($userCount users) ==========" | Add-Content $OutputFile
            
            # Format and append to log
            $users | Format-Table -AutoSize | Out-String | Add-Content $OutputFile
            
            Write-Host "  Found $userCount user(s)" -ForegroundColor Gray
        }
        else {
            Write-Host "  No enabled users found" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Warning "Failed to query $location : $_"
        "ERROR querying $location : $_" | Add-Content $OutputFile
    }
}

Write-Host "`nTotal users found: $totalUsers" -ForegroundColor Cyan
Write-Host "Results saved to: $OutputFile" -ForegroundColor Green
