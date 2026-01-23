# Python Cross-Platform System Management Tools

Enterprise-grade Python automation tools for cross-platform IT operations. Works on Windows, macOS, and Linux systems.

## Author
**Luis Ramirez**  
Systems Administrator / Infrastructure Engineer

## Overview

This collection demonstrates Python's power for building cross-platform enterprise tools that work identically on Windows and macOS environments. Perfect for heterogeneous enterprise infrastructures.

## Tools

### Management/
- **inventory_collector.py** - System inventory collection for asset management
  - Gathers hardware, OS, and software information
  - Supports JSON/CSV export and API upload to CMDB
  - Platform-agnostic design (Windows WMI + macOS system_profiler)

### Security/
- **user_account_auditor.py** - User account compliance auditing
  - Identifies inactive, disabled, and admin accounts
  - Works with Windows local/AD and macOS local accounts
  - Generates HTML compliance reports with remediation

- **security_baseline_checker.py** - Security configuration validation
  - Validates firewall, encryption, updates, password policy
  - Based on CIS benchmarks and industry standards
  - Color-coded results with remediation guidance

### Reporting/
*(Placeholder for future reporting tools)*

## Requirements

### Core (All Tools)
```bash
Python 3.7+
```

### Optional (Specific Features)
```bash
pip install requests     # For API upload in inventory_collector
pip install ldap3        # For Active Directory queries
```

## Usage Examples

### Inventory Collection
```bash
# Collect and display system inventory
python inventory_collector.py

# Export to CSV
python inventory_collector.py --output csv --file inventory.csv

# Upload to CMDB
python inventory_collector.py --upload https://cmdb.company.com/api --api-key YOUR_KEY

# Quick check without apps (faster)
python inventory_collector.py --no-apps
```

### User Account Auditing
```bash
# Auto-detect platform and audit local accounts
python user_account_auditor.py

# Audit Windows Active Directory (requires ldap3)
python user_account_auditor.py --platform windows --domain CONTOSO

# Export HTML compliance report
python user_account_auditor.py --export audit_report.html

# Find accounts inactive for 120+ days
python user_account_auditor.py --inactive-days 120
```

### Security Baseline Checking
```bash
# Run all security checks
python security_baseline_checker.py

# Verbose mode with remediation steps
python security_baseline_checker.py --verbose

# Export HTML report
python security_baseline_checker.py --export security_report.html
```

## Cross-Platform Design

All tools use platform detection and conditional logic:

```python
import platform

if platform.system() == 'Darwin':    # macOS
    # Use system_profiler, dscl, defaults
elif platform.system() == 'Windows':  # Windows
    # Use wmic, net user, PowerShell
```

### Platform-Specific Commands

| Task | Windows | macOS |
|------|---------|-------|
| Serial Number | `wmic bios get serialnumber` | `system_profiler SPHardwareDataType` |
| User List | `net user` | `dscl . list /Users` |
| Firewall Status | `netsh advfirewall show` | `defaults read /Library/Preferences/com.apple.alf` |
| Disk Encryption | `manage-bde -status` | `fdesetup status` |

## Enterprise Use Cases

1. **Asset Management**: Automated inventory collection from 1,000+ endpoints
2. **Compliance Auditing**: Identify security gaps across mixed Windows/Mac environment
3. **Help Desk Tools**: Quick system information gathering for support tickets
4. **Security Operations**: Baseline validation for SOC2/ISO27001 audits

## Features

✅ **Cross-Platform**: Single codebase for Windows, macOS, Linux  
✅ **Enterprise-Ready**: JSON/CSV/HTML output, API integration  
✅ **Compliance-Focused**: CIS benchmarks, security best practices  
✅ **Modular Design**: Import and reuse components  
✅ **Error Handling**: Graceful failures with meaningful messages  

## Best Practices Demonstrated

- Platform detection with `platform` module
- Subprocess error handling and timeouts
- Multiple output formats (JSON, CSV, HTML)
- API integration with authentication
- Command-line argument parsing
- Comprehensive documentation strings
- Security-conscious (password handling, sudo awareness)

## Contributing

These tools are part of my professional portfolio. For production use in your environment, consider:

1. **Authentication**: Add proper AD credentials or API key management
2. **Logging**: Implement structured logging to syslog/Event Log
3. **Scheduling**: Deploy via cron (macOS) or Task Scheduler (Windows)
4. **Error Handling**: Add retry logic and alerting for failures

## License

Professional work samples for portfolio demonstration.

## Contact

**Luis Ramirez**  
*Systems Administrator / Infrastructure Engineer*  
10+ years experience in enterprise IT automation

---

*Last Updated: January 2026*
