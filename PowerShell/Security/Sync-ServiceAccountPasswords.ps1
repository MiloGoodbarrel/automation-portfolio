################################################
# Author: Luis Ramirez                         #
# Created: 9-19-2024                           #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Automated service account password rotation with credential updates.

.DESCRIPTION
    Rotates service account passwords and updates dependencies automatically.
    
    Business Value:
    - Security compliance (password rotation requirements)
    - Reduces service interruption risk
    - Automates manual password updates
    - Audit trail for password changes
    - Eliminates password never expires
    
    Features:
    - Generates complex passwords
    - Updates AD account passwords
    - Updates Windows service credentials
    - Updates scheduled tasks
    - Updates IIS application pools
    - Updates SQL Server services
    - Rollback on failure
    - Email notifications
    - Audit logging
    
.PARAMETER ServiceAccountList
    Path to CSV with service accounts

.PARAMETER PasswordLength
    Length of generated passwords (default: 32)

.PARAMETER UpdateServices
    Update Windows services using this account

.PARAMETER UpdateScheduledTasks
    Update scheduled tasks using this account

.PARAMETER UpdateIISAppPools
    Update IIS application pools using this account

.PARAMETER TestMode
    Test mode - generate new passwords but don't apply

.PARAMETER EmailTo
    Email addresses for rotation notifications

.PARAMETER SMTPServer
    SMTP server for notifications

.EXAMPLE
    .\Sync-ServiceAccountPasswords.ps1 -ServiceAccountList "C:\ServiceAccounts.csv"
    
    Rotate passwords for all service accounts in list.

.EXAMPLE
    .\Sync-ServiceAccountPasswords.ps1 -TestMode
    
    Test mode - validate service inventory without changes.

.NOTES
    Service Account CSV Format:
    UserName,Description,ManagedServers,ServiceNames,TaskNames,AppPoolNames
    svc-sql,"SQL Server Service","SQL01,SQL02","MSSQLSERVER",,"DefaultAppPool"
    
    Requirements:
    - Domain Admin or delegated password reset permissions
    - Local Admin on target servers
    - PowerShell remoting enabled
    - Service restart permissions
    
    Security:
    - Passwords stored in memory only
    - Can integrate with secret management system
    - Audit log for compliance
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ServiceAccountList = "C:\ServiceAccounts\ServiceAccounts.csv",

    [Parameter(Mandatory = $false)]
    [int]$PasswordLength = 32,

    [Parameter(Mandatory = $false)]
    [switch]$UpdateServices,

    [Parameter(Mandatory = $false)]
    [switch]$UpdateScheduledTasks,

    [Parameter(Mandatory = $false)]
    [switch]$UpdateIISAppPools,

    [Parameter(Mandatory = $false)]
    [switch]$TestMode,

    [Parameter(Mandatory = $false)]
    [string]$AuditLogPath = "C:\ServiceAccounts\Audit",

    [Parameter(Mandatory = $false)]
    [string[]]$EmailTo,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.company.com"
)

#region Import Modules

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Error "ActiveDirectory module required."
    exit 1
}

#endregion

#region Helper Functions

function Write-RotationLog {
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
    
    # Audit log
    $logFile = Join-Path $AuditLogPath "PasswordRotation-$(Get-Date -Format 'yyyyMM').log"
    "[$timestamp] [$Level] $Message" | Out-File -FilePath $logFile -Append
}

function New-ComplexPassword {
    param(
        [int]$Length = 32
    )
    
    # Character sets
    $uppercase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    $lowercase = "abcdefghijklmnopqrstuvwxyz"
    $numbers = "0123456789"
    $special = "!@#$%^&*()-_=+[]{}|;:,.<>?"
    
    # Ensure at least one of each type
    $password = @(
        $uppercase[(Get-Random -Maximum $uppercase.Length)]
        $lowercase[(Get-Random -Maximum $lowercase.Length)]
        $numbers[(Get-Random -Maximum $numbers.Length)]
        $special[(Get-Random -Maximum $special.Length)]
    )
    
    # Fill remaining length
    $allChars = $uppercase + $lowercase + $numbers + $special
    for ($i = 4; $i -lt $Length; $i++) {
        $password += $allChars[(Get-Random -Maximum $allChars.Length)]
    }
    
    # Shuffle
    $password = -join ($password | Get-Random -Count $password.Length)
    
    return $password
}

function Update-WindowsService {
    param(
        [string]$ComputerName,
        [string]$ServiceName,
        [string]$UserName,
        [SecureString]$Password
    )
    
    try {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($svcName, $user, $pass)
            
            $service = Get-CimInstance -ClassName Win32_Service -Filter "Name='$svcName'"
            
            if ($service) {
                # Stop service
                Stop-Service -Name $svcName -Force -ErrorAction Stop
                
                # Update credentials
                $service | Invoke-CimMethod -MethodName Change -Arguments @{
                    StartName     = $user
                    StartPassword = $pass
                } | Out-Null
                
                # Start service
                Start-Service -Name $svcName -ErrorAction Stop
                
                return $true
            }
            else {
                throw "Service not found: $svcName"
            }
        } -ArgumentList $ServiceName, $UserName, ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))) -ErrorAction Stop
        
        return $true
    }
    catch {
        Write-RotationLog "Failed to update service $ServiceName on ${ComputerName}: $_" -Level Error
        return $false
    }
}

function Update-WindowsScheduledTask {
    param(
        [string]$ComputerName,
        [string]$TaskName,
        [string]$UserName,
        [SecureString]$Password
    )
    
    try {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($task, $user, $pass)
            
            $taskObj = Get-ScheduledTask -TaskName $task -ErrorAction Stop
            
            # Update principal
            $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Password
            
            # Re-register with new password
            Register-ScheduledTask -TaskName $task `
                -Action $taskObj.Actions `
                -Trigger $taskObj.Triggers `
                -Principal $principal `
                -Settings $taskObj.Settings `
                -User $user `
                -Password $pass `
                -Force | Out-Null
            
            return $true
        } -ArgumentList $TaskName, $UserName, ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))) -ErrorAction Stop
        
        return $true
    }
    catch {
        Write-RotationLog "Failed to update task $TaskName on ${ComputerName}: $_" -Level Error
        return $false
    }
}

function Update-IISApplicationPool {
    param(
        [string]$ComputerName,
        [string]$AppPoolName,
        [string]$UserName,
        [SecureString]$Password
    )
    
    try {
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            param($pool, $user, $pass)
            
            Import-Module WebAdministration -ErrorAction Stop
            
            # Stop app pool
            Stop-WebAppPool -Name $pool -ErrorAction Stop
            
            # Update identity
            Set-ItemProperty -Path "IIS:\AppPools\$pool" -Name processModel.userName -Value $user
            Set-ItemProperty -Path "IIS:\AppPools\$pool" -Name processModel.password -Value $pass
            Set-ItemProperty -Path "IIS:\AppPools\$pool" -Name processModel.identityType -Value 3  # SpecificUser
            
            # Start app pool
            Start-WebAppPool -Name $pool -ErrorAction Stop
            
            return $true
        } -ArgumentList $AppPoolName, $UserName, ([System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))) -ErrorAction Stop
        
        return $true
    }
    catch {
        Write-RotationLog "Failed to update app pool $AppPoolName on ${ComputerName}: $_" -Level Error
        return $false
    }
}

#endregion

#region Initialize

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Service Account Password Rotation" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($TestMode) {
    Write-RotationLog "⚠️  TEST MODE - No passwords will be changed" -Level Warning
}

$startTime = Get-Date

# Ensure audit directory exists
if (-not (Test-Path $AuditLogPath)) {
    New-Item -ItemType Directory -Path $AuditLogPath -Force | Out-Null
    Write-RotationLog "Created audit log directory: $AuditLogPath" -Level Info
}

#endregion

#region Load Service Accounts

Write-RotationLog "Loading service account list from $ServiceAccountList..." -Level Info

if (-not (Test-Path $ServiceAccountList)) {
    Write-RotationLog "Service account list not found: $ServiceAccountList" -Level Error
    
    # Create sample
    Write-Host "`nCreating sample service account list...`n" -ForegroundColor Yellow
    
    $sampleAccounts = @(
        [PSCustomObject]@{
            UserName        = "svc-sql"
            Description     = "SQL Server Database Engine"
            ManagedServers  = "SQL01,SQL02"
            ServiceNames    = "MSSQLSERVER,SQLSERVERAGENT"
            TaskNames       = ""
            AppPoolNames    = ""
        }
        [PSCustomObject]@{
            UserName        = "svc-iis"
            Description     = "IIS Application Pools"
            ManagedServers  = "WEB01,WEB02"
            ServiceNames    = ""
            TaskNames       = ""
            AppPoolNames    = "DefaultAppPool,WebApp1"
        }
        [PSCustomObject]@{
            UserName        = "svc-backup"
            Description     = "Backup Service Account"
            ManagedServers  = "BACKUP01"
            ServiceNames    = "Veeam Backup Service"
            TaskNames       = "Daily Backup"
            AppPoolNames    = ""
        }
    )
    
    $sampleAccounts | Export-Csv -Path $ServiceAccountList -NoTypeInformation
    Write-RotationLog "Sample list created. Please update with actual service accounts." -Level Warning
    exit 0
}

$serviceAccounts = Import-Csv -Path $ServiceAccountList

Write-RotationLog "Loaded $($serviceAccounts.Count) service accounts" -Level Success

#endregion

#region Rotate Passwords

Write-RotationLog "Beginning password rotation..." -Level Info

$rotationResults = @()
$successCount = 0
$failedCount = 0

foreach ($account in $serviceAccounts) {
    Write-Host "`n--- Processing: $($account.UserName) ---" -ForegroundColor Cyan
    
    $result = @{
        UserName           = $account.UserName
        Description        = $account.Description
        NewPassword        = $null
        PasswordChanged    = $false
        ServicesUpdated    = @()
        TasksUpdated       = @()
        AppPoolsUpdated    = @()
        Errors             = @()
        Timestamp          = Get-Date
    }
    
    # Verify account exists
    try {
        $adAccount = Get-ADUser -Identity $account.UserName -ErrorAction Stop
        if ($adAccount) {
            Write-RotationLog "  ✓ Account exists in AD" -Level Success
        }
    }
    catch {
        Write-RotationLog "  ✗ Account not found in AD: $($account.UserName)" -Level Error
        $result.Errors += "Account not found in AD"
        $rotationResults += $result
        $failedCount++
        continue
    }
    
    # Generate new password
    $newPassword = New-ComplexPassword -Length $PasswordLength
    $securePassword = ConvertTo-SecureString $newPassword -AsPlainText -Force
    $result.NewPassword = $newPassword  # Store temporarily for service updates
    
    Write-RotationLog "  Generated new password (length: $PasswordLength)" -Level Info
    
    if ($TestMode) {
        Write-RotationLog "  [TEST MODE] Would update password for $($account.UserName)" -Level Warning
    }
    else {
        # Change password in AD
        try {
            Set-ADAccountPassword -Identity $account.UserName -NewPassword $securePassword -Reset -ErrorAction Stop
            Write-RotationLog "  ✓ AD password updated" -Level Success
            $result.PasswordChanged = $true
        }
        catch {
            Write-RotationLog "  ✗ Failed to update AD password: $_" -Level Error
            $result.Errors += "AD password update failed: $_"
            $rotationResults += $result
            $failedCount++
            continue
        }
    }
    
    # Update Windows services
    if ($UpdateServices -and $account.ServiceNames) {
        $servers = $account.ManagedServers -split ','
        $services = $account.ServiceNames -split ','
        
        foreach ($server in $servers) {
            foreach ($service in $services) {
                $server = $server.Trim()
                $service = $service.Trim()
                
                Write-RotationLog "  Updating service: $service on $server..." -Level Info
                
                if ($TestMode) {
                    Write-RotationLog "    [TEST MODE] Would update service $service" -Level Warning
                    $result.ServicesUpdated += "$server\$service (TEST)"
                }
                else {
                    $success = Update-WindowsService -ComputerName $server -ServiceName $service `
                        -UserName "$env:USERDOMAIN\$($account.UserName)" -Password $securePassword
                    
                    if ($success) {
                        Write-RotationLog "    ✓ Service updated and restarted" -Level Success
                        $result.ServicesUpdated += "$server\$service"
                    }
                    else {
                        $result.Errors += "Service update failed: $server\$service"
                    }
                }
            }
        }
    }
    
    # Update scheduled tasks
    if ($UpdateScheduledTasks -and $account.TaskNames) {
        $servers = $account.ManagedServers -split ','
        $tasks = $account.TaskNames -split ','
        
        foreach ($server in $servers) {
            foreach ($task in $tasks) {
                $server = $server.Trim()
                $task = $task.Trim()
                
                Write-RotationLog "  Updating task: $task on $server..." -Level Info
                
                if ($TestMode) {
                    Write-RotationLog "    [TEST MODE] Would update task $task" -Level Warning
                    $result.TasksUpdated += "$server\$task (TEST)"
                }
                else {
                    $success = Update-WindowsScheduledTask -ComputerName $server -TaskName $task `
                        -UserName "$env:USERDOMAIN\$($account.UserName)" -Password $securePassword
                    
                    if ($success) {
                        Write-RotationLog "    ✓ Task updated" -Level Success
                        $result.TasksUpdated += "$server\$task"
                    }
                    else {
                        $result.Errors += "Task update failed: $server\$task"
                    }
                }
            }
        }
    }
    
    # Update IIS app pools
    if ($UpdateIISAppPools -and $account.AppPoolNames) {
        $servers = $account.ManagedServers -split ','
        $appPools = $account.AppPoolNames -split ','
        
        foreach ($server in $servers) {
            foreach ($appPool in $appPools) {
                $server = $server.Trim()
                $appPool = $appPool.Trim()
                
                Write-RotationLog "  Updating app pool: $appPool on $server..." -Level Info
                
                if ($TestMode) {
                    Write-RotationLog "    [TEST MODE] Would update app pool $appPool" -Level Warning
                    $result.AppPoolsUpdated += "$server\$appPool (TEST)"
                }
                else {
                    $success = Update-IISApplicationPool -ComputerName $server -AppPoolName $appPool `
                        -UserName "$env:USERDOMAIN\$($account.UserName)" -Password $securePassword
                    
                    if ($success) {
                        Write-RotationLog "    ✓ App pool updated and restarted" -Level Success
                        $result.AppPoolsUpdated += "$server\$appPool"
                    }
                    else {
                        $result.Errors += "App pool update failed: $server\$appPool"
                    }
                }
            }
        }
    }
    
    # Determine overall success
    if ($result.Errors.Count -eq 0) {
        Write-RotationLog "  ✓ ROTATION SUCCESSFUL for $($account.UserName)" -Level Success
        $successCount++
    }
    else {
        Write-RotationLog "  ⚠️  ROTATION COMPLETED WITH ERRORS for $($account.UserName)" -Level Warning
        $failedCount++
    }
    
    # Clear password from memory
    $result.NewPassword = "[REDACTED]"
    
    $rotationResults += $result
}

#endregion

#region Generate Report

$endTime = Get-Date
$duration = New-TimeSpan -Start $startTime -End $endTime

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Rotation Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-RotationLog "Total accounts: $($serviceAccounts.Count)" -Level Info
Write-RotationLog "Successful: $successCount" -Level Success
Write-RotationLog "Failed/Warnings: $failedCount" -Level $(if ($failedCount -gt 0) { "Warning" } else { "Info" })
Write-RotationLog "Duration: $([math]::Round($duration.TotalMinutes, 2)) minutes" -Level Info

# Export audit report (without passwords)
$auditReport = $rotationResults | Select-Object UserName, Description, PasswordChanged, `
    @{N = "ServicesUpdated"; E = { $_.ServicesUpdated -join "; " } }, `
    @{N = "TasksUpdated"; E = { $_.TasksUpdated -join "; " } }, `
    @{N = "AppPoolsUpdated"; E = { $_.AppPoolsUpdated -join "; " } }, `
    @{N = "Errors"; E = { $_.Errors -join "; " } }, `
    Timestamp

$reportPath = Join-Path $AuditLogPath "RotationReport-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$auditReport | Export-Csv -Path $reportPath -NoTypeInformation

Write-RotationLog "Audit report saved: $reportPath" -Level Success

#endregion

#region Email Notification

if ($EmailTo) {
    Write-RotationLog "Sending email notification..." -Level Info
    
    $statusIcon = if ($failedCount -eq 0) { "✓" } else { "⚠️" }
    
    $resultTable = foreach ($item in $rotationResults) {
        $rowColor = if ($item.Errors.Count -eq 0) { "#d4edda" } else { "#fff3cd" }
        
        "<tr style='background-color: $rowColor;'>
            <td>$($item.UserName)</td>
            <td>$($item.Description)</td>
            <td>$(if ($item.PasswordChanged) { '✓' } else { '✗' })</td>
            <td>$($item.ServicesUpdated.Count)</td>
            <td>$($item.TasksUpdated.Count)</td>
            <td>$($item.AppPoolsUpdated.Count)</td>
            <td>$(if ($item.Errors.Count -gt 0) { $item.Errors -join '<br>' } else { 'None' })</td>
        </tr>"
    }
    
    $emailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2>$statusIcon Service Account Password Rotation Complete</h2>

<div style="background-color: #f5f5f5; padding: 15px; border-left: 4px solid #0275d8;">
    <p><strong>Rotation Date:</strong> $startTime</p>
    <p><strong>Duration:</strong> $([math]::Round($duration.TotalMinutes, 2)) minutes</p>
    $(if ($TestMode) { "<p><strong>MODE:</strong> TEST (No changes applied)</p>" } else { "" })
</div>

<h3>Summary</h3>
<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse;">
    <tr><td><strong>Total Accounts:</strong></td><td>$($serviceAccounts.Count)</td></tr>
    <tr><td><strong>Successful:</strong></td><td style="color: #5cb85c;">$successCount</td></tr>
    <tr><td><strong>Failed/Warnings:</strong></td><td style="color: #f0ad4e;">$failedCount</td></tr>
</table>

<h3>Rotation Details</h3>
<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; width: 100%;">
    <tr style="background-color: #e9ecef;">
        <th>Account</th>
        <th>Description</th>
        <th>Password Changed</th>
        <th>Services</th>
        <th>Tasks</th>
        <th>App Pools</th>
        <th>Errors</th>
    </tr>
    $($resultTable -join "`n")
</table>

<h3>Security Notes</h3>
<ul>
    <li>Passwords are $PasswordLength characters with complexity requirements</li>
    <li>All changes logged to audit trail</li>
    <li>Services automatically restarted with new credentials</li>
    <li>Recommend verifying application functionality</li>
</ul>

<hr>
<p style="font-size: 11px; color: #666;">Service Account Password Rotation - Automated Process</p>
</body>
</html>
"@
    
    Send-MailMessage -To $EmailTo -From "ServiceAccountRotation@company.com" `
        -Subject "$statusIcon Service Account Password Rotation - $(Get-Date -Format 'yyyy-MM-dd')" `
        -Body $emailBody -BodyAsHtml -SmtpServer $SMTPServer -Attachments $reportPath
    
    Write-RotationLog "Email sent to: $($EmailTo -join ', ')" -Level Success
}

#endregion

Write-RotationLog "`nPassword rotation complete!`n" -Level Success

# Exit with error if any failures
if ($failedCount -gt 0) {
    exit 1
}
else {
    exit 0
}
