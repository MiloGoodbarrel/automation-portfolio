#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 1-25-2026                           #
# Updated: 1-25-2026                           #
################################################
#
# NAME
#   Configure-802.1X-WiFi.sh
#
# DESCRIPTION
#   Remediate 802.1X enterprise WiFi connectivity issues
#   Designed for Windows RADIUS server integration (EAP-TLS/PEAP)
#
# USAGE
#   Deploy via JAMF Pro when users report corporate WiFi issues
#   Can be run from Self Service to troubleshoot connectivity
#
# REQUIREMENTS
#   - Certificate installed via MDM (for EAP-TLS)
#   - JAMF Pro Configuration Profile with 802.1X payload
#   - macOS Ventura 13.x or later
#
# NOTES
#   - This script validates 802.1X configuration, not creates it
#   - Configuration profiles are preferred over networksetup commands
#   - Use JAMF to deploy certificates and 802.1X profiles
#

# Variables
CORPORATE_SSID="${4:-Corp-WiFi}"  # JAMF parameter 4 or default
RADIUS_SERVER="${5:-radius.company.com}"  # JAMF parameter 5 or default
LOG_FILE="/var/log/802.1x-remediation.log"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "=== Starting 802.1X WiFi Remediation ==="
log_message "Target SSID: $CORPORATE_SSID"

# Check macOS version (802.1X best supported in Ventura+)
os_version=$(sw_vers -productVersion | awk -F. '{print $1}')
if [ "$os_version" -lt 13 ]; then
    log_message "WARNING: macOS version $os_version detected. 802.1X works best on Ventura 13.x+"
fi

# Detect WiFi interface
wifi_interface=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/{getline; print $2}')
if [ -z "$wifi_interface" ]; then
    log_message "ERROR: Could not detect WiFi interface"
    osascript -e 'display dialog "WiFi interface not found.\n\nPlease ensure WiFi is enabled." buttons {"OK"} default button 1 with icon stop'
    exit 1
fi

log_message "WiFi interface: $wifi_interface"

# Check if 802.1X profile is installed
profile_installed=$(profiles list | grep -i "wifi" | grep -i "$CORPORATE_SSID")

if [ -z "$profile_installed" ]; then
    log_message "WARNING: 802.1X configuration profile not detected"
    
    osascript -e "display dialog \"802.1X configuration profile not installed.\n\nSSID: $CORPORATE_SSID\n\nPlease contact IT to deploy the enterprise WiFi profile via JAMF.\" buttons {\"OK\"} default button 1 with icon caution with title \"802.1X Configuration Missing\""
    
    log_message "Action required: Deploy 802.1X profile via JAMF Pro"
    exit 2
else
    log_message "802.1X profile detected for SSID: $CORPORATE_SSID"
fi

# Check if client certificate is installed (for EAP-TLS)
cert_check=$(security find-certificate -c "Corporate" -a /Library/Keychains/System.keychain 2>/dev/null)

if [ -z "$cert_check" ]; then
    log_message "WARNING: Corporate certificate not found in System keychain"
    log_message "EAP-TLS authentication may fail without user certificate"
else
    log_message "Corporate certificate found in System keychain"
fi

# Test connectivity to RADIUS server
if ping -c 2 -t 5 "$RADIUS_SERVER" >/dev/null 2>&1; then
    log_message "RADIUS server $RADIUS_SERVER is reachable"
else
    log_message "WARNING: Cannot reach RADIUS server $RADIUS_SERVER"
    log_message "This may indicate network connectivity issues"
fi

# Check current WiFi connection
current_ssid=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '/ SSID/ {print substr($0, index($0, $2))}')

log_message "Current SSID: $current_ssid"

# If connected to corporate SSID, test authentication
if [ "$current_ssid" = "$CORPORATE_SSID" ]; then
    log_message "Connected to $CORPORATE_SSID - checking authentication status"
    
    # Check if internet is accessible
    if curl -s --max-time 5 https://www.google.com >/dev/null; then
        log_message "SUCCESS: 802.1X authentication working - internet accessible"
        
        osascript -e "display dialog \"802.1X WiFi is working correctly.\n\nSSID: $CORPORATE_SSID\nInternet: Connected\" buttons {\"OK\"} default button 1 with icon note with title \"802.1X Status: OK\""
        exit 0
    else
        log_message "ERROR: Connected to WiFi but no internet access"
        log_message "This may indicate 802.1X authentication failure"
        
        # Attempt to rejoin network
        log_message "Attempting to rejoin $CORPORATE_SSID..."
        networksetup -setairportnetwork "$wifi_interface" "$CORPORATE_SSID"
        
        sleep 5
        
        # Retest
        if curl -s --max-time 5 https://www.google.com >/dev/null; then
            log_message "SUCCESS: Rejoin successful - internet now accessible"
            osascript -e 'display dialog "WiFi issue resolved!\n\nYou are now connected to the internet." buttons {"OK"} default button 1 with icon note'
            exit 0
        else
            log_message "ERROR: Rejoin failed - still no internet"
            osascript -e "display dialog \"Unable to authenticate to $CORPORATE_SSID.\n\nPossible causes:\n- Invalid certificate\n- RADIUS server issue\n- Network configuration problem\n\nPlease contact IT support.\" buttons {\"OK\"} default button 1 with icon stop with title \"802.1X Authentication Failed\""
            exit 3
        fi
    fi
else
    log_message "Not currently connected to $CORPORATE_SSID"
    
    # Attempt to join corporate WiFi
    user_action=$(osascript -e "display dialog \"You are not connected to $CORPORATE_SSID.\n\nWould you like to connect now?\" buttons {\"Cancel\", \"Connect\"} default button 2 with icon question" 2>/dev/null)
    
    if echo "$user_action" | grep -q "Connect"; then
        log_message "User requested connection to $CORPORATE_SSID"
        networksetup -setairportnetwork "$wifi_interface" "$CORPORATE_SSID"
        
        sleep 5
        
        # Verify connection
        new_ssid=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I | awk '/ SSID/ {print substr($0, index($0, $2))}')
        
        if [ "$new_ssid" = "$CORPORATE_SSID" ]; then
            log_message "SUCCESS: Connected to $CORPORATE_SSID"
            osascript -e 'display dialog "Successfully connected to corporate WiFi!" buttons {"OK"} default button 1 with icon note'
            exit 0
        else
            log_message "ERROR: Failed to connect to $CORPORATE_SSID"
            osascript -e 'display dialog "Connection failed.\n\nPlease verify:\n- WiFi is enabled\n- You are in range of corporate WiFi\n- 802.1X profile is installed" buttons {"OK"} default button 1 with icon stop'
            exit 4
        fi
    else
        log_message "User cancelled connection attempt"
        exit 0
    fi
fi

log_message "=== 802.1X Remediation Complete ==="
exit 0
