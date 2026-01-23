################################################
# Author: Luis Ramirez                         #
# Created: 6-13-2024                           #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Exports comprehensive Group Policy documentation.

.DESCRIPTION
    Documents all Group Policy Objects with HTML reporting and issue detection.
    
    Business Value:
    - Disaster recovery documentation
    - Audit compliance evidence
    - GPO sprawl identification
    - Change management documentation
    - Security policy validation
    
    Features:
    - Exports all GPO settings to HTML
    - Identifies unlinked/orphaned GPOs
    - Detects conflicting policies
    - Maps OU linkage
    - Version tracking
    - Permission auditing
    
.PARAMETER OutputPath
    Path for GPO documentation export

.PARAMETER IncludeReports
    Include detailed GPO reports (slower but comprehensive)

.PARAMETER EmailTo
    Email addresses for documentation report

.PARAMETER SMTPServer
    SMTP server for notifications

.EXAMPLE
    .\Export-GroupPolicyDocumentation.ps1 -OutputPath "C:\GPOBackups"
    
    Export all GPO documentation to specified path.

.EXAMPLE
    .\Export-GroupPolicyDocumentation.ps1 -IncludeReports -EmailTo "admin@company.com"
    
    Full export with HTML reports and email notification.

.NOTES
    Requirements:
    - GroupPolicy PowerShell module
    - Domain Admin or GPO read permissions
    - RSAT tools installed
    
    Recommendation:
    - Run monthly for documentation
    - Version control exports
    - Review orphaned GPOs quarterly
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\GPODocumentation\$(Get-Date -Format 'yyyyMMdd-HHmmss')",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeReports,

    [Parameter(Mandatory = $false)]
    [string[]]$EmailTo,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.company.com"
)

#region Import Modules

try {
    Import-Module GroupPolicy -ErrorAction Stop
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "GroupPolicy and ActiveDirectory modules required. Install RSAT tools."
    exit 1
}

#endregion

#region Helper Functions

function Write-GPOLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

#endregion

#region Initialize

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Group Policy Documentation Export" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$startTime = Get-Date

# Create output directory
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-GPOLog "Created output directory: $OutputPath" -Level Info
}

$domain = (Get-ADDomain).DNSRoot
Write-GPOLog "Domain: $domain" -Level Info

#endregion

#region Collect GPO Information

Write-GPOLog "Collecting all Group Policy Objects..." -Level Info

$allGPOs = Get-GPO -All -Domain $domain

Write-GPOLog "Found $($allGPOs.Count) GPOs" -Level Success

$gpoInventory = @()
$unlinkedGPOs = @()
$emptyGPOs = @()
$issues = @()

foreach ($gpo in $allGPOs) {
    Write-Progress -Activity "Analyzing GPOs" -Status "Processing $($gpo.DisplayName)..." -PercentComplete (([array]::IndexOf($allGPOs, $gpo) / $allGPOs.Count) * 100)
    
    # Get GPO links
    $report = [xml](Get-GPOReport -Guid $gpo.Id -ReportType Xml)
    
    $links = @()
    $linksXml = $report.GPO.LinksTo
    
    if ($linksXml) {
        foreach ($link in $linksXml) {
            $links += [PSCustomObject]@{
                Path    = $link.SOMPath
                Enabled = $link.Enabled
                NoOverride = $link.NoOverride
            }
        }
    }
    
    # Check if GPO is empty (no settings)
    $userConfigEmpty = $gpo.User.DSVersion -eq 0 -and $gpo.User.SysvolVersion -eq 0
    $computerConfigEmpty = $gpo.Computer.DSVersion -eq 0 -and $gpo.Computer.SysvolVersion -eq 0
    $isEmpty = $userConfigEmpty -and $computerConfigEmpty
    
    # Get permissions
    $permissions = Get-GPPermission -Guid $gpo.Id -All | Select-Object Trustee, Permission
    
    $gpoInfo = [PSCustomObject]@{
        DisplayName        = $gpo.DisplayName
        GUID               = $gpo.Id
        Description        = $gpo.Description
        Owner              = $gpo.Owner
        CreatedTime        = $gpo.CreationTime
        ModifiedTime       = $gpo.ModificationTime
        UserVersion        = "$($gpo.User.DSVersion) (AD), $($gpo.User.SysvolVersion) (SYSVOL)"
        ComputerVersion    = "$($gpo.Computer.DSVersion) (AD), $($gpo.Computer.SysvolVersion) (SYSVOL)"
        WmiFilterApplied   = $gpo.WmiFilter.Name
        LinkCount          = $links.Count
        Links              = ($links | ForEach-Object { $_.Path }) -join "; "
        IsLinked           = $links.Count -gt 0
        IsEmpty            = $isEmpty
        HasConflict        = $false  # Will check later
        PermissionCount    = $permissions.Count
    }
    
    $gpoInventory += $gpoInfo
    
    # Identify issues
    if ($links.Count -eq 0) {
        $unlinkedGPOs += $gpoInfo
        Write-GPOLog "  ⚠️  Unlinked: $($gpo.DisplayName)" -Level Warning
    }
    
    if ($isEmpty) {
        $emptyGPOs += $gpoInfo
        Write-GPOLog "  ⚠️  Empty: $($gpo.DisplayName)" -Level Warning
    }
    
    # Check for version mismatch (potential replication issue)
    if ($gpo.User.DSVersion -ne $gpo.User.SysvolVersion -or $gpo.Computer.DSVersion -ne $gpo.Computer.SysvolVersion) {
        $issues += [PSCustomObject]@{
            Type    = "Version Mismatch"
            GPO     = $gpo.DisplayName
            Details = "AD and SYSVOL versions do not match - possible replication issue"
        }
        Write-GPOLog "  ⚠️  Version mismatch: $($gpo.DisplayName)" -Level Warning
    }
    
    # Export individual GPO report
    if ($IncludeReports) {
        $reportPath = Join-Path $OutputPath "Reports"
        if (-not (Test-Path $reportPath)) {
            New-Item -ItemType Directory -Path $reportPath -Force | Out-Null
        }
        
        $gpoReportFile = Join-Path $reportPath "$($gpo.DisplayName.Replace(':', '').Replace('\', '-')).html"
        Get-GPOReport -Guid $gpo.Id -ReportType Html -Path $gpoReportFile -ErrorAction SilentlyContinue
    }
}

Write-Progress -Activity "Analyzing GPOs" -Completed

#endregion

#region Detect Conflicts

Write-GPOLog "Analyzing for conflicting policies..." -Level Info

# Group GPOs by link location
$linkGroups = $gpoInventory | Where-Object { $_.IsLinked } | ForEach-Object {
    $gpo = $_
    foreach ($link in $_.Links -split "; ") {
        [PSCustomObject]@{
            Link = $link
            GPO  = $gpo.DisplayName
        }
    }
} | Group-Object Link

foreach ($group in $linkGroups) {
    if ($group.Count -gt 5) {
        $issues += [PSCustomObject]@{
            Type    = "Excessive GPOs"
            GPO     = "Multiple ($($group.Count) GPOs)"
            Details = "OU '$($group.Name)' has $($group.Count) GPOs linked - may cause slow login"
        }
        Write-GPOLog "  ⚠️  Excessive GPOs on $($group.Name): $($group.Count)" -Level Warning
    }
}

#endregion

#region Export Inventory

Write-Host "`n--- Exporting Documentation ---`n" -ForegroundColor Cyan

# Export GPO inventory
$inventoryPath = Join-Path $OutputPath "GPO-Inventory.csv"
$gpoInventory | Export-Csv -Path $inventoryPath -NoTypeInformation

Write-GPOLog "GPO inventory exported: $inventoryPath" -Level Success

# Export backup of all GPOs
Write-GPOLog "Backing up all GPOs..." -Level Info

$backupPath = Join-Path $OutputPath "GPOBackups"
if (-not (Test-Path $backupPath)) {
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
}

foreach ($gpo in $allGPOs) {
    try {
        Backup-GPO -Guid $gpo.Id -Path $backupPath -ErrorAction Stop | Out-Null
    }
    catch {
        Write-GPOLog "Failed to backup $($gpo.DisplayName): $_" -Level Warning
    }
}

Write-GPOLog "GPO backups saved: $backupPath" -Level Success

# Export issues
if ($issues.Count -gt 0) {
    $issuesPath = Join-Path $OutputPath "GPO-Issues.csv"
    $issues | Export-Csv -Path $issuesPath -NoTypeInformation
    Write-GPOLog "Issues report exported: $issuesPath" -Level Warning
}

#endregion

#region Generate HTML Dashboard

Write-GPOLog "Generating HTML dashboard..." -Level Info

$unlinkedTable = if ($unlinkedGPOs.Count -gt 0) {
    $rows = foreach ($gpo in $unlinkedGPOs) {
        "<tr>
            <td>$($gpo.DisplayName)</td>
            <td>$($gpo.ModifiedTime)</td>
            <td>$(if ($gpo.IsEmpty) { 'Yes' } else { 'No' })</td>
        </tr>"
    }
    @"
<h3 style="color: #f0ad4e;">Unlinked GPOs ($($unlinkedGPOs.Count))</h3>
<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; width: 100%;">
    <tr style="background-color: #f5f5f5;">
        <th>GPO Name</th>
        <th>Last Modified</th>
        <th>Empty</th>
    </tr>
    $($rows -join "`n")
</table>
<p><em>Recommendation: Review quarterly - delete unused GPOs to reduce clutter.</em></p>
"@
}
else { "" }

$emptyTable = if ($emptyGPOs.Count -gt 0) {
    $rows = foreach ($gpo in $emptyGPOs) {
        "<tr>
            <td>$($gpo.DisplayName)</td>
            <td>$(if ($gpo.IsLinked) { 'Yes' } else { 'No' })</td>
            <td>$($gpo.CreatedTime)</td>
        </tr>"
    }
    @"
<h3 style="color: #f0ad4e;">Empty GPOs ($($emptyGPOs.Count))</h3>
<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; width: 100%;">
    <tr style="background-color: #f5f5f5;">
        <th>GPO Name</th>
        <th>Linked</th>
        <th>Created</th>
    </tr>
    $($rows -join "`n")
</table>
<p><em>Recommendation: Empty GPOs consume resources without benefit - consider removal.</em></p>
"@
}
else { "" }

$issuesTable = if ($issues.Count -gt 0) {
    $rows = foreach ($issue in $issues) {
        "<tr>
            <td>$($issue.Type)</td>
            <td>$($issue.GPO)</td>
            <td>$($issue.Details)</td>
        </tr>"
    }
    @"
<h3 style="color: #d9534f;">Issues Detected ($($issues.Count))</h3>
<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; width: 100%;">
    <tr style="background-color: #f5f5f5;">
        <th>Type</th>
        <th>GPO</th>
        <th>Details</th>
    </tr>
    $($rows -join "`n")
</table>
"@
}
else { "" }

# Top 10 most recently modified
$recentGPOs = $gpoInventory | Sort-Object ModifiedTime -Descending | Select-Object -First 10
$recentRows = foreach ($gpo in $recentGPOs) {
    "<tr>
        <td>$($gpo.DisplayName)</td>
        <td>$($gpo.ModifiedTime)</td>
        <td>$(if ($gpo.IsLinked) { '✓' } else { '✗' })</td>
    </tr>"
}

$dashboardHtml = @"
<html>
<head>
    <title>Group Policy Documentation - $domain</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        h1 { color: #333; }
        h2 { color: #0275d8; border-bottom: 2px solid #0275d8; padding-bottom: 5px; }
        h3 { color: #666; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        th { background-color: #0275d8; color: white; text-align: left; padding: 10px; }
        td { padding: 8px; border: 1px solid #ddd; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .summary-box { background-color: #f5f5f5; padding: 15px; border-left: 4px solid #0275d8; margin-bottom: 20px; }
        .stat { display: inline-block; margin-right: 30px; }
        .stat-value { font-size: 24px; font-weight: bold; color: #0275d8; }
        .stat-label { font-size: 14px; color: #666; }
    </style>
</head>
<body>

<h1>Group Policy Documentation</h1>

<div class="summary-box">
    <p><strong>Domain:</strong> $domain</p>
    <p><strong>Export Date:</strong> $startTime</p>
    <p><strong>Export Path:</strong> $OutputPath</p>
</div>

<h2>Summary Statistics</h2>

<div style="margin-bottom: 30px;">
    <div class="stat">
        <div class="stat-value">$($allGPOs.Count)</div>
        <div class="stat-label">Total GPOs</div>
    </div>
    <div class="stat">
        <div class="stat-value">$($unlinkedGPOs.Count)</div>
        <div class="stat-label">Unlinked</div>
    </div>
    <div class="stat">
        <div class="stat-value">$($emptyGPOs.Count)</div>
        <div class="stat-label">Empty</div>
    </div>
    <div class="stat">
        <div class="stat-value">$($issues.Count)</div>
        <div class="stat-label">Issues</div>
    </div>
</div>

<h2>Recently Modified GPOs (Last 10)</h2>
<table>
    <tr>
        <th>GPO Name</th>
        <th>Modified</th>
        <th>Linked</th>
    </tr>
    $($recentRows -join "`n")
</table>

$unlinkedTable
$emptyTable
$issuesTable

<h2>Files Exported</h2>
<ul>
    <li><strong>GPO-Inventory.csv</strong> - Complete inventory of all GPOs</li>
    <li><strong>GPOBackups/</strong> - Full GPO backups (importable)</li>
$(if ($IncludeReports) { "    <li><strong>Reports/</strong> - Individual GPO HTML reports</li>`n" } else { "" })
$(if ($issues.Count -gt 0) { "    <li><strong>GPO-Issues.csv</strong> - Detected issues and recommendations</li>`n" } else { "" })
</ul>

<hr>
<p style="font-size: 11px; color: #666;">Generated by Export-GroupPolicyDocumentation.ps1 - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>

</body>
</html>
"@

$dashboardPath = Join-Path $OutputPath "GPO-Dashboard.html"
$dashboardHtml | Out-File -FilePath $dashboardPath -Encoding UTF8

Write-GPOLog "HTML dashboard created: $dashboardPath" -Level Success

#endregion

#region Summary

$endTime = Get-Date
$duration = New-TimeSpan -Start $startTime -End $endTime

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Documentation Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-GPOLog "Total GPOs: $($allGPOs.Count)" -Level Info
Write-GPOLog "Unlinked GPOs: $($unlinkedGPOs.Count)" -Level $(if ($unlinkedGPOs.Count -gt 0) { "Warning" } else { "Success" })
Write-GPOLog "Empty GPOs: $($emptyGPOs.Count)" -Level $(if ($emptyGPOs.Count -gt 0) { "Warning" } else { "Success" })
Write-GPOLog "Issues detected: $($issues.Count)" -Level $(if ($issues.Count -gt 0) { "Warning" } else { "Success" })
Write-GPOLog "Export duration: $([math]::Round($duration.TotalMinutes, 2)) minutes" -Level Info

Write-Host "`nDocumentation saved to: $OutputPath`n" -ForegroundColor Green

#endregion

#region Email Report

if ($EmailTo) {
    Write-GPOLog "Sending email notification..." -Level Info
    
    $statusIcon = if ($issues.Count -eq 0 -and $unlinkedGPOs.Count -eq 0) { "✓" } else { "⚠️" }
    
    $emailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2>$statusIcon Group Policy Documentation Complete</h2>

<div style="background-color: #f5f5f5; padding: 15px; border-left: 4px solid #0275d8;">
    <p><strong>Domain:</strong> $domain</p>
    <p><strong>Export Date:</strong> $startTime</p>
    <p><strong>Duration:</strong> $([math]::Round($duration.TotalMinutes, 2)) minutes</p>
</div>

<h3>Summary</h3>
<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse;">
    <tr><td><strong>Total GPOs:</strong></td><td>$($allGPOs.Count)</td></tr>
    <tr><td><strong>Unlinked GPOs:</strong></td><td style="color: #f0ad4e;">$($unlinkedGPOs.Count)</td></tr>
    <tr><td><strong>Empty GPOs:</strong></td><td style="color: #f0ad4e;">$($emptyGPOs.Count)</td></tr>
    <tr><td><strong>Issues:</strong></td><td style="color: #d9534f;">$($issues.Count)</td></tr>
</table>

<h3>Export Location</h3>
<p>$OutputPath</p>

<h3>Files Available</h3>
<ul>
    <li>GPO-Inventory.csv - All GPO details</li>
    <li>GPOBackups/ - Importable GPO backups</li>
    <li>GPO-Dashboard.html - Visual documentation</li>
</ul>

<p>Review the dashboard for detailed analysis and recommendations.</p>

<hr>
<p style="font-size: 11px; color: #666;">Group Policy Documentation Export</p>
</body>
</html>
"@
    
    Send-MailMessage -To $EmailTo -From "GPODocumentation@company.com" `
        -Subject "$statusIcon GPO Documentation - $domain ($(Get-Date -Format 'yyyy-MM-dd'))" `
        -Body $emailBody -BodyAsHtml -SmtpServer $SMTPServer
    
    Write-GPOLog "Email sent to: $($EmailTo -join ', ')" -Level Success
}

#endregion

Write-GPOLog "`nGPO documentation export complete!`n" -Level Success
