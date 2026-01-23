#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 8-14-2019                           #
# Updated: 1-23-2026                           #
################################################
#
# NAME
#   check-filevault-status.sh
#
# DESCRIPTION
#   Checks FileVault 2 encryption status and progress.
#   Prevents macOS upgrades until encryption is complete.
#
# USAGE
#   Deploy via JAMF policy as pre-flight check
#
# NOTES
#   - Supports both APFS and HFS+ disks
#   - Shows encryption progress percentage
#   - Alerts user to wait for completion
#

fileVault2Status=$(fdesetup status | awk '{print $3}' | cut -d "." -f 1)
diskType=$(/usr/libexec/PlistBuddy -c "Print :FilesystemType" /dev/stdin <<< $(diskutil info -plist /))

echo "FileVault Status: $fileVault2Status"
echo "Disk Type: $diskType"

if [ -n "$fileVault2Status" ]; then
    if [ "$fileVault2Status" = 'On' ]; then
        # Check encryption progress based on disk type
        if [ "$diskType" = 'apfs' ]; then
            FVstatus=$(diskutil apfs list | grep "Encryption Progress")
            
            if [ -n "$FVstatus" ]; then
                osascript -e 'tell app "System Events" to display dialog "FileVault 2 encryption is in progress.\n\n'"$FVstatus"'\n\nPlease try again when encryption is completed." with icon caution with title "macOS Upgrade" buttons {"OK"} giving up after 5'
                exit 1
            fi
        elif [ "$diskType" = 'hfs' ]; then
            FVstatus=$(diskutil cs list | grep "Conversion Progress" | awk '{print $3,$4}')
            
            if [ -n "$FVstatus" ]; then
                osascript -e 'tell app "System Events" to display dialog "FileVault 2 encryption is in progress.\n\n'"$FVstatus"'\n\nPlease try again when encryption is completed." with icon caution with title "macOS Upgrade" buttons {"OK"} giving up after 5'
                exit 1
            fi
        fi
        
        echo "FileVault 2 is enabled and encryption is complete"
        exit 0
    else
        osascript -e 'tell app "System Events" to display dialog "FileVault 2 is not enabled.\n\nPlease enable FileVault before upgrading macOS." with icon caution with title "macOS Upgrade" buttons {"OK"} giving up after 5'
        exit 1
    fi
fi

exit 0
