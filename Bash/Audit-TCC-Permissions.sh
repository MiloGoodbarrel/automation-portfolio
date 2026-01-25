#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 1-25-2026                           #
# Updated: 1-25-2026                           #
################################################
#
# NAME
#   Audit-TCC-Permissions.sh
#
# DESCRIPTION
#   Audit Transparency, Consent, and Control (TCC) permissions
#   Report apps with Full Disk Access, Screen Recording, and other sensitive permissions
#
# USAGE
#   Deploy via JAMF Pro as compliance audit
#   Run monthly to identify unauthorized privacy permissions
#
# REQUIREMENTS
#   - macOS Monterey 12.x or later
#   - Runs as root (TCC database access requires elevated privileges)
#
# NOTES
#   - Direct TCC database modification blocked in Ventura+
#   - Use JAMF Configuration Profiles to grant permissions
#   - Privacy Preferences Policy Control payload required
#   - Useful for security compliance audits
#

# Variables
LOG_FILE="/var/log/tcc-audit.log"
TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
REPORT_FILE="/var/log/tcc-audit-report.txt"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "=== TCC Permissions Audit ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_message "ERROR: This script must run as root"
    echo "ERROR: Please run as root (sudo)"
    exit 1
fi

# Check macOS version
os_version=$(sw_vers -productVersion | awk -F. '{print $1}')
os_full_version=$(sw_vers -productVersion)

log_message "macOS version: $os_full_version"

# Check if TCC database exists
if [ ! -f "$TCC_DB" ]; then
    log_message "ERROR: TCC database not found at $TCC_DB"
    exit 2
fi

# Initialize report file
cat > "$REPORT_FILE" << EOF
===============================================
TCC PERMISSIONS AUDIT REPORT
===============================================
Generated: $(date '+%Y-%m-%d %H:%M:%S')
macOS Version: $os_full_version
Hostname: $(hostname)
===============================================

EOF

log_message "Generating TCC permissions report..."

# Query Full Disk Access permissions
log_message "Auditing Full Disk Access (SystemPolicyAllFiles)..."

fda_apps=$(sqlite3 "$TCC_DB" "SELECT client, auth_value, indirect_object_identifier FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND auth_value=2;" 2>/dev/null)

if [ -n "$fda_apps" ]; then
    echo "" >> "$REPORT_FILE"
    echo "FULL DISK ACCESS (High Risk)" >> "$REPORT_FILE"
    echo "======================================" >> "$REPORT_FILE"
    echo "$fda_apps" | while IFS='|' read -r client auth indirect; do
        echo "  App: $client" >> "$REPORT_FILE"
        echo "  Status: Allowed" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
    
    fda_count=$(echo "$fda_apps" | wc -l | tr -d ' ')
    log_message "Full Disk Access granted to $fda_count app(s)"
else
    echo "No apps with Full Disk Access" >> "$REPORT_FILE"
    log_message "No apps with Full Disk Access"
fi

# Query Screen Recording permissions
log_message "Auditing Screen Recording (ScreenCapture)..."

screen_apps=$(sqlite3 "$TCC_DB" "SELECT client, auth_value FROM access WHERE service='kTCCServiceScreenCapture' AND auth_value=2;" 2>/dev/null)

if [ -n "$screen_apps" ]; then
    echo "" >> "$REPORT_FILE"
    echo "SCREEN RECORDING (Medium Risk)" >> "$REPORT_FILE"
    echo "======================================" >> "$REPORT_FILE"
    echo "$screen_apps" | while IFS='|' read -r client auth; do
        echo "  App: $client" >> "$REPORT_FILE"
        echo "  Status: Allowed" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
    
    screen_count=$(echo "$screen_apps" | wc -l | tr -d ' ')
    log_message "Screen Recording granted to $screen_count app(s)"
else
    echo "No apps with Screen Recording" >> "$REPORT_FILE"
    log_message "No apps with Screen Recording"
fi

# Query Camera permissions
log_message "Auditing Camera access..."

camera_apps=$(sqlite3 "$TCC_DB" "SELECT client, auth_value FROM access WHERE service='kTCCServiceCamera' AND auth_value=2;" 2>/dev/null)

if [ -n "$camera_apps" ]; then
    echo "" >> "$REPORT_FILE"
    echo "CAMERA ACCESS" >> "$REPORT_FILE"
    echo "======================================" >> "$REPORT_FILE"
    echo "$camera_apps" | while IFS='|' read -r client auth; do
        echo "  App: $client" >> "$REPORT_FILE"
        echo "  Status: Allowed" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
    
    camera_count=$(echo "$camera_apps" | wc -l | tr -d ' ')
    log_message "Camera access granted to $camera_count app(s)"
else
    echo "No apps with Camera access" >> "$REPORT_FILE"
    log_message "No apps with Camera access"
fi

# Query Microphone permissions
log_message "Auditing Microphone access..."

mic_apps=$(sqlite3 "$TCC_DB" "SELECT client, auth_value FROM access WHERE service='kTCCServiceMicrophone' AND auth_value=2;" 2>/dev/null)

if [ -n "$mic_apps" ]; then
    echo "" >> "$REPORT_FILE"
    echo "MICROPHONE ACCESS" >> "$REPORT_FILE"
    echo "======================================" >> "$REPORT_FILE"
    echo "$mic_apps" | while IFS='|' read -r client auth; do
        echo "  App: $client" >> "$REPORT_FILE"
        echo "  Status: Allowed" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
    
    mic_count=$(echo "$mic_apps" | wc -l | tr -d ' ')
    log_message "Microphone access granted to $mic_count app(s)"
else
    echo "No apps with Microphone access" >> "$REPORT_FILE"
    log_message "No apps with Microphone access"
fi

# Query Accessibility permissions
log_message "Auditing Accessibility access..."

accessibility_apps=$(sqlite3 "$TCC_DB" "SELECT client, auth_value FROM access WHERE service='kTCCServiceAccessibility' AND auth_value=2;" 2>/dev/null)

if [ -n "$accessibility_apps" ]; then
    echo "" >> "$REPORT_FILE"
    echo "ACCESSIBILITY ACCESS (High Risk)" >> "$REPORT_FILE"
    echo "======================================" >> "$REPORT_FILE"
    echo "$accessibility_apps" | while IFS='|' read -r client auth; do
        echo "  App: $client" >> "$REPORT_FILE"
        echo "  Status: Allowed" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    done
    
    accessibility_count=$(echo "$accessibility_apps" | wc -l | tr -d ' ')
    log_message "Accessibility access granted to $accessibility_count app(s)"
else
    echo "No apps with Accessibility access" >> "$REPORT_FILE"
    log_message "No apps with Accessibility access"
fi

# Check for privacy-related configuration profiles
log_message "Checking for privacy configuration profiles..."

privacy_profiles=$(profiles list 2>/dev/null | grep -i "privacy")

if [ -n "$privacy_profiles" ]; then
    echo "" >> "$REPORT_FILE"
    echo "PRIVACY CONFIGURATION PROFILES" >> "$REPORT_FILE"
    echo "======================================" >> "$REPORT_FILE"
    echo "$privacy_profiles" >> "$REPORT_FILE"
    log_message "Privacy profiles detected"
else
    echo "" >> "$REPORT_FILE"
    echo "No privacy configuration profiles installed" >> "$REPORT_FILE"
    log_message "No privacy configuration profiles detected"
fi

# Summary
echo "" >> "$REPORT_FILE"
echo "===============================================" >> "$REPORT_FILE"
echo "SUMMARY" >> "$REPORT_FILE"
echo "===============================================" >> "$REPORT_FILE"
echo "Full Disk Access: ${fda_count:-0} app(s)" >> "$REPORT_FILE"
echo "Screen Recording: ${screen_count:-0} app(s)" >> "$REPORT_FILE"
echo "Camera: ${camera_count:-0} app(s)" >> "$REPORT_FILE"
echo "Microphone: ${mic_count:-0} app(s)" >> "$REPORT_FILE"
echo "Accessibility: ${accessibility_count:-0} app(s)" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo "Report saved to: $REPORT_FILE" >> "$REPORT_FILE"
echo "===============================================" >> "$REPORT_FILE"

log_message "=== TCC Audit Complete ==="
log_message "Report saved to: $REPORT_FILE"

# Display report summary
cat "$REPORT_FILE"

# For JAMF Extension Attribute reporting
echo "<result>FDA:${fda_count:-0}|Screen:${screen_count:-0}|Camera:${camera_count:-0}|Mic:${mic_count:-0}</result>"

exit 0
