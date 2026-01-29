################################################
# Author: Luis Ramirez                         #
# Created: 3-21-2019                           #
# Updated: 1-22-2026                           #
################################################
<###################################################################################
# Automated user provisioning and deprovisioning system integrated with HRIS.     #
#                                                                                  #
# This script synchronizes an HRIS system (Workday, etc.) with Active Directory:  #
# - Creates new users for employees not in AD                                     #
# - Disables users who have separated from the company                            #
# - Assigns department-based security groups using template accounts              #
# - Stores employee ID and department ID in AD extended attributes                #
#                                                                                  #
# CRITICAL SAFETY FEATURE:                                                         #
# This script will NEVER touch the following account types:                       #
#   - Elevated accounts (SA*, DA*, GA*, PA*, EA*, ADMIN*)                         #
#   - Service accounts (svc-*, app-*, service-*)                                  #
#   - Template accounts (template_*, tmpl_*)                                      #
#   - Accounts without EmployeeID attribute                                       #
#   - Accounts in excluded OUs (Service Accounts, Admin Accounts, Templates)     #
#                                                                                  #
# See AD-Naming-Standards.md for complete prerequisites and naming requirements.  #
#                                                                                  #
# HRIS CSV Format Required:                                                       #
#   EmployeeID, FirstName, LastName, Email, DepartmentID, Manager, Title         #
#                                                                                  #
# Parameters:                                                                      #
#   -HRISExportFile: Path to HRIS CSV export                                      #
#   -DepartmentMapFile: CSV mapping DepartmentID to template account              #
#   -ElevatedPrefixes: Array of elevated account prefixes to exclude              #
#   -ServiceAccountPrefixes: Array of service account prefixes to exclude         #
#   -TemplateAccountPrefixes: Array of template account prefixes to exclude       #
#   -ExcludeOUs: Array of OU names to exclude from processing                     #
#   -NewUserOU: OU path for new users                                             #
#   -DisabledUserOU: OU path for disabled users                                   #
#   -DryRun: Test mode - shows changes without applying them                      #
#   -EmailReport: Send summary email after completion                             #
#                                                                                  #
# Example: .\Sync-HRIStoActiveDirectory.ps1 -HRISExportFile "employees.csv" -DryRun
###################################################################################
.NOTES
Author: Luis Ramirez
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HRISExportFile,

    [Parameter(Mandatory = $true)]
    [string]$DepartmentMapFile,

    [Parameter(Mandatory = $false)]
    [string]$NewUserOU = "OU=Users,DC=contoso,DC=com",

    [Parameter(Mandatory = $false)]
    [string]$DisabledUserOU = "OU=Disabled,OU=Users,DC=contoso,DC=com",

    [Parameter(Mandatory = $false)]
    [string]$LogPath = "$env:TEMP\HRIS-AD-Sync-$(Get-Date -Format 'yyyyMMdd-HHmmss').log",

    [Parameter(Mandatory = $false)]
    [string[]]$ElevatedPrefixes = @("SA", "DA", "GA", "PA", "EA", "ADMIN"),

    [Parameter(Mandatory = $false)]
    [string[]]$ServiceAccountPrefixes = @("svc-", "service-", "app-"),

    [Parameter(Mandatory = $false)]
    [string[]]$TemplateAccountPrefixes = @("template_", "tmpl_"),

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeOUs = @("OU=Service Accounts", "OU=Admin Accounts", "OU=Templates"),

    [Parameter(Mandatory = $false)]
    [string]$EmailRecipient,

    [Parameter(Mandatory = $false)]
    [string]$SMTPServer,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

#region Functions

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warning', 'Error', 'Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console output with colors
    switch ($Level) {
        'Info'    { Write-Host $logMessage -ForegroundColor Gray }
        'Warning' { Write-Host $logMessage -ForegroundColor Yellow }
        'Error'   { Write-Host $logMessage -ForegroundColor Red }
        'Success' { Write-Host $logMessage -ForegroundColor Green }
    }
    
    # Log to file
    Add-Content -Path $LogPath -Value $logMessage
}

function Get-RandomPassword {
    param([int]$Length = 16)
    
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
    $password = -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    return ConvertTo-SecureString $password -AsPlainText -Force
}

function New-SamAccountName {
    param(
        [string]$FirstName,
        [string]$LastName
    )
    
    # Generate username: first initial + last name (e.g., jsmith)
    $samBase = ($FirstName.Substring(0,1) + $LastName).ToLower() -replace '[^a-z0-9]', ''
    
    # Ensure it's unique
    $samAccount = $samBase
    $counter = 1
    
    while (Get-ADUser -Filter "SamAccountName -eq '$samAccount'" -ErrorAction SilentlyContinue) {
        $samAccount = "$samBase$counter"
        $counter++
    }
    
    return $samAccount
}

function Copy-ADGroupMemberships {
    param(
        [string]$SourceUser,
        [string]$TargetUser
    )
    
    try {
        $groups = Get-ADUser -Identity $SourceUser -Properties MemberOf | 
            Select-Object -ExpandProperty MemberOf
        
        foreach ($group in $groups) {
            try {
                Add-ADGroupMember -Identity $group -Members $TargetUser -ErrorAction Stop
                Write-Log "Added $TargetUser to group: $group" -Level Success
            }
            catch {
function Test-ExcludedAccount {
    param(
        [Microsoft.ActiveDirectory.Management.ADUser]$User
    )
    
    $samAccount = $User.SamAccountName
    $dn = $User.DistinguishedName
    
    # Check for elevated account prefixes (SA*, DA*, GA*, etc.)
    foreach ($prefix in $ElevatedPrefixes) {
        if ($samAccount -like "$prefix*") {
            Write-Log "EXCLUDED: $samAccount (Elevated account - prefix: $prefix)" -Level Info
            return $true
        }
    }
    
    # Check for service account prefixes (svc-*, app-*, etc.)
    foreach ($prefix in $ServiceAccountPrefixes) {
        if ($samAccount -like "$prefix*") {
            Write-Log "EXCLUDED: $samAccount (Service account - prefix: $prefix)" -Level Info
            return $true
        }
    }
    
    # Check for template account prefixes (template_*, tmpl_*, etc.)
    foreach ($prefix in $TemplateAccountPrefixes) {
        if ($samAccount -like "$prefix*") {
            Write-Log "EXCLUDED: $samAccount (Template account - prefix: $prefix)" -Level Info
            return $true
        }
    }
    
    # Check if account is in excluded OUs
    foreach ($ou in $ExcludeOUs) {
        if ($dn -like "*$ou*") {
            Write-Log "EXCLUDED: $samAccount (In excluded OU: $ou)" -Level Info
            return $true
        }
    }
    
    # Check if account has no EmployeeID (indicates non-employee account)
    if (-not $User.EmployeeID) {
        Write-Log "EXCLUDED: $samAccount (No EmployeeID - likely service/admin account)" -Level Info
        return $true
    }
    
    return $false
}

                Write-Log "Failed to add $TargetUser to $group : $_" -Level Warning
            }
        }
        
        return $groups.Count
    }
    catch {
        Write-Log "Failed to copy group memberships from $SourceUser : $_" -Level Error
        return 0
    }
}

#endregion

#region Initialization

Write-Log "========== HRIS to Active Directory Sync Started ==========" -Level Info
Write-Log "HRIS Export: $HRISExportFile" -Level Info
Write-Log "Department Map: $DepartmentMapFile" -Level Info
Write-Log "Dry Run Mode: $DryRun" -Level Info

# Import required module
try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Log "Failed to load ActiveDirectory module. Ensure RSAT is installed." -Level Error
    exit 1
}

# Validate files exist
if (-not (Test-Path $HRISExportFile)) {
    Write-Log "HRIS export file not found: $HRISExportFile" -Level Error
    exit 1
}

if (-not (Test-Path $DepartmentMapFile)) {
    Write-Log "Department map file not found: $DepartmentMapFile" -Level Error
    exit 1
}

#endregion

#region Load Data

Write-Log "Loading HRIS employee data..." -Level Info
$hrisEmployees = Import-Csv -Path $HRISExportFile

Write-Log "Loading department mapping..." -Level Info
# Expected format: DepartmentID, DepartmentName, TemplateAccount
$departmentMap = @{}
$excludedCount = 0

foreach ($adUser in $adUsers) {
    # Skip excluded accounts (service, elevated, template, etc.)
    if (Test-ExcludedAccount -User $adUser) {
        $excludedCount++
        continue
    }
    
    # Only process enabled accounts with EmployeeIDs not in HRIS
    if ($adUser.EmployeeID -and 
        $adUser.Enabled -and 
        $hrisEmployeeIDs -notcontains $adUser.EmployeeID) {
        $separatedUsers += $adUser
    }
}

Write-Log "Found $($separatedUsers.Count) separated employee(s) to disable" -Level Warning
Write-Log "Excluded $excludedCount account(s) from processing (service/admin/template)" -Level Info
#endregion

#region Get Current AD Users

Write-Log "Retrieving current AD users..." -Level Info
$adUsers = Get-ADUser -Filter * -Properties EmployeeID, extensionAttribute1, Enabled, DistinguishedName

# Create lookup by EmployeeID for faster comparison
$adUsersByEmployeeID = @{}
foreach ($user in $adUsers) {
    if ($user.EmployeeID) {
        $adUsersByEmployeeID[$user.EmployeeID] = $user
    }
}

Write-Log "Found $($adUsers.Count) users in Active Directory" -Level Info

#endregion

#region Identify New Users (in HRIS but not in AD)

Write-Log "`nIdentifying new employees..." -Level Info
$newUsers = @()

foreach ($employee in $hrisEmployees) {
    if (-not $adUsersByEmployeeID.ContainsKey($employee.EmployeeID)) {
        $newUsers += $employee
    }
}

Write-Log "Found $($newUsers.Count) new employee(s) to create" -Level Success

#endregion

#region Identify Separated Users (in AD but not in HRIS)

Write-Log "`nIdentifying separated employees..." -Level Info
$hrisEmployeeIDs = $hrisEmployees | Select-Object -ExpandProperty EmployeeID
$separatedUsers = @()

foreach ($adUser in $adUsers) {
    if ($adUser.EmployeeID -and 
        $adUser.Enabled -and 
        $hrisEmployeeIDs -notcontains $adUser.EmployeeID) {
        $separatedUsers += $adUser
    }
}

Write-Log "Found $($separatedUsers.Count) separated employee(s) to disable" -Level Warning

#endregion

#region Create New Users

$createdCount = 0
$failedCreations = 0

if ($newUsers.Count -gt 0) {
    Write-Log "`n========== Creating New Users ==========" -Level Info
    
    foreach ($employee in $newUsers) {
        try {
            # Generate username
            $samAccountName = New-SamAccountName -FirstName $employee.FirstName -LastName $employee.LastName
            $upn = "$samAccountName@" + (Get-ADDomain).DNSRoot
            
            # Get department template
            $deptInfo = $departmentMap[$employee.DepartmentID]
            if (-not $deptInfo) {
                Write-Log "No department mapping for DepartmentID: $($employee.DepartmentID) - Employee: $($employee.FirstName) $($employee.LastName)" -Level Warning
                $deptInfo = @{ Name = "Unknown"; Template = $null }
            }
            
            Write-Log "Creating user: $samAccountName ($($employee.FirstName) $($employee.LastName)) - Dept: $($deptInfo.Name)" -Level Info
            
            if (-not $DryRun) {
                # Create user parameters
                $userParams = @{
                    Name = "$($employee.FirstName) $($employee.LastName)"
                    GivenName = $employee.FirstName
                    Surname = $employee.LastName
                    SamAccountName = $samAccountName
                    UserPrincipalName = $upn
                    EmailAddress = $employee.Email
                    Title = $employee.Title
                    Department = $deptInfo.Name
                    EmployeeID = $employee.EmployeeID
                    Path = $NewUserOU
                    AccountPassword = Get-RandomPassword
                    Enabled = $true
                    ChangePasswordAtLogon = $true
                }
                
                # Store DepartmentID in extensionAttribute1
                $userParams['OtherAttributes'] = @{
                    extensionAttribute1 = $employee.DepartmentID
                }
                
                # Create the user
                New-ADUser @userParams -ErrorAction Stop
                Write-Log "User created successfully: $samAccountName" -Level Success
                
                # Copy group memberships from department template
                if ($deptInfo.Template) {
                    Write-Log "Copying groups from template: $($deptInfo.Template)" -Level Info
                    $groupCount = Copy-ADGroupMemberships -SourceUser $deptInfo.Template -TargetUser $samAccountName
                    Write-Log "Copied $groupCount group memberships" -Level Success
                }
                
                $createdCount++
            }
            else {
                Write-Log "[DRY RUN] Would create user: $samAccountName with template: $($deptInfo.Template)" -Level Info
            }
        }
        catch {
            Write-Log "Failed to create user $($employee.FirstName) $($employee.LastName): $_" -Level Error
            $failedCreations++
        }
    }
}

#endregion

#region Disable Separated Users

$disabledCount = 0
$failedDisables = 0
$groupBackups = @()

if ($separatedUsers.Count -gt 0) {
    Write-Log "`n========== Disabling Separated Users ==========" -Level Info
    
    foreach ($user in $separatedUsers) {
        try {
            Write-Log "Disabling user: $($user.SamAccountName) ($($user.Name)) - EmployeeID: $($user.EmployeeID)" -Level Warning
            
            if (-not $DryRun) {
                # Export current group memberships BEFORE disabling
                $groups = Get-ADUser -Identity $user.SamAccountName -Properties MemberOf | 
                    Select-Object -ExpandProperty MemberOf
                
                $groupBackups += [PSCustomObject]@{
                    SamAccountName = $user.SamAccountName
                    EmployeeID = $user.EmployeeID
                    Name = $user.Name
                    DisabledDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                    GroupCount = $groups.Count
                    Groups = ($groups -join '; ')
                }
                
                Write-Log "Exported $($groups.Count) group memberships for $($user.SamAccountName)" -Level Info
                
                # Disable account
                Disable-ADAccount -Identity $user.SamAccountName -ErrorAction Stop
                
                # Move to disabled OU
                Move-ADObject -Identity $user.DistinguishedName -TargetPath $DisabledUserOU -ErrorAction Stop
                
                # Add separation date to extensionAttribute2 for lifecycle tracking
                $separationDate = Get-Date -Format 'yyyy-MM-dd'
                Set-ADUser -Identity $user.SamAccountName `
                    -Description "Separated: $separationDate" `
                    -Replace @{extensionAttribute2 = $separationDate} `
                    -ErrorAction Stop
                
                Write-Log "User disabled and moved: $($user.SamAccountName)" -Level Success
                $disabledCount++
            }
            else {
                Write-Log "[DRY RUN] Would disable user: $($user.SamAccountName)" -Level Info
            }
        }
        catch {
            Write-Log "Failed to disable user $($user.SamAccountName): $_" -Level Error
            $failedDisables++
        }
    }
    
    # Export group memberships to CSV for Help Desk backup
    if ($groupBackups.Count -gt 0 -and -not $DryRun) {
        $backupFile = "$env:TEMP\Separated-Users-Groups-$(Get-Date -Format 'yyyyMMdd').csv"
        $groupBackups | Export-Csv -Path $backupFile -NoTypeInformation
        Write-Log "Group membership backup saved to: $backupFile" -Level Success
        
        # Optionally email to Help Desk
        if ($EmailRecipient -and $SMTPServer) {
            try {
                $emailParams = @{
                    To = $EmailRecipient
                    From = "ad-sync@$((Get-ADDomain).DNSRoot)"
                    Subject = "Separated Users - Group Membership Backup - $(Get-Date -Format 'yyyy-MM-dd')"
                    Body = "Attached are the group memberships for $($groupBackups.Count) separated user(s). Keep this for restoration if employees return from leave."
                    Attachments = $backupFile
                    SmtpServer = $SMTPServer
                }
                Send-MailMessage @emailParams
                Write-Log "Group backup emailed to Help Desk" -Level Success
            }
            catch {
                Write-Log "Failed to email group backup: $_" -Level Warning
            }
        }
    }
}

#endregion

#region Summary Report

$summary = @"

========== HRIS to AD Sync Summary ==========
Execution Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Mode: $(if ($DryRun) { 'DRY RUN' } else { 'PRODUCTION' })

HRIS Employees:        $($hrisEmployees.Count)
AD Users (Active):     $(($adUsers | Where-Object Enabled).Count)

NEW USERS:
  - Identified:        $($newUsers.Count)
  - Created:           $createdCount
  - Failed:            $failedCreations

SEPARATED USERS:
  - Identified:        $($separatedUsers.Count)
  - Disabled:          $disabledCount
  - Failed:            $failedDisables

Log File: $LogPath
============================================
"@

Write-Host $summary -ForegroundColor Cyan
Add-Content -Path $LogPath -Value $summary

#endregion

#region Email Report (Optional)

if ($EmailRecipient -and $SMTPServer -and -not $DryRun) {
    try {
        $emailParams = @{
            To = $EmailRecipient
            From = "ad-sync@$((Get-ADDomain).DNSRoot)"
            Subject = "HRIS to AD Sync Report - $(Get-Date -Format 'yyyy-MM-dd')"
            Body = $summary
            SmtpServer = $SMTPServer
        }
        
        Send-MailMessage @emailParams
        Write-Log "Email report sent to: $EmailRecipient" -Level Success
    }
    catch {
        Write-Log "Failed to send email report: $_" -Level Warning
    }
}

#endregion

Write-Log "========== HRIS to Active Directory Sync Completed ==========" -Level Success
