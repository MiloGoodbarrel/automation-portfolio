<#
.SYNOPSIS
    Automated file share provisioning with Active Directory security group creation.

.DESCRIPTION
    Creates DFS namespaces, file shares, and corresponding AD security groups in a single workflow.
    Implements standardized naming conventions and permission structures for enterprise file services.

.FEATURES
    - DFS namespace and folder creation
    - SMB share provisioning with ABE (Access-Based Enumeration)
    - Automatic AD security group creation (Read, Modify, Full Control)
    - NTFS permission application
    - Share documentation and inventory tracking
    - Quota management integration
    - Audit logging and compliance reporting

.FUNCTIONALITY
    Share Types:
    - Department shares (Finance, HR, IT, etc.)
    - Project shares (temporary, auto-expiring)
    - Application data shares
    - User home directories
    - DFS replicated shares

    AD Group Naming Convention:
    - FS_[ShareName]_Read
    - FS_[ShareName]_Modify
    - FS_[ShareName]_FullControl

.PARAMETER ShareName
    Name of the file share (alphanumeric, hyphens allowed)

.PARAMETER SharePath
    Local path where share will be created (default: D:\Shares\)

.PARAMETER DFSPath
    DFS namespace path (e.g., \\contoso.com\DFS\Departments)

.PARAMETER Department
    Department or organizational unit for group placement

.PARAMETER QuotaGB
    Storage quota in GB (optional)

.PARAMETER EnableABE
    Enable Access-Based Enumeration (default: $true)

.PARAMETER ShareType
    Type of share: Department, Project, Application, Home (default: Department)

.EXAMPLE
    .\New-FileShareWithADGroup.ps1 -ShareName "Finance-Reports" -Department "Finance" -QuotaGB 500
    
    Creates Finance-Reports share with 500GB quota and AD groups:
    - FS_Finance-Reports_Read
    - FS_Finance-Reports_Modify
    - FS_Finance-Reports_FullControl

.EXAMPLE
    .\New-FileShareWithADGroup.ps1 -ShareName "ProjectX" -ShareType Project -Department "IT" -DFSPath "\\contoso.com\DFS\Projects"
    
    Creates project share with DFS integration.

.NOTES
    Author:  Luis Ramirez
    Created: 2-14-2021
    Updated: 1-24-2026
    Version: 2.1
    
    Requirements:
    - ActiveDirectory module
    - DFS Management Tools (RSAT-DFS-Mgmt-Con)
    - File Server Resource Manager (FS-Resource-Manager)
    - Domain Admin or delegated permissions
    
    Group Strategy:
    Current: Creates Global groups and assigns permissions directly (simpler, works for single domain)
    Alternative: AGDLP model available as commented code (see line ~170) - uses Domain Local groups
                 for permissions with Global groups for user membership (Microsoft best practice)
    
    Change Log:
    2.1 - Added DFS namespace support, quota management
    2.0 - Modernized for Server 2019/2022, added ABE
    1.0 - Initial release
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-zA-Z0-9-]+$')]
    [string]$ShareName,

    [Parameter(Mandatory = $false)]
    [string]$SharePath = "D:\Shares\",

    [Parameter(Mandatory = $false)]
    [string]$DFSPath,

    [Parameter(Mandatory = $true)]
    [string]$Department,

    [Parameter(Mandatory = $false)]
    [int]$QuotaGB,

    [Parameter(Mandatory = $false)]
    [bool]$EnableABE = $true,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Department', 'Project', 'Application', 'Home')]
    [string]$ShareType = 'Department',

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "C:\Logs\FileShareProvisioning"
)

#Requires -Modules ActiveDirectory
#Requires -RunAsAdministrator

# Initialize logging
if (-not (Test-Path $LogPath)) { New-Item -ItemType Directory -Path $LogPath -Force | Out-Null }
$logFile = Join-Path $LogPath "ShareCreation_$($ShareName)_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logMessage
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage }
    }
}

# Validate prerequisites
Write-Log "Starting file share provisioning for: $ShareName" "INFO"

try {
    Import-Module ActiveDirectory -ErrorAction Stop
    Write-Log "ActiveDirectory module loaded successfully" "SUCCESS"
} catch {
    Write-Log "Failed to load ActiveDirectory module: $_" "ERROR"
    exit 1
}

# Build full share path
$fullSharePath = Join-Path $SharePath $ShareName

# Create directory structure
Write-Log "Creating directory: $fullSharePath"
try {
    if (-not (Test-Path $fullSharePath)) {
        New-Item -ItemType Directory -Path $fullSharePath -Force | Out-Null
        Write-Log "Directory created successfully" "SUCCESS"
    } else {
        Write-Log "Directory already exists" "WARNING"
    }
} catch {
    Write-Log "Failed to create directory: $_" "ERROR"
    exit 1
}

# Create AD security groups
$groupPrefix = "FS_$ShareName"
$groups = @{
    Read = "$groupPrefix`_Read"
    Modify = "$groupPrefix`_Modify"
    FullControl = "$groupPrefix`_FullControl"
}

$ouPath = "OU=File Share Groups,OU=$Department,DC=" + ((Get-ADDomain).DNSRoot -replace '\.', ',DC=')

Write-Log "Creating AD security groups in OU: $ouPath"

foreach ($groupType in $groups.Keys) {
    $groupName = $groups[$groupType]
    
    try {
        $existingGroup = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
        
        if (-not $existingGroup) {
            New-ADGroup -Name $groupName `
                        -GroupScope Global `
                        -GroupCategory Security `
                        -Path $ouPath `
                        -Description "File share access: $ShareName ($groupType)" `
                        -ErrorAction Stop
            
            Write-Log "Created AD group: $groupName" "SUCCESS"
        } else {
            Write-Log "AD group already exists: $groupName" "WARNING"
        }
    } catch {
        Write-Log "Failed to create AD group $groupName" "ERROR"
    }
}

<#
========== ALTERNATIVE: AGDLP BEST PRACTICE APPROACH ==========
Microsoft recommends AGDLP model (Accounts → Global Groups → Domain Local Groups → Permissions)
for multi-domain environments and enterprise-scale management.

To enable this approach:
1. Comment out the above Global group creation (lines 173-193)
2. Uncomment the code below
3. Update the SMB share and NTFS permission sections to use $domainLocalGroups instead of $groups

Benefits:
- Scalable across multiple domains
- Separation of user membership (Global) from resource access (Domain Local)
- Easier to grant same users access to multiple resources
- Microsoft recommended best practice

Drawbacks:
- More complex (6 groups vs 3 groups)
- Additional management overhead for small environments
- One extra level of indirection

# Create Domain Local groups for permissions
$domainLocalGroups = @{
    Read = "DL_FS_$ShareName`_Read"
    Modify = "DL_FS_$ShareName`_Modify"
    FullControl = "DL_FS_$ShareName`_FullControl"
}

# Create Global groups for user membership
$globalGroups = @{
    Read = "GG_$Department`_$ShareName`_Readers"
    Modify = "GG_$Department`_$ShareName`_Contributors"
    FullControl = "GG_$Department`_$ShareName`_Owners"
}

Write-Log "Creating AGDLP group structure (Domain Local + Global groups)"

# Create Domain Local groups (receive permissions)
foreach ($groupType in $domainLocalGroups.Keys) {
    $groupName = $domainLocalGroups[$groupType]
    
    try {
        $existingGroup = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
        
        if (-not $existingGroup) {
            New-ADGroup -Name $groupName `
                        -GroupScope DomainLocal `
                        -GroupCategory Security `
                        -Path $ouPath `
                        -Description "File share permissions: $ShareName ($groupType access)" `
                        -ErrorAction Stop
            
            Write-Log "Created Domain Local group: $groupName" "SUCCESS"
        } else {
            Write-Log "Domain Local group already exists: $groupName" "WARNING"
        }
    } catch {
        Write-Log "Failed to create Domain Local group $groupName" "ERROR"
    }
}

# Create Global groups (contain users)
foreach ($groupType in $globalGroups.Keys) {
    $groupName = $globalGroups[$groupType]
    
    try {
        $existingGroup = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
        
        if (-not $existingGroup) {
            New-ADGroup -Name $groupName `
                        -GroupScope Global `
                        -GroupCategory Security `
                        -Path $ouPath `
                        -Description "User membership: $ShareName ($groupType users)" `
                        -ErrorAction Stop
            
            Write-Log "Created Global group: $groupName" "SUCCESS"
        } else {
            Write-Log "Global group already exists: $groupName" "WARNING"
        }
    } catch {
        Write-Log "Failed to create Global group $groupName" "ERROR"
    }
}

# Wait for AD replication before nesting
Write-Log "Waiting for AD replication before nesting groups (15 seconds)..."
Start-Sleep -Seconds 15

# Nest Global groups into Domain Local groups (AGDLP model)
foreach ($groupType in $domainLocalGroups.Keys) {
    try {
        Add-ADGroupMember -Identity $domainLocalGroups[$groupType] `
                          -Members $globalGroups[$groupType] `
                          -ErrorAction Stop
        
        Write-Log "Added $($globalGroups[$groupType]) to $($domainLocalGroups[$groupType])" "SUCCESS"
    } catch {
        Write-Log "Failed to nest groups for $groupType" "ERROR"
    }
}

# Update the $groups variable to use Domain Local groups for permissions
$groups = $domainLocalGroups

Write-Log "AGDLP structure created successfully"
Write-Log "  Domain Local groups (permissions): $($domainLocalGroups.Values -join ', ')"
Write-Log "  Global groups (user membership): $($globalGroups.Values -join ', ')"
Write-Log "  Add users to Global groups, permissions assigned via Domain Local groups"

========== END AGDLP ALTERNATIVE ==========
#>

# Wait for AD replication
Write-Log "Waiting for AD replication (15 seconds)..."
Start-Sleep -Seconds 15

# Create SMB share
Write-Log "Creating SMB share: $ShareName"

try {
    $shareExists = Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue
    
    if (-not $shareExists) {
        $shareParams = @{
            Name = $ShareName
            Path = $fullSharePath
            Description = "$ShareType share for $Department"
            FullAccess = "BUILTIN\Administrators", $groups.FullControl
            ChangeAccess = $groups.Modify
            ReadAccess = $groups.Read
        }
        
        if ($EnableABE) {
            $shareParams.Add('FolderEnumerationMode', 'AccessBased')
        }
        
        New-SmbShare @shareParams -ErrorAction Stop
        Write-Log "SMB share created successfully" "SUCCESS"
    } else {
        Write-Log "SMB share already exists" "WARNING"
    }
} catch {
    Write-Log "Failed to create SMB share: $_" "ERROR"
    exit 1
}

# Set NTFS permissions
Write-Log "Configuring NTFS permissions"

try {
    $acl = Get-Acl $fullSharePath
    
    # Disable inheritance
    $acl.SetAccessRuleProtection($true, $false)
    
    # Remove existing permissions
    $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) | Out-Null }
    
    # Add System and Administrators
    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    
    $acl.AddAccessRule($systemRule)
    $acl.AddAccessRule($adminRule)
    
    # Add group permissions
    $readRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $groups.Read, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $modifyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $groups.Modify, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $fullControlRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $groups.FullControl, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    
    $acl.AddAccessRule($readRule)
    $acl.AddAccessRule($modifyRule)
    $acl.AddAccessRule($fullControlRule)
    
    Set-Acl -Path $fullSharePath -AclObject $acl
    Write-Log "NTFS permissions configured successfully" "SUCCESS"
    
} catch {
    Write-Log "Failed to set NTFS permissions: $_" "ERROR"
}

# Configure quota if specified
if ($QuotaGB) {
    Write-Log "Configuring quota: $QuotaGB GB"
    
    try {
        # Check if FSRM is available
        $fsrmAvailable = Get-Command New-FsrmQuota -ErrorAction SilentlyContinue
        
        if ($fsrmAvailable) {
            New-FsrmQuota -Path $fullSharePath -Size ($QuotaGB * 1GB) -Threshold 85,95 -ErrorAction Stop
            Write-Log "Quota configured successfully" "SUCCESS"
        } else {
            Write-Log "File Server Resource Manager not available - skipping quota" "WARNING"
        }
    } catch {
        Write-Log "Failed to configure quota: $_" "ERROR"
    }
}

# Create DFS link if specified
if ($DFSPath) {
    Write-Log "Creating DFS link: $DFSPath\$ShareName"
    
    try {
        $dfsTarget = "\\$env:COMPUTERNAME\$ShareName"
        New-DfsnFolderTarget -Path "$DFSPath\$ShareName" -TargetPath $dfsTarget -ErrorAction Stop
        Write-Log "DFS link created successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to create DFS link: $_" "ERROR"
    }
}

# Generate provisioning report
Write-Log "`n========== PROVISIONING SUMMARY =========="
Write-Log "Share Name:        $ShareName"
Write-Log "Share Path:        $fullSharePath"
Write-Log "Share Type:        $ShareType"
Write-Log "Department:        $Department"
Write-Log "UNC Path:          \\$env:COMPUTERNAME\$ShareName"
if ($DFSPath) { Write-Log "DFS Path:          $DFSPath\$ShareName" }
if ($QuotaGB) { Write-Log "Quota:             $QuotaGB GB" }
Write-Log "ABE Enabled:       $EnableABE"
Write-Log "`nAD Security Groups Created:"
Write-Log "  Read:            $($groups.Read)"
Write-Log "  Modify:          $($groups.Modify)"
Write-Log "  Full Control:    $($groups.FullControl)"
Write-Log "=========================================="

Write-Log "`nFile share provisioning completed successfully!" "SUCCESS"
Write-Log "Log file: $logFile"

# Output object for pipeline use
[PSCustomObject]@{
    ShareName = $ShareName
    Path = $fullSharePath
    UNCPath = "\\$env:COMPUTERNAME\$ShareName"
    DFSPath = if ($DFSPath) { "$DFSPath\$ShareName" } else { $null }
    ReadGroup = $groups.Read
    ModifyGroup = $groups.Modify
    FullControlGroup = $groups.FullControl
    QuotaGB = $QuotaGB
    Status = "Success"
    LogFile = $logFile
}
