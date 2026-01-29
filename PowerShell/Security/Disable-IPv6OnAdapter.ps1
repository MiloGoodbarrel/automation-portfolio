################################################
# Author: Luis Ramirez                         #
# Created: 5-27-2021                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# This script disables the IPv6 protocol binding on a network adapter. Useful for #
# troubleshooting network issues or enforcing IPv4-only connectivity.             #
#                                                                                  #
# Parameters:                                                                      #
#   -InterfaceAlias: The network adapter name (default: "Ethernet0")              #
#                    Use Get-NetAdapter to list available adapters                #
#                                                                                  #
# Example: .\Disable-IPv6OnAdapter.ps1                                            #
# Example: .\Disable-IPv6OnAdapter.ps1 -InterfaceAlias "Ethernet"                 #
# Example: .\Disable-IPv6OnAdapter.ps1 -InterfaceAlias "Wi-Fi"                    #
###################################################################################
.NOTES
Author: Luis Ramirez
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $false)]
    [string]$InterfaceAlias = "Ethernet0"
)

# Verify running as administrator
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as Administrator"
    exit 1
}

try {
    # Check if adapter exists
    $adapter = Get-NetAdapter -Name $InterfaceAlias -ErrorAction Stop
    Write-Host "Found network adapter: $($adapter.Name) - $($adapter.InterfaceDescription)" -ForegroundColor Cyan

    # Get current IPv6 binding status
    Write-Host "`nCurrent IPv6 binding status:" -ForegroundColor Yellow
    $binding = Get-NetAdapterBinding -InterfaceAlias $InterfaceAlias -ComponentID ms_tcpip6 -ErrorAction Stop
    Write-Host "  Enabled: $($binding.Enabled)" -ForegroundColor Gray

    if (-not $binding.Enabled) {
        Write-Host "`nIPv6 is already disabled on $InterfaceAlias" -ForegroundColor Green
        exit 0
    }

    # Disable IPv6
    if ($PSCmdlet.ShouldProcess($InterfaceAlias, "Disable IPv6")) {
        Disable-NetAdapterBinding -InterfaceAlias $InterfaceAlias -ComponentID ms_tcpip6 -ErrorAction Stop
        Write-Host "`nIPv6 has been disabled on $InterfaceAlias" -ForegroundColor Green
        
        # Verify the change
        $newBinding = Get-NetAdapterBinding -InterfaceAlias $InterfaceAlias -ComponentID ms_tcpip6
        Write-Host "New status - Enabled: $($newBinding.Enabled)" -ForegroundColor Gray
    }
}
catch [Microsoft.PowerShell.Cmdletization.Cim.CimJobException] {
    Write-Error "Network adapter '$InterfaceAlias' not found. Available adapters:"
    Get-NetAdapter | Select-Object Name, InterfaceDescription, Status | Format-Table -AutoSize
    exit 1
}
catch {
    Write-Error "Failed to disable IPv6 on $InterfaceAlias : $_"
    exit 1
}
