#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 6-12-2019                           #
# Updated: 1-23-2026                           #
################################################
#
# NAME
#   configure-ntp-timezone.sh
#
# DESCRIPTION
#   Configures NTP time synchronization and sets timezone
#   based on geolocation. Enables automatic timezone detection.
#
# USAGE
#   Deploy via JAMF policy during initial setup
#
# NOTES
#   - Uses ipinfo.io for geolocation
#   - Requires jq for JSON parsing
#   - Enables automatic timezone updates
#   - Configures multiple NTP servers
#

# Use "/usr/sbin/systemsetup -listtimezones" to see available time zones
TimeZone=$(curl -s https://ipinfo.io | /opt/local/bin/jq -r '.timezone')
TimeServer1="pool.ntp.org"
TimeServer2="time.windows.com"
TimeServer3="time.apple.com"

# Pause for network services
/bin/sleep 20

# Disable network time temporarily
/usr/sbin/systemsetup -setusingnetworktime off 

# Set initial time zone
/usr/sbin/systemsetup -settimezone $TimeZone
/bin/echo "server ${TimeServer2}" >> /private/etc/ntp.conf

# Set specific time server
/usr/sbin/systemsetup -setnetworktimeserver $TimeServer2

# Enable location services
uuid=$(/usr/sbin/system_profiler SPHardwareDataType | grep "Hardware UUID" | cut -c22-57)
/usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd.$uuid LocationServicesEnabled -int 1
/usr/bin/defaults write /var/db/locationd/Library/Preferences/ByHost/com.apple.locationd.notbackedup.$uuid LocationServicesEnabled -int 1
/usr/sbin/chown -R _locationd:_locationd /var/db/locationd

# Set time zone automatically using current location 
/usr/bin/defaults write /Library/Preferences/com.apple.timezone.auto Active -bool true

# Re-enable network time
/usr/sbin/systemsetup -setusingnetworktime on 

# Verify configuration
/usr/sbin/systemsetup -gettimezone
/usr/sbin/systemsetup -getnetworktimeserver

exit 0
