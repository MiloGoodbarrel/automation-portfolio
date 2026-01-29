################################################
# Author: Luis Ramirez                         #
# Created: 5-27-2021                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# This script imports a CSV file containing JDE user IDs and cross-references     #
# them with Active Directory to verify account existence and status. Useful for   #
# user account reconciliation and compliance auditing.                            #
#                                                                                  #
# Parameters:                                                                      #
#   -JDEUserCSV: Path to CSV with JDE user IDs (must have 'userid' column)        #
#   -OutputFile: Path to output CSV for reconciliation results                    #
#                                                                                  #
# Example: .\Compare-JDEUsersWithAD.ps1                                           #
# Example: .\Compare-JDEUsersWithAD.ps1 -JDEUserCSV "C:\Data\users.csv"           #
###################################################################################
.NOTES
Author: Luis Ramirez
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$JDEUserCSV,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = "$env:USERPROFILE\Documents\reconciliation.csv"
)

# Example usage:
# .\Compare-JDEUsersWithAD.ps1 -JDEUserCSV "C:\Data\jdeusers.csv" -OutputFile "C:\Reports\reconciliation.csv"

Clear-Host

# Import Active Directory module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "Failed to load ActiveDirectory module. Ensure RSAT tools are installed."
    exit 1
}

# Verify input file exists
if (-not (Test-Path $JDEUserCSV)) {
    Write-Error "JDE user CSV file not found: $JDEUserCSV"
    exit 1
}

# Clear existing output file
if (Test-Path $OutputFile) {
    Remove-Item $OutputFile -Force
    Write-Host "Cleared existing output file" -ForegroundColor Yellow
}

Write-Host "Importing JDE users from: $JDEUserCSV" -ForegroundColor Cyan
$jdeUsers = Import-Csv $JDEUserCSV

if (-not $jdeUsers) {
    Write-Error "No users found in CSV file or invalid format"
    exit 1
}

Write-Host "Processing $($jdeUsers.Count) JDE user(s)...`n" -ForegroundColor Cyan

$results = @()

foreach ($jdeUser in $jdeUsers) {
    $jdeId = $jdeUser.userid
    
    Write-Host "Checking: $jdeId" -ForegroundColor Gray
    
    try {
        # Search for matching AD user
        $adUser = Get-ADUser -Filter "SamAccountName -like '*$jdeId*'" `
            -Properties SamAccountName, Enabled `
            -ErrorAction Stop
        
        if ($adUser) {
            # Account found
            $result = [PSCustomObject]@{
                JDEUser        = $jdeId
                SamAccountName = $adUser.SamAccountName
                Enabled        = $adUser.Enabled
                Status         = if ($adUser.Enabled) { "Active" } else { "Disabled" }
            }
            Write-Host "  Found: $($adUser.SamAccountName) - Enabled: $($adUser.Enabled)" -ForegroundColor Green
        }
        else {
            # Account not found
            $result = [PSCustomObject]@{
                JDEUser        = $jdeId
                SamAccountName = "Not Found"
                Enabled        = $false
                Status         = "Account does not exist"
            }
            Write-Host "  NOT FOUND in Active Directory" -ForegroundColor Red
        }
    }
    catch {
        # Error during query
        $result = [PSCustomObject]@{
            JDEUser        = $jdeId
            SamAccountName = "Error"
            Enabled        = $false
            Status         = "Query Error: $_"
        }
        Write-Warning "  Error querying AD: $_"
    }
    
    $results += $result
}

# Export results to CSV
Write-Host "`nExporting results to: $OutputFile" -ForegroundColor Cyan
$results | Export-Csv -Path $OutputFile -NoTypeInformation

# Display summary
Write-Host "`n========== SUMMARY ==========" -ForegroundColor Yellow
$totalUsers = $results.Count
$foundUsers = ($results | Where-Object { $_.SamAccountName -ne "Not Found" -and $_.SamAccountName -ne "Error" }).Count
$activeUsers = ($results | Where-Object { $_.Enabled -eq $true }).Count
$missingUsers = ($results | Where-Object { $_.Status -eq "Account does not exist" }).Count

Write-Host "Total JDE Users:     $totalUsers" -ForegroundColor Cyan
Write-Host "Found in AD:         $foundUsers" -ForegroundColor Green
Write-Host "Active Accounts:     $activeUsers" -ForegroundColor Green
Write-Host "Missing Accounts:    $missingUsers" -ForegroundColor Red
Write-Host "Results saved to:    $OutputFile" -ForegroundColor Gray
