########################
# Author: Luis Ramirez #
# Updated 5-19-2020    #
########################
# Details...           #
<###################################################################################
# This script checks for the existence of a Registry DWord. Then Checks the value  #
# If it exists it checks the value and sets it to 0 if necessary.                  #
# If it does not exist then it creates the Dword and sets the value to 0           #
####################################################################################>

$Key = 'HKLM:\SOFTWARE\Policies\Microsoft\WorkplaceJoin'
$Dword = 'autoWorkplaceJoin'
$Value = '0'

if ((Get-ItemProperty $Key -ErrorAction Ignore).PSObject.Properties.Name -contains $Dword) {
    # Registry value exists - check if it has correct value
    if ((Get-ItemProperty -LiteralPath $Key).$Dword -eq $Value) {
        Write-Host "Workplace Join is already disabled" -ForegroundColor Green
        exit 0
    }
    else {
        Set-ItemProperty -LiteralPath $Key -Name $Dword -Value $Value
        Write-Host "Workplace Join disabled" -ForegroundColor Yellow
    }
}
else {
    # Registry value does not exist
    if (Test-Path -LiteralPath $Key -ErrorAction Ignore) {
        # Key exists, create the value
        New-ItemProperty -LiteralPath $Key -Name $Dword -PropertyType DWORD -Value $Value | Out-Null
        Write-Host "Workplace Join disabled (value created)" -ForegroundColor Green
    }
    else {
        # Key doesn't exist, create it and the value
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name $Dword -PropertyType DWORD -Value $Value | Out-Null
        Write-Host "Workplace Join disabled (key and value created)" -ForegroundColor Green
    }
}
        