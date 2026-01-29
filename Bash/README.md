# macOS Automation Scripts

Enterprise macOS management scripts for JAMF Pro deployment.

**Last Updated:** January 25, 2026  
**Compatibility:** macOS Ventura (13.x) - Sequoia (15.x)  
**Legacy Support:** Monterey (12.x) and earlier

## Author
Luis Ramirez

## Overview
Collection of Bash scripts for macOS device management, primarily deployed via JAMF Pro policies. Scripts cover security hardening, system configuration, software updates, and user experience automation.

**Recent Updates (2026-01-25):** Modernized for Ventura-Sequoia compatibility with new scripts for Platform SSO, 802.1X WiFi, SMB/DFS integration, and enhanced security auditing.

## Directory Structure

### Security/
Security and access control scripts
- `grant-admin-access.sh` - IT-assisted admin access grants
- `request-temp-admin-access.sh` - User self-service temporary admin access (3-minute expiration)
- `check-filevault-status.sh` - FileVault 2 encryption status validation *(Updated 2026-01-25)*
- `remove-temp-admin.sh` - Revoke temporary administrator rights
- **NEW** `Audit-TCC-Permissions.sh` - Privacy permission compliance auditing (Full Disk Access, Screen Recording, etc.)
- **NEW** `Verify-FileVault-Escrow.sh` - Verifies FileVault is enabled and PRK exists (escrow validated in MDM)

### System-Configuration/
System setup and configuration automation
- `configure-ntp-timezone.sh` - NTP and timezone configuration with geolocation *(Updated 2026-01-25)*
- `set-default-homepage.sh` - Browser homepage standardization
- `cleanup-wifi-networks.sh` - Remove saved WiFi networks *(Updated 2026-01-25)*
- **NEW** `Configure-802.1X-WiFi.sh` - Enterprise WiFi troubleshooting and remediation
- **NEW** `Check-Platform-SSO.sh` - Azure AD/Entra ID Platform SSO health check
- **NEW** `Check-Rapid-Security-Response.sh` - Monitor automatic security patch installation

### Windows-Integration/
NEW - macOS integration with Windows enterprise environments
- **NEW** `Mount-SMB-DFS-Share.sh` - Auto-mount Windows DFS shares with Kerberos/SSO support

### Updates/
Software update automation
- `google-chrome-updater.sh` - Automated Chrome updates
- `zoom-updater.sh` - Automated Zoom updates
- `universal-updater.sh` - Generic application update framework
- `macos-upgrade.sh` - macOS major version upgrades
- `macos-upgrade-catalina.sh` - Catalina-specific upgrade workflow

### Utilities/
General purpose utilities
- `install-homebrew.sh` - Homebrew package manager installation
- `sys-info.sh` - System information gathering
- `diagnostic.sh` - System diagnostics and troubleshooting
- `checksum-verification.sh` - File integrity verification
- `image-conversion.sh` - Batch image format conversion
- `create-bootable-media.sh` - macOS bootable USB creation

### JAMF-Policies/
JAMF Pro policy scripts for deployment automation
- `prepare-jamf-policy.sh` - Policy preparation and validation

## What's New (2026-01-25)

### Updated Scripts
1. **SetNTP.sh (configure-ntp-timezone.sh)**
   - Fixed undefined TimeServer variable
   - Added macOS version detection for Ventura+ compatibility
   - Enhanced error handling and fallback timezone support
   - Improved jq dependency validation

2. **FV Status.sh (check-filevault-status.sh)**
   - Complete rewrite for modern macOS
   - Removed deprecated HFS+/Core Storage checks (APFS-only)
   - Fixed multiple syntax errors and logic bugs
   - Modernized user dialogs for System Settings (not System Preferences)
   - Proper exit codes for automation workflows

3. **Wi-Fi Cleanup.sh**
   - Added dynamic WiFi interface detection for Apple Silicon Macs
   - M-series Macs may use en1 instead of en0 - now auto-detected
   - Enhanced error handling for interface detection failures

### New Scripts

4. **Configure-802.1X-WiFi.sh**
   - Troubleshoot enterprise WiFi (EAP-TLS/PEAP) connectivity
   - Validate 802.1X configuration profiles from JAMF
   - Check certificate installation for Windows RADIUS servers
   - Auto-remediate connection failures

5. **Check-Platform-SSO.sh**
   - Monitor Azure AD/Entra ID Platform SSO integration health
   - Verify user sign-in status and token validity
   - Check Microsoft Company Portal SSO extension
   - Report seamless authentication status for M365, SharePoint, OneDrive

6. **Mount-SMB-DFS-Share.sh**
   - Auto-mount Windows DFS shares at login
   - Supports both AD-bound Macs (Kerberos) and Platform SSO (OAuth)
   - SMB3-only enforcement for security compliance
   - Creates Desktop shortcuts for easy user access
   - Handles credential fallback for unbound Macs

7. **Check-Rapid-Security-Response.sh**
   - Monitor Rapid Security Response (RSR) installation
   - Report pending critical security patches
   - Ensure automatic security updates enabled
   - Compliance reporting for security between major OS updates

8. **Audit-TCC-Permissions.sh**
   - Privacy permission compliance auditing
   - Report apps with Full Disk Access, Screen Recording, Accessibility
   - Export detailed audit logs for security review
   - Identify unauthorized privacy permission grants

## Key Features

### Zero-Trust Admin Access
Two-factor admin access scripts prevent permanent local admin accounts:
- User requests access via Self Service
- System generates random verification code
- User calls help desk with code
- Help desk provides algorithmic password
- Access automatically revokes after 3 minutes
- All activity logged for audit compliance

### Automated Geolocation Configuration
Scripts use geolocation APIs to automatically configure:
- Timezone based on IP location
- NTP servers with regional optimization
- Location Services enablement

### Pre-Flight Checks
Upgrade scripts validate system state before proceeding:
- FileVault encryption completion
- Available disk space
- Compatibility verification
- Active user sessions

### Self-Healing
Scripts include error handling and recovery:
- Network service delays (20-second pause)
- Multiple fallback servers (NTP, update mirrors)
- Graceful degradation
- Detailed logging

## Deployment via JAMF

### Self Service Scripts
Deploy via JAMF Self Service for user-initiated actions:
- Temporary admin access requests
- macOS upgrades
- Software updates

### Policy Scripts
Deploy via JAMF policies for automatic execution:
- Initial device setup (NTP, timezone)
- Security configuration (FileVault validation)
- Software updates (Chrome, Zoom)

### Scope Recommendations
- **Admin Access**: Scope to all users
- **Configuration**: Scope to new enrollments
- **Updates**: Scope to specific departments/testing groups first

## Prerequisites

### System Requirements
- **Modern macOS:** Ventura 13.x - Sequoia 15.x (recommended)
- **Legacy support:** Monterey 12.x and earlier
- **MDM:** JAMF Pro 10.x+ or compatible MDM
- **Shell:** Bash 3.2+ (default macOS shell)

### Optional Dependencies
- `jq` for JSON parsing (geolocation scripts) - Install via Homebrew
- `/usr/bin/curl` for API calls (built-in)
- `osascript` for user dialogs (built-in)
- **Platform SSO:** Microsoft Company Portal (for Azure AD integration)
- **802.1X:** Enterprise WiFi certificates deployed via JAMF

### Windows Integration Requirements
- Active Directory domain (for Kerberos) OR Platform SSO (Azure AD)
- Windows Server 2016+ with DFS namespace
- SMB3-compatible file servers
- Enterprise WiFi with RADIUS server (optional)

## Usage Examples

### Grant Admin Access (Help Desk)
```bash
sudo bash grant-admin-access.sh
# Prompts for username and passcode
# Generates algorithmic password
# Logs transaction
```

### Request Temp Admin (User Self-Service)
```bash
sudo bash request-temp-admin-access.sh
# Shows verification code
# User calls help desk
# Enters password
# Access expires after 3 minutes
```

### Configure NTP/Timezone (Updated for Ventura+)
```bash
sudo bash SetNTP.sh
# Auto-detects timezone from IP geolocation
# Configures NTP servers with fallback options
# Enables Location Services for automatic timezone
# macOS version-aware (Ventura+ compatible)
```

### Check FileVault Status (Modernized)
```bash
bash "FV Status.sh"
# Returns 0 if encryption complete
# Returns 1 if in progress
# Returns 2 if disabled
# Shows user-friendly progress dialogs
```

### NEW - Configure 802.1X WiFi
```bash
sudo bash Configure-802.1X-WiFi.sh "Corp-WiFi" "radius.company.com"
# Validates 802.1X configuration profile
# Checks enterprise certificate installation
# Tests RADIUS server connectivity
# Auto-remediates connection failures
```

### NEW - Check Platform SSO
```bash
sudo bash Check-Platform-SSO.sh
# Verifies Azure AD/Entra ID integration
# Reports user sign-in status
# Checks Microsoft Company Portal SSO extension
# Validates seamless authentication to M365
```

### NEW - Mount Windows DFS Share
```bash
sudo bash Mount-SMB-DFS-Share.sh "//domain.local/dfs/shares" "CompanyShares" "CORP"
# Auto-mounts at user login
# Prefers Kerberos (AD-bound) or Platform SSO authentication
# Falls back to manual credentials if needed
# Creates Desktop shortcut
# SMB3-only for security
```

### NEW - Check Rapid Security Responses
```bash
sudo bash Check-Rapid-Security-Response.sh
# Reports installed RSR patches
# Checks for pending security updates
# Ensures automatic installation enabled
# Generates compliance report
```

### NEW - Audit TCC Permissions
```bash
sudo bash Audit-TCC-Permissions.sh
# Reports Full Disk Access grants
# Lists Screen Recording permissions
# Audits Camera/Microphone access
# Exports detailed compliance report to /var/log/
```
# Enables automatic timezone updates
```

### Check FileVault Status
```bash
bash check-filevault-status.sh
# Returns 0 if encryption complete
# Returns 1 if in progress or disabled
# Shows progress percentage
```

## Logging

### Log Locations
- Admin access: `/var/log/tempAdmin/`
- Update scripts: `/private/var/log/`
- JAMF policies: JAMF Pro console

### Log Format
```
Date:MM-DD-YYYY Time:HH:MM:SS: Event description
```

## Security Considerations

1. **Admin Access Logging**: All admin grants logged with timestamp, user, and approver
2. **Time-Limited Access**: Automatic revocation prevents privilege creep
3. **Audit Trail**: Complete transaction history for compliance
4. **FileVault Validation**: Prevents upgrades on unencrypted systems
5. **Geolocation Privacy**: Uses IP-based lookup (no GPS tracking)

## Best Practices

1. **Test in Development**: Always test policies in dev environment first
2. **Scope Gradually**: Start with pilot group, expand after validation
3. **Monitor Logs**: Regular review of admin access logs
4. **Update Regularly**: Keep scripts current with macOS releases
5. **Document Changes**: Update script headers with modification dates

## Troubleshooting

### Admin Access Not Working
- Check `/var/log/tempAdmin/tempAdmin.log` for errors
- Verify user called help desk with correct verification code
- Ensure 3-minute window hasn't expired

### Timezone Not Setting
- Verify network connectivity (script pauses 20 seconds)
- Check `jq` installation for geolocation parsing
- Manually verify timezone: `systemsetup -gettimezone`

### FileVault Check Failing
- Run `fdesetup status` manually
- For APFS: `diskutil apfs list | grep "Encryption Progress"`
- For HFS+: `diskutil cs list | grep "Conversion Progress"`

## Version History

See individual script headers for creation and update dates. Scripts developed between 2019-2026 for enterprise macOS management.

## Contributing

For internal use. Contact IT Operations for script modification requests.

## License

Proprietary - Internal Use Only
