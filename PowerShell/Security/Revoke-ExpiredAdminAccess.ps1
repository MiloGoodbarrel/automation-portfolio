################################################
# Author: Luis Ramirez                         #
# Created: 5-11-2023                           #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Automatically revokes expired JIT admin access grants.

.DESCRIPTION
    Scheduled task script that runs periodically to revoke expired elevated access.
    
    Features:
    - Scans all granted access requests
    - Revokes access that has exceeded duration
    - Sends revocation notifications
    - Updates request status
    - Logs all actions for compliance
    
    Recommended Schedule:
    - Run every 15-30 minutes
    - Runs as SYSTEM or service account with AD permissions
    
.PARAMETER RequestQueuePath
    Path to request queue

.PARAMETER SMTPServer
    SMTP server for notifications

.PARAMETER DryRun
    Test mode - show what would be revoked

.EXAMPLE
    .\Revoke-ExpiredAdminAccess.ps1
    
    Revoke all expired access.

.EXAMPLE
    .\Revoke-ExpiredAdminAccess.ps1 -DryRun
    
    Test mode - see what would be revoked.

.NOTES
    Setup as Scheduled Task:
    
    $action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\Revoke-ExpiredAdminAccess.ps1"
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15) -RepetitionDuration ([TimeSpan]::MaxValue)
    Register-ScheduledTask -TaskName "JIT-Admin-Access-Revocation" -Action $action -Trigger $trigger -User "SYSTEM" -RunLevel Highest

Author: Luis Ramirez
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$RequestQueuePath = "C:\AdminAccess\Requests",

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.company.com",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
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

function Write-RevocationLog {
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
    
    # Log to file
    $logFile = Join-Path $RequestQueuePath "revocation-$(Get-Date -Format 'yyyyMM').log"
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $logFile -Append
}

#endregion

#region Main Script

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "JIT Admin Access - Automatic Revocation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($DryRun) {
    Write-RevocationLog "⚠️  DRY-RUN MODE - No changes will be made" -Level Warning
}

if (-not (Test-Path $RequestQueuePath)) {
    Write-RevocationLog "Request queue not found: $RequestQueuePath" -Level Error
    exit 1
}

#region Scan for Granted Requests

Write-RevocationLog "Scanning for granted access requests..." -Level Info

$requestFiles = Get-ChildItem -Path $RequestQueuePath -Filter "JIT-*.json" -ErrorAction SilentlyContinue

if ($requestFiles.Count -eq 0) {
    Write-RevocationLog "No request files found" -Level Info
    exit 0
}

$revokedCount = 0
$activeCount = 0
$errorCount = 0
$currentTime = Get-Date

foreach ($file in $requestFiles) {
    try {
        $request = Get-Content $file.FullName | ConvertFrom-Json
        
        # Only process granted requests
        if ($request.Status -ne "Granted") {
            continue
        }
        
        $activeCount++
        
        # Calculate expiration
        $grantedTime = [datetime]$request.GrantedTime
        $expirationTime = $grantedTime.AddHours($request.Duration)
        
        # Check if expired
        if ($currentTime -gt $expirationTime) {
            $minutesOverdue = [math]::Round(($currentTime - $expirationTime).TotalMinutes, 1)
            
            Write-RevocationLog "EXPIRED: $($request.RequestID) - User: $($request.UserName), Group: $($request.TargetGroup), Overdue: $minutesOverdue min" -Level Warning
            
            if ($DryRun) {
                Write-RevocationLog "  WOULD REVOKE: Remove $($request.UserName) from $($request.TargetGroup)" -Level Warning
            }
            else {
                try {
                    # Remove user from group
                    Remove-ADGroupMember -Identity $request.TargetGroup -Members $request.UserName -Confirm:$false -ErrorAction Stop
                    
                    # Update request status
                    $request.Status = "Revoked"
                    $request.RevokedTime = $currentTime
                    $request.RevokedReason = "Automatic expiration after $($request.Duration) hours"
                    
                    # Save updated request
                    $request | ConvertTo-Json | Out-File -FilePath $file.FullName -Encoding UTF8
                    
                    Write-RevocationLog "  ✓ REVOKED: $($request.UserName) removed from $($request.TargetGroup)" -Level Success
                    $revokedCount++
                    
                    # Send revocation notification
                    $emailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2>🔒 Admin Access Automatically Revoked</h2>

<p>Your temporary elevated access has expired and been automatically revoked.</p>

<div style="background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107;">
    <p><strong>Request ID:</strong> $($request.RequestID)</p>
    <p><strong>Target Group:</strong> $($request.TargetGroup)</p>
    <p><strong>Granted:</strong> $($request.GrantedTime)</p>
    <p><strong>Duration:</strong> $($request.Duration) hours</p>
    <p><strong>Revoked:</strong> $currentTime</p>
</div>

<h3>What This Means</h3>
<ul>
    <li>Your elevated access has been removed</li>
    <li>You no longer have permissions from the $($request.TargetGroup) group</li>
    <li>If you need continued access, submit a new request</li>
    <li>Log out and log back in for changes to take effect</li>
</ul>

<p>If you need elevated access again, please submit a new request with a valid ticket number.</p>

<hr>
<p style="font-size: 11px; color: #666;">JIT Admin Access System - Automatic Revocation</p>
</body>
</html>
"@
                    
                    try {
                        Send-MailMessage -To $request.UserEmail `
                            -From "JIT-AdminAccess@company.com" `
                            -Subject "Admin Access Revoked - $($request.RequestID)" `
                            -Body $emailBody `
                            -BodyAsHtml `
                            -SmtpServer $SMTPServer `
                            -ErrorAction Stop
                        
                        Write-RevocationLog "    Email notification sent to $($request.UserEmail)" -Level Success
                    }
                    catch {
                        Write-RevocationLog "    Failed to send email: $_" -Level Warning
                    }
                }
                catch {
                    Write-RevocationLog "  ✗ FAILED to revoke $($request.UserName) from $($request.TargetGroup): $_" -Level Error
                    $errorCount++
                }
            }
        }
        else {
            $minutesRemaining = [math]::Round(($expirationTime - $currentTime).TotalMinutes, 1)
            Write-RevocationLog "ACTIVE: $($request.RequestID) - User: $($request.UserName), Remaining: $minutesRemaining min" -Level Info
        }
    }
    catch {
        Write-RevocationLog "Error processing $($file.Name): $_" -Level Error
        $errorCount++
    }
}

#endregion

#region Summary

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Revocation Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-RevocationLog "Active grants: $activeCount" -Level Info
Write-RevocationLog "Revoked (expired): $revokedCount" -Level $(if ($revokedCount -gt 0) { "Success" } else { "Info" })
Write-RevocationLog "Errors: $errorCount" -Level $(if ($errorCount -gt 0) { "Error" } else { "Info" })

if ($DryRun) {
    Write-Host "`n⚠️  Dry-run complete - no changes were made`n" -ForegroundColor Yellow
}

#endregion

# Cleanup old request files (older than 90 days)
Write-RevocationLog "Cleaning up old request files (>90 days)..." -Level Info
$cutoffDate = (Get-Date).AddDays(-90)
$oldFiles = $requestFiles | Where-Object { $_.LastWriteTime -lt $cutoffDate -and (Get-Content $_.FullName | ConvertFrom-Json).Status -in @("Revoked", "Denied") }

if ($oldFiles.Count -gt 0 -and -not $DryRun) {
    $oldFiles | Remove-Item -Force
    Write-RevocationLog "Removed $($oldFiles.Count) old request file(s)" -Level Success
}

Write-RevocationLog "Revocation cycle complete`n" -Level Success
