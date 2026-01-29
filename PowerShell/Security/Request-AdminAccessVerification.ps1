################################################
# Author: Luis Ramirez                         #
# Created: 5-27-2021                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# This script generates a random verification code and displays it to the user.   #
# The user must contact the service desk with this code to receive an access      #
# password. This creates a two-factor authentication process for temporary admin  #
# access.                                                                          #
#                                                                                  #
# Parameters:                                                                      #
#   -ServiceDeskPhone: The phone number for service desk (default: 801-418-8822)  #
#   -AccessTimeoutMinutes: Minutes before access expires (default: 3)             #
#                                                                                  #
# Example: .\Request-AdminAccessVerification.ps1                                  #
# Example: .\Request-AdminAccessVerification.ps1 -ServiceDeskPhone "555-1234"     #
###################################################################################
.NOTES
Author: Luis Ramirez
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ServiceDeskPhone,

    [Parameter(Mandatory = $false)]
    [int]$AccessTimeoutMinutes = 3
)

# Example usage:
# .\Request-AdminAccessVerification.ps1 -ServiceDeskPhone "555-1234"

Clear-Host

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Generate random verification number
$verificationCode = Get-Random -Minimum 9999 -Maximum 99999

Write-Host "Verification Code: $verificationCode" -ForegroundColor Cyan

# Calculate response password using algorithm
$password = ([int]$verificationCode * 10)
$password = ([int]$password + 25)
$password = ([int]$password / 4)
$password = [math]::Round($password)

Write-Host "Expected Response: $password" -ForegroundColor Yellow
Write-Host ""

# Show verification message
$verificationMessage = "Verification is Required. Please Contact Service Desk at $ServiceDeskPhone with this number '$verificationCode' to get your Password to continue."

$msgBoxResult = [System.Windows.MessageBox]::Show($verificationMessage, 'Access Verification', 'OKCancel', 'Error')

switch ($msgBoxResult) {
    'OK' {
        # Create password input form
        $form = New-Object System.Windows.Forms.Form
        $form.Text = 'Admin Access Verification'
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
        $label.Text = 'Enter the Password provided by Service Desk:'
        $form.Controls.Add($label)

        $textBox = New-Object System.Windows.Forms.TextBox
        $textBox.Location = New-Object System.Drawing.Point(10, 40)
        $textBox.Size = New-Object System.Drawing.Size(260, 20)
        $form.Controls.Add($textBox)

        $form.Topmost = $true
        $form.Add_Shown({ $textBox.Select() })
        
        $result = $form.ShowDialog()

        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $userInput = $textBox.Text

            Write-Host "User Input: $userInput" -ForegroundColor Cyan
            Write-Host "Expected: $password" -ForegroundColor Yellow
            
            if ($userInput -eq $password) {
                $confirmMessage = "Confirmation Codes have been verified. Confirmation Complete. Granting Access."
                
                $accessMessage = @"
Access Granted.
Use Access Responsibly
All Admin usage will be logged.
Access will be revoked in $AccessTimeoutMinutes minutes!
"@
                
                [System.Windows.MessageBox]::Show($confirmMessage, 'Access Verification', 'OK', 'Information') | Out-Null
                [System.Windows.MessageBox]::Show($accessMessage, 'Access Verification', 'OK', 'Warning') | Out-Null
                
                Write-Host "Access granted successfully" -ForegroundColor Green
            }
            else {
                $errorMessage = "Confirmation Codes do not match. Please re-run application."
                [System.Windows.MessageBox]::Show($errorMessage, 'Access Verification', 'OK', 'Error') | Out-Null
                Write-Warning "Access denied - code mismatch"
            }
        }
    }

    'Cancel' {
        $cancelMessage = "Canceling operation, logging request and cancellation"
        [System.Windows.MessageBox]::Show($cancelMessage, 'Access Verification', 'OK', 'Error') | Out-Null
        Write-Host "Operation cancelled by user" -ForegroundColor Red
    }
}
