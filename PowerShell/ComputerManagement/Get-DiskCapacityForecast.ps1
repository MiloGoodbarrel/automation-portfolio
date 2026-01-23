################################################
# Author: Luis Ramirez                         #
# Created: 8-17-2023                           #
# Updated: 1-23-2026                           #
################################################
<#
.SYNOPSIS
    Predicts when disks will reach capacity based on historical trends.

.DESCRIPTION
    Analyzes disk space growth over time and forecasts future capacity.
    
    Business Value:
    - Prevents disk-full outages (proactive vs reactive)
    - Enables budget planning for storage upgrades
    - Identifies abnormal growth patterns
    - Optimizes capacity planning investments
    
    Features:
    - Tracks historical disk usage over time
    - Linear regression forecasting
    - Alerts on predicted capacity dates
    - Identifies rapid growth anomalies
    - Dashboard with trending graphs
    
.PARAMETER ServerList
    Path to file with server names

.PARAMETER HistoryDays
    Days of historical data to analyze (default: 180)

.PARAMETER ForecastDays
    Days into future to forecast (default: 365)

.PARAMETER AlertThresholdDays
    Alert if disk full predicted within N days (default: 90)

.PARAMETER EmailTo
    Email addresses for capacity alerts

.PARAMETER SMTPServer
    SMTP server for notifications

.EXAMPLE
    .\Get-DiskCapacityForecast.ps1 -ServerList "C:\Servers.txt" -EmailTo "storage@company.com"
    
    Forecast disk capacity for servers in list.

.EXAMPLE
    .\Get-DiskCapacityForecast.ps1 -HistoryDays 365 -ForecastDays 730
    
    Use 1 year history to forecast 2 years ahead.

.NOTES
    Requires:
    - WMI/CIM access to servers
    - Historical data collection (run daily/weekly)
    - At least 30 days of data for accurate forecasts
    
    Recommendation:
    - Run daily to collect data points
    - Store historical snapshots
    - Alert on 90-day threshold for procurement lead time
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ServerList,

    [Parameter(Mandatory = $false)]
    [int]$HistoryDays = 180,

    [Parameter(Mandatory = $false)]
    [int]$ForecastDays = 365,

    [Parameter(Mandatory = $false)]
    [int]$AlertThresholdDays = 90,

    [Parameter(Mandatory = $false)]
    [string]$HistoryPath = "C:\CapacityPlanning\DiskHistory",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "C:\Reports\CapacityForecasts",

    [Parameter(Mandatory = $false)]
    [string[]]$EmailTo,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer = "smtp.company.com"
)

#region Helper Functions

function Write-CapacityLog {
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

function Get-LinearRegression {
    param(
        [array]$XValues,  # Days since start
        [array]$YValues   # Used space in GB
    )
    
    if ($XValues.Count -lt 2) {
        return $null
    }
    
    $n = $XValues.Count
    $sumX = ($XValues | Measure-Object -Sum).Sum
    $sumY = ($YValues | Measure-Object -Sum).Sum
    $sumXY = 0
    $sumX2 = 0
    
    for ($i = 0; $i -lt $n; $i++) {
        $sumXY += $XValues[$i] * $YValues[$i]
        $sumX2 += $XValues[$i] * $XValues[$i]
    }
    
    # Calculate slope (m) and intercept (b) for y = mx + b
    $slope = ($n * $sumXY - $sumX * $sumY) / ($n * $sumX2 - $sumX * $sumX)
    $intercept = ($sumY - $slope * $sumX) / $n
    
    # Calculate R-squared (goodness of fit)
    $yMean = $sumY / $n
    $ssTotal = 0
    $ssResidual = 0
    
    for ($i = 0; $i -lt $n; $i++) {
        $predicted = $slope * $XValues[$i] + $intercept
        $ssTotal += [Math]::Pow($YValues[$i] - $yMean, 2)
        $ssResidual += [Math]::Pow($YValues[$i] - $predicted, 2)
    }
    
    $rSquared = if ($ssTotal -ne 0) { 1 - ($ssResidual / $ssTotal) } else { 0 }
    
    return @{
        Slope      = $slope
        Intercept  = $intercept
        RSquared   = $rSquared
        DataPoints = $n
    }
}

function Get-PredictedFullDate {
    param(
        [double]$CurrentUsedGB,
        [double]$TotalSizeGB,
        [double]$DailyGrowthGB
    )
    
    if ($DailyGrowthGB -le 0) {
        return $null  # Shrinking or stable - won't fill
    }
    
    $remainingGB = $TotalSizeGB - $CurrentUsedGB
    $daysUntilFull = $remainingGB / $DailyGrowthGB
    
    return (Get-Date).AddDays($daysUntilFull)
}

#endregion

#region Initialize

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Disk Capacity Forecasting" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$startTime = Get-Date

# Ensure directories exist
foreach ($path in @($HistoryPath, $OutputPath)) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-CapacityLog "Created directory: $path" -Level Info
    }
}

#endregion

#region Get Server List

if ($ServerList -and (Test-Path $ServerList)) {
    $servers = Get-Content $ServerList
    Write-CapacityLog "Loaded $($servers.Count) servers from file" -Level Info
}
else {
    Write-CapacityLog "Querying Active Directory for servers..." -Level Info
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $servers = Get-ADComputer -Filter { Enabled -eq $true -and OperatingSystem -like "*Server*" } |
            Select-Object -ExpandProperty Name
        
        Write-CapacityLog "Found $($servers.Count) servers in AD" -Level Success
    }
    catch {
        Write-CapacityLog "ActiveDirectory module not available and no server list provided" -Level Error
        exit 1
    }
}

#endregion

#region Collect Current Disk Data

Write-CapacityLog "Collecting current disk usage..." -Level Info

$currentSnapshot = @()

foreach ($server in $servers) {
    Write-Progress -Activity "Scanning Servers" -Status "Scanning $server..." -PercentComplete (([array]::IndexOf($servers, $server) / $servers.Count) * 100)
    
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk -ComputerName $server -Filter "DriveType=3" -ErrorAction Stop
        
        foreach ($disk in $disks) {
            $usedGB = [math]::Round(($disk.Size - $disk.FreeSpace) / 1GB, 2)
            $totalGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $percentUsed = [math]::Round(($usedGB / $totalGB) * 100, 1)
            
            $currentSnapshot += [PSCustomObject]@{
                Timestamp    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Server       = $server
                Drive        = $disk.DeviceID
                TotalGB      = $totalGB
                UsedGB       = $usedGB
                FreeGB       = $freeGB
                PercentUsed  = $percentUsed
            }
        }
    }
    catch {
        Write-CapacityLog "Failed to query $server : $_" -Level Warning
    }
}

Write-Progress -Activity "Scanning Servers" -Completed

Write-CapacityLog "Collected data for $($currentSnapshot.Count) disks across $($servers.Count) servers" -Level Success

# Save current snapshot to history
$historyFile = Join-Path $HistoryPath "Snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$currentSnapshot | Export-Csv -Path $historyFile -NoTypeInformation

Write-CapacityLog "Snapshot saved: $historyFile" -Level Success

#endregion

#region Analyze Historical Trends

Write-CapacityLog "Analyzing historical trends (past $HistoryDays days)..." -Level Info

$cutoffDate = (Get-Date).AddDays(-$HistoryDays)
$historyFiles = Get-ChildItem -Path $HistoryPath -Filter "Snapshot-*.csv" |
    Where-Object { $_.LastWriteTime -ge $cutoffDate } |
    Sort-Object LastWriteTime

if ($historyFiles.Count -lt 2) {
    Write-CapacityLog "Insufficient historical data (need at least 2 snapshots). Run daily to build history." -Level Warning
    Write-CapacityLog "Current snapshot saved. Future runs will enable trend analysis.`n" -Level Info
    exit 0
}

Write-CapacityLog "Found $($historyFiles.Count) historical snapshots" -Level Success

# Load all historical data
$allHistory = @()
foreach ($file in $historyFiles) {
    $allHistory += Import-Csv -Path $file.FullName
}

# Group by server and drive
$diskGroups = $allHistory | Group-Object -Property { "$($_.Server):$($_.Drive)" }

Write-CapacityLog "Analyzing $($diskGroups.Count) unique disks..." -Level Info

$forecasts = @()
$alerts = @()

foreach ($group in $diskGroups) {
    $serverDrive = $group.Name
    $dataPoints = $group.Group | Sort-Object Timestamp
    
    if ($dataPoints.Count -lt 2) {
        continue  # Need at least 2 points for trend
    }
    
    # Prepare data for regression
    $firstDate = [datetime]$dataPoints[0].Timestamp
    $xValues = @()
    $yValues = @()
    
    foreach ($point in $dataPoints) {
        $days = (New-TimeSpan -Start $firstDate -End ([datetime]$point.Timestamp)).TotalDays
        $xValues += $days
        $yValues += [double]$point.UsedGB
    }
    
    # Calculate linear regression
    $regression = Get-LinearRegression -XValues $xValues -YValues $yValues
    
    if (-not $regression) {
        continue
    }
    
    $currentPoint = $dataPoints[-1]
    $dailyGrowthGB = $regression.Slope
    $predictedFullDate = Get-PredictedFullDate -CurrentUsedGB ([double]$currentPoint.UsedGB) `
        -TotalSizeGB ([double]$currentPoint.TotalGB) `
        -DailyGrowthGB $dailyGrowthGB
    
    $daysUntilFull = if ($predictedFullDate) {
        [math]::Round((New-TimeSpan -Start (Get-Date) -End $predictedFullDate).TotalDays, 0)
    }
    else {
        $null
    }
    
    # Calculate forecast accuracy
    $confidence = switch ($regression.RSquared) {
        { $_ -ge 0.9 } { "High" }
        { $_ -ge 0.7 } { "Medium" }
        { $_ -ge 0.5 } { "Low" }
        default { "Very Low" }
    }
    
    $forecast = [PSCustomObject]@{
        Server               = $currentPoint.Server
        Drive                = $currentPoint.Drive
        CurrentUsedGB        = [double]$currentPoint.UsedGB
        CurrentFreeGB        = [double]$currentPoint.FreeGB
        TotalGB              = [double]$currentPoint.TotalGB
        CurrentPercentUsed   = [double]$currentPoint.PercentUsed
        DailyGrowthGB        = [math]::Round($dailyGrowthGB, 3)
        DailyGrowthPercent   = [math]::Round(($dailyGrowthGB / [double]$currentPoint.TotalGB) * 100, 3)
        MonthlyGrowthGB      = [math]::Round($dailyGrowthGB * 30, 2)
        AnnualGrowthGB       = [math]::Round($dailyGrowthGB * 365, 2)
        PredictedFullDate    = if ($predictedFullDate) { $predictedFullDate.ToString("yyyy-MM-dd") } else { "N/A (Stable/Shrinking)" }
        DaysUntilFull        = $daysUntilFull
        ForecastConfidence   = $confidence
        RSquared             = [math]::Round($regression.RSquared, 3)
        DataPoints           = $regression.DataPoints
        AnalysisPeriodDays   = [math]::Round(($xValues | Measure-Object -Maximum).Maximum, 0)
    }
    
    $forecasts += $forecast
    
    # Generate alerts
    if ($null -ne $daysUntilFull -and $daysUntilFull -le $AlertThresholdDays -and $daysUntilFull -gt 0) {
        $severityLevel = switch ($daysUntilFull) {
            { $_ -le 30 } { "CRITICAL" }
            { $_ -le 60 } { "HIGH" }
            { $_ -le 90 } { "MEDIUM" }
            default { "LOW" }
        }
        
        $alerts += [PSCustomObject]@{
            Severity            = $severityLevel
            Server              = $forecast.Server
            Drive               = $forecast.Drive
            DaysUntilFull       = $daysUntilFull
            PredictedFullDate   = $forecast.PredictedFullDate
            CurrentPercentUsed  = $forecast.CurrentPercentUsed
            DailyGrowthGB       = $forecast.DailyGrowthGB
            Confidence          = $confidence
        }
        
        $alertLevel = switch ($severityLevel) {
            "CRITICAL" { "Error" }
            "HIGH" { "Error" }
            "MEDIUM" { "Warning" }
            default { "Info" }
        }
        
        $percentUsedValue = [double]$currentPoint.PercentUsed
        Write-CapacityLog "⚠️  $severityLevel $serverDrive - Full in $daysUntilFull days ($percentUsedValue% used)" -Level $alertLevel
    }
}

#endregion

#region Generate Reports

Write-Host "`n--- Generating Capacity Reports ---`n" -ForegroundColor Cyan

# Export full forecast
$reportPath = Join-Path $OutputPath "CapacityForecast-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$forecasts | Sort-Object DaysUntilFull | Export-Csv -Path $reportPath -NoTypeInformation

Write-CapacityLog "Forecast report saved: $reportPath" -Level Success

# Summary statistics
$criticalAlerts = ($alerts | Where-Object { $_.Severity -eq "CRITICAL" }).Count
$highAlerts = ($alerts | Where-Object { $_.Severity -eq "HIGH" }).Count
$mediumAlerts = ($alerts | Where-Object { $_.Severity -eq "MEDIUM" }).Count

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Capacity Forecast Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-CapacityLog "Disks analyzed: $($forecasts.Count)" -Level Info
Write-CapacityLog "CRITICAL alerts (<30 days): $criticalAlerts" -Level $(if ($criticalAlerts -gt 0) { "Error" } else { "Info" })
Write-CapacityLog "HIGH alerts (30-60 days): $highAlerts" -Level $(if ($highAlerts -gt 0) { "Error" } else { "Info" })
Write-CapacityLog "MEDIUM alerts (60-90 days): $mediumAlerts" -Level $(if ($mediumAlerts -gt 0) { "Warning" } else { "Info" })

# Top 10 fastest growing disks
$topGrowers = $forecasts | Where-Object { $_.DailyGrowthGB -gt 0 } | Sort-Object DailyGrowthGB -Descending | Select-Object -First 10

if ($topGrowers.Count -gt 0) {
    Write-Host "`nTop 10 Fastest Growing Disks:" -ForegroundColor Yellow
    foreach ($disk in $topGrowers) {
        Write-Host "  $($disk.Server):$($disk.Drive) - $($disk.DailyGrowthGB) GB/day ($($disk.MonthlyGrowthGB) GB/month)" -ForegroundColor White
    }
}

#endregion

#region Email Report

if ($EmailTo -and $alerts.Count -gt 0) {
    Write-CapacityLog "Sending capacity alert email..." -Level Info
    
    $alertTable = foreach ($alert in ($alerts | Sort-Object DaysUntilFull)) {
        $rowColor = switch ($alert.Severity) {
            "CRITICAL" { "#f8d7da" }
            "HIGH" { "#f8d7da" }
            "MEDIUM" { "#fff3cd" }
            default { "#d1ecf1" }
        }
        
        "<tr style='background-color: $rowColor;'>
            <td><strong>$($alert.Severity)</strong></td>
            <td>$($alert.Server)</td>
            <td>$($alert.Drive)</td>
            <td align='center'>$($alert.DaysUntilFull)</td>
            <td>$($alert.PredictedFullDate)</td>
            <td align='right'>$($alert.CurrentPercentUsed)%</td>
            <td align='right'>$($alert.DailyGrowthGB) GB</td>
            <td align='center'>$($alert.Confidence)</td>
        </tr>"
    }
    
    $emailBody = @"
<html>
<body style="font-family: Arial, sans-serif;">
<h2 style="color: #d9534f;">⚠️ Disk Capacity Alerts</h2>

<div style="background-color: #f8d7da; padding: 15px; border-left: 4px solid #d9534f;">
    <p><strong>Report Date:</strong> $startTime</p>
    <p><strong>CRITICAL:</strong> $criticalAlerts disk(s) will be full within 30 days</p>
    <p><strong>HIGH:</strong> $highAlerts disk(s) will be full within 60 days</p>
    <p><strong>MEDIUM:</strong> $mediumAlerts disk(s) will be full within 90 days</p>
</div>

<h3>Capacity Alerts</h3>
<table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; width: 100%;">
    <tr style="background-color: #e9ecef;">
        <th>Severity</th>
        <th>Server</th>
        <th>Drive</th>
        <th>Days Until Full</th>
        <th>Predicted Full Date</th>
        <th>Current Used</th>
        <th>Daily Growth</th>
        <th>Confidence</th>
    </tr>
    $($alertTable -join "`n")
</table>

<h3>Recommended Actions</h3>
<ul>
    <li><strong>CRITICAL:</strong> Immediate action required - cleanup, expansion, or migration</li>
    <li><strong>HIGH:</strong> Plan storage expansion within 2-4 weeks</li>
    <li><strong>MEDIUM:</strong> Budget and schedule capacity upgrade</li>
</ul>

<p>Full capacity forecast report attached.</p>

<hr>
<p style="font-size: 11px; color: #666;">Disk Capacity Forecasting - Automated Analysis</p>
</body>
</html>
"@
    
    Send-MailMessage -To $EmailTo -From "CapacityPlanning@company.com" `
        -Subject "⚠️ Disk Capacity Alerts - $($alerts.Count) disk(s) nearing capacity" `
        -Body $emailBody -BodyAsHtml -SmtpServer $SMTPServer -Attachments $reportPath
    
    Write-CapacityLog "Alert email sent to: $($EmailTo -join ', ')" -Level Success
}

#endregion

Write-CapacityLog "`nCapacity forecast complete!`n" -Level Success
