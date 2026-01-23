################################################
# Author: Luis Ramirez                         #
# Created: 10-6-2022                           #
# Updated: 1-22-2026                           #
################################################
<#
.SYNOPSIS
    Validates Active Directory naming conventions before deploying HRIS automation.

.DESCRIPTION
    This script checks your AD environment for compliance with the naming standards
    required for safe HRIS automation. It identifies accounts that may need to be
    renamed or have attributes corrected before enabling automated user lifecycle
    management.

.PARAMETER ReportPath
    Optional path for HTML report output. Default: current directory.

.PARAMETER FixIssues
    Switch to automatically fix certain issues (adds descriptive flags to accounts).
    WARNING: Use with caution. Review proposed changes first.

.EXAMPLE
    .\Test-ADNamingCompliance.ps1
    
    Generates compliance report to current directory.

.EXAMPLE
    .\Test-ADNamingCompliance.ps1 -ReportPath "C:\Reports\AD-Compliance.html"
    
    Saves report to specific location.

.NOTES
    Run this script BEFORE implementing HRIS automation to identify potential issues.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\AD-Naming-Compliance-$(Get-Date -Format 'yyyyMMdd-HHmmss').html",

    [Parameter(Mandatory = $false)]
    [string[]]$ElevatedPrefixes = @("SA", "DA", "GA", "PA", "EA", "ADMIN"),

    [Parameter(Mandatory = $false)]
    [string[]]$ServiceAccountPrefixes = @("svc-", "service-", "app-"),

    [Parameter(Mandatory = $false)]
    [string[]]$TemplateAccountPrefixes = @("template_", "tmpl_"),

    [Parameter(Mandatory = $false)]
    [switch]$FixIssues
)

#region Import Required Modules

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "ActiveDirectory module not found. Please install RSAT tools."
    exit 1
}

#endregion

#region Helper Functions

function Write-ComplianceReport {
    param(
        [string]$Message,
        [ValidateSet("Pass", "Warning", "Fail", "Info")]
        [string]$Status = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Status) {
        "Pass" { "Green" }
        "Warning" { "Yellow" }
        "Fail" { "Red" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] [$Status] $Message" -ForegroundColor $color
    
    return [PSCustomObject]@{
        Timestamp = $timestamp
        Status = $Status
        Message = $Message
    }
}

function Test-AccountNaming {
    param($Account, $Prefixes, $Type)
    
    foreach ($prefix in $Prefixes) {
        if ($Account.SamAccountName -like "$prefix*") {
            return $true
        }
    }
    return $false
}

#endregion

#region Main Validation

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Active Directory Naming Compliance Check" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$issues = @{
    Critical = @()
    Warning = @()
    Info = @()
}

# Get all users
Write-Host "Querying Active Directory users..." -ForegroundColor Cyan
$allUsers = Get-ADUser -Filter * -Properties EmployeeID, DistinguishedName, Description, Enabled

$stats = @{
    Total = $allUsers.Count
    WithEmployeeID = 0
    WithoutEmployeeID = 0
    ElevatedAccounts = 0
    ServiceAccounts = 0
    TemplateAccounts = 0
    StandardEmployees = 0
    Unclassified = 0
}

Write-Host "`nAnalyzing $($allUsers.Count) accounts...`n" -ForegroundColor Cyan

#region Classification Analysis

foreach ($user in $allUsers) {
    $classified = $false
    
    # Count EmployeeID statistics
    if ($user.EmployeeID) {
        $stats.WithEmployeeID++
    }
    else {
        $stats.WithoutEmployeeID++
    }
    
    # Check for elevated accounts
    if (Test-AccountNaming -Account $user -Prefixes $ElevatedPrefixes -Type "Elevated") {
        $stats.ElevatedAccounts++
        $classified = $true
        
        # CRITICAL: Elevated account has EmployeeID
        if ($user.EmployeeID) {
            $issues.Critical += [PSCustomObject]@{
                Account = $user.SamAccountName
                Issue = "Elevated account has EmployeeID (will be processed by automation!)"
                EmployeeID = $user.EmployeeID
                Recommendation = "Remove EmployeeID attribute immediately"
            }
        }
    }
    
    # Check for service accounts
    if (Test-AccountNaming -Account $user -Prefixes $ServiceAccountPrefixes -Type "Service") {
        $stats.ServiceAccounts++
        $classified = $true
        
        # CRITICAL: Service account has EmployeeID
        if ($user.EmployeeID) {
            $issues.Critical += [PSCustomObject]@{
                Account = $user.SamAccountName
                Issue = "Service account has EmployeeID (will be disabled by automation!)"
                EmployeeID = $user.EmployeeID
                Recommendation = "Remove EmployeeID attribute immediately"
            }
        }
    }
    
    # Check for template accounts
    if (Test-AccountNaming -Account $user -Prefixes $TemplateAccountPrefixes -Type "Template") {
        $stats.TemplateAccounts++
        $classified = $true
        
        # CRITICAL: Template account has EmployeeID
        if ($user.EmployeeID) {
            $issues.Critical += [PSCustomObject]@{
                Account = $user.SamAccountName
                Issue = "Template account has EmployeeID (will be processed by automation!)"
                EmployeeID = $user.EmployeeID
                Recommendation = "Remove EmployeeID attribute immediately"
            }
        }
        
        # WARNING: Template account is enabled
        if ($user.Enabled) {
            $issues.Warning += [PSCustomObject]@{
                Account = $user.SamAccountName
                Issue = "Template account is enabled (should be disabled)"
                Recommendation = "Disable this account: Disable-ADAccount -Identity '$($user.SamAccountName)'"
            }
        }
    }
    
    # Standard employee
    if (-not $classified -and $user.EmployeeID) {
        $stats.StandardEmployees++
        $classified = $true
    }
    
    # Unclassified (potential issue)
    if (-not $classified) {
        $stats.Unclassified++
        
        # WARNING: Active account without EmployeeID and no recognized prefix
        if ($user.Enabled -and $user.DistinguishedName -notlike "*OU=Service Accounts*" -and
            $user.DistinguishedName -notlike "*OU=Admin*" -and
            $user.DistinguishedName -notlike "*OU=Template*") {
            
            $issues.Warning += [PSCustomObject]@{
                Account = $user.SamAccountName
                Issue = "Active account with no EmployeeID and no recognized naming prefix"
                DistinguishedName = $user.DistinguishedName
                Recommendation = "Verify: Is this a service/admin account? Rename with proper prefix or add EmployeeID"
            }
        }
    }
}

#endregion

#region Report Results

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Account Classification Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Total Accounts: $($stats.Total)" -ForegroundColor White
Write-Host "  - With EmployeeID: $($stats.WithEmployeeID)" -ForegroundColor Green
Write-Host "  - Without EmployeeID: $($stats.WithoutEmployeeID)" -ForegroundColor Yellow
Write-Host ""
Write-Host "Account Type Breakdown:" -ForegroundColor White
Write-Host "  - Standard Employees: $($stats.StandardEmployees)" -ForegroundColor Green
Write-Host "  - Elevated Accounts: $($stats.ElevatedAccounts)" -ForegroundColor Cyan
Write-Host "  - Service Accounts: $($stats.ServiceAccounts)" -ForegroundColor Cyan
Write-Host "  - Template Accounts: $($stats.TemplateAccounts)" -ForegroundColor Cyan
Write-Host "  - Unclassified: $($stats.Unclassified)" -ForegroundColor Yellow

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Issues Found" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($issues.Critical.Count -eq 0 -and $issues.Warning.Count -eq 0) {
    Write-Host "✓ No critical issues found!" -ForegroundColor Green
    Write-Host "✓ Your AD environment appears ready for HRIS automation.`n" -ForegroundColor Green
}
else {
    Write-Host "CRITICAL ISSUES: $($issues.Critical.Count)" -ForegroundColor Red
    Write-Host "WARNINGS: $($issues.Warning.Count)" -ForegroundColor Yellow
    Write-Host ""
    
    if ($issues.Critical.Count -gt 0) {
        Write-Host "Critical Issues (MUST FIX BEFORE AUTOMATION):" -ForegroundColor Red
        $issues.Critical | Format-Table -AutoSize -Wrap
    }
    
    if ($issues.Warning.Count -gt 0) {
        Write-Host "`nWarnings (Should Review):" -ForegroundColor Yellow
        $issues.Warning | Format-Table -AutoSize -Wrap
    }
}

#endregion

#region Generate HTML Report

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>AD Naming Compliance Report - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; }
        .summary { background-color: white; padding: 20px; border-radius: 5px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .stat { display: inline-block; margin: 10px 20px; }
        .stat-label { font-weight: bold; color: #666; }
        .stat-value { font-size: 24px; color: #0078d4; }
        .critical { background-color: #fef0f0; border-left: 4px solid #dc3545; padding: 15px; margin: 10px 0; }
        .warning { background-color: #fffbf0; border-left: 4px solid #ffc107; padding: 15px; margin: 10px 0; }
        .pass { background-color: #f0fef0; border-left: 4px solid #28a745; padding: 15px; margin: 10px 0; }
        table { border-collapse: collapse; width: 100%; background-color: white; margin: 10px 0; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <h1>🔍 Active Directory Naming Compliance Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    
    <div class="summary">
        <h2>Account Statistics</h2>
        <div class="stat">
            <div class="stat-label">Total Accounts</div>
            <div class="stat-value">$($stats.Total)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Standard Employees</div>
            <div class="stat-value">$($stats.StandardEmployees)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Elevated Accounts</div>
            <div class="stat-value">$($stats.ElevatedAccounts)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Service Accounts</div>
            <div class="stat-value">$($stats.ServiceAccounts)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Template Accounts</div>
            <div class="stat-value">$($stats.TemplateAccounts)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Unclassified</div>
            <div class="stat-value">$($stats.Unclassified)</div>
        </div>
    </div>
    
    <h2>Compliance Status</h2>
"@

if ($issues.Critical.Count -eq 0 -and $issues.Warning.Count -eq 0) {
    $html += @"
    <div class="pass">
        <h3>✓ READY FOR AUTOMATION</h3>
        <p>No critical issues found. Your Active Directory environment meets the naming standards required for HRIS automation.</p>
    </div>
"@
}
else {
    $html += "<p><strong>Critical Issues:</strong> $($issues.Critical.Count) | <strong>Warnings:</strong> $($issues.Warning.Count)</p>"
    
    if ($issues.Critical.Count -gt 0) {
        $html += "<h2>❌ Critical Issues (MUST FIX)</h2>"
        $html += "<table><tr><th>Account</th><th>Issue</th><th>EmployeeID</th><th>Recommendation</th></tr>"
        foreach ($issue in $issues.Critical) {
            $html += "<tr><td>$($issue.Account)</td><td>$($issue.Issue)</td><td>$($issue.EmployeeID)</td><td>$($issue.Recommendation)</td></tr>"
        }
        $html += "</table>"
    }
    
    if ($issues.Warning.Count -gt 0) {
        $html += "<h2>⚠️ Warnings (Should Review)</h2>"
        $html += "<table><tr><th>Account</th><th>Issue</th><th>Recommendation</th></tr>"
        foreach ($issue in $issues.Warning) {
            $html += "<tr><td>$($issue.Account)</td><td>$($issue.Issue)</td><td>$($issue.Recommendation)</td></tr>"
        }
        $html += "</table>"
    }
}

$html += @"
    
    <div class="footer">
        <p><strong>Next Steps:</strong></p>
        <ol>
            <li>Fix all critical issues immediately (service/admin accounts with EmployeeID)</li>
            <li>Review warnings and reclassify accounts as needed</li>
            <li>Run this validation again to confirm compliance</li>
            <li>Test HRIS sync in dry-run mode</li>
            <li>Enable production automation</li>
        </ol>
        <p>For detailed naming standards, see <strong>AD-Naming-Standards.md</strong></p>
        <p>Generated by: Luis Ramirez | PowerShell Automation Framework</p>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $ReportPath -Encoding UTF8
Write-Host "`n✓ HTML report saved to: $ReportPath" -ForegroundColor Green

#endregion

#region Summary

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Compliance Check Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($issues.Critical.Count -gt 0) {
    Write-Host "⚠️  ACTION REQUIRED: Fix $($issues.Critical.Count) critical issue(s) before enabling automation" -ForegroundColor Red
    Write-Host "    Review the HTML report for detailed recommendations.`n" -ForegroundColor Yellow
    exit 1
}
elseif ($issues.Warning.Count -gt 0) {
    Write-Host "✓ No critical issues, but $($issues.Warning.Count) warning(s) found" -ForegroundColor Yellow
    Write-Host "  Review warnings before enabling automation.`n" -ForegroundColor Yellow
    exit 0
}
else {
    Write-Host "✓ All checks passed! Your AD environment is ready for HRIS automation." -ForegroundColor Green
    Write-Host "  Next step: Test Sync-HRIStoActiveDirectory.ps1 with -DryRun`n" -ForegroundColor Green
    exit 0
}

#endregion
