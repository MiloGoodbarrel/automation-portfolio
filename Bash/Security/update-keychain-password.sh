#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 6-10-2020                           #
# Updated: 1-23-2026                           #
################################################
# 
# NAME
#   update-keychain-password.sh
#
# DESCRIPTION
#   Updates macOS keychain password after user password change
#   Finds renamed keychains and synchronizes with new account password
#   Creates backup archive before modification
#
# USAGE
#   sudo ./update-keychain-password.sh
#
# NOTES
#   - Requires user interaction (password prompts)
#   - Creates backup in ~/Desktop/Keychain Archive
#   - Handles renamed keychains from password changes
#   - Validates old password before applying changes
#

username=$( scutil <<< "show State:/Users/ConsoleUser" | awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}' )
loggedInUID=$(id -u "$username")

## Find the renamed keychains
renamed=""

for n in {1..9} ; do
	long="Users/$username/Library/Keychains/login_renamed_$n.keychain-db"
	short="login_renamed_$n.keychain-db"
	echo "$long"
	if [[ ! -f $long ]] ; then
		echo "Above Keychain not Found"
	else
		renamed="$long"
		short_renamed="$short"
		echo "renamed set to Above Keychain"
	fi
done

## If the rename keychain isn't found then exit

if [[ -z "$renamed" ]] ; then
	echo "Renamed keychain not found."
	dialog="Old keychain not found."
	cmd="Tell app \"System Events\" to display dialog \"$dialog\""
	/usr/bin/osascript -e "$cmd"
	exit 1
fi

#renamed=`echo ${renamed%???}`

## Prompt use for current password


currentPass=$(#!/usr/bin/env 
END
tell application "System Events"
activate
set the answer to text returned of (display dialog "Please enter your Current account Password:" default answer "" with hidden answer buttons {"Continue"} default button 1)
end tell
END)

previousPass=$(/usr/bin/osascript<<END
tell application "System Events"
activate
set the answer to text returned of (display dialog "Please enter your Previous account Password:" default answer "" with hidden answer buttons {"Continue"} default button 1)
end tell
END)

## Open the keychain to load it into keychain access
open "$renamed" &

sleep 2

## close keychain access
#killall Keychain\ Access

## unlock the previous keychain
unlock_result=`expect -c "
spawn /bin/launchctl asuser $loggedInUID sudo -iu $username security unlock-keychain $short_renamed
expect \"password to unlock $renamed\"
send ${previousPass}\r
expect"`

if [[ "$unlock_result" == *"The user name or passphrase you entered is not correct."* ]] ; then
	echo "Previous Password did not unlock keychain"
	dialog="Previous Account password did not unlock the old keychain."
	cmd="Tell app \"System Events\" to display dialog \"$dialog\""
	/usr/bin/osascript -e "$cmd"
	exit 1
fi

### If it gets this far the Previous Password is correct

## change the password to the previous keychain
expect -c "
spawn /bin/launchctl asuser $loggedInUID sudo -iu $username security set-keychain-password $short_renamed
expect \"Old Password:\"
send ${previousPass}\r
expect \"New Password:\"
send ${currentPass}\r
expect \"Retype New Password:\"
send ${currentPass}\r
expect"

## Make a keychain archive on the users desktop
mkdir /Users/$username/Desktop/Keychain\ Archive

## move the login keychain to the archive
mv /Users/$username/Library/Keychains/login.keychain-db /Users/$username/Desktop/Keychain\ Archive/login.keychain-db
## copy the renamed keychain to the archive
cp /Users/$username/Library/Keychains/$short_renamed /Users/$username/Desktop/Keychain\ Archive/$short_renamed
## wipe current keychain list
/bin/launchctl asuser $loggedInUID sudo -iu "$username" security list-keychains -s none
## rename the renamed keychain to login
mv $renamed /Users/$username/Library/Keychains/login.keychain-db
## add the login keychain to the list.
/bin/launchctl asuser $loggedInUID sudo -iu "$username" security list-keychains -s login.keychain-db

##unlock keychain
expect -c "
spawn /bin/launchctl asuser $loggedInUID sudo -iu $username security unlock-keychain login.keychain-db
expect \"password to unlock $renamed\"
send ${currentPass}\r
expect"

## set that keychain to the default keychain
result=$(/bin/launchctl asuser "$loggedInUID" sudo -iu "$username" security default-keychain -s "login.keychain-db")
if [[ -z $result ]] ; then
	dialog="Updating Old Keychain is complete. Recommended to verify keychain looks correct then reboot the computer"
else
	echo "$result"
	dialog="$result"
fi
cmd="Tell app \"System Events\" to display dialog \"$dialog\""
/usr/bin/osascript -e "$cmd"

exit 0