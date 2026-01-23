################################################
# Author: Luis Ramirez                         #
# Created: 5-27-2021                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# This script is the service desk counterpart to Request-AdminAccessVerification  #
# Service desk personnel run this script, enter the user's verification code,     #
# and receive the password to provide back to the user for access approval.       #
#                                                                                  #
# This script uses the same algorithm as Request-AdminAccessVerification.ps1 to   #
# generate matching access codes for verification.                                #
#                                                                                  #
# Example: .\Grant-AdminAccessCode.ps1                                            #
####################################################################################>

Clear-Host

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create input form for verification code
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Service Desk - Access Code Generator'
$form.Size = New-Object System.Drawing.Size(300, 200)
$form.StartPosition = 'CenterScreen'

$OKButton = New-Object System.Windows.Forms.Button
$OKButton.Location = New-Object System.Drawing.Point(75, 120)
$OKButton.Size = New-Object System.Drawing.Size(75, 23)
$OKButton.Text = 'OK'
$OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.AcceptButton = $OKButton
$form.Controls.Add($OKButton)

$CancelButton = New-Object System.Windows.Forms.Button
$CancelButton.Location = New-Object System.Drawing.Point(150, 120)
$CancelButton.Size = New-Object System.Drawing.Size(75, 23)
$CancelButton.Text = 'Cancel'
$CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.CancelButton = $CancelButton
$form.Controls.Add($CancelButton)

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(10, 20)
$label.Size = New-Object System.Drawing.Size(280, 20)
$label.Text = 'Enter the Verification Code from User:'
$form.Controls.Add($label)

$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Location = New-Object System.Drawing.Point(10, 40)
$textBox.Size = New-Object System.Drawing.Size(260, 20)
$form.Controls.Add($textBox)

$form.Topmost = $true
$form.Add_Shown({ $textBox.Select() })

$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    $verificationCode = $textBox.Text

    # Convert to integer and apply algorithm
    $codeNumber = $verificationCode -as [int]

    if ($null -eq $codeNumber) {
        [System.Windows.MessageBox]::Show("Invalid verification code. Please enter a numeric value.", 'Error', 'OK', 'Error')
        exit
    }

    # Calculate access password using same algorithm as Request script
    $password = ([int]$codeNumber * 10)
    $password = ([int]$password + 25)
    $password = ([int]$password / 4)
    $password = [math]::Round($password)
    
    Write-Host "Verification Code: $verificationCode" -ForegroundColor Cyan
    Write-Host "Access Password: $password" -ForegroundColor Green
    
    # Show password to service desk
    $passwordMessage = "Please give this password back to user: '$password'"
    [System.Windows.MessageBox]::Show($passwordMessage, 'Access Password', 'OK', 'Information') | Out-Null
    
    # Log approval
    $logMessage = "Confirmation Code sent for approval. Logging access approval."
    [System.Windows.MessageBox]::Show($logMessage, 'Access Verification', 'OK', 'Information') | Out-Null
    
    # Optional: Add logging to file
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Verification Code: $verificationCode - Access Granted by: $env:USERNAME"
    Write-Host $logEntry
}
else {
    Write-Host "Operation cancelled" -ForegroundColor Yellow
}
