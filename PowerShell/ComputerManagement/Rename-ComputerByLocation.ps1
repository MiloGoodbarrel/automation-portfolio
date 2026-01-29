################################################
# Author: Luis Ramirez                         #
# Created: 5-27-2021                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# This script renames computers based on a customizable naming convention.        #
# Can use subnet-based location detection, hardware type, and serial number.      #
#                                                                                  #
# Supports organizations of ANY size - from single office to global enterprise.   #
#                                                                                  #
# Parameters:                                                                      #
#   -ConfigFile: CSV file with subnet mappings (columns: Subnet, LocationCode)    #
#   -NamingTemplate: Pattern for computer name (e.g., "{Location}{HW}{Serial5}")  #
#   -HardwareMap: Hashtable mapping hardware models to type codes (optional)      #
#   -DefaultLocation: Location code if subnet not matched (default: "SITE")       #
#   -DefaultHardware: Hardware code if model not matched (default: "PC")          #
#   -Domain: Domain to use for credential (optional)                              #
#   -DryRun: Test mode - shows what would happen without making changes           #
#                                                                                  #
# Examples:                                                                        #
#   .\Rename-ComputerByLocation.ps1 -ConfigFile "subnets.csv" -DryRun             #
#   .\Rename-ComputerByLocation.ps1 -NamingTemplate "{HW}-{Serial5}"              #
#   .\Rename-ComputerByLocation.ps1 -DefaultLocation "HQ" -DefaultHardware "WS"   #
###################################################################################
.NOTES
Author: Luis Ramirez
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile,

    [Parameter(Mandatory = $false)]
    [string]$NamingTemplate = "{Location}{HW}{Serial5}",

    [Parameter(Mandatory = $false)]
    [hashtable]$HardwareMap,

    [Parameter(Mandatory = $false)]
    [string]$DefaultLocation = "SITE",

    [Parameter(Mandatory = $false)]
    [string]$DefaultHardware = "PC",

    [Parameter(Mandatory = $false)]
    [string]$Domain,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

# Function to check if IP is in subnet (CIDR notation)
function Test-IPInSubnet {
    param(
        [string]$IPAddress,
        [string]$Subnet
    )
    
    $subnetParts = $Subnet.Split('/')
    $subnetIP = $subnetParts[0]
    $subnetMask = [int]$subnetParts[1]
    
    # Convert IP addresses to binary
    $ipBinary = ([System.Net.IPAddress]::Parse($IPAddress)).GetAddressBytes()
    $subnetBinary = ([System.Net.IPAddress]::Parse($subnetIP)).GetAddressBytes()
    
    # Calculate mask
    $maskBytes = [byte[]]::new(4)
    $fullBytes = [Math]::Floor($subnetMask / 8)
    $remainingBits = $subnetMask % 8
    
    for ($i = 0; $i -lt $fullBytes; $i++) {
        $maskBytes[$i] = 0xFF
    }
    if ($remainingBits -gt 0) {
        $maskBytes[$fullBytes] = (0xFF -shl (8 - $remainingBits)) -band 0xFF
    }
    
    # Compare
    for ($i = 0; $i -lt 4; $i++) {
        if (($ipBinary[$i] -band $maskBytes[$i]) -ne ($subnetBinary[$i] -band $maskBytes[$i])) {
            return $false
        }
    }
    return $true
}

# Load subnet configuration from CSV or use defaults
$subnetMap = @{}

if ($ConfigFile) {
    if (Test-Path $ConfigFile) {
        Write-Host "Loading subnet configuration from: $ConfigFile" -ForegroundColor Cyan
        $csvData = Import-Csv -Path $ConfigFile
        foreach ($row in $csvData) {
            if ($row.Subnet -and $row.LocationCode) {
                $subnetMap[$row.Subnet] = $row.LocationCode
            }
        }
        Write-Host "Loaded $($subnetMap.Count) subnet mapping(s)" -ForegroundColor Green
    }
    else {
        Write-Warning "Config file not found: $ConfigFile. Using defaults."
    }
}

# If no hardware map provided, use common defaults
if (-not $HardwareMap) {
    $HardwareMap = @{
        "*Laptop*"       = "LT"
        "*Notebook*"     = "LT"
        "*Desktop*"      = "DT"
        "*Workstation*"  = "WS"
        "*Virtual*"      = "VM"
        "*OptiPlex*"     = "DT"
        "*Latitude*"     = "LT"
        "*Precision*"    = "WS"
        "*ThinkPad*"     = "LT"
        "*ThinkCentre*"  = "DT"
        "*EliteBook*"    = "LT"
        "*ProBook*"      = "LT"
        "*Surface*"      = "LT"
    }
}

# Gather system information
Write-Host "`n========== Computer Rename Utility ==========" -ForegroundColor Cyan
Write-Host "Gathering system information...`n" -ForegroundColor Yellow
 (if mapping provided)
$locationCode = $DefaultLocation
if ($subnetMap.Count -gt 0) {
    foreach ($subnet in $subnetMap.Keys) {
        if (Test-IPInSubnet -IPAddress $IP -Subnet $subnet) {
            $locationCode = $subnetMap[$subnet]
            Write-Host "Location:     $locationCode (matched subnet $subnet)" -ForegroundColor Green
            $matched = $true
            break
        }
    }
    if (-not $matched) {
        Write-Warning "IP $IP did not match any subnet - using default: $DefaultLocation"
    }
}
else {
    Write-Host "Location:     $locationCode (using default - no subnet map provided)" -ForegroundColor Yellow
}

# Determine Hardware Type from Model
$hardwareCode = $DefaultHardware
$hwMatched = $false
foreach ($pattern in $HardwareMap.Keys) {
    if ($model -like $pattern) {
        $hardwareCode = $HardwareMap[$pattern]
        Write-Host "Hardware:     $hardwareCode (matched pattern: $pattern)" -ForegroundColor Green
        $hwMatched = $true
        break
    }
}

if (-not $hwMatched) {
    Write-Host "Hardware:     $hardwareCode (using default - model '$model' not matched)" -ForegroundColor Yellow
}

# Build new computer name using template
# Available tokens: {Location}, {HW}, {Serial5}, {SerialFull}, {Model}
$newName = $NamingTemplate
$newName = $newName -replace '\{Location\}', $locationCode
$newName = $newName -replace '\{HW\}', $hardwareCode
$newName = $newName -replace '\{Serial5\}', $serialLast5
$newName = $newName -replace '\{SerialFull\}', $serialFull
$newName = $newName -replace '\{Model\}', ($model -replace '\s+', '')

Write-Host "`nNaming Template: $NamingTemplate" -ForegroundColor Gray
Write-Host "Proposed Name:  
Write-Host "Serial:       $serialFull (using last 5: $serialLast5)" -ForegroundColor Gray

# Get Hardware Model
$computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem
$model = $computerSystem.Model
Write-Host "Model:        $model" -ForegroundColor Gray

# Determine Location from Subnet
$locationCode = "UNK"
foreach ($subnet in $SubnetMap.Keys) {
    if (Test-IPInSubnet -IPAddress $IP -Subnet $subnet) {
        $locationCode = $SubnetMap[$subnet]
        Write-Host "Location:     $locationCode (matched subnet $subnet)" -ForegroundColor Green
        break
    }
}

if ($locationCode -eq "UNK") {
    Write-Warning "Could not determine location from IP $IP - using 'UNK'"
}

# Determine Hardware Type from Model
$hardwareCode = "XX"
foreach ($pattern in $HardwareMap.Keys) {
    if ($model -like $pattern) {
        $hardwareCode = $HardwareMap[$pattern]
        Write-Host "Hardware:     $hardwareCode (matched pattern: $pattern)" -ForegroundColor Green
        break
    }
}

if ($hardwareCode -eq "XX") {
    Write-Warning "Could not determine hardware type from model '$model' - using 'XX'"
}

# Build new computer name
$newName = "$locationCode$hardwareCode$serialLast5"
Write-Host "`nProposed Name: $newName" -ForegroundColor Cyan

# Validate name length (NetBIOS limit is 15 characters)
if ($newName.Length -gt 15) {
    Write-Error "Computer name '$newName' exceeds 15 character limit (${newName.Length} chars)"
    exit 1
}

# Check if already named correctly
if ($currentName -eq $newName) {
    Write-Host "`nComputer is already named correctly!" -ForegroundColor Green
    exit 0
}

# DryRun mode
if ($DryRun) {
    Write-Host "`n[DRY RUN MODE] Would rename computer from '$currentName' to '$newName'" -ForegroundColor Yellow
    Write-Host "Run without -DryRun parameter to apply changes" -ForegroundColor Yellow
    exit 0
}

# Prompt for confirmation
Write-Host "`nWARNING: This will rename the computer and require a restart!" -ForegroundColor Red
$confirmation = Read-Host "Continue? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Operation cancelled" -ForegroundColor Yellow
    exit 0
}

# Rename the computer
Write-Host "`nRenaming computer..." -ForegroundColor Yellow

try {
    if ($Domain) {
        $credential = Get-Credential -Message "Enter domain credentials for $Domain"
        Rename-Computer -NewName $newName -DomainCredential $credential -Force -PassThru -Verbose
    }
    else {
        Rename-Computer -NewName $newName -Force -PassThru -Verbose
    }
    
    Write-Host "`nComputer renamed successfully to: $newName" -ForegroundColor Green
    Write-Host "A restart is required for changes to take effect." -ForegroundColor Yellow
    
    $restart = Read-Host "`nRestart now? (yes/no)"
    if ($restart -eq "yes") {
        Write-Host "Restarting in 10 seconds..." -ForegroundColor Red
        Start-Sleep -Seconds 10
        Restart-Computer -Force
    }
}
catch {
    Write-Error "Failed to rename computer: $_"
    exit 1
}
