################################################
# Author: Luis Ramirez                         #
# Created: 6-19-2018                           #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Identifies stale computer and user objects in Active Directory for cleanup.

.DESCRIPTION
    This script finds inactive AD objects based on configurable criteria:
    
    Computer Objects:
    - Not logged in for X days (default: 90)
    - Password not changed for X days
    - Excludes: Domain controllers, servers, specific OUs
    
    User Objects:
    - Not logged in for X days (default: 60)
    - Never logged in (potential orphaned accounts)
    - Excludes: Service accounts, elevated accounts, disabled accounts
    
    Safety Features:
    - Dry-run mode (default)
    - Export to CSV before any action
    - Exclude lists (OUs, naming patterns)
    - Approval workflow option
    
.PARAMETER ObjectType
    Type of objects to find: Computer, User, or Both

.PARAMETER InactiveDays
    Number of days of inactivity to consider stale
    
.PARAMETER ExcludeOUs
    Array of OUs to exclude from search

.PARAMETER ExcludePatterns
    Array of name patterns to exclude (e.g., "svc-*", "SA*")

.PARAMETER ExportPath
    Path for CSV export

.PARAMETER DryRun
    Show what would be found without taking action (default: true)

.EXAMPLE
    .\Find-StaleADObjects.ps1 -ObjectType Computer -InactiveDays 90
    
    Find computers inactive for 90+ days (dry-run).

.EXAMPLE
    .\Find-StaleADObjects.ps1 -ObjectType User -InactiveDays 60 -ExportPath "C:\Reports\stale-users.csv"
    
    Find inactive users and export to CSV.

.NOTES
    Requires:
    - ActiveDirectory module
    - Read permissions on AD
    
    Best Practice:
    - Run as dry-run first
    - Review export file
    - Get management approval
    - Use Remove-StaleComputersWorkflow.ps1 for staged deletion
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Computer", "User", "Both")]
    [string]$ObjectType = "Both",

    [Parameter(Mandatory = $false)]
    [int]$InactiveDaysComputer = 90,

    [Parameter(Mandatory = $false)]
    [int]$InactiveDaysUser = 60,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeOUs = @("OU=Domain Controllers", "OU=Servers", "OU=Service Accounts", "OU=Admin Accounts"),

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeComputerPatterns = @("DC*", "*-SRV-*", "*-SQL-*", "*-EXCH-*"),

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeUserPatterns = @("svc-*", "SA*", "DA*", "GA*", "PA*", "template_*", "admin*"),

    [Parameter(Mandatory = $false)]
    [string]$ExportPath = ".\Stale-ADObjects-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeNeverLoggedOn,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

#region Import Module

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "ActiveDirectory module required. Install RSAT tools."
    exit 1
}

#endregion

#region Helper Functions

function Write-StaleLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Success")]
        [string]$Level = "Info"
    )
    
    $color = switch ($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        default { "White" }
    }
    
    Write-Host $Message -ForegroundColor $color
}

function Test-ExcludedObject {
    param(
        $ADObject,
        [string[]]$Patterns,
        [string[]]$OUs
    )
    
    # Check OU exclusions
    foreach ($ou in $OUs) {
        if ($ADObject.DistinguishedName -like "*$ou*") {
            return $true, "In excluded OU: $ou"
        }
    }
    
    # Check name pattern exclusions
    foreach ($pattern in $Patterns) {
        if ($ADObject.Name -like $pattern) {
            return $true, "Matches excluded pattern: $pattern"
        }
    }
    
    return $false, ""
}

#endregion

#region Main Script

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Stale AD Object Discovery" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($DryRun) {
    Write-StaleLog "⚠️  DRY-RUN MODE - No changes will be made" -Level Warning
}

$staleObjects = @()
$excludedCount = 0
$cutoffDate = (Get-Date).AddDays(-$InactiveDaysComputer)
$userCutoffDate = (Get-Date).AddDays(-$InactiveDaysUser)

#region Find Stale Computers

if ($ObjectType -eq "Computer" -or $ObjectType -eq "Both") {
    Write-StaleLog "`nSearching for stale computer objects..." -Level Info
    Write-StaleLog "  Inactive for: $InactiveDaysComputer+ days (since $($cutoffDate.ToString('yyyy-MM-dd')))" -Level Info
    
    $computers = Get-ADComputer -Filter * -Properties LastLogonDate, PasswordLastSet, OperatingSystem, Description, Enabled |
        Where-Object { $_.LastLogonDate -lt $cutoffDate -or $null -eq $_.LastLogonDate }
    
    Write-StaleLog "  Found $($computers.Count) potentially stale computers" -Level Info
    
    foreach ($computer in $computers) {
        $excluded, $reason = Test-ExcludedObject -ADObject $computer -Patterns $ExcludeComputerPatterns -OUs $ExcludeOUs
        
        if ($excluded) {
            $excludedCount++
            Write-Verbose "EXCLUDED: $($computer.Name) - $reason"
            continue
        }
        
        # Additional safety: Skip if it's a server OS
        if ($computer.OperatingSystem -match "Server") {
            $excludedCount++
            Write-Verbose "EXCLUDED: $($computer.Name) - Server OS detected"
            continue
        }
        
        $daysSinceLogon = if ($computer.LastLogonDate) {
            ((Get-Date) - $computer.LastLogonDate).Days
        } else {
            "Never"
        }
        
        $staleObjects += [PSCustomObject]@{
            Type = "Computer"
            Name = $computer.Name
            DistinguishedName = $computer.DistinguishedName
            LastLogonDate = $computer.LastLogonDate
            DaysSinceLogon = $daysSinceLogon
            PasswordLastSet = $computer.PasswordLastSet
            OperatingSystem = $computer.OperatingSystem
            Description = $computer.Description
            Enabled = $computer.Enabled
            RecommendedAction = "Disable and move to staging OU"
        }
    }
    
    Write-StaleLog "  Stale computers found: $($staleObjects.Where({$_.Type -eq 'Computer'}).Count)" -Level Warning
    Write-StaleLog "  Excluded (DCs/servers/protected): $excludedCount" -Level Info
}

#endregion

#region Find Stale Users

if ($ObjectType -eq "User" -or $ObjectType -eq "Both") {
    Write-StaleLog "`nSearching for stale user objects..." -Level Info
    Write-StaleLog "  Inactive for: $InactiveDaysUser+ days (since $($userCutoffDate.ToString('yyyy-MM-dd')))" -Level Info
    
    $users = Get-ADUser -Filter * -Properties LastLogonDate, PasswordLastSet, EmployeeID, Description, Enabled, WhenCreated |
        Where-Object { 
            ($_.LastLogonDate -lt $userCutoffDate -or $null -eq $_.LastLogonDate) -and
            $_.Enabled -eq $true  # Only look at enabled accounts
        }
    
    Write-StaleLog "  Found $($users.Count) potentially stale users" -Level Info
    
    $userExcludedCount = 0
    
    foreach ($user in $users) {
        $excluded, $reason = Test-ExcludedObject -ADObject $user -Patterns $ExcludeUserPatterns -OUs $ExcludeOUs
        
        if ($excluded) {
            $userExcludedCount++
            Write-Verbose "EXCLUDED: $($user.SamAccountName) - $reason"
            continue
        }
        
        # Exclude accounts with no EmployeeID (likely service/admin accounts)
        if (-not $user.EmployeeID) {
            $userExcludedCount++
            Write-Verbose "EXCLUDED: $($user.SamAccountName) - No EmployeeID (likely service/admin account)"
            continue
        }
        
        $daysSinceLogon = if ($user.LastLogonDate) {
            ((Get-Date) - $user.LastLogonDate).Days
        } else {
            if ($IncludeNeverLoggedOn) {
                "Never"
            } else {
                $userExcludedCount++
                continue  # Skip never logged on unless specifically requested
            }
        }
        
        $staleObjects += [PSCustomObject]@{
            Type = "User"
            Name = $user.SamAccountName
            DisplayName = $user.Name
            DistinguishedName = $user.DistinguishedName
            LastLogonDate = $user.LastLogonDate
            DaysSinceLogon = $daysSinceLogon
            PasswordLastSet = $user.PasswordLastSet
            EmployeeID = $user.EmployeeID
            Description = $user.Description
            Enabled = $user.Enabled
            WhenCreated = $user.WhenCreated
            RecommendedAction = "Verify with HRIS, then disable"
        }
    }
    
    Write-StaleLog "  Stale users found: $($staleObjects.Where({$_.Type -eq 'User'}).Count)" -Level Warning
    Write-StaleLog "  Excluded (service/admin/no EmployeeID): $userExcludedCount" -Level Info
}

#endregion

#region Results Summary

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-StaleLog "Total stale objects found: $($staleObjects.Count)" -Level Warning
if ($staleObjects.Count -gt 0) {
    Write-StaleLog "  Computers: $($staleObjects.Where({$_.Type -eq 'Computer'}).Count)" -Level Info
    Write-StaleLog "  Users: $($staleObjects.Where({$_.Type -eq 'User'}).Count)" -Level Info
}

if ($staleObjects.Count -eq 0) {
    Write-StaleLog "`n✓ No stale objects found matching criteria!" -Level Success
    exit 0
}

# Show top 10 oldest
Write-Host "`nTop 10 Oldest Objects:" -ForegroundColor Cyan
$staleObjects | Sort-Object LastLogonDate | Select-Object -First 10 |
    Format-Table Type, Name, LastLogonDate, DaysSinceLogon, RecommendedAction -AutoSize

#endregion

#region Export

Write-StaleLog "`nExporting to CSV: $ExportPath" -Level Info
$staleObjects | Export-Csv -Path $ExportPath -NoTypeInformation
Write-StaleLog "✓ Export complete: $($staleObjects.Count) objects" -Level Success

#endregion

#region Recommendations

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Next Steps" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "1. Review exported CSV file" -ForegroundColor Yellow
Write-Host "2. Get management approval for cleanup" -ForegroundColor Yellow
Write-Host "3. Use Remove-StaleComputersWorkflow.ps1 for staged cleanup:" -ForegroundColor Yellow
Write-Host "   .\Remove-StaleComputersWorkflow.ps1 -CSVFile '$ExportPath' -Stage Disable" -ForegroundColor White
Write-Host "`n4. Or manually disable individual objects:" -ForegroundColor Yellow
Write-Host "   Disable-ADAccount -Identity 'COMPUTER-NAME'" -ForegroundColor White
Write-Host "   Set-ADComputer -Identity 'COMPUTER-NAME' -Description 'Disabled $(Get-Date -Format yyyy-MM-dd) - Stale object'" -ForegroundColor White

Write-Host "`n⚠️  IMPORTANT: Always verify with asset management/HRIS before deletion`n" -ForegroundColor Red

#endregion
