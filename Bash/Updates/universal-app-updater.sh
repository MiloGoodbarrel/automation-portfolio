#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 8-5-2019                            #
# Updated: 1-23-2026                           #
################################################
# 
# NAME
#   universal-app-updater.sh
#
# DESCRIPTION
#   Generic application updater framework for JAMF Pro
#   Downloads and installs applications with user notifications
#   Handles running applications and user postponement
#
# USAGE
#   Via JAMF Pro policy with parameters:
#   Parameter 4: Application path (e.g., /Applications/AppName.app)
#   Parameter 5: Icon name (e.g., AppIcon)
#   Parameter 6: Download URL
#
# NOTES
#   - Prompts user if app is running
#   - Allows postponement of updates
#   - Uses jamfHelper for UI dialogs
#   - Supports DMG and PKG installers
#

loggedInUser=$(/bin/ls -l /dev/console | /usr/bin/awk '{ print $3 }')


# -------------------------------------------------------------------------------------

# USER DESIGNATED VARIABLES TO ALTER VIA JAMF PARAMETERS
# ADD APP DIRECTORY
# 	Example: app_path="/Applications/$AppLNCH"
# ADD THE DIRECT DOWNLOAD LINK FOR YOUR APP HERE:
# 	Example: DownloadURL="https://dl.google.com/chrome/mac/stable/googlechrome.dmg"

app_Path="${4}"
icns="${5}"
DownloadURL="${6}"

# FIXED VARIABLES DETERMINED BY SCRIPT
# ADD APP LAUNCHER FILE
# 	Example: APPFile="Google Chrome.app"
AppUIIcon=""$app_Path"/Contents/Resources/'$icns'.icns"
app_name="$(echo "$app_Path" | sed -e 's#/$##' -e 's/\.app$//' | /usr/bin/awk '{ gsub("^/Applications/",""); gsub(/.app*/,""); print $0}')"
PROCESS=$app_name
#Add Dialogue INFORMATION

jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"

CloseToUpdate="$app_name is open and needs to close prior to updating application."

PostponeUpdate="Please open $app_name app in the Jamf Self Service when ready to proceed with update."

AppUIIcon=""$app_Path"/Contents/Resources/"$icns".icns"

# -------------------------------------------------------------------------------------

# CHECK FOR IF APP IS INSTALLED ON SYSTEM
AppCheck(){
	if [[  -e "$app_Path" ]]; then 
		echo "$app_name is already installed"
		installed=True
		number=$(ps aux | grep -v grep | grep -ci "$PROCESS")
	fi
		
}	
		
# Checks if App is running
RunCheck(){
	if [ "$number" -gt "0" ]; then
		dialog="$("$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$Name Needs to update" -description "$CloseToUpdate" -button1 "Proceed" -button2 "Not Now" -cancelButton 2 -defaultButton 1 )"
		if [ "$dialog" != 2 ];  then
			
			killall "$PROCESS" 
			
			rm -rf "$app_Path" 
			# LEAVE THIS CODE ALONE:
			
			# Create directory /tmp/jamf, continue if directory already exists
			mkdir /tmp/jamf || :
			
			# Change directory to /tmp/jamf
			cd /tmp/jamf
		else
			"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$Name Needs to update" -description "$PostponeUpdate" -button1 "OK" -defaultButton 1
			exit 0
		fi
	else
		rm -rf "$app_Path"		
		# LEAVE THIS CODE ALONE:
		
		# Create directory /tmp/jamf, continue if directory already exists
		mkdir /tmp/jamf || :
		
		# Change directory to /tmp/jamf
		cd /tmp/jamf
	
	fi
}
		
TeamsDownloader(){
	echo "downloading Microsoft Teams"
	
	TeamsURL="https://teams.microsoft.com/downloads/DesktopUrl?env=production&plat=osx&arch=64"
	
	## Get the actual download URL
	DownloadURL=$(curl -s "$TeamsURL")
	
	## Extract the DMG Name from the path
	DMGName="${DownloadURL##*/}"
	
	## Download the DMG into /tmp/
	curl -s "$DownloadURL" -o "/tmp/jamf/$DMGName"
}

FirefoxDownloader(){
	echo "Downloading Firefox"
	
	FirefoxURL=https://download.mozilla.org/\?product\=firefox-latest\&os\=osx\&lang\=en-US
	
	DownloadURL=$(curl -l $FirefoxURL | grep -Eo "(http|https)://[a-zA-Z0-9./?=_%:-]*" )
	
	curl $DownloadURL -O -L
}

		
DownloadApp(){
		if [ "$app_name" = "Microsoft Teams" ]; then
			TeamsDownloader
		elif [ "$app_name" = "Firefox" ]; then
			FirefoxDownloader
		elif [ "$app_name" = "Zscaler" ];then
			ZscalerDownloader
		else
			curl $DownloadURL -O -L
		fi
}

FileExtractor(){
	if [ -e /tmp/jamf/*.dmg ]; then
		echo " "
		echo $(ls /tmp/jamf/)
		echo "file is a DMG"
		hdiutil attach /tmp/jamf/*.dmg -nobrowse -noverify -mountpoint /tmp/jamf/mount
		cp -pPR /tmp/jamf/mount/*.app /Applications
		hdiutil detach /tmp/jamf/mount
	elif [ -e /tmp/jamf/*.zip ]; then
		echo $(ls /tmp/jamf/)
		unzip /tmp/jamf/* -d tmp/jamf/mount
		if [ -e /tmp/jamf/mount/*.dmg ]; then
			echo " "
			echo $(ls /tmp/jamf/mount/)
			echo "file is a DMG"
			hdiutil attach /tmp/jamf/*.dmg -nobrowse -noverify -mountpoint /tmp/jamf/mount
			cp -pPR /tmp/jamf/mount/*.app /Applications
			hdiutil detach /tmp/jamf/mount
		else 
			echo " "
			PKG=$(ls /tmp/jamf/mount/)
			echo $(ls /tmp/jamf/mount/)
			echo $PKG
			echo "file is a PKG"
			installer -pkg /tmp/jamf/mount/"$PKG" -target /
		fi
	else 
		echo " "
		PKG=$(ls /tmp/jamf/)
		echo $(ls /tmp/jamf/)
		echo $PKG
		echo "file is a PKG"
		installer -pkg /tmp/jamf/"$PKG" -target /
	fi
	rm -r /tmp/jamf
	open -a "$PROCESS"
}


AppCheck
if [ $installed = True ]; then
	RunCheck
	DownloadApp 
	FileExtractor
else
# Create directory /tmp/jamf, continue if directory already exists
		mkdir /tmp/jamf || :
		
		# Change directory to /tmp/jamf
		cd /tmp/jamf

	DownloadApp 
	FileExtractor
fi
	