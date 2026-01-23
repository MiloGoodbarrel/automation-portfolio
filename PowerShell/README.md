# PowerShell Automation Scripts

Enterprise-ready PowerShell scripts for Windows system administration, security, and automation tasks. These scripts follow modern PowerShell best practices and are designed to be reusable across different environments.

## 📁 Repository Structure

```
powershell-automation/
├── ComputerManagement/    # Computer naming, admin group management
├── Security/              # Access control, verification systems
├── ActiveDirectory/       # AD queries and user management
├── Registry/              # Registry-based configurations
└── Examples/              # Sample configuration files
```

## 🚀 Featured Scripts

### Computer Management

#### Rename-ComputerByLocation.ps1
Flexible computer renaming based on customizable conventions. Supports subnet-based location detection, hardware type identification, and serial number integration.

**Features:**
- Works for organizations of any size (single office to global enterprise)
- CSV-based subnet-to-location mapping
- Customizable naming templates
- Dry-run mode for testing
- Smart hardware detection (laptop vs desktop vs VM)

**Example:**
```powershell
# Test mode
.\Rename-ComputerByLocation.ps1 -ConfigFile "subnets.csv" -DryRun

# Apply custom naming pattern
.\Rename-ComputerByLocation.ps1 -NamingTemplate "{Location}-{HW}-{Serial5}"
```

#### Add-DomainGroupsToLocalAdmin.ps1
Adds specified domain groups to the local Administrators group with error handling and duplicate prevention.

#### Ensure-RequiredLocalAdmins.ps1
Ensures specific domain groups remain in local Administrators, adding missing members automatically.

### Security & Access Control

#### Request-AdminAccessVerification.ps1
Two-factor verification system for temporary admin access. Generates verification codes that must be validated through service desk.

#### Grant-AdminAccessCode.ps1
Service desk companion script that generates matching access codes for verification.

#### Disable-IPv6OnAdapter.ps1
Safely disables IPv6 on specified network adapters with validation and rollback support.

### Active Directory

#### 🌟 HRIS-to-AD Synchronization System (Enterprise Automation)
**The crown jewel of this repository** - a complete enterprise user lifecycle management system for organizations of any size.

**Sync-HRIStoActiveDirectory.ps1**
Automates the complete employee lifecycle from hire to separation, with enterprise-grade safety controls.

**Features:**
- ✅ **Automated Provisioning:** Creates accounts for new hires using template-based group assignment
- ✅ **Automated Deprovisioning:** Disables separated employees within 24 hours
- ✅ **Multi-Layer Safety:** Prevents accidental modification of service/admin/template accounts
- ✅ **Compliance Ready:** Full audit logging, EmployeeID tracking, retention policies
- ✅ **Email Reporting:** Automated notifications to IT/HR/Help Desk
- ✅ **Template-Based:** Consistent access provisioning based on department

**Manage-SeparatedUserLifecycle.ps1**
180-day retention policy enforcement with three-stage lifecycle management.

**Features:**
- Days 0-60: Account disabled, data accessible for Help Desk
- Days 61-120: Moved to "TO DELETE" OU
- Days 121+: Account and data permanently deleted
- Elevated account detection (SA*, DA*, GA*)
- Group membership backup before deletion
- JSON export of all user data for compliance

**Restore-SeparatedUser.ps1**
Handles users returning from leave (maternity, medical, etc.).

**Features:**
- Re-enables disabled accounts
- Restores group memberships from backup
- Re-enables associated elevated accounts
- Clears separation flags

**⚠️ Critical Prerequisite:** These scripts require strict AD naming conventions. See [AD-Naming-Standards.md](ActiveDirectory/AD-Naming-Standards.md) for complete requirements.

**Business Value:**
- Saves 15-30 minutes per new hire (manual provisioning eliminated)
- Ensures separated employees lose access within 24 hours (compliance)
- Prevents accidental deletion of returning employees (maternity/medical leave)
- Complete audit trail for compliance officers

---

#### Get-ADUsersByLocation.ps1
Queries AD users by geographic location/OU and exports detailed reports.

**Features:**
- Supports multiple locations in one run
- Customizable properties export
- Progress tracking and error handling

#### Compare-JDEUsersWithAD.ps1
Cross-references external user databases (e.g., JD Edwards) with Active Directory for compliance auditing.

### Registry Configuration

#### Disable_iPv6.ps1
Registry-based IPv6 disabling with modern error handling.

#### Disable OS Upgrade.ps1
Prevents automatic Windows OS upgrades via registry settings.

#### Screen Lockout - Wn10 Above.ps1
Configures automatic screen lock timeout for security compliance.

## 📋 Requirements

- **PowerShell:** 5.1 or higher (PowerShell 7+ recommended)
- **Modules:** ActiveDirectory (for AD scripts)
- **Permissions:** Administrator rights (for most scripts)
- **OS:** Windows 10/11, Windows Server 2016+

## 🔧 Installation

1. Clone this repository:
```powershell
git clone https://github.com/yourusername/powershell-automation.git
cd powershell-automation
```

2. Review script headers for specific requirements

3. Test scripts with `-DryRun` or `-WhatIf` parameters where available

## 💡 Usage Tips

### Always Test First
```powershell
# Most scripts support dry-run mode
.\SomeScript.ps1 -DryRun

# Or use WhatIf for cmdlets that support it
.\SomeScript.ps1 -WhatIf
```

### Check Script Help
```powershell
Get-Help .\ScriptName.ps1 -Full
```

### Run with Appropriate Permissions
```powershell
# Run PowerShell as Administrator
Start-Process powershell -Verb RunAs
```

## 📝 Script Standards

All scripts in this repository follow these standards:

- ✅ Proper comment-based help
- ✅ Parameter validation
- ✅ Error handling with try/catch
- ✅ Modern cmdlet usage (Get-CimInstance vs Get-WmiObject)
- ✅ Full parameter names (not aliases)
- ✅ Color-coded console output
- ✅ Support for -Verbose and -WhatIf where applicable

## 🤝 Contributing

These scripts are maintained as part of a professional portfolio. Suggestions and improvements are welcome via issues.

## 📄 License

MIT License - Feel free to use and modify for your own purposes.

## 👤 Author

**Luis Ramirez**
- Scripts created during enterprise system administration roles
- Updated and modernized for PowerShell 5.1+ / 7+ compatibility

## 📚 Additional Resources

- [PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [PowerShell Gallery](https://www.powershellgallery.com/)
- [PowerShell Best Practices](https://docs.microsoft.com/powershell/scripting/developer/cmdlet/strongly-encouraged-development-guidelines)

---

⭐ If you find these scripts useful, please star the repository!
