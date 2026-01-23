#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 2-20-2020                           #
# Updated: 1-23-2026                           #
################################################
#
# NAME
#   grant-admin-access.sh
#
# DESCRIPTION
#   Grants temporary admin access rights to user making request,
#   based on IT Administrator's judgement. All transactions are
#   logged in the console and JAMF.
#
# USAGE
#   Deploy via JAMF policy for help desk use
#
# NOTES
#   - Prompts for username and passcode
#   - Generates algorithmic password
#   - Logs all access grants/denials
#

# Prompt for the username of requester
remoteUser="$(osascript -e 'Tell application "System Events" to display dialog "Enter the username of Access requester" default answer ""' -e 'text returned of result' 2>/dev/null)"

# Prompt for the number given by User
Numbers="$(osascript -e 'Tell application "System Events" to display dialog "Enter the Passcode given by the User" default answer ""' -e 'text returned of result' 2>/dev/null)"

# Generate the password by using $Numbers x Random Algorithm
Password=$(expr $Numbers \* 10)
Password2=$(expr $Password + 25)
Password3=$(expr $Password2 / 4)

# Build log files in /var/logs/tempAdmin
mkdir -p /var/log/tempAdmin
mkdir -p /var/tempAdmin
TIME=$(date "+%A %Y-%m-%d %H:%M:%S.%s%z")
USERNAME="$(stat -f "%Su" /dev/console)"

# Display the password
if [ -n "$Numbers" ]; then
    osascript -e 'tell application "System Events" to display dialog "Please give this password '"$Password3"' to user '"$remoteUser"' " buttons {"Acknowledge"} default button 1'
    echo "$TIME: Admin access granted to $remoteUser by $USERNAME" >> /var/log/tempAdmin/grantAccess.log
    exit 0
else
    osascript -e 'tell application "System Events" to display dialog "No input" buttons {"Acknowledge"} default button 1'
    echo "$TIME: Admin access request for $remoteUser rejected by $USERNAME" >> /var/log/tempAdmin/grantAccess.log
    exit 0
fi
