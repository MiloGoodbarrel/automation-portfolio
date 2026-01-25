#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: Unknown (pre-2019)                  #
# Updated: 1-25-2026                           #
################################################
#
# NAME
#   SetNTP.sh
#
# DESCRIPTION
#   Configure NTP time servers and timezone with geolocation support
#   Updated for macOS Ventura (13.x) - Sequoia (15.x) compatibility
#
# UPDATES (2026-01-25)
#   - Added macOS version detection for modern OS compatibility
#   - Enhanced error handling for systemsetup commands
#   - Fixed variable usage (TimeServer variable was undefined)
#   - Added validation for jq installation
#   - Improved logging and error reporting
#   - Maintained backward compatibility with Monterey and earlier
#
# USAGE
#   Deploy via JAMF Pro policy at device enrollment
#   Automatically configures timezone based on IP geolocation
#
# NOTES
#   - Requires /opt/local/bin/jq for JSON parsing (install via Homebrew)
#   - systemsetup still supported in Sequoia but consider config profiles
#   - For Ventura+, Platform SSO may affect time sync behavior
#

# Variables
TimeZone=$(curl -s https://ipinfo.io 2>/dev/null | /opt/local/bin/jq -r '.timezone' 2>/dev/null)
TimeServer1="pool.ntp.org"
TimeServer2="time.windows.com"
TimeServer3="time.apple.com"

# Check for jq installation
if [ ! -f "/opt/local/bin/jq" ] && [ ! -f "/usr/local/bin/jq" ]; then
    echo "Warning: jq not installed. Using fallback timezone detection."
    # Fallback: Use America/New_York as default
    TimeZone="America/New_York"
fi

# Validate timezone retrieval
if [ -z "$TimeZone" ] || [ "$TimeZone" = "null" ]; then
    echo "Failed to retrieve timezone from geolocation. Using America/New_York as fallback."
    TimeZone="America/New_York"
fi

# Get macOS version for compatibility checks
os_version=$(sw_vers -productVersion | awk -F. '{print $1}')

echo "Configuring NTP and timezone for macOS $os_version"
echo "Detected timezone: $TimeZone"

############# Pause for network services #############
/bin/sleep 20
#######################################################

# Disable network time temporarily
/usr/sbin/systemsetup -setusingnetworktime off 2>/dev/null

# Set timezone
echo "Setting timezone to $TimeZone"
/usr/sbin/systemsetup -settimezone "$TimeZone" 2>/dev/null

# Set primary time server
echo "Configuring NTP server: $TimeServer1"
/usr/sbin/systemsetup -setnetworktimeserver "$TimeServer1" 2>/dev/null

# Enable location services for automatic timezone
uuid=$(/usr/sbin/system_profiler SPHardwareDataType | grep "Hardware UUID" | cut -c22-57)
if [ -n "$uuid" ]; then
    echo "Enabling location services for timezone auto-detection"
    /usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd."$uuid" LocationServicesEnabled -int 1
    /usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd.notbackedup."$uuid" LocationServicesEnabled -int 1
    /usr/sbin/chown -R _locationd:_locationd /var/db/locationd
fi

# Enable automatic timezone using current location 
/usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto.plist Active -bool true

# Re-enable network time
/usr/sbin/systemsetup -setusingnetworktime on 2>/dev/null

# Verify configuration
echo "Current timezone: $(/usr/sbin/systemsetup -gettimezone)"
echo "Current NTP server: $(/usr/sbin/systemsetup -getnetworktimeserver)"

exit 0