########################
# Author: Luis Ramirez #
# Updated 6-12-2020    #
########################
# Details...           #
<#####################################################################################
# This script checks for the existence of a Registry DWord. Then Checks the value    #
# If it exists it checks the value and sets it to 600 if necessary.                  #
# If it does not exist then it creates the Dword and sets the value to 600           #
######################################################################################>

$Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\'
$Dword = 'InactivityTimeoutSecs'
$Value = '600'

if ((Get-ItemProperty $Key -ErrorAction Ignore).PSObject.Properties.Name -contains $Dword) {
    # Registry value exists - check if it has correct value
    if ((Get-ItemProperty -LiteralPath $Key).$Dword -eq $Value) {
        Write-Host "Registry value is already set correctly" -ForegroundColor Green
        exit 0
    }
    else {
        Set-ItemProperty -LiteralPath $Key -Name $Dword -Value $Value
        Write-Host "Registry value updated to $Value" -ForegroundColor Yellow
    }
}
else {
    # Registry value does not exist
    if (Test-Path -LiteralPath $Key -ErrorAction Ignore) {
        # Key exists, create the value
        New-ItemProperty -LiteralPath $Key -Name $Dword -PropertyType DWORD -Value $Value | Out-Null
        Write-Host "Registry value created with value $Value" -ForegroundColor Green
    }
    else {
        # Key doesn't exist, create it and the value
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name $Dword -PropertyType DWORD -Value $Value | Out-Null
        Write-Host "Registry key and value created with value $Value" -ForegroundColor Green
    }
}
        