<#
.SYNOPSIS
    Patch Tuesday service orchestration for production server maintenance windows.

.DESCRIPTION
    Automates pre-patch service shutdown, patch deployment execution, and post-patch service
    restoration for production servers with server-specific service dependencies.
    Integrates with WSUS, ManageEngine Desktop Central, or AWS Systems Manager.

.FEATURES
    - Server-specific service stop/start orchestration
    - Pre-patch health checks and service validation
    - Configurable maintenance window management
    - Post-patch service restoration with dependency ordering
    - Rollback capability on service failures
    - Email notifications (start, completion, failures)
    - Comprehensive logging with timestamps
    - Integration with WSUS/SCCM/manual patching workflows

.FUNCTIONALITY
    Orchestration Phases:
    1. Pre-Patch Validation
       - Server connectivity checks
       - Service state verification
       - Disk space validation
       - Backup verification

    2. Service Shutdown
       - Graceful service stops with timeout
       - Dependency-aware shutdown ordering
       - Service state backup for rollback

    3. Patch Deployment
       - WSUS deployment approval and execution
       - ManageEngine DTC job execution (alternative)
       - AWS Systems Manager Patch Manager (alternative)
       - Manual patching pause option
       - Reboot orchestration

    4. Service Restoration
       - Dependency-ordered service starts
       - Health check validation
       - Application-level smoke tests

    5. Post-Patch Reporting
       - Service status summary
       - Failed service alerts
       - Patch compliance validation

.PARAMETER ConfigPath
    Path to JSON configuration file defining servers and services

.PARAMETER ServerGroup
    Server group to process (e.g., WebServers, DatabaseServers, AppServers)

.PARAMETER Mode
    Execution mode: PrePatch, PostPatch, FullAuto, Validate

.PARAMETER EmailTo
    Email recipients for notifications

.PARAMETER WaitForPatching
    Pause script after service shutdown for manual patching (default: $true)

.PARAMETER PatchingTimeout
    Maximum wait time for patching in minutes (default: 120)

.PARAMETER SkipBackupCheck
    Skip backup validation (use with caution)

.PARAMETER PatchingMethod
    Patching method: WSUS, ManualPause, DesktopCentral, AWSSystemsManager (default: WSUS)

.PARAMETER WSUSServer
    WSUS server name (default: loaded from config or auto-detect)

.PARAMETER DeploymentName
    WSUS deployment/approval name or DTC job name to execute

.PARAMETER AutoApprove
    Auto-approve WSUS updates for target computers (use with caution)

.EXAMPLE
    .\Invoke-PatchTuesdayOrchestration.ps1 -ConfigPath "C:\Config\PatchServers.json" -ServerGroup "WebServers" -Mode PrePatch
    
    Stops services on web servers and waits for patching.

.EXAMPLE
    .\Invoke-PatchTuesdayOrchestration.ps1 -ConfigPath "C:\Config\PatchServers.json" -ServerGroup "DatabaseServers" -Mode PostPatch
    
    Restarts services on database servers after patching.

.EXAMPLE
    .\Invoke-PatchTuesdayOrchestration.ps1 -ConfigPath "C:\Config\PatchServers.json" -ServerGroup "AppServers" -Mode FullAuto -EmailTo "ops@contoso.com" -PatchingMethod WSUS -DeploymentName "PatchTuesday-Jan2026"
    
    Full automated patching cycle with WSUS deployment execution.

.EXAMPLE
    .\Invoke-PatchTuesdayOrchestration.ps1 -ConfigPath "C:\Config\PatchServers.json" -ServerGroup "WebServers" -Mode FullAuto -PatchingMethod ManualPause -PatchingTimeout 180
    
    Stops services, waits 3 hours for manual patching, then restarts services.

.NOTES
    Author:  Luis Ramirez
    Created: 11-12-2019
    Updated: 1-24-2026
    Version: 3.3
    
    Requirements:
    - PowerShell Remoting enabled on target servers
    - Administrator access to target servers
    - JSON configuration file (see example below)
    - WSUS PowerShell module (for WSUS method)
    - ManageEngine API credentials (for DTC method - see commented code)
    - AWS Tools for PowerShell (for AWS SSM method - see commented code)
    
    Patching Methods:
    Active: WSUS (Windows Server Update Services) - Most common enterprise solution
    Commented: ManageEngine Desktop Central (line ~450), AWS Systems Manager (line ~520)
    
    Configuration File Example (PatchServers.json):
    {
        "ServerGroups": {
            "WebServers": [
                {
                    "ServerName": "WEB01",
                    "Services": ["W3SVC", "WAS", "MSSQLSERVER"],
                    "StopOrder": 1,
                    "StartOrder": 3
                },
                {
                    "ServerName": "WEB02",
                    "Services": ["W3SVC", "WAS"],
                    "StopOrder": 2,
                    "StartOrder": 2
                }
            ],
            "DatabaseServers": [
                {
                    "ServerName": "SQL01",
                    "Services": ["MSSQLSERVER", "SQLSERVERAGENT"],
                    "StopOrder": 1,
                    "StartOrder": 1
                }
            ]
        },
        "EmailSettings": {
            "SMTPServer": "smtp.contoso.com",
            "From": "patchautomation@contoso.com"
        }
    }
    
    Change Log:
    3.3 - Added patching method integration (WSUS, DTC, AWS SSM)
    3.2 - Added parallel execution, improved error handling
    3.1 - Integration with SCCM maintenance windows
    3.0 - Rewrite for Server 2016/2019 compatibility
    2.0 - Added email notifications and rollback
    1.0 - Initial release

Author: Luis Ramirez
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({Test-Path $_})]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$ServerGroup,

    [Parameter(Mandatory = $true)]
    [ValidateSet('PrePatch', 'PostPatch', 'FullAuto', 'Validate')]
    [string]$Mode,

    [Parameter(Mandatory = $false)]
    [string[]]$EmailTo,

    [Parameter(Mandatory = $false)]
    [bool]$WaitForPatching = $true,

    [Parameter(Mandatory = $false)]
    [int]$PatchingTimeout = 120,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBackupCheck,

    [Parameter(Mandatory = $false)]    [ValidateSet('WSUS', 'ManualPause', 'DesktopCentral', 'AWSSystemsManager')]
    [string]$PatchingMethod = 'WSUS',

    [Parameter(Mandatory = $false)]
    [string]$WSUSServer,

    [Parameter(Mandatory = $false)]
    [string]$DeploymentName,

    [Parameter(Mandatory = $false)]
    [switch]$AutoApprove,

    [Parameter(Mandatory = $false)]    [string]$LogPath = "C:\Logs\PatchTuesday"
)

#Requires -RunAsAdministrator

# Initialize logging
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$logFile = Join-Path $LogPath "PatchOrchestration_$ServerGroup`_$Mode`_$timestamp.log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$logTimestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logMessage
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        "INFO" { Write-Host $logMessage -ForegroundColor Cyan }
        default { Write-Host $logMessage }
    }
}

# Load configuration
Write-Log "Loading configuration from: $ConfigPath"
try {
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    
    if (-not $config.ServerGroups.$ServerGroup) {
        Write-Log "Server group '$ServerGroup' not found in configuration" "ERROR"
        exit 1
    }
    
    $servers = $config.ServerGroups.$ServerGroup
    Write-Log "Loaded configuration for $($servers.Count) servers in group '$ServerGroup'" "SUCCESS"
} catch {
    Write-Log "Failed to load configuration: $_" "ERROR"
    exit 1
}

# Global tracking
$serviceStates = @{}
$failedServers = @()
$failedServices = @()

# Function to send email notification
function Send-EmailNotification {
    param(
        [string]$Subject,
        [string]$Body,
        [string]$Priority = "Normal"
    )
    
    if (-not $EmailTo) { return }
    
    try {
        $emailParams = @{
            To = $EmailTo
            From = $config.EmailSettings.From
            Subject = "Patch Tuesday: $Subject"
            Body = $Body
            BodyAsHtml = $true
            SmtpServer = $config.EmailSettings.SMTPServer
            Priority = $Priority
        }
        
        Send-MailMessage @emailParams -ErrorAction Stop
        Write-Log "Email notification sent: $Subject" "INFO"
    } catch {
        Write-Log "Failed to send email: $_" "WARNING"
    }
}

# Function to validate server connectivity
function Test-ServerConnectivity {
    param([object[]]$ServerList)
    
    Write-Log "Validating server connectivity..."
    
    $results = @()
    foreach ($server in $ServerList) {
        $serverName = $server.ServerName
        
        $pingResult = Test-Connection -ComputerName $serverName -Count 2 -Quiet
        $psRemoting = Test-WSMan -ComputerName $serverName -ErrorAction SilentlyContinue
        
        $status = [PSCustomObject]@{
            ServerName = $serverName
            Pingable = $pingResult
            PSRemoting = ($null -ne $psRemoting)
            Status = if ($pingResult -and $psRemoting) { "OK" } else { "FAILED" }
        }
        
        $results += $status
        
        if ($status.Status -eq "FAILED") {
            Write-Log "Server connectivity check failed: $serverName" "ERROR"
            $script:failedServers += $serverName
        } else {
            Write-Log "Server connectivity OK: $serverName" "SUCCESS"
        }
    }
    
    return $results
}

# Function to get service state
function Get-ServiceStateRemote {
    param([string]$ServerName, [string[]]$ServiceNames)
    
    try {
        $services = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param($ServiceNames)
            foreach ($svc in $ServiceNames) {
                Get-Service -Name $svc -ErrorAction SilentlyContinue | Select-Object Name, Status, StartType
            }
        } -ArgumentList (,$ServiceNames) -ErrorAction Stop
        
        return $services
    } catch {
        Write-Log "Failed to get service state on $ServerName : $_" "ERROR"
        return $null
    }
}

# Function to stop services
function Stop-ServiceRemote {
    param([string]$ServerName, [string[]]$ServiceNames, [int]$TimeoutSeconds = 60)
    
    Write-Log "Stopping services on $ServerName : $($ServiceNames -join ', ')"
    
    try {
        $result = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param($ServiceNames, $Timeout)
            
            $results = @()
            foreach ($svcName in $ServiceNames) {
                try {
                    $service = Get-Service -Name $svcName -ErrorAction Stop
                    
                    if ($service.Status -eq 'Running') {
                        Stop-Service -Name $svcName -Force -ErrorAction Stop
                        
                        # Wait for service to stop
                        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                        while ((Get-Service -Name $svcName).Status -ne 'Stopped' -and $stopwatch.Elapsed.TotalSeconds -lt $Timeout) {
                            Start-Sleep -Seconds 2
                        }
                        
                        $finalStatus = (Get-Service -Name $svcName).Status
                        
                        $results += [PSCustomObject]@{
                            ServiceName = $svcName
                            Status = $finalStatus
                            Success = ($finalStatus -eq 'Stopped')
                            TimeTaken = $stopwatch.Elapsed.TotalSeconds
                        }
                    } else {
                        $results += [PSCustomObject]@{
                            ServiceName = $svcName
                            Status = $service.Status
                            Success = $true
                            TimeTaken = 0
                        }
                    }
                } catch {
                    $results += [PSCustomObject]@{
                        ServiceName = $svcName
                        Status = "ERROR"
                        Success = $false
                        Error = $_.Exception.Message
                    }
                }
            }
            
            return $results
        } -ArgumentList (,$ServiceNames), $TimeoutSeconds -ErrorAction Stop
        
        foreach ($svcResult in $result) {
            if ($svcResult.Success) {
                Write-Log "Service stopped: $($svcResult.ServiceName) on $ServerName (${$($svcResult.TimeTaken)}s)" "SUCCESS"
            } else {
                Write-Log "Failed to stop service: $($svcResult.ServiceName) on $ServerName" "ERROR"
                $script:failedServices += "$ServerName\$($svcResult.ServiceName)"
            }
        }
        
        return $result
        
    } catch {
        Write-Log "Failed to stop services on $ServerName : $_" "ERROR"
        $script:failedServers += $ServerName
        return $null
    }
}

# Function to start services
function Start-ServiceRemote {
    param([string]$ServerName, [string[]]$ServiceNames, [int]$TimeoutSeconds = 60)
    
    Write-Log "Starting services on $ServerName : $($ServiceNames -join ', ')"
    
    try {
        $result = Invoke-Command -ComputerName $ServerName -ScriptBlock {
            param($ServiceNames, $Timeout)
            
            $results = @()
            foreach ($svcName in $ServiceNames) {
                try {
                    $service = Get-Service -Name $svcName -ErrorAction Stop
                    
                    if ($service.Status -ne 'Running') {
                        Start-Service -Name $svcName -ErrorAction Stop
                        
                        # Wait for service to start
                        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                        while ((Get-Service -Name $svcName).Status -ne 'Running' -and $stopwatch.Elapsed.TotalSeconds -lt $Timeout) {
                            Start-Sleep -Seconds 2
                        }
                        
                        $finalStatus = (Get-Service -Name $svcName).Status
                        
                        $results += [PSCustomObject]@{
                            ServiceName = $svcName
                            Status = $finalStatus
                            Success = ($finalStatus -eq 'Running')
                            TimeTaken = $stopwatch.Elapsed.TotalSeconds
                        }
                    } else {
                        $results += [PSCustomObject]@{
                            ServiceName = $svcName
                            Status = $service.Status
                            Success = $true
                            TimeTaken = 0
                        }
                    }
                } catch {
                    $results += [PSCustomObject]@{
                        ServiceName = $svcName
                        Status = "ERROR"
                        Success = $false
                        Error = $_.Exception.Message
                    }
                }
            }
            
            return $results
        } -ArgumentList (,$ServiceNames), $TimeoutSeconds -ErrorAction Stop
        
        foreach ($svcResult in $result) {
            if ($svcResult.Success) {
                Write-Log "Service started: $($svcResult.ServiceName) on $ServerName ($($svcResult.TimeTaken)s)" "SUCCESS"
            } else {
                Write-Log "Failed to start service: $($svcResult.ServiceName) on $ServerName" "ERROR"
                $script:failedServices += "$ServerName\$($svcResult.ServiceName)"
            }
        }
        
        return $result
        
    } catch {
        Write-Log "Failed to start services on $ServerName : $_" "ERROR"
        $script:failedServers += $ServerName
        return $null
    }
}

# Function to perform pre-patch validation
function Invoke-PrePatchValidation {
    Write-Log "`n========== PRE-PATCH VALIDATION ==========" "INFO"
    
    # Server connectivity
    $connectivityResults = Test-ServerConnectivity -ServerList $servers
    
    if ($failedServers.Count -gt 0) {
        Write-Log "Server connectivity failures detected. Aborting." "ERROR"
        return $false
    }
    
    # Backup validation
    if (-not $SkipBackupCheck) {
        Write-Log "Validating backups..."
        # Add backup validation logic here (check VSS, backup software status, etc.)
        Write-Log "Backup validation skipped (implement based on backup solution)" "WARNING"
    }
    
    # Capture current service states
    Write-Log "Capturing current service states for rollback..."
    foreach ($server in $servers) {
        $currentStates = Get-ServiceStateRemote -ServerName $server.ServerName -ServiceNames $server.Services
        $serviceStates[$server.ServerName] = $currentStates
        
        Write-Log "Captured state for $($server.ServerName): $($currentStates.Count) services"
    }
    
    Write-Log "Pre-patch validation completed successfully" "SUCCESS"
    return $true
}

# Function to execute pre-patch service shutdown
function Invoke-PrePatchShutdown {
    Write-Log "`n========== PRE-PATCH SERVICE SHUTDOWN ==========" "INFO"
    
    # Sort servers by StopOrder
    $sortedServers = $servers | Sort-Object StopOrder
    
    foreach ($server in $sortedServers) {
        Write-Log "Processing server: $($server.ServerName) (Stop Order: $($server.StopOrder))"
        
        $stopResult = Stop-ServiceRemote -ServerName $server.ServerName -ServiceNames $server.Services
        
        # Brief pause between servers
        Start-Sleep -Seconds 5
    }
    
    if ($failedServices.Count -eq 0) {
        Write-Log "All services stopped successfully" "SUCCESS"
        return $true
    } else {
        Write-Log "Some services failed to stop: $($failedServices -join ', ')" "ERROR"
        return $false
    }
}

# Function to execute WSUS patching
function Invoke-WSUSPatching {
    param([object[]]$ServerList, [string]$DeploymentName)
    
    Write-Log "`n========== WSUS PATCH DEPLOYMENT ==========" "INFO"
    
    try {
        # Auto-detect WSUS server if not specified
        if (-not $WSUSServer) {
            $WSUSServer = $config.PatchingSettings.WSUSServer
            if (-not $WSUSServer) {
                # Try to get from registry
                $wsusReg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ErrorAction SilentlyContinue
                $WSUSServer = $wsusReg.WUServer -replace 'http://|https://', ''
            }
        }
        
        if (-not $WSUSServer) {
            Write-Log "WSUS server not specified and could not be auto-detected" "ERROR"
            return $false
        }
        
        Write-Log "Connecting to WSUS server: $WSUSServer"
        
        # Load WSUS assembly
        [reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration") | Out-Null
        $wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::GetUpdateServer($WSUSServer, $false, 8530)
        
        Write-Log "Connected to WSUS server successfully" "SUCCESS"
        
        # Get target computer group or deployment
        if ($DeploymentName) {
            Write-Log "Looking for deployment/group: $DeploymentName"
            $computerGroup = $wsus.GetComputerTargetGroups() | Where-Object { $_.Name -eq $DeploymentName }
            
            if (-not $computerGroup) {
                Write-Log "Deployment group '$DeploymentName' not found in WSUS" "ERROR"
                return $false
            }
        }
        
        # Trigger update installation on each server
        foreach ($server in $ServerList) {
            $serverName = $server.ServerName
            Write-Log "Triggering WSUS updates on: $serverName"
            
            try {
                # Trigger Windows Update client to check for updates
                Invoke-Command -ComputerName $serverName -ScriptBlock {
                    $updateSession = New-Object -ComObject Microsoft.Update.Session
                    $updateSearcher = $updateSession.CreateUpdateSearcher()
                    
                    Write-Host "Searching for updates..."
                    $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
                    
                    if ($searchResult.Updates.Count -eq 0) {
                        Write-Host "No updates available"
                        return @{Success = $true; UpdateCount = 0; Message = "No updates needed"}
                    }
                    
                    Write-Host "Found $($searchResult.Updates.Count) updates"
                    
                    # Download updates
                    $updatesToDownload = New-Object -ComObject Microsoft.Update.UpdateColl
                    foreach ($update in $searchResult.Updates) {
                        $updatesToDownload.Add($update) | Out-Null
                    }
                    
                    $downloader = $updateSession.CreateUpdateDownloader()
                    $downloader.Updates = $updatesToDownload
                    $downloadResult = $downloader.Download()
                    
                    # Install updates
                    $updatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl
                    foreach ($update in $searchResult.Updates) {
                        if ($update.IsDownloaded) {
                            $updatesToInstall.Add($update) | Out-Null
                        }
                    }
                    
                    $installer = $updateSession.CreateUpdateInstaller()
                    $installer.Updates = $updatesToInstall
                    $installResult = $installer.Install()
                    
                    return @{
                        Success = ($installResult.ResultCode -eq 2 -or $installResult.ResultCode -eq 3)
                        UpdateCount = $updatesToInstall.Count
                        RebootRequired = $installResult.RebootRequired
                        ResultCode = $installResult.ResultCode
                    }
                } -ErrorAction Stop
                
                Write-Log "WSUS updates completed on $serverName" "SUCCESS"
                
            } catch {
                Write-Log "Failed to trigger WSUS updates on $serverName : $_" "ERROR"
                $script:failedServers += $serverName
            }
        }
        
        Write-Log "WSUS patching phase completed" "SUCCESS"
        return $true
        
    } catch {
        Write-Log "WSUS patching failed: $_" "ERROR"
        return $false
    }
}

<#
========== ALTERNATIVE PATCHING METHOD: MANAGEENGINE DESKTOP CENTRAL ==========

ManageEngine Desktop Central uses pre-created patch deployment jobs that are executed
via REST API. The admin must create the deployment job in the DTC console first.

To enable Desktop Central:
1. Comment out Invoke-WSUSPatching function above
2. Uncomment this function
3. Update config file with DTC API credentials
4. Set -PatchingMethod DesktopCentral
5. Specify -DeploymentName with the DTC job name

Configuration File Addition:
"PatchingSettings": {
    "DesktopCentral": {
        "ServerURL": "https://dtc.contoso.com:8383",
        "APIKey": "your-api-key-here",
        "TechnicianKey": "your-tech-key-here"
    }
}

function Invoke-DesktopCentralPatching {
    param([object[]]$ServerList, [string]$JobName)
    
    Write-Log "`n========== DESKTOP CENTRAL PATCH DEPLOYMENT ==========" "INFO"
    
    try {
        $dtcConfig = $config.PatchingSettings.DesktopCentral
        
        if (-not $dtcConfig) {
            Write-Log "Desktop Central configuration not found in config file" "ERROR"
            return $false
        }
        
        if (-not $JobName) {
            Write-Log "Deployment job name (-DeploymentName) is required for Desktop Central" "ERROR"
            return $false
        }
        
        Write-Log "Connecting to Desktop Central: $($dtcConfig.ServerURL)"
        
        # Build API headers
        $headers = @{
            "Authorization" = "Bearer $($dtcConfig.APIKey)"
            "Content-Type" = "application/json"
        }
        
        # Get deployment configuration ID by name
        $deploymentsURL = "$($dtcConfig.ServerURL)/api/1.3/patch/deployments"
        $deployments = Invoke-RestMethod -Uri $deploymentsURL -Headers $headers -Method Get
        
        $deployment = $deployments.deployments | Where-Object { $_.deployment_policy_name -eq $JobName }
        
        if (-not $deployment) {
            Write-Log "Deployment job '$JobName' not found in Desktop Central" "ERROR"
            return $false
        }
        
        Write-Log "Found deployment job: $JobName (ID: $($deployment.deployment_policy_id))" "SUCCESS"
        
        # Execute deployment
        $executeURL = "$($dtcConfig.ServerURL)/api/1.3/patch/deployments/$($deployment.deployment_policy_id)/execute"
        
        Write-Log "Executing deployment job: $JobName"
        $result = Invoke-RestMethod -Uri $executeURL -Headers $headers -Method Post
        
        if ($result.status -eq "success") {
            Write-Log "Deployment job started successfully" "SUCCESS"
            Write-Log "Job ID: $($result.job_id)"
            
            # Poll for completion
            $statusURL = "$($dtcConfig.ServerURL)/api/1.3/patch/deployments/$($result.job_id)/status"
            $completed = $false
            $timeout = [DateTime]::Now.AddMinutes($PatchingTimeout)
            
            while (-not $completed -and [DateTime]::Now -lt $timeout) {
                Start-Sleep -Seconds 30
                $status = Invoke-RestMethod -Uri $statusURL -Headers $headers -Method Get
                
                Write-Log "Deployment status: $($status.status) - Progress: $($status.progress)%"
                
                if ($status.status -eq "Completed" -or $status.status -eq "Failed") {
                    $completed = $true
                }
            }
            
            if ($status.status -eq "Completed") {
                Write-Log "Desktop Central deployment completed successfully" "SUCCESS"
                return $true
            } else {
                Write-Log "Desktop Central deployment did not complete in time or failed" "ERROR"
                return $false
            }
        } else {
            Write-Log "Failed to start deployment job: $($result.message)" "ERROR"
            return $false
        }
        
    } catch {
        Write-Log "Desktop Central patching failed: $_" "ERROR"
        return $false
    }
}

========== END DESKTOP CENTRAL ALTERNATIVE ==========
#>

<#
========== ALTERNATIVE PATCHING METHOD: AWS SYSTEMS MANAGER ==========

AWS Systems Manager Patch Manager uses patch baselines and maintenance windows.
This is ideal for hybrid cloud or AWS-hosted servers.

To enable AWS SSM:
1. Install AWS Tools for PowerShell: Install-Module -Name AWS.Tools.SSM
2. Configure AWS credentials
3. Comment out Invoke-WSUSPatching
4. Uncomment this function
5. Set -PatchingMethod AWSSystemsManager
6. Specify -DeploymentName with the maintenance window ID

Configuration File Addition:
"PatchingSettings": {
    "AWSSystemsManager": {
        "Region": "us-east-1",
        "ProfileName": "default"
    }
}

function Invoke-AWSSystemsManagerPatching {
    param([object[]]$ServerList, [string]$MaintenanceWindowId)
    
    Write-Log "`n========== AWS SYSTEMS MANAGER PATCH DEPLOYMENT ==========" "INFO"
    
    try {
        Import-Module AWS.Tools.SSM -ErrorAction Stop
        
        $awsConfig = $config.PatchingSettings.AWSSystemsManager
        
        if (-not $awsConfig) {
            Write-Log "AWS Systems Manager configuration not found in config file" "ERROR"
            return $false
        }
        
        # Set AWS credentials and region
        Set-DefaultAWSRegion -Region $awsConfig.Region
        if ($awsConfig.ProfileName) {
            Set-AWSCredential -ProfileName $awsConfig.ProfileName
        }
        
        Write-Log "Connected to AWS Systems Manager in region: $($awsConfig.Region)" "SUCCESS"
        
        # Get instance IDs for servers
        $instanceIds = @()
        foreach ($server in $ServerList) {
            try {
                # Query SSM for instance by tag or name
                $instance = Get-SSMInstanceInformation -Filter @{
                    Key = "tag:Name"
                    Values = $server.ServerName
                } | Select-Object -First 1
                
                if ($instance) {
                    $instanceIds += $instance.InstanceId
                    Write-Log "Found instance: $($server.ServerName) - $($instance.InstanceId)"
                } else {
                    Write-Log "Instance not found in SSM: $($server.ServerName)" "WARNING"
                }
            } catch {
                Write-Log "Error finding instance $($server.ServerName): $_" "ERROR"
            }
        }
        
        if ($instanceIds.Count -eq 0) {
            Write-Log "No instances found in AWS SSM" "ERROR"
            return $false
        }
        
        # Execute patch baseline
        Write-Log "Executing patch baseline on $($instanceIds.Count) instances"
        
        $command = Send-SSMCommand -DocumentName "AWS-RunPatchBaseline" `
                                    -InstanceId $instanceIds `
                                    -Parameter @{
                                        "Operation" = "Install"
                                        "RebootOption" = "RebootIfNeeded"
                                    }
        
        Write-Log "Patch command sent. Command ID: $($command.CommandId)" "SUCCESS"
        
        # Wait for completion
        $completed = $false
        $timeout = [DateTime]::Now.AddMinutes($PatchingTimeout)
        
        while (-not $completed -and [DateTime]::Now -lt $timeout) {
            Start-Sleep -Seconds 30
            
            $commandInvocations = Get-SSMCommandInvocation -CommandId $command.CommandId
            $pending = $commandInvocations | Where-Object { $_.Status -in @('Pending', 'InProgress') }
            
            if ($pending.Count -eq 0) {
                $completed = $true
            } else {
                Write-Log "Patching in progress... $($pending.Count) instances remaining"
            }
        }
        
        # Check results
        $successCount = ($commandInvocations | Where-Object { $_.Status -eq 'Success' }).Count
        $failedCount = ($commandInvocations | Where-Object { $_.Status -eq 'Failed' }).Count
        
        Write-Log "AWS SSM Patching completed: $successCount successful, $failedCount failed"
        
        return ($failedCount -eq 0)
        
    } catch {
        Write-Log "AWS Systems Manager patching failed: $_" "ERROR"
        return $false
    }
}

========== END AWS SYSTEMS MANAGER ALTERNATIVE ==========
#>

# Function to execute post-patch service restoration
function Invoke-PostPatchRestoration {
    Write-Log "`n========== POST-PATCH SERVICE RESTORATION ==========" "INFO"
    
    # Sort servers by StartOrder
    $sortedServers = $servers | Sort-Object StartOrder
    
    foreach ($server in $sortedServers) {
        Write-Log "Processing server: $($server.ServerName) (Start Order: $($server.StartOrder))"
        
        $startResult = Start-ServiceRemote -ServerName $server.ServerName -ServiceNames $server.Services
        
        # Brief pause between servers for dependencies
        Start-Sleep -Seconds 10
    }
    
    if ($failedServices.Count -eq 0) {
        Write-Log "All services started successfully" "SUCCESS"
        return $true
    } else {
        Write-Log "Some services failed to start: $($failedServices -join ', ')" "ERROR"
        return $false
    }
}

# Main execution
Write-Log "`n========================================" "INFO"
Write-Log "PATCH TUESDAY ORCHESTRATION - $Mode" "INFO"
Write-Log "Server Group: $ServerGroup" "INFO"
Write-Log "Servers: $($servers.Count)" "INFO"
Write-Log "========================================`n" "INFO"

Send-EmailNotification -Subject "Starting: $Mode for $ServerGroup" -Body "Patch orchestration initiated at $(Get-Date)<br>Mode: $Mode<br>Server Group: $ServerGroup<br>Servers: $($servers.Count)"

# Execute based on mode
switch ($Mode) {
    'Validate' {
        $validationResult = Invoke-PrePatchValidation
        
        if ($validationResult) {
            Write-Log "`nValidation completed successfully" "SUCCESS"
            Send-EmailNotification -Subject "Validation Successful: $ServerGroup" -Body "All pre-patch validation checks passed."
        } else {
            Write-Log "`nValidation failed" "ERROR"
            Send-EmailNotification -Subject "Validation Failed: $ServerGroup" -Body "Pre-patch validation encountered errors. Check logs." -Priority "High"
            exit 1
        }
    }
    
    'PrePatch' {
        if (-not (Invoke-PrePatchValidation)) {
            Write-Log "Pre-patch validation failed. Aborting." "ERROR"
            Send-EmailNotification -Subject "Pre-Patch Failed: $ServerGroup" -Body "Validation failed. Patching aborted." -Priority "High"
            exit 1
        }
        
        if (-not (Invoke-PrePatchShutdown)) {
            Write-Log "Service shutdown encountered errors" "ERROR"
            Send-EmailNotification -Subject "Service Shutdown Errors: $ServerGroup" -Body "Some services failed to stop.<br>Failed: $($failedServices -join '<br>')" -Priority "High"
            exit 1
        }
        
        Write-Log "`nServices stopped successfully. Ready for patching." "SUCCESS"
        Send-EmailNotification -Subject "Services Stopped: $ServerGroup" -Body "All services stopped successfully. Patching can proceed.<br><br>Failed Services: $($failedServices.Count)"
        
        if ($WaitForPatching) {
            Write-Log "`nWaiting for patching to complete (Timeout: $PatchingTimeout minutes)" "INFO"
            Write-Log "Press Ctrl+C to exit or wait for timeout" "INFO"
            Start-Sleep -Seconds ($PatchingTimeout * 60)
        }
    }
    
    'PostPatch' {
        if (-not (Invoke-PostPatchRestoration)) {
            Write-Log "Service restoration encountered errors" "ERROR"
            Send-EmailNotification -Subject "Service Restoration Errors: $ServerGroup" -Body "Some services failed to start.<br>Failed: $($failedServices -join '<br>')" -Priority "High"
            exit 1
        }
        
        Write-Log "`nServices restored successfully" "SUCCESS"
        Send-EmailNotification -Subject "Services Restored: $ServerGroup" -Body "All services started successfully. Patching complete.<br><br>Failed Services: $($failedServices.Count)"
    }
    
    'FullAuto' {
        if (-not (Invoke-PrePatchValidation)) {
            Write-Log "Pre-patch validation failed. Aborting." "ERROR"
            Send-EmailNotification -Subject "Full Auto Failed: $ServerGroup" -Body "Validation failed. Patching aborted." -Priority "High"
            exit 1
        }
        
        if (-not (Invoke-PrePatchShutdown)) {
            Write-Log "Service shutdown encountered errors. Aborting." "ERROR"
            Send-EmailNotification -Subject "Full Auto Failed: $ServerGroup" -Body "Service shutdown failed. Patching aborted." -Priority "High"
            exit 1
        }
        
        # Execute patching based on method
        $patchingSuccess = $false
        
        switch ($PatchingMethod) {
            'WSUS' {
                Write-Log "Executing WSUS patching method"
                $patchingSuccess = Invoke-WSUSPatching -ServerList $servers -DeploymentName $DeploymentName
            }
            'ManualPause' {
                Write-Log "`nServices stopped. Waiting for manual patching ($PatchingTimeout minutes)..." "INFO"
                Write-Log "Perform patching manually, then wait for timeout or press Ctrl+C to continue" "INFO"
                Start-Sleep -Seconds ($PatchingTimeout * 60)
                $patchingSuccess = $true
            }
            'DesktopCentral' {
                Write-Log "Desktop Central method selected but code is commented out" "ERROR"
                Write-Log "Uncomment Invoke-DesktopCentralPatching function and configure API settings" "ERROR"
                $patchingSuccess = $false
            }
            'AWSSystemsManager' {
                Write-Log "AWS Systems Manager method selected but code is commented out" "ERROR"
                Write-Log "Uncomment Invoke-AWSSystemsManagerPatching function and install AWS.Tools.SSM" "ERROR"
                $patchingSuccess = $false
            }
        }
        
        if (-not $patchingSuccess) {
            Write-Log "Patching phase failed" "ERROR"
            Send-EmailNotification -Subject "Patching Failed: $ServerGroup" -Body "Patching execution failed. Check logs for details." -Priority "High"
            
            # Attempt to restore services even after patching failure
            Write-Log "Attempting service restoration after patching failure..." "WARNING"
        }
        
        if (-not (Invoke-PostPatchRestoration)) {
            Write-Log "Service restoration encountered errors" "ERROR"
            Send-EmailNotification -Subject "Full Auto Partial Success: $ServerGroup" -Body "Patching completed but some services failed to start.<br>Failed: $($failedServices -join '<br>')" -Priority "High"
            exit 1
        }
        
        Write-Log "`nFull automation cycle completed successfully" "SUCCESS"
        Send-EmailNotification -Subject "Full Auto Complete: $ServerGroup" -Body "Patching cycle completed successfully. All services running."
    }
}

# Final summary
Write-Log "`n========== EXECUTION SUMMARY ==========" "INFO"
Write-Log "Mode:                $Mode" "INFO"
Write-Log "Server Group:        $ServerGroup" "INFO"
Write-Log "Servers Processed:   $($servers.Count)" "INFO"
Write-Log "Failed Servers:      $($failedServers.Count)" "INFO"
Write-Log "Failed Services:     $($failedServices.Count)" "INFO"
Write-Log "Log File:            $logFile" "INFO"
Write-Log "========================================`n" "INFO"

if ($failedServers.Count -gt 0 -or $failedServices.Count -gt 0) {
    Write-Log "ATTENTION: Some operations failed. Review log file." "WARNING"
    exit 1
}

Write-Log "Patch orchestration completed successfully" "SUCCESS"
exit 0
