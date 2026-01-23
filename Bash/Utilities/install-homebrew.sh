#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 5-8-2019                            #
# Updated: 1-23-2026                           #
################################################
#
# NAME
#   install-homebrew.sh
#
# DESCRIPTION
#   Installs Homebrew package manager on macOS.
#   Includes Xcode Command Line Tools installation if needed.
#
# USAGE
#   Deploy via JAMF policy for developer workstations
#
# NOTES
#   - Installs Xcode CLT if missing
#   - Runs as current console user (not root)
#   - Sets proper permissions
#   - Caffeinate prevents sleep during install
#   - Logs all actions
#

# Logging
LOGFOLDER="/private/var/log/"
LOG="${LOGFOLDER}homebrew-install.log"

# Ensure log directory exists
mkdir -p "$LOGFOLDER"

logme() {
    if [ -z "$1" ]; then
        echo "$(date) - logme function call error: no text passed to function!" | tee -a "$LOG"
        exit 1
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG"
}

logme "=== Homebrew Installation Started ==="

# Get console user
consoleuser=$(stat -f%Su /dev/console)
logme "Console user: $consoleuser"

# Caffeinate the Mac to prevent sleep
caffeinate -d -i -m -u &
caffeinatepid=$!
logme "Caffeinating Mac (PID: $caffeinatepid)"

# Check for Xcode Command Line Tools
logme "Checking for Xcode Command Line Tools"
check=$(pkgutil --pkgs | grep -c com.apple.pkg.CLTools_Executables)

if [ "$check" != 1 ]; then
    logme "Installing Xcode Command Line Tools"
    
    # Prompt softwareupdate to list CLT
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    
    clt=$(softwareupdate -l | \
        grep -B 1 -E "Command Line (Developer|Tools)" | \
        awk -F"*" '/^ +\*/ {print $2}' | \
        sed 's/^ *//' | \
        tail -n1)
    
    logme "Installing: $clt"
    softwareupdate -i "$clt" --verbose
    
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools
    
    logme "Xcode Command Line Tools installed"
else
    logme "Xcode Command Line Tools already installed"
fi

# Check if Homebrew is already installed
which -s brew
if [ $? = 1 ]; then
    logme "Homebrew not found - installing"
    
    # Download and install Homebrew
    logme "Downloading Homebrew from GitHub"
    curl -L https://github.com/Homebrew/brew/tarball/master | \
        tar xz --strip 1 -C /usr/local
    
    # Create necessary directories
    logme "Creating Homebrew directories"
    mkdir -p /usr/local/Cellar \
             /usr/local/Homebrew \
             /usr/local/Frameworks \
             /usr/local/bin \
             /usr/local/etc \
             /usr/local/include \
             /usr/local/lib \
             /usr/local/opt \
             /usr/local/sbin \
             /usr/local/share \
             /usr/local/share/zsh \
             /usr/local/share/zsh/site-functions \
             /usr/local/var
    
    # Set ownership to console user
    logme "Setting ownership to $consoleuser"
    chown -R "$consoleuser" /usr/local
    
    # Verify installation
    if [ -f /usr/local/bin/brew ]; then
        version=$(su -l "$consoleuser" -c "/usr/local/bin/brew --version" | head -n1)
        logme "Homebrew installed successfully: $version"
    else
        logme "ERROR: Homebrew installation failed"
        kill $caffeinatepid
        exit 1
    fi
else
    # Update existing Homebrew
    logme "Homebrew already installed - updating"
    su -l "$consoleuser" -c "/usr/local/bin/brew update"
    version=$(su -l "$consoleuser" -c "/usr/local/bin/brew --version" | head -n1)
    logme "Homebrew updated: $version"
fi

# Run brew doctor
logme "Running brew doctor"
su -l "$consoleuser" -c "/usr/local/bin/brew doctor" >> "$LOG" 2>&1

# Kill caffeinate process
kill $caffeinatepid
logme "Decaffeinated Mac"

logme "=== Homebrew Installation Complete ==="
exit 0
