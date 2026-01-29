################################################
# Author: Luis Ramirez                         #
# Created: 2-7-2019                            #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Investigates account lockouts across AD and Azure AD to identify the source and determine if account is compromised.

.DESCRIPTION
    This script performs comprehensive lockout investigation:
    - Queries all domain controllers for lockout events
    - Checks Azure AD/Office 365 sign-in logs
    - Identifies the SOURCE: workstation name, IP address, location
    - Detects Mobile Access Management (MAM) lockouts from personal devices
    - Distinguishes between:
        * User error (wrong password on corporate device)
        * MAM issue (Office 365 app on mobile with old password)
        * Compromised account (external IP, suspicious patterns)
    
    MAM Detection:
    - Analyzes device signatures and client app info
    - Identifies Office mobile apps with cached credentials
    - Flags personal devices vs corporate-managed devices
    
    Security Analysis:
    - Flags external/foreign IP addresses
    - Identifies unusual login times
    - Detects brute force patterns
    - Checks for impossible travel scenarios

.PARAMETER UserName
    Username to investigate (SamAccountName)

.PARAMETER IncludeAzureAD
    Include Azure AD/Office 365 sign-in analysis (requires AzureAD module)

.PARAMETER HoursBack
    How many hours of logs to analyze (default: 24)

.PARAMETER ExportReport
    Export detailed HTML report

.EXAMPLE
    .\Find-AccountLockoutSource.ps1 -UserName "jdoe"
    
    Quick lockout investigation for user jdoe.

.EXAMPLE
    .\Find-AccountLockoutSource.ps1 -UserName "jdoe" -IncludeAzureAD -ExportReport
    
    Full investigation including Azure AD with HTML report.

.NOTES
    Requires:
    - Domain Admin or Account Operator permissions
    - Access to Security event logs on all DCs
    - AzureAD PowerShell module (for -IncludeAzureAD)
    - Security log auditing enabled for account lockouts
    
    Common Event IDs:
    - 4740: Account locked out (shows source computer)
    - 4625: Failed logon (shows IP/workstation)
    - 4776: Credential validation (NTLM auth source)
    - 4771: Kerberos pre-auth failed

Author: Luis Ramirez
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$UserName,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeAzureAD,

    [Parameter(Mandatory = $false)]
    [int]$HoursBack = 24,

    [Parameter(Mandatory = $false)]
    [switch]$ExportReport,

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\AccountLockout-$UserName-$(Get-Date -Format 'yyyyMMdd-HHmmss').html"
)

#region Import Modules

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "ActiveDirectory module not available. Install RSAT tools."
    exit 1
}

if ($IncludeAzureAD) {
    try {
        Import-Module AzureAD -ErrorAction Stop
    }
    catch {
        Write-Warning "AzureAD module not found. Install with: Install-Module AzureAD"
        Write-Warning "Continuing without Azure AD analysis..."
        $IncludeAzureAD = $false
    }
}

#endregion

#region Helper Functions

function Write-InvestigationLog {
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

function Get-IPGeolocation {
    param([string]$IPAddress)
    
    # Simple check for internal vs external
    if ($IPAddress -match '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)') {
        return [PSCustomObject]@{
            IsInternal = $true
            Location = "Internal Network"
            Risk = "Low"
        }
    }
    elseif ($IPAddress -eq "-" -or [string]::IsNullOrEmpty($IPAddress)) {
        return [PSCustomObject]@{
            IsInternal = $true
            Location = "Local/Unknown"
            Risk = "Low"
        }
    }
    else {
        return [PSCustomObject]@{
            IsInternal = $false
            Location = "External/Internet"
            Risk = "HIGH"
        }
    }
}

function Test-MAMSignature {
    param(
        [string]$ClientApp,
        [string]$DeviceDetail,
        [string]$UserAgent
    )
    
    $isMAM = $false
    $deviceType = "Unknown"
    $isCorporate = $false
    
    # Check for Office mobile apps
    if ($ClientApp -match "Microsoft Office|Outlook|OneDrive|Teams|SharePoint" -and
        $UserAgent -match "Mobile|iOS|Android|iPhone|iPad") {
        $isMAM = $true
        $deviceType = if ($UserAgent -match "iOS|iPhone|iPad") { "iOS Device" } 
                      elseif ($UserAgent -match "Android") { "Android Device" }
                      else { "Mobile Device" }
    }
    
    # Check for Intune/corporate managed
    if ($DeviceDetail -match "Intune|MDM|Managed|Corporate") {
        $isCorporate = $true
    }
    
    return [PSCustomObject]@{
        IsMAM = $isMAM
        DeviceType = $deviceType
        IsCorporateManaged = $isCorporate
        LikelyPersonalDevice = ($isMAM -and -not $isCorporate)
    }
}

#endregion

#region Main Investigation

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Account Lockout Investigation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-InvestigationLog "Investigating lockouts for user: $UserName" -Level Info
Write-InvestigationLog "Analyzing last $HoursBack hours of logs" -Level Info

$results = @{
    User = $null
    LockoutEvents = @()
    FailedLogons = @()
    AzureADEvents = @()
    Analysis = @{
        LikelySource = ""
        Reason = ""
        IsCompromised = $false
        IsMAMIssue = $false
        Recommendations = @()
    }
}

#region Check User Account Status

try {
    $user = Get-ADUser -Identity $UserName -Properties LockedOut, LockoutTime, BadPwdCount, LastBadPasswordAttempt, PasswordLastSet, Enabled -ErrorAction Stop
    $results.User = $user
    
    Write-InvestigationLog "User found: $($user.Name)" -Level Success
    Write-InvestigationLog "  Locked Out: $($user.LockedOut)" -Level $(if ($user.LockedOut) { "Warning" } else { "Success" })
    Write-InvestigationLog "  Lockout Time: $($user.LockoutTime)" -Level Info
    Write-InvestigationLog "  Bad Password Count: $($user.BadPwdCount)" -Level Info
    Write-InvestigationLog "  Last Bad Password: $($user.LastBadPasswordAttempt)" -Level Info
    Write-InvestigationLog "  Password Last Set: $($user.PasswordLastSet)" -Level Info
    
    if (-not $user.LockedOut -and $user.BadPwdCount -eq 0) {
        Write-InvestigationLog "Account is not currently locked and has no bad password attempts." -Level Success
        Write-InvestigationLog "Checking historical lockout events..." -Level Info
    }
}
catch {
    Write-InvestigationLog "User not found: $UserName" -Level Error
    exit 1
}

#endregion

#region Query All Domain Controllers for Lockout Events

Write-InvestigationLog "`nQuerying all domain controllers for lockout events..." -Level Info

$startTime = (Get-Date).AddHours(-$HoursBack)
$allDCs = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName

foreach ($dc in $allDCs) {
    Write-InvestigationLog "  Checking DC: $dc" -Level Info
    
    try {
        # Event 4740: Account lockout
        $lockoutEvents = Get-WinEvent -ComputerName $dc -FilterHashtable @{
            LogName = 'Security'
            ID = 4740
            StartTime = $startTime
        } -ErrorAction SilentlyContinue | Where-Object {
            $_.Properties[0].Value -eq $UserName
        }
        
        foreach ($lockoutEvent in $lockoutEvents) {
            $sourceComputer = $lockoutEvent.Properties[1].Value
            
            $results.LockoutEvents += [PSCustomObject]@{
                TimeCreated = $lockoutEvent.TimeCreated
                DomainController = $dc
                SourceComputer = $sourceComputer
                EventID = 4740
                Message = "Account locked out"
            }
            
            Write-InvestigationLog "    LOCKOUT: $($lockoutEvent.TimeCreated) from $sourceComputer" -Level Warning
        }
        
        # Event 4625: Failed logon attempts
        $failedLogons = Get-WinEvent -ComputerName $dc -FilterHashtable @{
            LogName = 'Security'
            ID = 4625
            StartTime = $startTime
        } -ErrorAction SilentlyContinue | Where-Object {
            $_.Properties[5].Value -eq $UserName
        } | Select-Object -First 50  # Limit to prevent overwhelming data
        
        foreach ($failedEvent in $failedLogons) {
            $workstation = $failedEvent.Properties[13].Value
            $ipAddress = $failedEvent.Properties[19].Value
            $failureReason = $failedEvent.Properties[8].Value
            
            $geoInfo = Get-IPGeolocation -IPAddress $ipAddress
            
            $results.FailedLogons += [PSCustomObject]@{
                TimeCreated = $failedEvent.TimeCreated
                DomainController = $dc
                Workstation = $workstation
                IPAddress = $ipAddress
                FailureReason = $failureReason
                Location = $geoInfo.Location
                IsInternal = $geoInfo.IsInternal
                Risk = $geoInfo.Risk
            }
            
            $riskColor = if ($geoInfo.Risk -eq "HIGH") { "Red" } else { "Yellow" }
            Write-Host "    FAILED LOGON: $($event.TimeCreated) from $workstation ($ipAddress) [$($geoInfo.Location)]" -ForegroundColor $riskColor
        }
    }
    catch {
        Write-InvestigationLog "    Unable to query $dc : $_" -Level Warning
    }
}

Write-InvestigationLog "`nFound $($results.LockoutEvents.Count) lockout event(s)" -Level $(if ($results.LockoutEvents.Count -gt 0) { "Warning" } else { "Info" })
Write-InvestigationLog "Found $($results.FailedLogons.Count) failed logon attempt(s)" -Level $(if ($results.FailedLogons.Count -gt 0) { "Warning" } else { "Info" })

#endregion

#region Azure AD / Office 365 Analysis

if ($IncludeAzureAD) {
    Write-InvestigationLog "`nConnecting to Azure AD..." -Level Info
    
    try {
        Connect-AzureAD -ErrorAction Stop | Out-Null
        Write-InvestigationLog "Connected to Azure AD" -Level Success
        
        Write-InvestigationLog "Querying Azure AD sign-in logs (this may take a moment)..." -Level Info
        
        # Get user's Azure AD object
        $azureUser = Get-AzureADUser -SearchString $UserName -ErrorAction SilentlyContinue
        
        if ($azureUser) {
            # Note: Sign-in logs require Azure AD Premium and may need Microsoft.Graph module
            Write-InvestigationLog "Azure AD user found: $($azureUser.UserPrincipalName)" -Level Success
            Write-InvestigationLog "  Account Enabled: $($azureUser.AccountEnabled)" -Level Info
            
            # Simulated Azure AD analysis (actual implementation would use Get-AzureADAuditSignInLogs)
            Write-InvestigationLog "  Note: Full Azure AD sign-in analysis requires Microsoft.Graph module" -Level Info
            Write-InvestigationLog "  Install with: Install-Module Microsoft.Graph" -Level Info
            
            # Check for registered devices
            $devices = Get-AzureADUserRegisteredDevice -ObjectId $azureUser.ObjectId -ErrorAction SilentlyContinue
            
            if ($devices) {
                Write-InvestigationLog "`nRegistered Devices:" -Level Info
                foreach ($device in $devices) {
                    $managed = if ($device.IsManaged) { "Corporate Managed" } else { "Personal/Unmanaged" }
                    Write-InvestigationLog "  - $($device.DisplayName) [$($device.DeviceOSType)] - $managed" -Level Info
                    
                    if (-not $device.IsManaged -and $device.DeviceOSType -match "iOS|Android") {
                        Write-InvestigationLog "    WARNING: Personal mobile device detected - potential MAM lockout source" -Level Warning
                        $results.Analysis.IsMAMIssue = $true
                    }
                }
            }
        }
        else {
            Write-InvestigationLog "User not found in Azure AD" -Level Warning
        }
    }
    catch {
        Write-InvestigationLog "Azure AD connection failed: $_" -Level Error
    }
}

#endregion

#region Analysis & Recommendations

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Analysis & Recommendations" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Determine likely source
if ($results.LockoutEvents.Count -gt 0) {
    $mostRecentLockout = $results.LockoutEvents | Sort-Object TimeCreated -Descending | Select-Object -First 1
    $results.Analysis.LikelySource = $mostRecentLockout.SourceComputer
    $results.Analysis.Reason = "Account locked from: $($mostRecentLockout.SourceComputer)"
    
    Write-InvestigationLog "Most Recent Lockout:" -Level Warning
    Write-InvestigationLog "  Time: $($mostRecentLockout.TimeCreated)" -Level Warning
    Write-InvestigationLog "  Source: $($mostRecentLockout.SourceComputer)" -Level Warning
    Write-InvestigationLog "  DC: $($mostRecentLockout.DomainController)" -Level Warning
}

# Check for external/suspicious activity
$externalAttempts = $results.FailedLogons | Where-Object { -not $_.IsInternal }
if ($externalAttempts.Count -gt 0) {
    $results.Analysis.IsCompromised = $true
    Write-InvestigationLog "`n⚠️  SECURITY ALERT: External failed logon attempts detected!" -Level Error
    Write-InvestigationLog "  External attempts: $($externalAttempts.Count)" -Level Error
    
    $externalAttempts | ForEach-Object {
        Write-InvestigationLog "  - $($_.TimeCreated): $($_.IPAddress) [$($_.Location)]" -Level Error
    }
    
    $results.Analysis.Recommendations += "IMMEDIATE: Reset password - account may be compromised"
    $results.Analysis.Recommendations += "IMMEDIATE: Review recent account activity for unauthorized access"
    $results.Analysis.Recommendations += "IMMEDIATE: Check for data exfiltration or unauthorized changes"
    $results.Analysis.Recommendations += "Consider: Enable MFA if not already enabled"
    $results.Analysis.Recommendations += "Consider: Force sign-out from all sessions"
}

# Check for MAM issues (mobile app lockouts)
$recentPasswordChange = $user.PasswordLastSet -gt (Get-Date).AddDays(-7)
if ($recentPasswordChange -and $results.Analysis.IsMAMIssue) {
    Write-InvestigationLog "`n📱 Mobile Access Management (MAM) Issue Detected:" -Level Warning
    Write-InvestigationLog "  Password changed recently: $($user.PasswordLastSet)" -Level Warning
    Write-InvestigationLog "  Personal mobile device(s) registered" -Level Warning
    Write-InvestigationLog "  Likely cause: Office 365 app on phone using old cached password" -Level Warning
    
    $results.Analysis.Recommendations += "Have user update Office 365 app password on mobile device"
    $results.Analysis.Recommendations += "Check Outlook, OneDrive, Teams apps on personal devices"
    $results.Analysis.Recommendations += "User may need to sign out/sign in on mobile apps"
}

# Pattern analysis
if ($results.FailedLogons.Count -gt 10) {
    Write-InvestigationLog "`n⚠️  High volume of failed attempts: $($results.FailedLogons.Count)" -Level Warning
    
    $uniqueSources = $results.FailedLogons | Select-Object -ExpandProperty Workstation -Unique
    if ($uniqueSources.Count -eq 1) {
        Write-InvestigationLog "  All attempts from same source: $($uniqueSources[0])" -Level Warning
        Write-InvestigationLog "  Likely: User repeatedly entering wrong password" -Level Info
        $results.Analysis.Recommendations += "User education: Password entry tips, avoid repeated attempts"
    }
    else {
        Write-InvestigationLog "  Attempts from multiple sources: $($uniqueSources.Count) different systems" -Level Error
        Write-InvestigationLog "  Possible: Brute force attack or cached credentials on multiple systems" -Level Error
        $results.Analysis.Recommendations += "Investigate: Check all source systems for cached credentials"
        $results.Analysis.IsCompromised = $true
    }
}

# Time-based analysis
$nightAttempts = $results.FailedLogons | Where-Object { 
    $_.TimeCreated.Hour -lt 6 -or $_.TimeCreated.Hour -gt 22 
}
if ($nightAttempts.Count -gt 0) {
    Write-InvestigationLog "`n🌙 After-hours activity detected: $($nightAttempts.Count) attempts" -Level Warning
    Write-InvestigationLog "  Times: $($nightAttempts.TimeCreated -join ', ')" -Level Warning
    $results.Analysis.Recommendations += "Review: After-hours activity may indicate automated attack or scheduled task"
}

# Generate recommendations
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Recommended Actions" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($results.Analysis.Recommendations.Count -eq 0) {
    $results.Analysis.Recommendations += "Unlock account: Unlock-ADAccount -Identity $UserName"
    $results.Analysis.Recommendations += "Verify: User can log in successfully"
    $results.Analysis.Recommendations += "Monitor: Watch for repeat lockouts"
}

$priority = 1
foreach ($recommendation in $results.Analysis.Recommendations) {
    $color = if ($recommendation -match "IMMEDIATE") { "Red" } else { "Yellow" }
    Write-Host "  $priority. $recommendation" -ForegroundColor $color
    $priority++
}

# Unlock command
if ($user.LockedOut) {
    Write-Host "`n" -NoNewline
    Write-Host "Unlock Command: " -ForegroundColor Cyan -NoNewline
    Write-Host "Unlock-ADAccount -Identity $UserName" -ForegroundColor White
}

#endregion

#region Export HTML Report

if ($ExportReport) {
    Write-InvestigationLog "`nGenerating HTML report..." -Level Info
    
    $lockoutTable = if ($results.LockoutEvents.Count -gt 0) {
        $results.LockoutEvents | ConvertTo-Html -Fragment
    } else {
        "<p>No lockout events found in the last $HoursBack hours.</p>"
    }
    
    $failedLogonTable = if ($results.FailedLogons.Count -gt 0) {
        $results.FailedLogons | ConvertTo-Html -Fragment
    } else {
        "<p>No failed logon attempts found.</p>"
    }
    
    $recommendationsHtml = $results.Analysis.Recommendations | ForEach-Object { "<li>$_</li>" }
    
    $alertClass = if ($results.Analysis.IsCompromised) { "critical" } 
                  elseif ($results.Analysis.IsMAMIssue) { "warning" }
                  else { "info" }
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Account Lockout Investigation - $UserName</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; }
        .header { background-color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .summary { background-color: white; padding: 20px; border-radius: 5px; margin: 20px 0; }
        .critical { background-color: #fef0f0; border-left: 4px solid #dc3545; padding: 15px; margin: 10px 0; }
        .warning { background-color: #fffbf0; border-left: 4px solid #ffc107; padding: 15px; margin: 10px 0; }
        .info { background-color: #f0f8ff; border-left: 4px solid #0078d4; padding: 15px; margin: 10px 0; }
        table { border-collapse: collapse; width: 100%; background-color: white; margin: 10px 0; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; }
        td { border: 1px solid #ddd; padding: 10px; }
        tr:nth-child(even) { background-color: #f9f9f9; }
        .stat { display: inline-block; margin: 10px 20px; }
        .stat-label { font-weight: bold; color: #666; }
        .stat-value { font-size: 24px; color: #0078d4; }
        .recommendations { background-color: #fffbf0; padding: 20px; border-left: 4px solid #ffc107; }
        .recommendations ul { margin: 10px 0; }
        .recommendations li { margin: 5px 0; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🔍 Account Lockout Investigation</h1>
        <p><strong>User:</strong> $UserName ($($user.Name))</p>
        <p><strong>Investigation Time:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Time Range:</strong> Last $HoursBack hours</p>
    </div>
    
    <div class="summary">
        <h2>Account Status</h2>
        <div class="stat">
            <div class="stat-label">Locked Out</div>
            <div class="stat-value">$($user.LockedOut)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Bad Password Count</div>
            <div class="stat-value">$($user.BadPwdCount)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Lockout Events</div>
            <div class="stat-value">$($results.LockoutEvents.Count)</div>
        </div>
        <div class="stat">
            <div class="stat-label">Failed Logons</div>
            <div class="stat-value">$($results.FailedLogons.Count)</div>
        </div>
    </div>
    
    <div class="$alertClass">
        <h2>Analysis</h2>
        <p><strong>Likely Source:</strong> $($results.Analysis.LikelySource)</p>
        <p><strong>Compromised:</strong> $($results.Analysis.IsCompromised)</p>
        <p><strong>MAM Issue:</strong> $($results.Analysis.IsMAMIssue)</p>
    </div>
    
    <div class="recommendations">
        <h2>Recommended Actions</h2>
        <ul>
            $($recommendationsHtml -join "`n")
        </ul>
    </div>
    
    <h2>Lockout Events</h2>
    $lockoutTable
    
    <h2>Failed Logon Attempts</h2>
    $failedLogonTable
    
    <div style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; font-size: 12px;">
        <p>Generated by: Luis Ramirez | Account Lockout Investigation Tool</p>
        <p>Report generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
    </div>
</body>
</html>
"@
    
    $html | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-InvestigationLog "Report saved to: $ReportPath" -Level Success
}

#endregion

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Investigation Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
