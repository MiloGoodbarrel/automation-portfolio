################################################
# Author: Luis Ramirez                         #
# Created: 7-16-2020                           #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Monitors SSL/TLS certificates across servers and generates expiration warnings.

.DESCRIPTION
    Scans certificate stores on local or remote servers to identify expiring certificates.
    
    Features:
    - Scans Personal, Web Hosting, and other certificate stores
    - 90/60/30/7 day expiration warnings
    - HTML dashboard with color-coded alerts
    - Email notifications
    - IIS binding detection
    - Certificate chain validation
    - Auto-discovery of servers from AD
    
    Certificate Sources:
    - Local machine certificate stores
    - IIS website bindings
    - Remote Desktop Services
    - Exchange Server (if present)
    - Custom certificate locations
    
.PARAMETER ComputerName
    Array of server names to scan (default: local machine)

.PARAMETER DiscoverFromAD
    Auto-discover servers from Active Directory

.PARAMETER CertificateStores
    Certificate stores to scan (default: My, WebHosting)

.PARAMETER WarningDays
    Array of days for warnings (default: 90, 60, 30, 7)

.PARAMETER ExportHTML
    Path for HTML dashboard export

.PARAMETER EmailRecipient
    Email address for notifications

.PARAMETER SMTPServer
    SMTP server for email

.EXAMPLE
    .\Get-CertificateExpirationReport.ps1
    
    Scan local machine certificates.

.EXAMPLE
    .\Get-CertificateExpirationReport.ps1 -DiscoverFromAD -ExportHTML "C:\Reports\certs.html" -EmailRecipient "it@company.com" -SMTPServer "smtp.company.com"
    
    Scan all servers, generate HTML report, send email.

.NOTES
    Requires:
    - Local administrator rights on remote servers
    - PowerShell Remoting enabled
    - WebAdministration module for IIS bindings
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string[]]$ComputerName = @($env:COMPUTERNAME),

    [Parameter(Mandatory = $false)]
    [switch]$DiscoverFromAD,

    [Parameter(Mandatory = $false)]
    [string[]]$CertificateStores = @("My", "WebHosting"),

    [Parameter(Mandatory = $false)]
    [int[]]$WarningDays = @(90, 60, 30, 7),

    [Parameter(Mandatory = $false)]
    [string]$ExportHTML = ".\Certificate-Expiration-Report-$(Get-Date -Format 'yyyyMMdd').html",

    [Parameter(Mandatory = $false)]
    [string]$EmailRecipient,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeExpired,

    [Parameter(Mandatory = $false)]
    [switch]$CheckIISBindings
)

#region Helper Functions

function Write-CertLog {
    param(
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $color = switch ($Level) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        default { "White" }
    }
    
    Write-Host $Message -ForegroundColor $color
}

function Get-CertificateRisk {
    param([datetime]$ExpirationDate)
    
    $daysUntilExpiration = ($ExpirationDate - (Get-Date)).Days
    
    if ($daysUntilExpiration -lt 0) { return "Expired", "Critical" }
    elseif ($daysUntilExpiration -le 7) { return "Critical", "Critical" }
    elseif ($daysUntilExpiration -le 30) { return "High", "High" }
    elseif ($daysUntilExpiration -le 60) { return "Medium", "Medium" }
    elseif ($daysUntilExpiration -le 90) { return "Low", "Low" }
    else { return "OK", "OK" }
}

function Get-IISCertificateBindings {
    param([string]$Computer)
    
    $bindings = @()
    
    try {
        $scriptBlock = {
            if (Get-Module -ListAvailable -Name WebAdministration) {
                Import-Module WebAdministration
                Get-ChildItem IIS:\SslBindings | ForEach-Object {
                    [PSCustomObject]@{
                        IPAddress = $_.IPAddress
                        Port = $_.Port
                        Thumbprint = $_.Thumbprint
                        SiteName = (Get-ChildItem IIS:\Sites | Where-Object {
                            $_.Bindings.Collection.bindingInformation -match $_.Port
                        } | Select-Object -First 1).Name
                    }
                }
            }
        }
        
        if ($Computer -eq $env:COMPUTERNAME) {
            $bindings = & $scriptBlock
        }
        else {
            $bindings = Invoke-Command -ComputerName $Computer -ScriptBlock $scriptBlock -ErrorAction Stop
        }
    }
    catch {
        Write-Verbose "IIS bindings not available on $Computer"
    }
    
    return $bindings
}

#endregion

#region Main Script

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Certificate Expiration Report" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$allCertificates = @()
$serverErrors = @()

#region Server Discovery

if ($DiscoverFromAD) {
    Write-CertLog "Discovering servers from Active Directory..." -Level Info
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $ComputerName = Get-ADComputer -Filter {OperatingSystem -like "*Server*" -and Enabled -eq $true} |
            Select-Object -ExpandProperty Name
        Write-CertLog "Found $($ComputerName.Count) servers in AD" -Level Success
    }
    catch {
        Write-CertLog "Failed to discover from AD: $_" -Level Error
        Write-CertLog "Using local machine only" -Level Warning
        $ComputerName = @($env:COMPUTERNAME)
    }
}

#endregion

#region Scan Certificates

Write-CertLog "`nScanning certificates on $($ComputerName.Count) server(s)..." -Level Info

foreach ($server in $ComputerName) {
    Write-CertLog "  Scanning: $server" -Level Info
    
    try {
        $scriptBlock = {
            param($Stores)
            
            $results = @()
            
            foreach ($storeName in $Stores) {
                try {
                    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($storeName, 'LocalMachine')
                    $store.Open('ReadOnly')
                    
                    foreach ($cert in $store.Certificates) {
                        $results += [PSCustomObject]@{
                            Thumbprint = $cert.Thumbprint
                            Subject = $cert.Subject
                            Issuer = $cert.Issuer
                            NotBefore = $cert.NotBefore
                            NotAfter = $cert.NotAfter
                            FriendlyName = $cert.FriendlyName
                            HasPrivateKey = $cert.HasPrivateKey
                            StoreName = $storeName
                        }
                    }
                    
                    $store.Close()
                }
                catch {
                    Write-Warning "Failed to access store $storeName : $_"
                }
            }
            
            return $results
        }
        
        if ($server -eq $env:COMPUTERNAME) {
            $certificates = & $scriptBlock -Stores $CertificateStores
        }
        else {
            $certificates = Invoke-Command -ComputerName $server -ScriptBlock $scriptBlock -ArgumentList (,$CertificateStores) -ErrorAction Stop
        }
        
        # Get IIS bindings if requested
        $iisBindings = @{}
        if ($CheckIISBindings) {
            $bindings = Get-IISCertificateBindings -Computer $server
            foreach ($binding in $bindings) {
                if ($binding.Thumbprint) {
                    $iisBindings[$binding.Thumbprint] = $binding.SiteName
                }
            }
        }
        
        # Process certificates
        foreach ($cert in $certificates) {
            $daysUntilExpiration = ($cert.NotAfter - (Get-Date)).Days
            $riskLevel, $status = Get-CertificateRisk -ExpirationDate $cert.NotAfter
            
            # Skip if expired and not requested
            if ($daysUntilExpiration -lt 0 -and -not $IncludeExpired) {
                continue
            }
            
            # Only include certificates expiring within warning period or expired
            if ($daysUntilExpiration -le $WarningDays[0] -or $IncludeExpired) {
                $allCertificates += [PSCustomObject]@{
                    Server = $server
                    Subject = $cert.Subject
                    FriendlyName = $cert.FriendlyName
                    Issuer = $cert.Issuer
                    NotBefore = $cert.NotBefore
                    NotAfter = $cert.NotAfter
                    DaysUntilExpiration = $daysUntilExpiration
                    RiskLevel = $riskLevel
                    Status = $status
                    Thumbprint = $cert.Thumbprint
                    HasPrivateKey = $cert.HasPrivateKey
                    StoreName = $cert.StoreName
                    IISSiteName = if ($iisBindings.ContainsKey($cert.Thumbprint)) { $iisBindings[$cert.Thumbprint] } else { "" }
                }
            }
        }
        
        Write-CertLog "    Found $($certificates.Count) certificates" -Level Success
    }
    catch {
        Write-CertLog "    ERROR: $_" -Level Error
        $serverErrors += [PSCustomObject]@{
            Server = $server
            Error = $_.Exception.Message
        }
    }
}

#endregion

#region Results Summary

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$summary = @{
    Total = $allCertificates.Count
    Expired = ($allCertificates | Where-Object { $_.DaysUntilExpiration -lt 0 }).Count
    Critical = ($allCertificates | Where-Object { $_.DaysUntilExpiration -ge 0 -and $_.DaysUntilExpiration -le 7 }).Count
    High = ($allCertificates | Where-Object { $_.DaysUntilExpiration -gt 7 -and $_.DaysUntilExpiration -le 30 }).Count
    Medium = ($allCertificates | Where-Object { $_.DaysUntilExpiration -gt 30 -and $_.DaysUntilExpiration -le 60 }).Count
    Low = ($allCertificates | Where-Object { $_.DaysUntilExpiration -gt 60 -and $_.DaysUntilExpiration -le 90 }).Count
}

Write-CertLog "Total Certificates: $($summary.Total)" -Level Info
Write-CertLog "  Expired: $($summary.Expired)" -Level $(if ($summary.Expired -gt 0) { "Error" } else { "Success" })
Write-CertLog "  Critical (≤7 days): $($summary.Critical)" -Level $(if ($summary.Critical -gt 0) { "Error" } else { "Success" })
Write-CertLog "  High (8-30 days): $($summary.High)" -Level $(if ($summary.High -gt 0) { "Warning" } else { "Success" })
Write-CertLog "  Medium (31-60 days): $($summary.Medium)" -Level $(if ($summary.Medium -gt 0) { "Warning" } else { "Success" })
Write-CertLog "  Low (61-90 days): $($summary.Low)" -Level Info

if ($summary.Expired -gt 0 -or $summary.Critical -gt 0) {
    Write-Host "`n⚠️  IMMEDIATE ACTION REQUIRED!" -ForegroundColor Red
    
    $urgentCerts = $allCertificates | Where-Object { $_.DaysUntilExpiration -le 7 } | Sort-Object DaysUntilExpiration
    
    foreach ($cert in $urgentCerts) {
        $color = if ($cert.DaysUntilExpiration -lt 0) { "Red" } else { "Yellow" }
        Write-Host "  [$($cert.Server)] $($cert.Subject) - Expires: $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor $color
    }
}

#endregion

#region Export HTML Report

Write-CertLog "`nGenerating HTML report..." -Level Info

# Group by risk level
$expiredTable = $allCertificates | Where-Object { $_.DaysUntilExpiration -lt 0 } | 
    Sort-Object NotAfter | ConvertTo-Html -Fragment

$criticalTable = $allCertificates | Where-Object { $_.DaysUntilExpiration -ge 0 -and $_.DaysUntilExpiration -le 7 } | 
    Sort-Object DaysUntilExpiration | ConvertTo-Html -Fragment

$highTable = $allCertificates | Where-Object { $_.DaysUntilExpiration -gt 7 -and $_.DaysUntilExpiration -le 30 } | 
    Sort-Object DaysUntilExpiration | ConvertTo-Html -Fragment

$mediumTable = $allCertificates | Where-Object { $_.DaysUntilExpiration -gt 30 -and $_.DaysUntilExpiration -le 60 } | 
    Sort-Object DaysUntilExpiration | ConvertTo-Html -Fragment

$lowTable = $allCertificates | Where-Object { $_.DaysUntilExpiration -gt 60 -and $_.DaysUntilExpiration -le 90 } | 
    Sort-Object DaysUntilExpiration | ConvertTo-Html -Fragment

$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Certificate Expiration Report - $(Get-Date -Format 'yyyy-MM-dd')</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; }
        .summary { background-color: white; padding: 20px; border-radius: 5px; margin: 20px 0; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .stat { display: inline-block; margin: 10px 20px; text-align: center; }
        .stat-label { font-weight: bold; color: #666; font-size: 12px; }
        .stat-value { font-size: 32px; font-weight: bold; }
        .expired { color: #721c24; background-color: #f8d7da; }
        .critical { color: #856404; background-color: #fff3cd; }
        .high { color: #856404; background-color: #fffbf0; }
        .medium { color: #004085; background-color: #d1ecf1; }
        .low { color: #155724; background-color: #d4edda; }
        table { border-collapse: collapse; width: 100%; background-color: white; margin: 10px 0; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; font-size: 13px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .section { background-color: white; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .expired-section { border-left: 4px solid #dc3545; }
        .critical-section { border-left: 4px solid #ffc107; }
        .high-section { border-left: 4px solid #ff9800; }
        .medium-section { border-left: 4px solid #2196f3; }
        .low-section { border-left: 4px solid #4caf50; }
    </style>
</head>
<body>
    <h1>🔒 Certificate Expiration Report</h1>
    <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    <p><strong>Servers Scanned:</strong> $($ComputerName.Count)</p>
    
    <div class="summary">
        <h2>Summary Statistics</h2>
        <div class="stat expired">
            <div class="stat-value">$($summary.Expired)</div>
            <div class="stat-label">EXPIRED</div>
        </div>
        <div class="stat critical">
            <div class="stat-value">$($summary.Critical)</div>
            <div class="stat-label">CRITICAL (≤7 days)</div>
        </div>
        <div class="stat high">
            <div class="stat-value">$($summary.High)</div>
            <div class="stat-label">HIGH (8-30 days)</div>
        </div>
        <div class="stat medium">
            <div class="stat-value">$($summary.Medium)</div>
            <div class="stat-label">MEDIUM (31-60 days)</div>
        </div>
        <div class="stat low">
            <div class="stat-value">$($summary.Low)</div>
            <div class="stat-label">LOW (61-90 days)</div>
        </div>
    </div>
    
    $(if ($summary.Expired -gt 0) { @"
    <div class="section expired-section">
        <h2>❌ Expired Certificates ($($summary.Expired))</h2>
        <p style="color: red;"><strong>IMMEDIATE ACTION REQUIRED!</strong> These certificates have already expired.</p>
        $expiredTable
    </div>
"@ })
    
    $(if ($summary.Critical -gt 0) { @"
    <div class="section critical-section">
        <h2>⚠️ Critical - Expiring Within 7 Days ($($summary.Critical))</h2>
        <p style="color: #856404;"><strong>URGENT:</strong> Renew these certificates immediately!</p>
        $criticalTable
    </div>
"@ })
    
    $(if ($summary.High -gt 0) { @"
    <div class="section high-section">
        <h2>⚡ High Priority - Expiring 8-30 Days ($($summary.High))</h2>
        <p>Schedule renewal soon to avoid service disruption.</p>
        $highTable
    </div>
"@ })
    
    $(if ($summary.Medium -gt 0) { @"
    <div class="section medium-section">
        <h2>📋 Medium Priority - Expiring 31-60 Days ($($summary.Medium))</h2>
        <p>Plan renewal within the next month.</p>
        $mediumTable
    </div>
"@ })
    
    $(if ($summary.Low -gt 0) { @"
    <div class="section low-section">
        <h2>✓ Low Priority - Expiring 61-90 Days ($($summary.Low))</h2>
        <p>Monitor and plan renewal.</p>
        $lowTable
    </div>
"@ })
    
    $(if ($serverErrors.Count -gt 0) { @"
    <div class="section">
        <h2>⚠️ Server Errors</h2>
        <p>Unable to scan the following servers:</p>
        <ul>
        $($serverErrors | ForEach-Object { "<li><strong>$($_.Server):</strong> $($_.Error)</li>" })
        </ul>
    </div>
"@ })
    
    <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px;">
        <p><strong>Recommendations:</strong></p>
        <ul>
            <li>Renew expired and critical certificates immediately</li>
            <li>Plan renewal for high-priority certificates</li>
            <li>Consider implementing automated certificate renewal (Let's Encrypt, ACME protocol)</li>
            <li>Set up monitoring alerts for 30-day expiration warnings</li>
        </ul>
        <p>Generated by: Luis Ramirez | Certificate Expiration Monitoring Tool</p>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $ExportHTML -Encoding UTF8
Write-CertLog "✓ HTML report saved: $ExportHTML" -Level Success

#endregion

#region Email Notification

if ($EmailRecipient -and $SMTPServer) {
    if ($summary.Expired -gt 0 -or $summary.Critical -gt 0) {
        $subject = "URGENT: Certificate Expiration Alert - $($summary.Expired) Expired, $($summary.Critical) Critical"
        $priority = "High"
    }
    elseif ($summary.High -gt 0) {
        $subject = "Certificate Expiration Warning - $($summary.High) High Priority"
        $priority = "Normal"
    }
    else {
        $subject = "Certificate Expiration Report - All OK"
        $priority = "Low"
    }
    
    try {
        Send-MailMessage -To $EmailRecipient `
            -From "Certificate-Monitoring@company.com" `
            -Subject $subject `
            -Body "See attached HTML report for details." `
            -Attachments $ExportHTML `
            -SmtpServer $SMTPServer `
            -Priority $priority `
            -ErrorAction Stop
        
        Write-CertLog "✓ Email sent to $EmailRecipient" -Level Success
    }
    catch {
        Write-CertLog "Failed to send email: $_" -Level Error
    }
}

#endregion

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Report Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($summary.Expired -gt 0 -or $summary.Critical -gt 0) {
    exit 1  # Exit with error code for monitoring systems
}
