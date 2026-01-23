################################################
# Author: Luis Ramirez                         #
# Created: 12-9-2021                           #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Audits software installations against purchased licenses.

.DESCRIPTION
    Scans installed software across endpoints and compares to license inventory.
    
    Business Value:
    - Identifies license compliance risks (audit exposure)
    - Finds unused/wasted licenses (cost optimization)
    - Tracks software deployments
    - Enables license reclamation
    
    Features:
    - Scans computers via WMI/CIM
    - Compares to license inventory CSV
    - Identifies over-deployed software (compliance risk)
    - Identifies under-utilized licenses (waste)
    - Generates compliance dashboard
    - Calculates potential cost savings
    
.PARAMETER ComputerList
    Path to file with computer names (one per line)

.PARAMETER LicenseInventoryPath
    Path to CSV with purchased licenses

.PARAMETER OutputPath
    Path for compliance reports

.PARAMETER EmailTo
    Email addresses for compliance report

.PARAMETER SMTPServer
    SMTP server for notifications

.EXAMPLE
    .\Get-SoftwareLicenseCompliance.ps1 -ComputerList "C:\Computers.txt" -LicenseInventoryPath "C:\Licenses.csv"
    
    Audit all computers against license inventory.

.EXAMPLE
    .\Get-SoftwareLicenseCompliance.ps1 -EmailTo "management@company.com,finance@company.com"
    
    Send compliance report to management and finance.

.NOTES
    License Inventory CSV Format:
    ProductName,LicenseCount,PurchaseDate,AnnualCost,LicenseType
    "Microsoft Office 365 E3",500,2024-01-15,15000,Subscription
    "Adobe Acrobat Pro DC",100,2023-06-20,14999,Perpetual
    
    Requirements:
    - WMI/CIM access to target computers
    - Administrator permissions
    - License inventory maintained
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ComputerList,

    [Parameter(Mandatory = $false)]
    [string]$LicenseInventoryPath = "C:\IT\LicenseInventory.csv",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\Reports\LicenseCompliance",

    [Parameter(Mandatory = $false)]
    [string[]]$EmailTo,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.company.com",

    [Parameter(Mandatory = $false)]
    [int]$ThrottleLimit = 10
)

#region Helper Functions

function Write-ComplianceLog {
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
}

function Get-InstalledSoftware {
    param(
        [string]$ComputerName
    )
    
    try {
        # Try CIM first (faster)
        $software = Get-CimInstance -ClassName Win32_Product -ComputerName $ComputerName -ErrorAction Stop |
            Select-Object Name, Version, Vendor, InstallDate
        
        return $software
    }
    catch {
        # Fall back to registry query
        try {
            $regPaths = @(
                "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall",
                "SOFTWARE\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall"
            )
            
            $software = foreach ($path in $regPaths) {
                Invoke-Command -ComputerName $ComputerName -ScriptBlock {
                    param($regPath)
                    Get-ItemProperty "HKLM:\$regPath\*" |
                        Where-Object { $_.DisplayName } |
                        Select-Object @{N = "Name"; E = { $_.DisplayName } },
                        @{N = "Version"; E = { $_.DisplayVersion } },
                        @{N = "Vendor"; E = { $_.Publisher } },
                        @{N = "InstallDate"; E = { $_.InstallDate } }
                } -ArgumentList $path -ErrorAction Stop
            }
            
            return $software
        }
        catch {
            Write-ComplianceLog "Failed to query $ComputerName : $_" -Level Error
            return $null
        }
    }
}

function Compare-ProductName {
    param(
        [string]$InstalledName,
        [string]$LicenseName
    )
    
    # Fuzzy matching for product names
    $cleanInstalled = $InstalledName -replace '\s+', ' ' -replace '\d{4}', '' -replace '\(\d+-bit\)', '' -replace 'x64', '' -replace 'x86', ''
    $cleanLicense = $LicenseName -replace '\s+', ' ' -replace '\d{4}', '' -replace '\(\d+-bit\)', '' -replace 'x64', '' -replace 'x86', ''
    
    # Exact match
    if ($cleanInstalled -eq $cleanLicense) {
        return $true
    }
    
    # Contains match
    if ($cleanInstalled -like "*$cleanLicense*" -or $cleanLicense -like "*$cleanInstalled*") {
        return $true
    }
    
    # Partial match (core words)
    $installedWords = $cleanInstalled -split '\s+' | Where-Object { $_.Length -gt 3 }
    $licenseWords = $cleanLicense -split '\s+' | Where-Object { $_.Length -gt 3 }
    
    $matchCount = 0
    foreach ($word in $licenseWords) {
        if ($installedWords -contains $word) {
            $matchCount++
        }
    }
    
    # At least 60% of words match
    return ($matchCount / $licenseWords.Count) -ge 0.6
}

#endregion

#region Initialize

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Software License Compliance Audit" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$startTime = Get-Date

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-ComplianceLog "Created output directory: $OutputPath" -Level Info
}

#endregion

#region Load License Inventory

Write-ComplianceLog "Loading license inventory from $LicenseInventoryPath..." -Level Info

if (-not (Test-Path $LicenseInventoryPath)) {
    Write-ComplianceLog "License inventory file not found: $LicenseInventoryPath" -Level Error
    Write-Host "`nCreating sample license inventory file...`n" -ForegroundColor Yellow
    
    $sampleLicenses = @(
        [PSCustomObject]@{
            ProductName  = "Microsoft Office 365 E3"
            LicenseCount = 500
            PurchaseDate = "2024-01-15"
            AnnualCost   = 15000
            LicenseType  = "Subscription"
        }
        [PSCustomObject]@{
            ProductName  = "Adobe Acrobat Pro DC"
            LicenseCount = 100
            PurchaseDate = "2023-06-20"
            AnnualCost   = 14999
            LicenseType  = "Perpetual"
        }
        [PSCustomObject]@{
            ProductName  = "WinZip"
            LicenseCount = 250
            PurchaseDate = "2023-03-10"
            AnnualCost   = 8750
            LicenseType  = "Perpetual"
        }
    )
    
    $sampleLicenses | Export-Csv -Path $LicenseInventoryPath -NoTypeInformation
    Write-ComplianceLog "Sample inventory created. Please update with actual license data." -Level Warning
}

$licenseInventory = Import-Csv -Path $LicenseInventoryPath

Write-ComplianceLog "Loaded $($licenseInventory.Count) licensed products" -Level Success

#endregion

#region Get Computer List

if ($ComputerList -and (Test-Path $ComputerList)) {
    $computers = Get-Content $ComputerList
    Write-ComplianceLog "Loaded $($computers.Count) computers from file" -Level Info
}
else {
    Write-ComplianceLog "Querying Active Directory for computers..." -Level Info
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $computers = Get-ADComputer -Filter { Enabled -eq $true -and OperatingSystem -like "*Windows*" } |
            Select-Object -ExpandProperty Name
        
        Write-ComplianceLog "Found $($computers.Count) Windows computers in AD" -Level Success
    }
    catch {
        Write-ComplianceLog "ActiveDirectory module not available and no computer list provided" -Level Error
        exit 1
    }
}

#endregion

#region Scan Installed Software

Write-ComplianceLog "Scanning $($computers.Count) computers for installed software..." -Level Info
Write-ComplianceLog "Throttle limit: $ThrottleLimit concurrent scans" -Level Info

$allInstalledSoftware = @()
$scannedCount = 0
$failedComputers = @()

$jobs = @()

foreach ($computer in $computers) {
    # Throttle concurrent jobs
    while ((Get-Job -State Running).Count -ge $ThrottleLimit) {
        Start-Sleep -Milliseconds 100
    }
    
    $jobs += Start-Job -ScriptBlock {
        param($comp, $funcDef)
        
        # Import function
        Invoke-Expression $funcDef
        
        $result = @{
            Computer = $comp
            Software = $null
            Success  = $false
        }
        
        # Test connectivity
        if (Test-Connection -ComputerName $comp -Count 1 -Quiet) {
            $software = Get-InstalledSoftware -ComputerName $comp
            
            if ($software) {
                $result.Software = $software
                $result.Success = $true
            }
        }
        
        return $result
    } -ArgumentList $computer, ${function:Get-InstalledSoftware}.ToString()
}

# Wait for all jobs and collect results
Write-Host "`nWaiting for scans to complete..."

$results = $jobs | Wait-Job | Receive-Job

foreach ($result in $results) {
    if ($result.Success) {
        foreach ($software in $result.Software) {
            $allInstalledSoftware += [PSCustomObject]@{
                ComputerName = $result.Computer
                ProductName  = $software.Name
                Version      = $software.Version
                Vendor       = $software.Vendor
                InstallDate  = $software.InstallDate
            }
        }
        $scannedCount++
    }
    else {
        $failedComputers += $result.Computer
    }
    
    # Progress indicator
    $percentComplete = [math]::Round(($scannedCount / $computers.Count) * 100, 1)
    Write-Progress -Activity "Scanning Computers" -Status "$scannedCount of $($computers.Count) completed ($percentComplete%)" -PercentComplete $percentComplete
}

# Cleanup jobs
$jobs | Remove-Job -Force

Write-Progress -Activity "Scanning Computers" -Completed

Write-ComplianceLog "Successfully scanned: $scannedCount computers" -Level Success
Write-ComplianceLog "Failed scans: $($failedComputers.Count) computers" -Level $(if ($failedComputers.Count -gt 0) { "Warning" } else { "Info" })

#endregion

#region Analyze Compliance

Write-Host "`n--- Analyzing License Compliance ---`n" -ForegroundColor Cyan

$complianceResults = @()

foreach ($license in $licenseInventory) {
    Write-ComplianceLog "Analyzing: $($license.ProductName)..." -Level Info
    
    # Find all installations matching this license
    $installations = $allInstalledSoftware | Where-Object {
        Compare-ProductName -InstalledName $_.ProductName -LicenseName $license.ProductName
    }
    
    $uniqueInstalls = ($installations | Select-Object -ExpandProperty ComputerName -Unique).Count
    $totalInstalls = $installations.Count
    
    $licenseCount = [int]$license.LicenseCount
    $compliance = if ($uniqueInstalls -le $licenseCount) { "Compliant" }
    elseif ($uniqueInstalls -le ($licenseCount * 1.05)) { "Warning" }  # 5% grace
    else { "Over-Deployed" }
    
    $utilizationPercent = if ($licenseCount -gt 0) {
        [math]::Round(($uniqueInstalls / $licenseCount) * 100, 1)
    }
    else { 0 }
    
    $wastedLicenses = [math]::Max(0, $licenseCount - $uniqueInstalls)
    $shortfallLicenses = [math]::Max(0, $uniqueInstalls - $licenseCount)
    
    # Calculate cost impact
    $annualCost = [double]$license.AnnualCost
    $costPerLicense = if ($licenseCount -gt 0) { $annualCost / $licenseCount } else { 0 }
    $wastedCost = $wastedLicenses * $costPerLicense
    $complianceRisk = $shortfallLicenses * $costPerLicense * 3  # Penalty typically 3x cost
    
    $result = [PSCustomObject]@{
        Product             = $license.ProductName
        LicensesPurchased   = $licenseCount
        UniqueInstalls      = $uniqueInstalls
        TotalInstalls       = $totalInstalls
        Utilization         = "$utilizationPercent%"
        Compliance          = $compliance
        WastedLicenses      = $wastedLicenses
        LicenseShortfall    = $shortfallLicenses
        AnnualCost          = $annualCost
        WastedCost          = $wastedCost
        ComplianceRisk      = $complianceRisk
        LicenseType         = $license.LicenseType
        PurchaseDate        = $license.PurchaseDate
    }
    
    $complianceResults += $result
    
    # Log status
    $statusColor = switch ($compliance) {
        "Compliant" { "Success" }
        "Warning" { "Warning" }
        "Over-Deployed" { "Error" }
    }
    
    Write-ComplianceLog "  Status: $compliance - $uniqueInstalls/$licenseCount used ($utilizationPercent%)" -Level $statusColor
}

#endregion

#region Generate Reports

Write-Host "`n--- Generating Reports ---`n" -ForegroundColor Cyan

# Export detailed results
$reportPath = Join-Path $OutputPath "LicenseCompliance-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$complianceResults | Export-Csv -Path $reportPath -NoTypeInformation

Write-ComplianceLog "Detailed report saved: $reportPath" -Level Success

# Export installation inventory
$inventoryPath = Join-Path $OutputPath "SoftwareInventory-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$allInstalledSoftware | Export-Csv -Path $inventoryPath -NoTypeInformation

Write-ComplianceLog "Installation inventory saved: $inventoryPath" -Level Success

# Calculate totals
$totalWastedCost = ($complianceResults | Measure-Object -Property WastedCost -Sum).Sum
$totalComplianceRisk = ($complianceResults | Measure-Object -Property ComplianceRisk -Sum).Sum
$overDeployedCount = ($complianceResults | Where-Object { $_.Compliance -eq "Over-Deployed" }).Count
$compliantCount = ($complianceResults | Where-Object { $_.Compliance -eq "Compliant" }).Count

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Compliance Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-ComplianceLog "Products analyzed: $($complianceResults.Count)" -Level Info
Write-ComplianceLog "Compliant: $compliantCount" -Level Success
Write-ComplianceLog "Over-deployed (risk): $overDeployedCount" -Level $(if ($overDeployedCount -gt 0) { "Error" } else { "Info" })
Write-ComplianceLog "Potential wasted cost: `$$([math]::Round($totalWastedCost, 2))" -Level $(if ($totalWastedCost -gt 0) { "Warning" } else { "Info" })
Write-ComplianceLog "Compliance risk exposure: `$$([math]::Round($totalComplianceRisk, 2))" -Level $(if ($totalComplianceRisk -gt 0) { "Error" } else { "Info" })

#endregion

#region Email Report

if ($EmailTo) {
    Write-ComplianceLog "Sending email report..." -Level Info
    
    $statusIcon = if ($overDeployedCount -eq 0 -and $totalWastedCost -lt 1000) { "✓" } else { "⚠️" }
    
    $complianceTable = foreach ($item in ($complianceResults | Sort-Object Compliance -Descending)) {
        $rowColor = switch ($item.Compliance) {
            "Over-Deployed" { "#f8d7da" }
            "Warning" { "#fff3cd" }
            "Compliant" { "#d4edda" }
        }
        
        "<tr style='background-color: $rowColor;'>
            <td>$($item.Product)</td>
            <td align='center'>$($item.LicensesPurchased)</td>
            <td align='center'>$($item.UniqueInstalls)</td>
            <td align='center'>$($item.Utilization)</td>
            <td align='center'><strong>$($item.Compliance)</strong></td>
            <td align='right'>`$$([math]::Round($item.WastedCost, 2))</td>
            <td align='right'>`$$([math]::Round($item.ComplianceRisk, 2))</td>
        </tr>"
    }
    
    $emailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2>$statusIcon Software License Compliance Report</h2>

<div style="background-color: #f5f5f5; padding: 15px; border-left: 4px solid #0275d8;">
    <p><strong>Scan Date:</strong> $startTime</p>
    <p><strong>Computers Scanned:</strong> $scannedCount / $($computers.Count)</p>
    <p><strong>Products Analyzed:</strong> $($complianceResults.Count)</p>
    <p><strong>Duration:</strong> $([math]::Round((New-TimeSpan -Start $startTime -End (Get-Date)).TotalMinutes, 2)) minutes</p>
</div>

<h3>Executive Summary</h3>
<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse;">
    <tr><td><strong>Compliant Products:</strong></td><td style="color: #5cb85c;">$compliantCount</td></tr>
    <tr><td><strong>Over-Deployed (Audit Risk):</strong></td><td style="color: #d9534f;">$overDeployedCount</td></tr>
    <tr><td><strong>Wasted License Cost:</strong></td><td style="color: #f0ad4e;">`$$([math]::Round($totalWastedCost, 2))</td></tr>
    <tr><td><strong>Compliance Risk Exposure:</strong></td><td style="color: #d9534f;">`$$([math]::Round($totalComplianceRisk, 2))</td></tr>
</table>

<h3>License Details</h3>
<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; width: 100%;">
    <tr style="background-color: #e9ecef;">
        <th>Product</th>
        <th>Purchased</th>
        <th>Installed</th>
        <th>Utilization</th>
        <th>Status</th>
        <th>Wasted Cost</th>
        <th>Risk</th>
    </tr>
    $($complianceTable -join "`n")
</table>

<h3>Recommendations</h3>
<ul>
    <li><strong>Cost Optimization:</strong> Reclaim $($complianceResults | Where-Object { $_.WastedLicenses -gt 5 } | Measure-Object | Select-Object -ExpandProperty Count) products with 5+ unused licenses</li>
    <li><strong>Compliance Action:</strong> Purchase additional licenses for $overDeployedCount over-deployed products</li>
    <li><strong>Potential Savings:</strong> Up to `$$([math]::Round($totalWastedCost, 2)) annually by optimizing license allocation</li>
</ul>

<hr>
<p style="font-size: 11px; color: #666;">Software License Compliance Audit - Automated Analysis</p>
</body>
</html>
"@
    
    Send-MailMessage -To $EmailTo -From "LicenseCompliance@company.com" `
        -Subject "License Compliance Report - $statusIcon $(Get-Date -Format 'yyyy-MM-dd')" `
        -Body $emailBody -BodyAsHtml -SmtpServer $SMTPServer -Attachments $reportPath
    
    Write-ComplianceLog "Email sent to: $($EmailTo -join ', ')" -Level Success
}

#endregion

Write-ComplianceLog "`nCompliance audit complete!`n" -Level Success
