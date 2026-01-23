################################################
# Author: Luis Ramirez                         #
# Updated 6-17-2020                            #
#                                              #
# Modified from Workplace Join By Kyle Pearson #
################################################
# Details...           #
<###################################################################################
# This script checks for the existence of a Registry DWord. Then Checks the value  #
# If it exists it checks the value and sets it to 0 if necessary.                  #
# If it does not exist then it creates the Dword and sets the value to 0           #
####################################################################################>

$Key = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\'
$Dword = 'DisabledComponents'
$Value = '255'

if ((Get-ItemProperty $Key -ErrorAction Ignore).PSObject.Properties.Name -contains $Dword) {
    # Registry value exists - check if it has correct value
    if ((Get-ItemProperty -LiteralPath $Key).$Dword -eq $Value) {
        Write-Host "IPv6 is already disabled" -ForegroundColor Green
        exit 0
    }
    else {
        Set-ItemProperty -LiteralPath $Key -Name $Dword -Value $Value
        Write-Host "IPv6 disabled" -ForegroundColor Yellow
    }
}
else {
    # Registry value does not exist
    if (Test-Path -LiteralPath $Key -ErrorAction Ignore) {
        # Key exists, create the value
        New-ItemProperty -LiteralPath $Key -Name $Dword -PropertyType DWORD -Value $Value | Out-Null
        Write-Host "IPv6 disabled (value created)" -ForegroundColor Green
    }
    else {
        # Key doesn't exist, create it and the value
        New-Item -Path $Key -Force | Out-Null
        New-ItemProperty -LiteralPath $Key -Name $Dword -PropertyType DWORD -Value $Value | Out-Null
        Write-Host "IPv6 disabled (key and value created)" -ForegroundColor Green
    }
}
        