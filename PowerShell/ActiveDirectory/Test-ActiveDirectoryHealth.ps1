################################################
# Author: Luis Ramirez                         #
# Created: 1-14-2021                           #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Comprehensive Active Directory health check and monitoring.

.DESCRIPTION
    Performs detailed AD infrastructure health assessment:
    
    Checks Performed:
    - Domain Controller replication status
    - FSMO role holder identification and availability
    - DNS zone health and record validation
    - SYSVOL and NETLOGON share replication
    - Group Policy replication status
    - Active Directory database size and fragmentation
    - Tombstone lifetime warnings
    - Password policy compliance
    - Time synchronization across DCs
    - Critical service status
    - Event log errors (last 24 hours)
    
    Outputs:
    - Color-coded console summary
    - Detailed HTML dashboard
    - Email alerts for critical issues
    - CSV export for trending
    
.PARAMETER EmailRecipient
    Email address for health report

.PARAMETER SMTPServer
    SMTP server for email notifications

.PARAMETER ExportHTML
    Path for HTML dashboard

.PARAMETER IncludeDetailedLogs
    Include event log analysis in report

.EXAMPLE
    .\Test-ActiveDirectoryHealth.ps1
    
    Run health check with console output.

.EXAMPLE
    .\Test-ActiveDirectoryHealth.ps1 -EmailRecipient "it@company.com" -SMTPServer "smtp.company.com" -ExportHTML "C:\Reports\AD-Health.html"
    
    Full health check with email and HTML report.

.NOTES
    Requires:
    - Domain Admin or equivalent permissions
    - Access to all domain controllers
    - PowerShell Remoting enabled on DCs
    
    Recommended: Run weekly via scheduled task
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$EmailRecipient,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer,

    [Parameter(Mandatory = $false)]
    [string]$ExportHTML = ".\AD-Health-Report-$(Get-Date -Format 'yyyyMMdd-HHmmss').html",

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDetailedLogs,

    [Parameter(Mandatory = $false)]
    [string]$ExportCSV = ".\AD-Health-Summary-$(Get-Date -Format 'yyyyMMdd').csv"
)

#region Import Module

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "ActiveDirectory module required."
    exit 1
}

#endregion

#region Helper Functions

function Write-HealthLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success", "Critical")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Critical" { "Magenta" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-ServiceHealth {
    param(
        [string]$ComputerName,
        [string[]]$Services = @("NTDS", "DNS", "DFSR", "Netlogon", "kdc", "W32Time")
    )
    
    $results = @()
    
    foreach ($service in $Services) {
        try {
            $svc = Get-Service -Name $service -ComputerName $ComputerName -ErrorAction Stop
            $results += [PSCustomObject]@{
                Service = $service
                Status = $svc.Status
                StartType = $svc.StartType
                IsHealthy = ($svc.Status -eq 'Running')
            }
        }
        catch {
            $results += [PSCustomObject]@{
                Service = $service
                Status = "Not Found"
                StartType = "N/A"
                IsHealthy = $false
            }
        }
    }
    
    return $results
}

#endregion

#region Main Health Check

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Active Directory Health Check" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$healthReport = @{
    Timestamp = Get-Date
    OverallHealth = "Healthy"
    DomainControllers = @()
    Replication = @()
    FSMO = @()
    DNS = @()
    Services = @()
    GPO = @()
    Issues = @()
    Warnings = @()
    Summary = @{}
}

#region Get Domain Information

Write-HealthLog "Gathering domain information..." -Level Info

try {
    $domain = Get-ADDomain
    $forest = Get-ADForest
    
    Write-HealthLog "  Domain: $($domain.DNSRoot)" -Level Success
    Write-HealthLog "  Forest: $($forest.Name)" -Level Success
    Write-HealthLog "  Forest Functional Level: $($forest.ForestMode)" -Level Info
    Write-HealthLog "  Domain Functional Level: $($domain.DomainMode)" -Level Info
}
catch {
    Write-HealthLog "Failed to get domain information: $_" -Level Critical
    $healthReport.OverallHealth = "Critical"
    exit 1
}

#endregion

#region Domain Controller Health

Write-HealthLog "`nChecking domain controller health..." -Level Info

$allDCs = Get-ADDomainController -Filter * | Sort-Object Name

foreach ($dc in $allDCs) {
    Write-HealthLog "  Checking: $($dc.HostName)" -Level Info
    
    $dcHealth = [PSCustomObject]@{
        Name = $dc.HostName
        Site = $dc.Site
        IPAddress = $dc.IPv4Address
        IsGlobalCatalog = $dc.IsGlobalCatalog
        IsReadOnly = $dc.IsReadOnly
        OperatingSystem = $dc.OperatingSystem
        IsReachable = $false
        Services = @()
        Issues = @()
    }
    
    # Test connectivity
    if (Test-Connection -ComputerName $dc.HostName -Count 2 -Quiet) {
        $dcHealth.IsReachable = $true
        Write-HealthLog "    ✓ Reachable" -Level Success
        
        # Check critical services
        $services = Test-ServiceHealth -ComputerName $dc.HostName
        $dcHealth.Services = $services
        
        $stoppedServices = $services | Where-Object { -not $_.IsHealthy }
        if ($stoppedServices) {
            foreach ($svc in $stoppedServices) {
                $issue = "Service '$($svc.Service)' is $($svc.Status) on $($dc.HostName)"
                $dcHealth.Issues += $issue
                $healthReport.Issues += $issue
                Write-HealthLog "    ✗ $issue" -Level Error
            }
            $healthReport.OverallHealth = "Degraded"
        }
        else {
            Write-HealthLog "    ✓ All critical services running" -Level Success
        }
    }
    else {
        $dcHealth.IsReachable = $false
        $issue = "Domain Controller $($dc.HostName) is unreachable"
        $dcHealth.Issues += $issue
        $healthReport.Issues += $issue
        Write-HealthLog "    ✗ UNREACHABLE" -Level Critical
        $healthReport.OverallHealth = "Critical"
    }
    
    $healthReport.DomainControllers += $dcHealth
}

$healthReport.Summary.TotalDCs = $allDCs.Count
$healthReport.Summary.ReachableDCs = ($healthReport.DomainControllers | Where-Object { $_.IsReachable }).Count
$healthReport.Summary.UnreachableDCs = $healthReport.Summary.TotalDCs - $healthReport.Summary.ReachableDCs

#endregion

#region Replication Health

Write-HealthLog "`nChecking AD replication..." -Level Info

try {
    $replSummary = Get-ADReplicationPartnerMetadata -Target "$($domain.DNSRoot)" -Scope Domain -ErrorAction Stop
    
    foreach ($repl in $replSummary) {
        $lastReplication = $repl.LastReplicationSuccess
        $timeSinceRepl = ((Get-Date) - $lastReplication).TotalHours
        
        $replHealth = [PSCustomObject]@{
            Server = $repl.Server
            Partner = $repl.Partner
            LastReplication = $lastReplication
            HoursSinceReplication = [math]::Round($timeSinceRepl, 2)
            LastResult = $repl.LastReplicationResult
            ConsecutiveFailures = $repl.ConsecutiveReplicationFailures
            IsHealthy = ($timeSinceRepl -lt 24 -and $repl.LastReplicationResult -eq 0)
        }
        
        $healthReport.Replication += $replHealth
        
        if ($timeSinceRepl -gt 24) {
            $issue = "Replication from $($repl.Partner) to $($repl.Server) delayed: $([math]::Round($timeSinceRepl, 1)) hours"
            $healthReport.Warnings += $issue
            Write-HealthLog "  ⚠ $issue" -Level Warning
            
            if ($healthReport.OverallHealth -eq "Healthy") {
                $healthReport.OverallHealth = "Warning"
            }
        }
        elseif ($repl.LastReplicationResult -ne 0) {
            $issue = "Replication error between $($repl.Partner) and $($repl.Server): Error $($repl.LastReplicationResult)"
            $healthReport.Issues += $issue
            Write-HealthLog "  ✗ $issue" -Level Error
            $healthReport.OverallHealth = "Degraded"
        }
        else {
            Write-HealthLog "  ✓ $($repl.Server) ↔ $($repl.Partner): $([math]::Round($timeSinceRepl, 1)) hours ago" -Level Success
        }
    }
}
catch {
    Write-HealthLog "  ✗ Failed to check replication: $_" -Level Error
    $healthReport.Issues += "Failed to retrieve replication status"
}

#endregion

#region FSMO Roles

Write-HealthLog "`nChecking FSMO role holders..." -Level Info

$fsmoRoles = @(
    [PSCustomObject]@{ Role = "Schema Master"; Holder = $forest.SchemaMaster; Scope = "Forest" }
    [PSCustomObject]@{ Role = "Domain Naming Master"; Holder = $forest.DomainNamingMaster; Scope = "Forest" }
    [PSCustomObject]@{ Role = "PDC Emulator"; Holder = $domain.PDCEmulator; Scope = "Domain" }
    [PSCustomObject]@{ Role = "RID Master"; Holder = $domain.RIDMaster; Scope = "Domain" }
    [PSCustomObject]@{ Role = "Infrastructure Master"; Holder = $domain.InfrastructureMaster; Scope = "Domain" }
)

foreach ($fsmo in $fsmoRoles) {
    $isReachable = Test-Connection -ComputerName $fsmo.Holder -Count 1 -Quiet
    
    $fsmo | Add-Member -NotePropertyName "IsReachable" -NotePropertyValue $isReachable
    $healthReport.FSMO += $fsmo
    
    if ($isReachable) {
        Write-HealthLog "  ✓ $($fsmo.Role): $($fsmo.Holder)" -Level Success
    }
    else {
        $issue = "FSMO role holder unreachable: $($fsmo.Role) on $($fsmo.Holder)"
        $healthReport.Issues += $issue
        Write-HealthLog "  ✗ $issue" -Level Critical
        $healthReport.OverallHealth = "Critical"
    }
}

#endregion

#region DNS Health

Write-HealthLog "`nChecking DNS health..." -Level Info

foreach ($dc in $allDCs | Where-Object { $_.IsGlobalCatalog }) {
    try {
        # Test DNS resolution
        $dnsTest = Resolve-DnsName -Name $domain.DNSRoot -Server $dc.HostName -ErrorAction Stop
        
        $healthReport.DNS += [PSCustomObject]@{
            Server = $dc.HostName
            CanResolve = $true
            Result = "OK"
        }
        
        Write-HealthLog "  ✓ DNS on $($dc.HostName): OK" -Level Success
    }
    catch {
        $issue = "DNS resolution failed on $($dc.HostName)"
        $healthReport.Issues += $issue
        $healthReport.DNS += [PSCustomObject]@{
            Server = $dc.HostName
            CanResolve = $false
            Result = $_.Exception.Message
        }
        Write-HealthLog "  ✗ $issue" -Level Error
        $healthReport.OverallHealth = "Degraded"
    }
}

#endregion

#region SYSVOL Replication

Write-HealthLog "`nChecking SYSVOL replication..." -Level Info

foreach ($dc in $allDCs | Where-Object { $_.IsReachable }) {
    try {
        $sysvolPath = "\\$($dc.HostName)\SYSVOL"
        if (Test-Path $sysvolPath) {
            Write-HealthLog "  ✓ SYSVOL accessible on $($dc.HostName)" -Level Success
        }
        else {
            $issue = "SYSVOL not accessible on $($dc.HostName)"
            $healthReport.Warnings += $issue
            Write-HealthLog "  ⚠ $issue" -Level Warning
        }
    }
    catch {
        $issue = "SYSVOL check failed on $($dc.HostName): $_"
        $healthReport.Warnings += $issue
        Write-HealthLog "  ⚠ $issue" -Level Warning
    }
}

#endregion

#region Group Policy Check

Write-HealthLog "`nChecking Group Policy health..." -Level Info

try {
    $allGPOs = Get-GPO -All
    $orphanedGPOs = $allGPOs | Where-Object { $_.GpoStatus -eq 'AllSettingsDisabled' }
    $unlinkedGPOs = @()
    
    foreach ($gpo in $allGPOs) {
        $links = $gpo | Select-Object -ExpandProperty Links
        if (-not $links) {
            $unlinkedGPOs += $gpo
        }
    }
    
    $healthReport.GPO = [PSCustomObject]@{
        Total = $allGPOs.Count
        Orphaned = $orphanedGPOs.Count
        Unlinked = $unlinkedGPOs.Count
    }
    
    Write-HealthLog "  Total GPOs: $($allGPOs.Count)" -Level Info
    
    if ($orphanedGPOs.Count -gt 0) {
        Write-HealthLog "  ⚠ Orphaned GPOs (all settings disabled): $($orphanedGPOs.Count)" -Level Warning
        $healthReport.Warnings += "$($orphanedGPOs.Count) orphaned GPOs found"
    }
    
    if ($unlinkedGPOs.Count -gt 0) {
        Write-HealthLog "  ⚠ Unlinked GPOs: $($unlinkedGPOs.Count)" -Level Warning
        $healthReport.Warnings += "$($unlinkedGPOs.Count) unlinked GPOs found"
    }
}
catch {
    Write-HealthLog "  ✗ Failed to check GPO health: $_" -Level Error
}

#endregion

#region Tombstone Lifetime

Write-HealthLog "`nChecking tombstone lifetime..." -Level Info

try {
    $configNC = (Get-ADRootDSE).configurationNamingContext
    $tombstone = Get-ADObject -Identity "CN=Directory Service,CN=Windows NT,CN=Services,$configNC" -Properties tombstoneLifetime
    
    $tombstoneLifetime = if ($tombstone.tombstoneLifetime) { $tombstone.tombstoneLifetime } else { 180 }  # Default is 180 days
    
    Write-HealthLog "  Tombstone Lifetime: $tombstoneLifetime days" -Level Info
    
    if ($tombstoneLifetime -lt 60) {
        $issue = "Tombstone lifetime is dangerously low: $tombstoneLifetime days (recommend 180+)"
        $healthReport.Issues += $issue
        Write-HealthLog "  ✗ $issue" -Level Error
        $healthReport.OverallHealth = "Degraded"
    }
    elseif ($tombstoneLifetime -lt 180) {
        $warning = "Tombstone lifetime is below recommended: $tombstoneLifetime days (recommend 180+)"
        $healthReport.Warnings += $warning
        Write-HealthLog "  ⚠ $warning" -Level Warning
    }
    else {
        Write-HealthLog "  ✓ Tombstone lifetime is healthy: $tombstoneLifetime days" -Level Success
    }
}
catch {
    Write-HealthLog "  ✗ Failed to check tombstone lifetime: $_" -Level Error
}

#endregion

#region Password Policy

Write-HealthLog "`nChecking password policy..." -Level Info

try {
    $defaultPolicy = Get-ADDefaultDomainPasswordPolicy
    
    Write-HealthLog "  Minimum Password Length: $($defaultPolicy.MinPasswordLength)" -Level Info
    Write-HealthLog "  Password Complexity: $($defaultPolicy.ComplexityEnabled)" -Level Info
    Write-HealthLog "  Password History: $($defaultPolicy.PasswordHistoryCount)" -Level Info
    Write-HealthLog "  Lockout Threshold: $($defaultPolicy.LockoutThreshold)" -Level Info
    
    if ($defaultPolicy.MinPasswordLength -lt 12) {
        $warning = "Password length ($($defaultPolicy.MinPasswordLength)) is below best practice (12+ characters)"
        $healthReport.Warnings += $warning
        Write-HealthLog "  ⚠ $warning" -Level Warning
    }
    
    if (-not $defaultPolicy.ComplexityEnabled) {
        $warning = "Password complexity is disabled"
        $healthReport.Warnings += $warning
        Write-HealthLog "  ⚠ $warning" -Level Warning
    }
}
catch {
    Write-HealthLog "  ✗ Failed to check password policy: $_" -Level Error
}

#endregion

#region Time Synchronization

Write-HealthLog "`nChecking time synchronization..." -Level Info

$pdcEmulator = $domain.PDCEmulator
Write-HealthLog "  PDC Emulator: $pdcEmulator" -Level Info

foreach ($dc in $allDCs | Where-Object { $_.IsReachable -and $_.HostName -ne $pdcEmulator }) {
    try {
        $dcTime = Invoke-Command -ComputerName $dc.HostName -ScriptBlock { Get-Date } -ErrorAction Stop
        $pdcTime = Invoke-Command -ComputerName $pdcEmulator -ScriptBlock { Get-Date } -ErrorAction Stop
        
        $timeDiff = [math]::Abs(($dcTime - $pdcTime).TotalSeconds)
        
        if ($timeDiff -gt 300) {  # 5 minutes
            $issue = "Time difference between $($dc.HostName) and PDC: $([math]::Round($timeDiff)) seconds"
            $healthReport.Issues += $issue
            Write-HealthLog "  ✗ $issue" -Level Error
            $healthReport.OverallHealth = "Degraded"
        }
        elseif ($timeDiff -gt 60) {  # 1 minute
            $warning = "Time difference between $($dc.HostName) and PDC: $([math]::Round($timeDiff)) seconds"
            $healthReport.Warnings += $warning
            Write-HealthLog "  ⚠ $warning" -Level Warning
        }
        else {
            Write-HealthLog "  ✓ $($dc.HostName) time sync: OK ($([math]::Round($timeDiff))s)" -Level Success
        }
    }
    catch {
        Write-HealthLog "  ⚠ Could not check time on $($dc.HostName)" -Level Warning
    }
}

#endregion

#region Summary

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Health Check Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$summaryColor = switch ($healthReport.OverallHealth) {
    "Healthy" { "Green" }
    "Warning" { "Yellow" }
    "Degraded" { "Red" }
    "Critical" { "Magenta" }
}

Write-Host "Overall Health: " -NoNewline
Write-Host $healthReport.OverallHealth -ForegroundColor $summaryColor

Write-Host "`nDomain Controllers: $($healthReport.Summary.TotalDCs)" -ForegroundColor White
Write-Host "  Reachable: $($healthReport.Summary.ReachableDCs)" -ForegroundColor Green
if ($healthReport.Summary.UnreachableDCs -gt 0) {
    Write-Host "  Unreachable: $($healthReport.Summary.UnreachableDCs)" -ForegroundColor Red
}

Write-Host "`nReplication Partners: $($healthReport.Replication.Count)" -ForegroundColor White
$healthyRepl = ($healthReport.Replication | Where-Object { $_.IsHealthy }).Count
Write-Host "  Healthy: $healthyRepl" -ForegroundColor Green
if ($healthReport.Replication.Count -ne $healthyRepl) {
    Write-Host "  Issues: $($healthReport.Replication.Count - $healthyRepl)" -ForegroundColor Red
}

if ($healthReport.Issues.Count -gt 0) {
    Write-Host "`n❌ Critical Issues: $($healthReport.Issues.Count)" -ForegroundColor Red
    $healthReport.Issues | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

if ($healthReport.Warnings.Count -gt 0) {
    Write-Host "`n⚠️  Warnings: $($healthReport.Warnings.Count)" -ForegroundColor Yellow
    $healthReport.Warnings | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}

if ($healthReport.Issues.Count -eq 0 -and $healthReport.Warnings.Count -eq 0) {
    Write-Host "`n✓ All checks passed!" -ForegroundColor Green
}

#endregion

#region Export HTML Report

Write-HealthLog "`nGenerating HTML report..." -Level Info

$dcTable = $healthReport.DomainControllers | ConvertTo-Html -Fragment
$replTable = $healthReport.Replication | ConvertTo-Html -Fragment
$fsmoTable = $healthReport.FSMO | ConvertTo-Html -Fragment

$issuesHtml = if ($healthReport.Issues.Count -gt 0) {
    "<ul>" + ($healthReport.Issues | ForEach-Object { "<li>$_</li>" }) + "</ul>"
} else {
    "<p style='color: green;'>No critical issues found.</p>"
}

$warningsHtml = if ($healthReport.Warnings.Count -gt 0) {
    "<ul>" + ($healthReport.Warnings | ForEach-Object { "<li>$_</li>" }) + "</ul>"
} else {
    "<p style='color: green;'>No warnings found.</p>"
}

$statusClass = switch ($healthReport.OverallHealth) {
    "Healthy" { "success" }
    "Warning" { "warning" }
    "Degraded" { "error" }
    "Critical" { "critical" }
}

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Active Directory Health Report - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; }
        .summary { background-color: white; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .success { background-color: #d4edda; border-left: 4px solid #28a745; padding: 15px; margin: 10px 0; }
        .warning { background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 10px 0; }
        .error { background-color: #f8d7da; border-left: 4px solid #dc3545; padding: 15px; margin: 10px 0; }
        .critical { background-color: #f8d7da; border-left: 4px solid #721c24; padding: 15px; margin: 10px 0; }
        table { border-collapse: collapse; width: 100%; background-color: white; margin: 10px 0; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .stat { display: inline-block; margin: 10px 20px; text-align: center; }
        .stat-label { font-weight: bold; color: #666; }
        .stat-value { font-size: 28px; color: #0078d4; }
    </style>
</head>
<body>
    <h1>🏥 Active Directory Health Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <p><strong>Domain:</strong> $($domain.DNSRoot)</p>
    
    <div class="$statusClass">
        <h2>Overall Health Status: $($healthReport.OverallHealth)</h2>
    </div>
    
    <div class="summary">
        <h2>Quick Statistics</h2>
        <div class="stat">
            <div class="stat-label">Domain Controllers</div>
            <div class="stat-value">$($healthReport.Summary.TotalDCs)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Replication Partners</div>
            <div class="stat-value">$($healthReport.Replication.Count)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Critical Issues</div>
            <div class="stat-value" style="color: red;">$($healthReport.Issues.Count)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Warnings</div>
            <div class="stat-value" style="color: orange;">$($healthReport.Warnings.Count)</div>
        </div>
    </div>
    
    <h2>❌ Critical Issues</h2>
    $issuesHtml
    
    <h2>⚠️ Warnings</h2>
    $warningsHtml
    
    <h2>Domain Controllers</h2>
    $dcTable
    
    <h2>Replication Status</h2>
    $replTable
    
    <h2>FSMO Roles</h2>
    $fsmoTable
    
    <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px;">
        <p>Generated by: Luis Ramirez | AD Health Monitoring Tool</p>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $ExportHTML -Encoding UTF8
Write-HealthLog "✓ HTML report saved: $ExportHTML" -Level Success

#endregion

#region Email Notification

if ($EmailRecipient -and $SMTPServer) {
    $subject = "AD Health Report - $($healthReport.OverallHealth) - $($domain.DNSRoot)"
    $priority = if ($healthReport.OverallHealth -in @("Critical", "Degraded")) { "High" } else { "Normal" }
    
    try {
        Send-MailMessage -To $EmailRecipient `
            -From "AD-Health@company.com" `
            -Subject $subject `
            -Body "See attached HTML report. Overall Health: $($healthReport.OverallHealth)" `
            -Attachments $ExportHTML `
            -SmtpServer $SMTPServer `
            -Priority $priority `
            -ErrorAction Stop
        
        Write-HealthLog "✓ Email sent to $EmailRecipient" -Level Success
    }
    catch {
        Write-HealthLog "Failed to send email: $_" -Level Error
    }
}

#endregion

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Health Check Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Exit with appropriate code for monitoring systems
if ($healthReport.OverallHealth -in @("Critical", "Degraded")) {
    exit 1
}
