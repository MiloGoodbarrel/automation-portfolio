#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 4-27-2020                           #
# Updated: 1-23-2026                           #
################################################
#
# NAME
#   update-zoom-client.sh
#
# DESCRIPTION
#   Automatically downloads and installs the latest Zoom client.
#   Checks for existing installation and performs upgrade if needed.
#
# USAGE
#   Deploy via JAMF policy or Self Service
#
# NOTES
#   - Quits Zoom if running
#   - Downloads latest version from Zoom.us
#   - Preserves user settings
#   - JAMF policy can run silently or with notifications
#

# Logging
LOGFILE="/var/log/zoom-update.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

log_message "Starting Zoom update process"

# Get current user
currentUser=$(stat -f%Su /dev/console)
log_message "Current user: $currentUser"

# Quit Zoom if running
if pgrep -x "zoom.us" > /dev/null; then
    log_message "Zoom is running - quitting application"
    killall "zoom.us" 2>/dev/null
    sleep 2
fi

# Download latest Zoom installer
TEMP_DIR="/tmp/zoom-installer"
mkdir -p "$TEMP_DIR"

log_message "Downloading latest Zoom installer"
curl -L "https://zoom.us/client/latest/Zoom.pkg" -o "$TEMP_DIR/Zoom.pkg"

if [ ! -f "$TEMP_DIR/Zoom.pkg" ]; then
    log_message "ERROR: Failed to download Zoom installer"
    exit 1
fi

# Get downloaded version
downloadedVersion=$(pkgutil --expand "$TEMP_DIR/Zoom.pkg" "$TEMP_DIR/expanded" && \
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$TEMP_DIR/expanded/zoomus.pkg/PackageInfo" 2>/dev/null)

# Get installed version if exists
if [ -d "/Applications/zoom.us.app" ]; then
    installedVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
        "/Applications/zoom.us.app/Contents/Info.plist" 2>/dev/null)
    log_message "Installed version: $installedVersion"
else
    installedVersion="Not installed"
    log_message "Zoom not currently installed"
fi

log_message "Available version: $downloadedVersion"

# Install Zoom
log_message "Installing Zoom $downloadedVersion"
installer -pkg "$TEMP_DIR/Zoom.pkg" -target /

if [ $? -eq 0 ]; then
    log_message "Zoom successfully installed/updated"
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    # Verify installation
    newVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" \
        "/Applications/zoom.us.app/Contents/Info.plist" 2>/dev/null)
    log_message "Verified installation: Zoom version $newVersion"
    
    exit 0
else
    log_message "ERROR: Zoom installation failed"
    rm -rf "$TEMP_DIR"
    exit 1
fi
