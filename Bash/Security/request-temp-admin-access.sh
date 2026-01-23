#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 2-20-2020                           #
# Updated: 1-23-2026                           #
################################################
#
# NAME
#   request-temp-admin-access.sh
#
# DESCRIPTION
#   User self-service script to request temporary admin access.
#   Uses two-factor verification (random code + help desk approval).
#   Access automatically revokes after 3 minutes.
#
# USAGE
#   Deploy via JAMF Self Service
#
# NOTES
#   - Generates random verification code
#   - User calls help desk with code
#   - Help desk provides password
#   - Access expires after 180 seconds
#   - All activity logged
#

# Generate random verification number
Numbers=$((RANDOM%55555+11111))

# Generate the password by using basic math calculation
Password=$(expr $Numbers \* 10)
Password2=$(expr $Password + 25)
Password3=$(expr $Password2 / 4)

Descr="Please use responsibly. 
All administrative activity will be logged. 
Access will expire in 3 minutes."

USERNAME="$(stat -f "%Su" /dev/console)"

# Display the random numbers and advise user to call Service Desk
dialog="$(osascript -e 'tell app "System Events" to display dialog "Verification is Required. Please Contact Service Desk with this number '"$Numbers"' to get your Password to continue." buttons {"Ok", "Not Now"} default button "Ok"')"

if [ "$dialog" = "button returned:Ok" ]; then
    # Prompt user for the password
    dialog2="$(osascript -e 'Tell application "System Events" to display dialog "Please enter your Password given by the Service Desk to enable administrator access" default answer ""' -e 'text returned of result' 2>/dev/null)"
    
    if [ "$dialog2" == "$Password3" ]; then
        # Build log files in /var/logs/tempAdmin
        mkdir -p /var/log/tempAdmin
        mkdir -p /var/tempAdmin
        TIME=$(date "+Date:%m-%d-%Y Time:%H:%M:%S")
        
        # Log temp admin state
        echo "$TIME: Admin access granted to $USERNAME by Service Desk" >> /var/log/tempAdmin/tempAdmin.log
        echo "$TIME: $USERNAME added to /groups/admin" >> /var/log/tempAdmin/tempAdmin.log
        
        # Note the user
        echo $USERNAME >> /var/tempAdmin/userToRemove
        
        # Give current logged user admin rights
        dscl . -append /groups/admin GroupMembership $USERNAME
        
        osascript -e 'tell application "System Events" to display dialog "'"$Descr"'" buttons "" giving up after 2 '
    else
        osascript -e 'tell application "System Events" to display dialog "Password is Incorrect! Please re-run the program again with the right Password" buttons {"Ok"} default button 1'
    fi
else
    osascript -e 'tell application "System Events" to display dialog "Please run the program again when you are ready" buttons {"Confirm"} default button 1'
    exit 0
fi

# Wait 3 minutes
sleep 180

# Revoke admin access
if [ -f /var/tempAdmin/userToRemove ]; then
    echo "$TIME: removing $USERNAME from admin group" >> /var/log/tempAdmin/revokeAdmin.log
    dseditgroup -o edit -d $USERNAME -t user admin
    echo "$TIME: $USERNAME has been removed from admin group" >> /var/log/tempAdmin/revokeAdmin.log
    rm -rf /var/tempAdmin/userToRemove
else
    exit 0
fi
