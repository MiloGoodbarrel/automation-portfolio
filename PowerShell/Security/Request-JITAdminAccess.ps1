################################################
# Author: Luis Ramirez                         #
# Created: 9-8-2022                            #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Request temporary elevated admin access (Just-In-Time Admin Access).

.DESCRIPTION
    Implements Zero-Trust privileged access management by requesting temporary elevation.
    
    Workflow:
    1. User requests temporary admin access
    2. Request logged with ticket number, reason, duration
    3. Approval workflow triggered (manager + security team)
    4. Upon approval, elevated access granted for specified time
    5. Automatic revocation after expiration
    6. All actions logged for compliance
    
    Security Features:
    - Requires business justification (ticket number)
    - Maximum duration limits (2-8 hours)
    - Approval required from 2 parties
    - Automatic expiration
    - Complete audit trail
    - Email notifications at key stages
    
.PARAMETER UserName
    User requesting access (default: current user)

.PARAMETER TargetGroup
    Admin group to add user to temporarily

.PARAMETER Duration
    Duration in hours (default: 4, max: 8)

.PARAMETER TicketNumber
    ServiceNow/Jira ticket number (required)

.PARAMETER Justification
    Business reason for elevated access

.PARAMETER EmailApprovers
    Email addresses of approvers

.EXAMPLE
    .\Request-JITAdminAccess.ps1 -TargetGroup "Server Administrators" -Duration 4 -TicketNumber "INC0012345" -Justification "Emergency server maintenance"
    
    Request 4-hour access to Server Administrators group.

.NOTES
    Requires:
    - Active Directory module
    - Permissions to read/write AD
    - Access to approval database/queue
    
    Companion Scripts:
    - Approve-AdminAccessRequest.ps1 (for approvers)
    - Revoke-ExpiredAdminAccess.ps1 (scheduled task)

Author: Luis Ramirez
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$UserName = $env:USERNAME,

    [Parameter(Mandatory = $true)]
    [string]$TargetGroup,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 8)]
    [int]$Duration = 4,

    [Parameter(Mandatory = $true)]
    [string]$TicketNumber,

    [Parameter(Mandatory = $true)]
    [string]$Justification,

    [Parameter(Mandatory = $false)]
    [string[]]$EmailApprovers = @("manager@company.com", "security@company.com"),

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.company.com",

    [Parameter(Mandatory = $false)]
    [string]$RequestQueuePath = "C:\AdminAccess\Requests"
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

function Write-JITLog {
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
    
    # Also log to audit file
    $logFile = Join-Path $RequestQueuePath "audit.log"
    "[$timestamp] [$Level] [$UserName] $Message" | Out-File -FilePath $logFile -Append
}

#endregion

#region Main Script

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Just-In-Time Admin Access Request" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Ensure request queue exists
if (-not (Test-Path $RequestQueuePath)) {
    New-Item -Path $RequestQueuePath -ItemType Directory -Force | Out-Null
}

#region Validate User

Write-JITLog "Validating user: $UserName" -Level Info

try {
    $user = Get-ADUser -Identity $UserName -Properties MemberOf, EmailAddress -ErrorAction Stop
    Write-JITLog "  User found: $($user.Name)" -Level Success
}
catch {
    Write-JITLog "User not found: $UserName" -Level Error
    exit 1
}

#endregion

#region Validate Target Group

Write-JITLog "Validating target group: $TargetGroup" -Level Info

try {
    $group = Get-ADGroup -Identity $TargetGroup -ErrorAction Stop
    Write-JITLog "  Group found: $($group.Name)" -Level Success
}
catch {
    Write-JITLog "Group not found: $TargetGroup" -Level Error
    exit 1
}

# Check if user is already a member
if ($user.MemberOf -contains $group.DistinguishedName) {
    Write-JITLog "User is already a member of $TargetGroup" -Level Warning
    Write-Host "User is already a member. No action needed." -ForegroundColor Yellow
    exit 0
}

#endregion

#region Create Request

$requestID = "JIT-$(Get-Date -Format 'yyyyMMddHHmmss')-$($UserName)"
$requestTime = Get-Date
$expirationTime = $requestTime.AddHours($Duration)

$request = [PSCustomObject]@{
    RequestID = $requestID
    UserName = $UserName
    UserEmail = $user.EmailAddress
    TargetGroup = $TargetGroup
    Duration = $Duration
    TicketNumber = $TicketNumber
    Justification = $Justification
    RequestTime = $requestTime
    ExpirationTime = $expirationTime
    Status = "Pending Approval"
    ApprovedBy = @()
    GrantedTime = $null
    RevokedTime = $null
}

Write-JITLog "Request created: $requestID" -Level Success

# Save request to queue
$requestFile = Join-Path $RequestQueuePath "$requestID.json"
$request | ConvertTo-Json | Out-File -FilePath $requestFile -Encoding UTF8

Write-JITLog "Request saved: $requestFile" -Level Success

#endregion

#region Display Request Summary

Write-Host "`nRequest Summary:" -ForegroundColor Cyan
Write-Host "  Request ID: $requestID" -ForegroundColor White
Write-Host "  User: $UserName" -ForegroundColor White
Write-Host "  Target Group: $TargetGroup" -ForegroundColor White
Write-Host "  Duration: $Duration hours" -ForegroundColor White
Write-Host "  Expiration: $($expirationTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
Write-Host "  Ticket: $TicketNumber" -ForegroundColor White
Write-Host "  Justification: $Justification" -ForegroundColor White

#endregion

#region Send Approval Email

Write-JITLog "Sending approval request emails..." -Level Info

$emailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2>🔐 Just-In-Time Admin Access Request</h2>

<div style="background-color: #f0f0f0; padding: 15px; border-left: 4px solid #0078d4;">
    <p><strong>Request ID:</strong> $requestID</p>
    <p><strong>User:</strong> $UserName ($($user.Name))</p>
    <p><strong>Target Group:</strong> $TargetGroup</p>
    <p><strong>Duration:</strong> $Duration hours</p>
    <p><strong>Expiration:</strong> $($expirationTime.ToString('yyyy-MM-dd HH:mm:ss'))</p>
    <p><strong>Ticket Number:</strong> $TicketNumber</p>
    <p><strong>Business Justification:</strong> $Justification</p>
    <p><strong>Requested:</strong> $($requestTime.ToString('yyyy-MM-dd HH:mm:ss'))</p>
</div>

<h3>Action Required</h3>
<p>Please review this request and approve or deny using:</p>
<p><code>.\Approve-AdminAccessRequest.ps1 -RequestID "$requestID" -Action Approve</code></p>
<p><code>.\Approve-AdminAccessRequest.ps1 -RequestID "$requestID" -Action Deny -Reason "Your reason"</code></p>

<p><strong>Security Note:</strong> Access will be automatically revoked after $Duration hours.</p>

<hr>
<p style="font-size: 11px; color: #666;">
Automated JIT Admin Access System<br>
Request File: $requestFile
</p>
</body>
</html>
"@

foreach ($approver in $EmailApprovers) {
    try {
        Send-MailMessage -To $approver `
            -From "JIT-AdminAccess@company.com" `
            -Subject "ACTION REQUIRED: Admin Access Request - $UserName" `
            -Body $emailBody `
            -BodyAsHtml `
            -Priority High `
            -SmtpServer $SMTPServer `
            -ErrorAction Stop
        
        Write-JITLog "  Email sent to $approver" -Level Success
    }
    catch {
        Write-JITLog "  Failed to send email to $approver : $_" -Level Warning
    }
}

#endregion

#region User Notification

if ($user.EmailAddress) {
    $userEmailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2>Your Admin Access Request</h2>

<p>Your request for temporary elevated access has been submitted and is pending approval.</p>

<div style="background-color: #f0f0f0; padding: 15px; border-left: 4px solid #0078d4;">
    <p><strong>Request ID:</strong> $requestID</p>
    <p><strong>Target Group:</strong> $TargetGroup</p>
    <p><strong>Duration:</strong> $Duration hours</p>
    <p><strong>Ticket:</strong> $TicketNumber</p>
</div>

<p>You will receive a notification when your request is approved or denied.</p>
<p>If approved, access will be automatically granted and will expire at: <strong>$($expirationTime.ToString('yyyy-MM-dd HH:mm:ss'))</strong></p>

<hr>
<p style="font-size: 11px; color: #666;">JIT Admin Access System</p>
</body>
</html>
"@
    
    try {
        Send-MailMessage -To $user.EmailAddress `
            -From "JIT-AdminAccess@company.com" `
            -Subject "Admin Access Request Submitted - $requestID" `
            -Body $userEmailBody `
            -BodyAsHtml `
            -SmtpServer $SMTPServer `
            -ErrorAction Stop
        
        Write-JITLog "User notification sent to $($user.EmailAddress)" -Level Success
    }
    catch {
        Write-JITLog "Failed to send user notification: $_" -Level Warning
    }
}

#endregion

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Request Submitted Successfully" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Your request has been submitted for approval." -ForegroundColor Green
Write-Host "Request ID: $requestID" -ForegroundColor White
Write-Host "`nApprovers have been notified via email." -ForegroundColor White
Write-Host "You will be notified when a decision is made.`n" -ForegroundColor White

Write-JITLog "Request workflow completed for $requestID" -Level Success
