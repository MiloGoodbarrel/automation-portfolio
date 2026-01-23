# macOS Automation Scripts

Enterprise macOS management scripts for JAMF Pro deployment.

## Author
Luis Ramirez

## Overview
Collection of Bash scripts for macOS device management, primarily deployed via JAMF Pro policies. Scripts cover security hardening, system configuration, software updates, and user experience automation.

## Directory Structure

### JAMF-Policies/
JAMF Pro policy scripts for deployment automation
- `prepare-jamf-policy.sh` - Policy preparation and validation

### Security/
Security and access control scripts
- `grant-admin-access.sh` - IT-assisted admin access grants
- `request-temp-admin-access.sh` - User self-service temporary admin access (3-minute expiration)
- `check-filevault-status.sh` - FileVault 2 encryption status validation
- `remove-temp-admin.sh` - Revoke temporary administrator rights

### System-Configuration/
System setup and configuration automation
- `configure-ntp-timezone.sh` - NTP and timezone configuration with geolocation
- `set-default-homepage.sh` - Browser homepage standardization
- `cleanup-wifi-networks.sh` - Remove saved WiFi networks

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
- macOS 10.13+
- JAMF Pro 10.x+
- Bash 3.2+ (default macOS shell)

### Optional Dependencies
- `jq` for JSON parsing (geolocation scripts)
- `/usr/bin/curl` for API calls
- `osascript` for user dialogs (built-in)

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

### Configure NTP/Timezone
```bash
sudo bash configure-ntp-timezone.sh
# Auto-detects timezone from IP
# Configures NTP servers
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
