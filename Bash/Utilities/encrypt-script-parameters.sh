#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 7-22-2019                           #
# Updated: 1-23-2026                           #
################################################
# 
# NAME
#   encrypt-script-parameters.sh
#
# DESCRIPTION
#   Encrypts script parameters using OpenSSL for secure credential passing
#   Provides functions to generate and decrypt encrypted strings
#   Used with JAMF Pro to secure passwords in script parameters
#
# USAGE
#   Source functions in your script:
#   GenerateEncryptedString "MyPassword"  # Run locally to get encrypted value
#   DecryptString "EncryptedValue" "Salt" "Passphrase"  # In deployed script
#
# NOTES
#   - DO NOT include GenerateEncryptedString() in production scripts
#   - Store Salt and Passphrase securely in your script
#   - Additional security layer for JSS parameter passing
#

# Use GenerateEncryptedString() locally - DO NOT include in the script!
# The 'Encrypted String' will become a parameter for the script in the JSS
# The unique 'Salt' and 'Passphrase' values will be present in your script
function GenerateEncryptedString() {
    # Usage ~$ GenerateEncryptedString "String"
    local STRING="${1}"
    local SALT=$(openssl rand -hex 8)
    local K=$(openssl rand -hex 12)
    local ENCRYPTED=$(echo "${STRING}" | openssl enc -aes256 -a -A -S "${SALT}" -k "${K}")
    echo "Encrypted String: ${ENCRYPTED}"
    echo "Salt: ${SALT} | Passphrase: ${K}"
}

# Include DecryptString() with your script to decrypt the password sent by the JSS
# The 'Salt' and 'Passphrase' values would be present in the script
function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String" "Salt" "Passphrase"
    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "${2}" -k "${3}"
}

# Alternative format for DecryptString function
#function DecryptString() {
    # Usage: ~$ DecryptString "Encrypted String"
#    local SALT=""
#    local K=""
#    echo "${1}" | /usr/bin/openssl enc -aes256 -d -a -A -S "$SALT" -k "$K"
#}


echo "New Password"
GenerateEncryptedString "P01\$0n3d@ppl3@nt1d0t3"
echo " "
echo "Old Password"
GenerateEncryptedString "S@lm0n!"




