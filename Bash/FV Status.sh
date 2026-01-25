#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: Unknown (pre-2019)                  #
# Updated: 1-25-2026                           #
################################################
#
# NAME
#   FV Status.sh (FileVault Status Checker)
#
# DESCRIPTION
#   Verify FileVault 2 encryption status and progress
#   Updated for macOS Ventura (13.x) - Sequoia (15.x) compatibility
#
# UPDATES (2026-01-25)
#   - Complete rewrite for modern macOS compatibility
#   - Removed deprecated HFS+/Core Storage checks (APFS universal since High Sierra)
#   - Fixed multiple syntax errors and logic issues
#   - Improved error handling and user messaging
#   - Added proper exit codes for automation workflows
#   - Updated dialog boxes for modern macOS UI
#
# USAGE
#   Deploy via JAMF Pro as pre-flight check before OS upgrades
#   Can be scoped to run at device check-in
#
# EXIT CODES
#   0: FileVault enabled and fully encrypted
#   1: FileVault enabled but encryption in progress
#   2: FileVault disabled
#   3: Unable to determine FileVault status
#

# Get FileVault status
fv_status=$(/usr/bin/fdesetup status 2>/dev/null)

# Log status
echo "=== FileVault Status Check ==="
echo "Raw status: $fv_status"

# Check if FileVault is enabled
if echo "$fv_status" | grep -q "FileVault is On"; then
    echo "FileVault is enabled"
    
    # Check encryption progress (all modern Macs use APFS)
    encryption_progress=$(diskutil apfs list 2>/dev/null | grep "Encryption Progress" | awk '{print $3}')
    
    if [ -n "$encryption_progress" ]; then
        echo "Encryption in progress: $encryption_progress"
        
        # Show user dialog with progress
        /usr/bin/osascript -e "display dialog \"FileVault encryption in progress: $encryption_progress\n\nPlease wait for encryption to complete before upgrading macOS.\n\nYou can continue using your Mac while encryption runs in the background.\" buttons {\"OK\"} default button 1 with icon caution with title \"FileVault Encryption in Progress\"" 2>/dev/null
        
        exit 1
    else
        echo "FileVault fully encrypted - ready for macOS upgrade"
        exit 0
    fi
    
elif echo "$fv_status" | grep -q "FileVault is Off"; then
    echo "FileVault is NOT enabled"
    
    # Show user dialog prompting to enable FileVault
    /usr/bin/osascript -e 'display dialog "FileVault is not enabled.\n\nFor security compliance, FileVault must be enabled before upgrading macOS.\n\nPlease enable FileVault in:\nSystem Settings > Privacy & Security > FileVault" buttons {"OK"} default button 1 with icon stop with title "FileVault Required"' 2>/dev/null
    
    exit 2
    
else
    echo "Unable to determine FileVault status"
    echo "This may indicate a system issue or permission problem"
    
    # Show generic error
    /usr/bin/osascript -e 'display dialog "Unable to verify FileVault status.\n\nPlease contact IT support for assistance." buttons {"OK"} default button 1 with icon caution with title "FileVault Status Unknown"' 2>/dev/null
    
    exit 3
fi