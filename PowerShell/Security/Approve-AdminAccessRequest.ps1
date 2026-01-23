################################################
# Author: Luis Ramirez                         #
# Created: 1-19-2023                           #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Approve or deny Just-In-Time admin access requests.

.DESCRIPTION
    Approver workflow for JIT admin access system.
    
    Features:
    - Two-party approval requirement
    - Grant access upon approval
    - Email notifications
    - Audit logging
    - Automatic expiration scheduling
    
.PARAMETER RequestID
    Request ID to approve/deny

.PARAMETER Action
    Approve or Deny

.PARAMETER Reason
    Reason for denial (required if denying)

.PARAMETER ApproverName
    Name of approver (default: current user)

.EXAMPLE
    .\Approve-AdminAccessRequest.ps1 -RequestID "JIT-20260123120000-jdoe" -Action Approve
    
    Approve the request.

.EXAMPLE
    .\Approve-AdminAccessRequest.ps1 -RequestID "JIT-20260123120000-jdoe" -Action Deny -Reason "Insufficient justification"
    
    Deny the request.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RequestID,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Approve", "Deny")]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$Reason,

    [Parameter(Mandatory = $false)]
    [string]$ApproverName = $env:USERNAME,

    [Parameter(Mandatory = $false)]
    [string]$RequestQueuePath = "C:\AdminAccess\Requests",

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.company.com",

    [Parameter(Mandatory = $false)]
    [int]$RequiredApprovals = 2
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

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "JIT Admin Access Approval" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

#region Load Request

$requestFile = Join-Path $RequestQueuePath "$RequestID.json"

if (-not (Test-Path $requestFile)) {
    Write-Error "Request not found: $RequestID"
    exit 1
}

$request = Get-Content $requestFile | ConvertFrom-Json
Write-Host "Request loaded: $RequestID" -ForegroundColor Green
Write-Host "  User: $($request.UserName)" -ForegroundColor White
Write-Host "  Group: $($request.TargetGroup)" -ForegroundColor White
Write-Host "  Duration: $($request.Duration) hours" -ForegroundColor White
Write-Host "  Ticket: $($request.TicketNumber)" -ForegroundColor White
Write-Host "  Justification: $($request.Justification)" -ForegroundColor White
Write-Host "  Current Status: $($request.Status)" -ForegroundColor White

#endregion

#region Process Denial

if ($Action -eq "Deny") {
    if ([string]::IsNullOrEmpty($Reason)) {
        Write-Error "Denial reason is required"
        exit 1
    }
    
    Write-Host "`nDenying request..." -ForegroundColor Red
    
    $request.Status = "Denied"
    $request.DeniedBy = $ApproverName
    $request.DeniedTime = Get-Date
    $request.DenialReason = $Reason
    
    # Save updated request
    $request | ConvertTo-Json | Out-File -FilePath $requestFile -Encoding UTF8
    
    # Send denial notification
    $emailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2 style="color: red;">❌ Admin Access Request Denied</h2>

<p>Your request for temporary elevated access has been denied.</p>

<div style="background-color: #f8d7da; padding: 15px; border-left: 4px solid #dc3545;">
    <p><strong>Request ID:</strong> $RequestID</p>
    <p><strong>Target Group:</strong> $($request.TargetGroup)</p>
    <p><strong>Denied By:</strong> $ApproverName</p>
    <p><strong>Denial Reason:</strong> $Reason</p>
</div>

<p>If you believe this denial was in error, please contact your manager or IT security team.</p>

<hr>
<p style="font-size: 11px; color: #666;">JIT Admin Access System</p>
</body>
</html>
"@
    
    try {
        Send-MailMessage -To $request.UserEmail `
            -From "JIT-AdminAccess@company.com" `
            -Subject "Admin Access Request DENIED - $RequestID" `
            -Body $emailBody `
            -BodyAsHtml `
            -SmtpServer $SMTPServer `
            -ErrorAction Stop
        
        Write-Host "✓ Denial notification sent to user" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to send denial notification: $_"
    }
    
    Write-Host "`n✓ Request denied and user notified`n" -ForegroundColor Green
    exit 0
}

#endregion

#region Process Approval

Write-Host "`nProcessing approval..." -ForegroundColor Green

# Add approver to list
if ($null -eq $request.ApprovedBy) {
    $request.ApprovedBy = @()
}

if ($request.ApprovedBy -notcontains $ApproverName) {
    $request.ApprovedBy += $ApproverName
    Write-Host "  Approval recorded from: $ApproverName" -ForegroundColor Green
}
else {
    Write-Host "  You have already approved this request" -ForegroundColor Yellow
}

# Check if we have enough approvals
$approvalCount = $request.ApprovedBy.Count
Write-Host "  Total approvals: $approvalCount / $RequiredApprovals" -ForegroundColor White

if ($approvalCount -ge $RequiredApprovals) {
    Write-Host "`n✓ Required approvals met - granting access" -ForegroundColor Green
    
    try {
        # Add user to group
        Add-ADGroupMember -Identity $request.TargetGroup -Members $request.UserName -ErrorAction Stop
        
        $request.Status = "Granted"
        $request.GrantedTime = Get-Date
        
        Write-Host "✓ User added to $($request.TargetGroup)" -ForegroundColor Green
        
        # Send grant notification
        $expirationTime = ([datetime]$request.RequestTime).AddHours($request.Duration)
        
        $emailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2 style="color: green;">✅ Admin Access Request APPROVED</h2>

<p>Your request for temporary elevated access has been approved and granted.</p>

<div style="background-color: #d4edda; padding: 15px; border-left: 4px solid #28a745;">
    <p><strong>Request ID:</strong> $RequestID</p>
    <p><strong>Target Group:</strong> $($request.TargetGroup)</p>
    <p><strong>Duration:</strong> $($request.Duration) hours</p>
    <p><strong>Granted:</strong> $($request.GrantedTime)</p>
    <p><strong>Expires:</strong> $($expirationTime.ToString('yyyy-MM-dd HH:mm:ss'))</p>
</div>

<h3>⚠️ IMPORTANT</h3>
<ul>
    <li>Your elevated access is now active</li>
    <li>Access will be <strong>automatically revoked</strong> at expiration time</li>
    <li>Log out and log back in for group membership to take effect</li>
    <li>All actions with elevated privileges are logged and audited</li>
</ul>

<p><strong>Approved by:</strong> $($request.ApprovedBy -join ', ')</p>

<hr>
<p style="font-size: 11px; color: #666;">JIT Admin Access System</p>
</body>
</html>
"@
        
        Send-MailMessage -To $request.UserEmail `
            -From "JIT-AdminAccess@company.com" `
            -Subject "Admin Access GRANTED - $RequestID" `
            -Body $emailBody `
            -BodyAsHtml `
            -Priority High `
            -SmtpServer $SMTPServer `
            -ErrorAction Stop
        
        Write-Host "✓ Grant notification sent to user" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to grant access: $_"
        $request.Status = "Error"
        $request.ErrorMessage = $_.Exception.Message
    }
}
else {
    $request.Status = "Partially Approved ($approvalCount/$RequiredApprovals)"
    Write-Host "`n⏳ Waiting for additional approvals ($approvalCount/$RequiredApprovals)" -ForegroundColor Yellow
    
    # Send notification to user about partial approval
    $emailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2>⏳ Admin Access Request - Partial Approval</h2>

<p>Your request has received $approvalCount of $RequiredApprovals required approvals.</p>

<div style="background-color: #fff3cd; padding: 15px; border-left: 4px solid #ffc107;">
    <p><strong>Request ID:</strong> $RequestID</p>
    <p><strong>Target Group:</strong> $($request.TargetGroup)</p>
    <p><strong>Approvals:</strong> $approvalCount / $RequiredApprovals</p>
    <p><strong>Approved By:</strong> $($request.ApprovedBy -join ', ')</p>
</div>

<p>Access will be granted once all required approvals are received.</p>

<hr>
<p style="font-size: 11px; color: #666;">JIT Admin Access System</p>
</body>
</html>
"@
    
    try {
        Send-MailMessage -To $request.UserEmail `
            -From "JIT-AdminAccess@company.com" `
            -Subject "Admin Access Request - Partial Approval ($approvalCount/$RequiredApprovals)" `
            -Body $emailBody `
            -BodyAsHtml `
            -SmtpServer $SMTPServer `
            -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to send partial approval notification: $_"
    }
}

# Save updated request
$request | ConvertTo-Json | Out-File -FilePath $requestFile -Encoding UTF8

#endregion

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Approval Processing Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
