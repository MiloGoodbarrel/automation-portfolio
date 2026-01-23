#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 4-23-2021                           #
# Updated: 1-23-2026                           #
################################################
# 
# NAME
#   create-bootable-usb.sh
#
# DESCRIPTION
#   Interactive macOS bootable USB creator for JAMF Self Service
#   Downloads macOS installer if not present, creates bootable media
#   Uses installinstallmacos.py and jamfHelper for user interface
#
# USAGE
#   Deploy via JAMF Pro Self Service policy
#   User selects macOS version and target USB drive
#
# NOTES
#   - Requires installinstallmacos.py in /usr/local/macadmin-scripts-main/
#   - Uses jamfHelper for GUI dialogs
#   - Downloads installer if not present on system
#   - Supports multiple macOS versions
#   - Validates USB drive selection before formatting
#   - Useful for help desk to create recovery media
#



# VARIABLES

	jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
	prompt="Please Enter the macOS version you wish to convert into a bootable medium"
	AppUIIcon="/System/Library/CoreServices/DiskImageMounter.app/Contents/Resources/diskcopy.icns"
	verslist=$(/usr/local/macadmin-scripts-main/installinstallmacos.py --list | cut -d : -f 4,7,8,9 | sed -e '1,19d;21,31d' | awk '{print $7,$8}')
	title="Bootable Media Creator"

# INITIAL DIALOGS
InitialDialogs(){
	"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$prompt" -timeout 5
	
	dialog=$( /usr/bin/osascript -e "display dialog \" Enter macOS version here \"  default answer \"$verslist\" with title\" $title\" buttons {\"Cancel\",\"OK\"} default button {\"OK\"}" )
	theButton=$( echo "$dialog" | /usr/bin/awk -F "button returned:|," '{print $2}' )
	OSversion=$( echo "$dialog" | /usr/bin/awk -F "text returned:" '{print $2}' )
	if [[ $theButton = OK ]]; then
		installer_path="/Applications/Install macOS $OSversion.app/"
		app_name="$(echo "$installer_path" | sed -e 's#/$##' -e 's/\.app$//' | /usr/bin/awk '{ gsub("^/Applications/",""); gsub(/.app*/,""); print $0}')"
	fi
}



# FUNCTIONS USED TO RUN SCRIPT

# Function to create the USB 
CreateMediaAPFS(){
	mntVol=$(ls /Volumes/ | grep -v -e "Macintosh" -e "Recovery" -e "Time")
	echo $mntVol
	dialog4="is $mntVol the name of the external media you wish to make a bootable version of $app_name?"
	dialog5="$("$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$dialog4" -button1 "Yes" -button2 "No" -defaultButton 1 )"
	echo $dialog5
	if [ $dialog5 != 0 ]; then
		echo "Please provide the name of the USB Volume you will be writing to"
		prefill="Enter Volume Name Here"
		dialog6=$( /usr/bin/osascript -e "display dialog \" Please provide the name of the USB Volume you will be writing to \"  default answer \"$prefill\" with title\" $title\" buttons {\"Cancel\",\"OK\"} default button {\"OK\"}" )
		dialog6button=$( echo "$dialog6" | /usr/bin/awk -F "button returned:|," '{print $2}' )
		mntVol=$( echo "$dialog6" | /usr/bin/awk -F "text returned:" '{print $2}' )
		echo $dialog6button
		echo $mntVol
		mediacreation="Creating bootable media for $OSversion."
		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$mediacreation" -timeout 10
		"$installer_path/Contents/Resources/createinstallmedia" --volume /Volumes/$mntVol --nointeraction
	else
		#hdiutil create -o /tmp/$OSversion.cdr -size 9000m -layout SPUD -fs HFS+J
		#hdiutil attach /tmp/$OSversion.cdr.dmg -noverify -mountpoint /Volumes/$mntVol
		mediacreation="Creating bootable media for $OSversion."
		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$mediacreation" -timeout 10
		"$installer_path/Contents/Resources/createinstallmedia" --volume /Volumes/$mntVol --nointeraction
		#hdiutil detach "/Volumes/Install macOS $OSversion"
		#hdiutil convert /tmp/Catalina.cdr.dmg -format UDTO -o /tmp/Catalina.iso
		#mv /tmp/$OSversion.iso.cdr ~/Desktop/$OSversion.iso
		#rm /tmp/$OSversion.cdr.dmg
	fi
}

#CreateMediaHFS(){
#	mntVol=$(ls /Volumes/ | grep -v -e "Macintosh" -e "Recovery" -e "Time")
#	echo $mntVol
#	dialog4="is $mntVol the name of the external media you wish to make a bootable version of $app_name?"
#	dialog5="$("$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$dialog4" -button1 "Yes" -button2 "No" -defaultButton 1 )"
#	echo $dialog5
#	if [ $dialog5 != 0 ]; then
#		echo "please provide the name of the external media you will write to"
#		prefill="Enter Volume Name Here"
#		dialog6=$( /usr/bin/osascript -e "display dialog \" Please provide the name of the USB Volume you will be writing to \"  default answer \"$prefill\" with title\" $title\" buttons {\"Cancel\",\"OK\"} default button {\"OK\"}" )
#		dialog6button=$( echo "$dialog6" | /usr/bin/awk -F "button returned:|," '{print $2}' )
#		mntVol=$( echo "$dialog6" | /usr/bin/awk -F "text returned:" '{print $2}' )
#		echo $dialog6button
#		echo $mntVol
#		mediacreation="Creating bootable media for $OSversion."
#		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$mediacreation" -timeout 10
#		"$installer_path/Contents/Resources/createinstallmedia" --volume /Volumes/$mntVol --applicationpath "$installer_path" --nointeraction
#	else
#		#hdiutil create -o /tmp/$OSversion.cdr -size 9000m -layout SPUD -fs HFS+J
#		#hdiutil attach /tmp/$OSversion.cdr.dmg -noverify -mountpoint /Volumes/$mntVol
#		mediacreation="Creating bootable media for $OSversion."
#		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$mediacreation" -timeout 10
#		"$installer_path/Contents/Resources/createinstallmedia" --volume /Volumes/$mntVol --applicationpath "$installer_path" --nointeraction
#		#hdiutil detach "/Volumes/Install macOS $OSversion"
#		#hdiutil convert /tmp/Catalina.cdr.dmg -format UDTO -o /tmp/Catalina.iso
#		#mv /tmp/$OSversion.iso.cdr ~/Desktop/$OSversion.iso
#		#rm /tmp/$OSversion.cdr.dmg
#	fi
	
#}

# Function checking if version is supported by Apple
VersionAgeChecker(){
	if [[ $OSversion = Big\ Sur || $OSversion = Catalina || $OSversion = Mojave || $OSversion = High\ Sierra ]]; then
		echo "Creating Bootable USB macOS installer for $OSversion"
		gatherinfo="gathering information for media creation"
		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$gatherinfo" -timeout 5
		CreateMediaAPFS 
		#elif [[ $ver = Sierra || $ver = El\ Capitan ]]; then
		#	echo "Creating Bootable USB macOS installer for $OSversion"
		#gatherinfo="gathering information for media creation"
		#"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$gatherinfo" -timeout 5
		#CreateMediaHFS
	else
		echo "macOS $OSversion is no longer supported by Apple, please download a supported version of macOS."
		Unsupported="macOS $OSversion is no longer supported, please download a supported version of macOS."
		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$Unsupported" -timeout 10
	fi
}


# Function Checking to see if macOS installer is available

CheckPath(){
	if [[ $theButton = OK ]]; then
		echo "$theButton was pressed"
		dialog2="Checking if $installer_path exists..."
		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$dialog2" -timeout 10
		if [[ -e "$installer_path" ]]; then
			dialog3="$app_name is already installed. Proceeding with creation of Bootable USB Installer"
			"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$dialog3" -timeout 10
		else
			if [[ $OSversion = Big\ Sur ]]; then
				macOSver=11.3
				build=20E232
			elif [[ $OSversion = Catalina ]]; then
				macOSver=10.15.7
				build=19H15
			elif [[ $OSversion = Mojave ]]; then
				macOSver=10.14.6
				build=18G103
			elif [[ $OSversion = High\ Sierra ]]; then
				macOSver=10.13.6
				build=17G66
			elif [[ $OSversion = Sierra ]]; then
				macOSver=unsupported
			elif [[ $OSversion = El\ Capitan ]]; then
				macOSver=unsupported
			else
				macOSver=unsupported
			fi
			
		fi
	fi
}

# Function to Download, Extract and install macOS installer app

InstallInstaller(){
	mkdir /tmp/jamf
	DownloadPrompt="Downloading macOS $macOSver installer"
	"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$DownloadPrompt" -timeout 5
	/usr/local/macadmin-scripts-main/installinstallmacos.py --build $build --workdir /tmp/jamf
	
	ExtractionPrompt="installing macOS $macOSver installer"
	"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$ExtractionPrompt" -timeout 5
	hdiutil attach /tmp/jamf/*.dmg -nobrowse -noverify -mountpoint /tmp/jamf/mount
	
	cp -pPR /tmp/jamf/mount/*.app /Applications/
	hdiutil detach /tmp/jamf/mount/
	rm -rf /tmp/jamf/
}

# Function checking if Installer is missing Download then Proceed

VersionChecker(){
	if [[ $macOSver = 11.3 || $macOSver = 10.15.7 || $macOSver = 10.14.6 || $macOSver = 10.13.6 ]]; then
		echo "downloading and installing macOS installer for $OSversion"
		DLPrompt="downloading and installing macOS installer for $OSversion"
		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$DLPrompt" -timeout 5
		InstallInstaller
		gatherinfo="gathering information for media creation"
		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$gatherinfo" -timeout 5
		CreateMediaAPFS 
		#elif [[ $macOSver = 10.12.6 || $macOSver = 10.11.6 ]]; then
		#echo "downloading and installing macOS installer for $OSversion"
		#DLPrompt="downloading and installing macOS installer for $OSversion"
		#"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$DLPrompt" -timeout 5
		#InstallInstaller
		#gatherinfo="gathering information for media creation"
		#"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$gatherinfo" -timeout 5
		#CreateMediaHFS 
	else
		echo "macOS $OSversion is no longer supported, please download a supported version of macOS."
		Unsupported="macOS $OSversion is no longer supported, please download a supported version of macOS."
		"$jamfHelper" -windowType utility -icon "$AppUIIcon" -title "$title" -description "$Unsupported" -timeout 10
	fi
}

# Script begins here

InitialDialogs 
CheckPath 
if [[ -e $installer_path ]]; then
	VersionAgeChecker 
	exit 0
else 
	VersionChecker 
fi