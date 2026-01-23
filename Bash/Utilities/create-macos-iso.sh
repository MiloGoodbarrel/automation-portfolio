#!/usr/bin/env bash

################################################
# Author: Luis Ramirez                         #
# Created: 10-12-2019                          #
# Updated: 1-23-2026                           #
################################################
# 
# NAME
#   create-macos-iso.sh
#
# DESCRIPTION
#   Creates bootable macOS ISO image from App Store installer
#   Converts macOS installer to ISO format for virtualization
#   Designed for macOS High Sierra (adaptable to other versions)
#
# USAGE
#   ./create-macos-iso.sh
#
# NOTES
#   - Requires macOS installer in /Applications
#   - Creates 8.5GB temporary DMG
#   - Final ISO saved to ~/Desktop
#   - Works with official App Store installers only
#   - Useful for VM deployment (VMware, VirtualBox)
#

hdiutil create -o /tmp/High\ Sierra -size 8500m -volname High\ Sierra -layout SPUD -fs HFS+J
sleep 3
hdiutil attach /tmp/High\ Sierra.dmg -noverify -mountpoint /Volumes/High\ Sierra
sleep 3
sudo /Applications/Install\ macOS\ High\ Sierra.app/Contents/Resources/createinstallmedia  --volume /Volumes/High\ Sierra --nointeraction
sleep 3
hdiutil detach /volumes/Install\ macOS\ High\ Sierra
sleep 3
#mv /tmp/High\ Sierra.cdr.dmg /tmp/High\ Sierra.dmg
hdiutil convert /tmp/High\ Sierra.dmg -format UDTO -o /tmp/High\ Sierra.cdr
#hdiutil detach "/Volumes/Install macOS High\ Sierra"
sleep 3
mv /tmp/High\ Sierra.iso.cdr ~/Desktop/High\ Sierra.iso
#rm /tmp/High\ Sierra.dmg