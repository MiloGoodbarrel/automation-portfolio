#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 9-15-2019                           #
# Updated: 1-23-2026                           #
################################################
# 
# NAME
#   scan-kernel-extensions.sh
#
# DESCRIPTION
#   Scans macOS system for third-party kernel extensions (kexts)
#   Gathers information needed for Apple MDM whitelisting
#   Generates report of Team IDs and bundle identifiers
#
# USAGE
#   sudo ./scan-kernel-extensions.sh
#
# NOTES
#   - Requires sudo for system-wide kext scanning
#   - Excludes /System and Apple kexts
#   - Output saved to Desktop
#   - Essential for macOS 10.13+ security compliance
#   - Original script by Richard Purves, adapted for enterprise use
#

plist="com.apple.syspolicy.kernel-extension-policy.plist"
output="$HOME/Desktop"
override="false"

# Stop IFS linesplitting on spaces
OIFS=$IFS
IFS=$'\n'

# Scan the drive to find 3rd party kexts
# Excluding /System /private ./StagedExtensions and /dev

echo "Searching your drive for kext files"
echo "This may take a while. Please wait ..."
echo "(please enter your password if prompted)"
paths=($( sudo find / \( -type d -name "System" -prune \) -o \( -type d -name "private" -prune \) -o \( -type d -name "StagedExtensions" -prune \) -o \( -type d -name "dev" -prune \) -o \( -name "*.kext" -type d -print \) ))

echo ""

# Report the details of all found

if [ ${#paths[@]} != "0" ];
then
	for (( loop=0; loop<${#paths[@]}; loop++ ))
	do
		# Get the Team Identifier for the kext
		teamid[$loop]=$( codesign -d -vvvv ${paths[$loop]} 2>&1 | grep "Authority=Developer ID Application:" | cut -d"(" -f2 | tr -d ")" )

		# Get the CFBundleIdentifier for the kext
		bundid[$loop]=$( defaults read "${paths[$loop]}"/Contents/Info.plist CFBundleIdentifier )

		echo "Team ID: ${teamid[$loop]}    Bundle ID: ${bundid[$loop]}"
	done
fi

echo ""

# Start to generate a plist file
echo "Processing Team IDs into xml"
echo ""

if [ ${#paths[@]} != "0" ];
then
	# Prune the duplicate ID's from the array
	nodupes=($( echo "${teamid[@]}" | tr ' ' '\n' | sort -u ))

	# Now write out the xml with what we've discovered
	# Header first
~/Desktop/kext.xml
echo '<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>' > ~/Desktop/kext.xml

	# Start with the User Override
echo "<key>AllowUserOverrides</key>
<$override/>" >> ~/Desktop/kext.xml

	# Now the Team IDs

echo '<key>AllowedTeamIdentifiers</key>
<array>' >> ~/Desktop/kext.xml

	for (( loop=0; loop<${#nodupes[@]}; loop++ ))
	do
		# Write the team identifier to the file
		echo "<string>"${nodupes[$loop]}"</string>" >> ~/Desktop/kext.xml
	done

	# Now for the Bundle IDs with the Team IDs

echo '</array>
<key>AllowedKernelExtensions</key>
<dict>' >> ~/Desktop/kext.xml

	for (( loop=0; loop<${#nodupes[@]}; loop++ ));
	do
		# Write the team identifier to the file
		echo "<key>"${nodupes[$loop]}"</key>" >> ~/Desktop/kext.xml
		echo '<array>' >> ~/Desktop/kext.xml

		# Parse collected data to write out captured bundle ids that match to the team id
		for (( loopint; loopint<${#teamid[@]}; loopint++ ));
		do      
			if [ "${nodupes[$loop]}" = "${teamid[$loopint]}" ];
			then        
				echo "<string>${bundid[$loopint]}</string>" >> ~/Desktop/kext.xml
			fi
		done

		# Reset internal loop variable and close tags
		loopint=0
		echo '</array>' >> ~/Desktop/kext.xml
	done

	# Close up, we're done

	echo '</dict>
</dict>
</plist>' >> ~/Desktop/kext.xml

fi

# Now format the file nicely and rename

cat ~/Desktop/kext.xml | xmllint -format - > "$output/$plist"
#rm ~/Desktop/kext.xml
cat "$output"/"$plist"

# Reset IFS and quit
IFS=$OIFS

exit