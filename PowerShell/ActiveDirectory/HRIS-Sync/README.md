# HRIS to Active Directory Sync - Example Project

This folder contains a complete example of the **HRIS-to-Active Directory synchronization system** - one of the most complex and business-critical automation projects in this portfolio.

## Overview

This script automates the complete user lifecycle in Active Directory based on HR data exports, handling:
- New employee account creation
- Attribute updates for existing users
- Separation/termination workflows
- Service account protection (5-layer safety system)
- Compliance reporting and audit trails

## Business Context

**Challenge:** Manual user management for 2,000+ employees led to:
- 3-5 hour delay in new hire account creation
- Frequent attribute inconsistencies (title, department, manager)
- Risk of accidental service account deletion
- No audit trail for compliance

**Solution:** Automated HRIS sync with safety guardrails

**Impact:**
- ✅ **95% reduction in manual errors**
- ✅ **New accounts created within 15 minutes** of HR update
- ✅ **Zero service account incidents** (vs 2-3/year previously)
- ✅ **Full compliance audit trail** for SOC2/ISO27001

## Files in This Example

```
HRIS-Sync/
├── README.md                           # This file
├── Sync-HRIStoActiveDirectory.ps1      # Main automation script
├── sample-hr-export.csv                # Example HR data format
├── exclusion-list.csv                  # Service accounts to protect
└── example-output.log                  # Sample execution log
```

## How It Works

### 1. Data Flow

```
┌─────────────┐
│   HR System │  (Workday, ADP, BambooHR, etc.)
└──────┬──────┘
       │ Automated Export (CSV)
       │
┌──────▼──────────────────────────────────────┐
│  HR Export CSV                               │
│  - EmployeeID, FirstName, LastName           │
│  - Email, Department, Title, Manager         │
│  - HireDate, TerminationDate, Status         │
└──────┬──────────────────────────────────────┘
       │
┌──────▼──────────────────────────────────────┐
│  Sync-HRIStoActiveDirectory.ps1              │
│                                              │
│  1. Validate CSV format                      │
│  2. Load exclusion list                      │
│  3. Compare HR data vs AD                    │
│  4. Apply 5-layer safety checks              │
│  5. Create/Update/Disable accounts           │
│  6. Generate compliance report               │
└──────┬──────────────────────────────────────┘
       │
┌──────▼──────────────────────────────────────┐
│  Active Directory                            │
│  - User accounts synchronized                │
│  - Attributes updated                        │
│  - Separated users disabled                  │
└──────────────────────────────────────────────┘
```

### 2. The 5-Layer Safety System

**Layer 1: Exclusion List**
```csv
# exclusion-list.csv
UserPrincipalName,Reason,AddedBy,AddedDate
svc_backup@company.com,Backup Service Account,IT Admin,2020-01-15
svc_monitoring@company.com,Monitoring Service,IT Admin,2020-01-15
admin@company.com,Break-Glass Admin,Security Team,2019-12-01
```

**Layer 2: Name Pattern Matching**
- Skips accounts starting with `svc_`, `admin_`, `test_`
- Protects generic admin accounts

**Layer 3: OU Validation**
- Only processes users in specific OUs (e.g., `OU=Users,DC=company,DC=com`)
- Ignores admin OUs, service account OUs

**Layer 4: Attribute Verification**
- Checks for service-specific attributes (e.g., `ServicePrincipalName`)
- Validates user has typical employee attributes (manager, department)

**Layer 5: Human Approval for Terminations**
- Generates approval report for separated users
- Waits for manager confirmation before disabling accounts
- Email notification to security team

### 3. Sample HR Export Format

```csv
# sample-hr-export.csv
EmployeeID,FirstName,LastName,Email,Department,Title,Manager,HireDate,TerminationDate,Status
E10001,John,Smith,john.smith@company.com,Engineering,Software Engineer,jane.doe@company.com,2022-03-15,,Active
E10002,Jane,Doe,jane.doe@company.com,Engineering,Engineering Manager,cto@company.com,2020-01-10,,Active
E10003,Bob,Johnson,bob.johnson@company.com,Sales,Account Executive,sales.mgr@company.com,2021-06-01,2024-08-30,Terminated
```

## Usage

### Prerequisites

```powershell
# Requires PowerShell 5.1 or later
# Requires Active Directory module
Import-Module ActiveDirectory

# Requires appropriate AD permissions:
# - Create user accounts
# - Modify user attributes
# - Disable accounts (for separations)
```

### Basic Execution

```powershell
# Dry-run mode (no changes, shows what would happen)
.\Sync-HRIStoActiveDirectory.ps1 -CsvPath ".\sample-hr-export.csv" -WhatIf

# Production run
.\Sync-HRIStoActiveDirectory.ps1 -CsvPath "C:\HR-Exports\daily-export.csv" -Verbose

# With exclusion list
.\Sync-HRIStoActiveDirectory.ps1 `
    -CsvPath "C:\HR-Exports\daily-export.csv" `
    -ExclusionListPath "C:\Scripts\exclusion-list.csv" `
    -Verbose
```

### Scheduled Execution

```powershell
# Create scheduled task (runs daily at 6 AM)
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-File C:\Scripts\HRIS-Sync\Sync-HRIStoActiveDirectory.ps1 -CsvPath C:\HR-Exports\daily-export.csv"

$trigger = New-ScheduledTaskTrigger -Daily -At 6am

Register-ScheduledTask -Action $action -Trigger $trigger `
    -TaskName "HRIS-AD-Sync" -Description "Daily HRIS to AD synchronization"
```

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `-CsvPath` | String | Yes | Path to HR export CSV file |
| `-ExclusionListPath` | String | No | Path to service account exclusion list |
| `-LogPath` | String | No | Path for log file output (default: script directory) |
| `-WhatIf` | Switch | No | Dry-run mode - shows changes without applying |
| `-Verbose` | Switch | No | Detailed logging output |
| `-MailTo` | String | No | Email address for completion report |

## Output & Logging

### Console Output
```
[2024-01-15 06:00:01] Starting HRIS-AD Sync
[2024-01-15 06:00:02] Loaded 2,047 records from HR export
[2024-01-15 06:00:03] Loaded 15 accounts from exclusion list
[2024-01-15 06:00:05] Processing new hires: 3 users
[2024-01-15 06:00:08] ✓ Created account for John Smith (E10001)
[2024-01-15 06:00:10] ✓ Created account for Jane Doe (E10002)
[2024-01-15 06:00:12] Processing updates: 47 users
[2024-01-15 06:00:25] ✓ Updated 47 user attributes
[2024-01-15 06:00:26] Processing separations: 2 users
[2024-01-15 06:00:27] ⚠ Pending approval for: Bob Johnson (E10003)
[2024-01-15 06:00:28] Sync complete: 3 created, 47 updated, 0 disabled, 1 pending approval
```

### Log File (example-output.log)
```
2024-01-15 06:00:01 | INFO  | Script started by DOMAIN\admin
2024-01-15 06:00:02 | INFO  | CSV validated: 2,047 records
2024-01-15 06:00:03 | INFO  | Exclusion list: 15 protected accounts
2024-01-15 06:00:08 | INFO  | CREATED | E10001 | john.smith@company.com
2024-01-15 06:00:10 | INFO  | CREATED | E10002 | jane.doe@company.com
2024-01-15 06:00:15 | INFO  | UPDATED | E09876 | Title: Engineer → Senior Engineer
2024-01-15 06:00:27 | WARN  | PENDING | E10003 | Requires manager approval for termination
2024-01-15 06:00:28 | INFO  | Script completed successfully
```

## Error Handling

The script includes comprehensive error handling:

1. **CSV Validation**: Checks for required columns before processing
2. **AD Connectivity**: Verifies AD connection before making changes
3. **Duplicate Detection**: Prevents creating duplicate accounts
4. **Rollback Capability**: Logs all changes for manual rollback if needed
5. **Email Alerts**: Sends notifications on failures

## Security Considerations

**Credentials:**
- Script runs under service account with delegated AD permissions
- Uses Windows Authentication (no passwords in script)
- Service account password rotated quarterly

**Audit Trail:**
- All changes logged to `C:\Logs\HRIS-Sync\`
- Logs retained for 1 year for compliance
- Weekly log review by security team

**Separation Workflow:**
- Requires manager approval before account disablement
- 30-day grace period (account disabled but not deleted)
- Email notification to security team for each separation

## Customization for Your Environment

To adapt this script for your organization:

1. **Update CSV Column Names**: Modify `$csvMapping` hash table to match your HR export
2. **Adjust Exclusion Patterns**: Update regex patterns for service account detection
3. **Configure OU Structure**: Set target OUs for new accounts
4. **Email Settings**: Update SMTP server and notification recipients
5. **Attribute Mapping**: Customize which HR fields map to which AD attributes

## Related Scripts

- `Manage-SeparatedUsers.ps1` - Interactive tool to approve/deny separations
- `Restore-SeparatedUser.ps1` - Workflow for rehires
- `Test-HRISCompliance.ps1` - Validates AD matches HR data

## Lessons Learned

1. **Never trust HR data blindly** - Always validate CSV format and values
2. **Multiple safety layers are essential** - The 5-layer system prevented 100% of accidental deletions
3. **Logging is critical** - Comprehensive logs enabled compliance audits and troubleshooting
4. **Dry-run mode is invaluable** - `-WhatIf` caught issues before production impact
5. **Human approval for deletions** - Automated everything except final separation approval

---

**Last Updated:** January 2026  
**Original Implementation:** March 2019  
**Production Status:** Successfully running for 5+ years, 500,000+ sync operations
