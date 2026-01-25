#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 1-25-2026                           #
# Updated: 1-25-2026                           #
################################################
#
# NAME
#   Check-Rapid-Security-Response.sh
#
# DESCRIPTION
#   Monitor and report Rapid Security Response (RSR) installation status
#   RSR provides critical security patches between major macOS updates
#
# USAGE
#   Deploy via JAMF Pro as recurring check-in policy
#   Ensures automatic security updates are enabled
#
# REQUIREMENTS
#   - macOS Ventura 13.x or later (RSR introduced in Ventura)
#
# NOTES
#   - Rapid Security Response = Quick security fixes without full OS update
#   - Automatically installed if enabled in Software Update preferences
#   - Critical for maintaining security posture between major updates
#

# Variables
LOG_FILE="/var/log/rapid-security-response.log"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "=== Rapid Security Response Check ==="

# Check macOS version (RSR requires Ventura 13.x+)
os_version=$(sw_vers -productVersion | awk -F. '{print $1}')
os_full_version=$(sw_vers -productVersion)

log_message "macOS version: $os_full_version"

if [ "$os_version" -lt 13 ]; then
    log_message "Rapid Security Response not available on macOS $os_full_version"
    log_message "Requires: macOS Ventura 13.0 or later"
    exit 0
fi

# Check for installed Rapid Security Responses
log_message "Checking for installed Rapid Security Responses..."

rsr_installed=$(system_profiler SPInstallHistoryDataType 2>/dev/null | grep -A 5 "Rapid Security Response")

if [ -n "$rsr_installed" ]; then
    log_message "Rapid Security Responses installed:"
    log_message "$rsr_installed"
    
    # Count how many RSRs are installed
    rsr_count=$(echo "$rsr_installed" | grep -c "Rapid Security Response")
    log_message "Total RSRs installed: $rsr_count"
else
    log_message "No Rapid Security Responses installed yet"
    log_message "This is normal if macOS is recently installed or fully up-to-date"
fi

# Check for pending Rapid Security Response updates
log_message "Checking for pending RSR updates..."

pending_updates=$(softwareupdate --list 2>&1 | grep -i "rapid security")

if [ -n "$pending_updates" ]; then
    log_message "PENDING Rapid Security Response updates found:"
    log_message "$pending_updates"
    
    # Show notification to user
    osascript -e 'display notification "Rapid Security Response updates are available. These critical security patches will be installed automatically." with title "Security Updates Available"'
    
    # Optionally install immediately (remove comment to enable)
    # log_message "Installing pending RSR updates..."
    # softwareupdate --install --all --verbose 2>&1 | tee -a "$LOG_FILE"
    
else
    log_message "No pending Rapid Security Response updates"
fi

# Check if automatic RSR installation is enabled
log_message "Checking automatic RSR installation settings..."

auto_security_updates=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticallyInstallSecurityUpdates 2>/dev/null)
config_data_install=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist ConfigDataInstall 2>/dev/null)

if [ "$auto_security_updates" = "1" ]; then
    log_message "Automatic security updates: ENABLED ✓"
else
    log_message "WARNING: Automatic security updates: DISABLED"
    log_message "Recommendation: Enable automatic security updates"
    
    # Enable automatic security updates
    log_message "Enabling automatic security updates..."
    defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist AutomaticallyInstallSecurityUpdates -bool true
    log_message "Automatic security updates now ENABLED"
fi

if [ "$config_data_install" = "1" ]; then
    log_message "Automatic config data install: ENABLED ✓"
else
    log_message "WARNING: Automatic config data install: DISABLED"
    log_message "Enabling automatic config data install for RSR..."
    defaults write /Library/Preferences/com.apple.SoftwareUpdate.plist ConfigDataInstall -bool true
    log_message "Config data install now ENABLED"
fi

# Check last successful update check
last_check=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist LastSuccessfulDate 2>/dev/null)

if [ -n "$last_check" ]; then
    log_message "Last successful update check: $last_check"
else
    log_message "WARNING: Cannot determine last update check date"
fi

# Generate summary report
log_message "=== RSR Check Summary ==="
log_message "macOS Version: $os_full_version"
log_message "RSRs Installed: ${rsr_count:-0}"
log_message "Automatic Security Updates: $([ "$auto_security_updates" = "1" ] && echo "Enabled" || echo "Disabled")"
log_message "Config Data Install: $([ "$config_data_install" = "1" ] && echo "Enabled" || echo "Disabled")"
log_message "Pending Updates: $([ -n "$pending_updates" ] && echo "Yes" || echo "None")"

# Report to JAMF via Extension Attribute (optional)
# echo "<result>RSRs Installed: ${rsr_count:-0}</result>"

log_message "=== Rapid Security Response Check Complete ==="

exit 0
