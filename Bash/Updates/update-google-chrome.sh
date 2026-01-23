#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 3-15-2019                           #
# Updated: 1-23-2026                           #
################################################
#
# NAME
#   update-google-chrome.sh
#
# DESCRIPTION
#   Automatically downloads and installs the latest Google Chrome.
#   Handles DMG mounting, installation, and cleanup.
#
# USAGE
#   Deploy via JAMF policy for automatic updates
#
# NOTES
#   - Quits Chrome if running
#   - Downloads from Google's stable channel
#   - Preserves user profiles and extensions
#   - Logs all actions
#

# Logging
LOGFILE="/var/log/chrome-update.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

log_message "Starting Google Chrome update process"

# Vendor supplied DMG file
VendorDMG="googlechrome.dmg"
TempPath="/tmp/$VendorDMG"

# Get current user
currentUser=$(stat -f%Su /dev/console)
log_message "Current user: $currentUser"

# Quit Chrome if running
if pgrep -x "Google Chrome" > /dev/null; then
    log_message "Chrome is running - quitting application"
    osascript -e 'quit app "Google Chrome"' 2>/dev/null
    sleep 3
fi

# Get installed version if exists
if [ -d "/Applications/Google Chrome.app" ]; then
    installedVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "/Applications/Google Chrome.app/Contents/Info.plist" 2>/dev/null)
    log_message "Installed version: $installedVersion"
else
    installedVersion="Not installed"
    log_message "Chrome not currently installed"
fi

# Download latest Chrome DMG
log_message "Downloading latest Google Chrome"
curl -L "https://dl.google.com/chrome/mac/stable/GGRO/$VendorDMG" -o "$TempPath"

if [ ! -f "$TempPath" ]; then
    log_message "ERROR: Failed to download Chrome installer"
    exit 1
fi

# Mount the DMG
log_message "Mounting Chrome DMG"
hdiutil attach "$TempPath" -nobrowse -quiet

if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to mount DMG"
    rm -f "$TempPath"
    exit 1
fi

# Copy Chrome to Applications (preserves attributes and ACLs)
log_message "Installing Google Chrome"
cp -pPR "/Volumes/Google Chrome/Google Chrome.app" /Applications/

if [ $? -eq 0 ]; then
    log_message "Chrome successfully copied to /Applications"
else
    log_message "ERROR: Failed to copy Chrome to Applications"
fi

# Identify the correct mount point for the DMG
ChromeDMG=$(hdiutil info | grep "/Volumes/Google Chrome" | awk '{ print $1 }')

# Unmount the DMG
log_message "Unmounting DMG"
hdiutil detach "$ChromeDMG" -quiet

# Remove the downloaded DMG file
rm -f "$TempPath"
log_message "Cleaned up temporary files"

# Verify installation
if [ -d "/Applications/Google Chrome.app" ]; then
    newVersion=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
        "/Applications/Google Chrome.app/Contents/Info.plist" 2>/dev/null)
    log_message "Verified installation: Chrome version $newVersion"
    exit 0
else
    log_message "ERROR: Chrome installation verification failed"
    exit 1
fi
