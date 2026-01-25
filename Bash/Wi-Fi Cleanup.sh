#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 10-2-2020                           #
# Updated: 1-25-2026                           #
################################################
#
# NAME
#   Wi-Fi Cleanup.sh
#
# DESCRIPTION
#   Allows users to clean up unused SSIDs without requiring admin password
#   Updated for macOS Ventura (13.x) - Sequoia (15.x) compatibility
#
# UPDATES (2026-01-25)
#   - Added dynamic WiFi interface detection for Apple Silicon Macs
#   - M-series Macs may use en1 or other interface names instead of en0
#   - Enhanced error handling for interface detection
#   - Improved user dialogs for modern macOS
#
# USAGE
#   Deploy via JAMF Pro Self Service
#   User can remove saved WiFi networks without admin rights
#
# NOTES
#   - Works on both Intel and Apple Silicon Macs
#   - Automatically detects correct WiFi interface
#   - Safe to run - only removes networks user selects
#

#----------VARIABLES---------

# Detect WiFi service name (may be "Wi-Fi" or "AirPort" on older systems)
wifiOrAirport=$(/usr/sbin/networksetup -listallnetworkservices | grep -Ei '(Wi-Fi|AirPort)')

# Dynamically detect WiFi interface (handles Apple Silicon M-series Macs)
wirelessDevice=$(networksetup -listallhardwareports | awk "/$wifiOrAirport/,/Device/" | awk 'NR==2' | cut -d " " -f 2)

# Validate interface detection
if [ -z "$wirelessDevice" ]; then
    echo "Error: Could not detect WiFi interface"
    osascript -e 'display dialog "Unable to detect WiFi interface.\n\nPlease ensure WiFi is enabled and try again." buttons {"OK"} default button 1 with icon stop with title "WiFi Cleanup Error"'
    exit 1
fi

echo "Detected WiFi interface: $wirelessDevice"

# Generate List of Current SSIDs in Preferred Networks
listSSID="$(networksetup -listpreferredwirelessnetworks "$wirelessDevice" 2>/dev/null)"

# Check if any networks are configured
if [ -z "$listSSID" ] || echo "$listSSID" | grep -q "There are no preferred wireless networks"; then
    osascript -e 'display dialog "No saved WiFi networks found.\n\nYour preferred network list is empty." buttons {"OK"} default button 1 with icon note with title "WiFi Cleanup"'
    exit 0
fi 
	

#----------START SCRIPT--------

	# Prompts for user to dollow in order to remove SSID's from Preferred Network List 	
	dialog="$(osascript -e 'tell app "System Events" to display dialog "Below is a list of all Wi-Fi Networks you have previoiusly connected to. In order to remove a network from the list follow the instructions on the following prompts. 
		
		'"$listSSID"' " buttons {"Ok"} default button "Ok"')"

	if [ "$dialog" = "button returned:Ok" ]; 
		then
			
			#prompt for user to enter SSID to remove
			undesiredNetwork="$(osascript -e 'Tell application "System Events" to display dialog "Please enter your the name of the Wi-Fi network you would like to remove" default answer ""' -e 'text returned of result' 2>/dev/null)"
			# Remove the  SSID from the list of preferred networks
			echo "Removing $undesiredNetwork from Preferred Networks list"
				networksetup -removepreferredwirelessnetwork "$wirelessDevice" "$undesiredNetwork"
				networksetup -listpreferredwirelessnetworks en0
			# Prompt for User to continue Forgetting Networks
			dialog2="$(osascript -e 'tell app "System Events" to display dialog "Would you like to remove additional neworks?" buttons {"Yes", "No"}default button "Yes"')"
	fi

	
	# If user selects Yes Continue with Loop, end on No
	while [[ "$dialog2" == "button returned:Yes" ]]
	do
		if [ "$dialog" = "button returned:Ok" ]; 
			then
				#update SSID list
				listSSID="$(networksetup -listpreferredwirelessnetworks en0)"
				#List SSID
				osascript -e 'tell app "System Events" to display dialog "Below is an updated list of all Wi-Fi Networks. 
						
				'"$listSSID"' " buttons {"Ok"} default button "Ok"'
						
				#prompt for user to enter SSID to remove
				undesiredNetwork="$(osascript -e 'Tell application "System Events" to display dialog "Please enter your the name of the Wi-Fi network you would like to remove" default answer ""' -e 'text returned of result' 2>/dev/null)"
				# Remove the  SSID from the list of preferred networks
				echo "Removing $undesiredNetwork from Preferred Networks list"
					networksetup -removepreferredwirelessnetwork "$wirelessDevice" "$undesiredNetwork"
					networksetup -listpreferredwirelessnetworks en0
				dialog2="$(osascript -e 'tell app "System Events" to display dialog "Would you like to remove additional neworks?" buttons {"Yes", "No"}default button "Yes"')"
		fi
	done

	

