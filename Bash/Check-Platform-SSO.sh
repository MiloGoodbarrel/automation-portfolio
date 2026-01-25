#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 1-25-2026                           #
# Updated: 1-25-2026                           #
################################################
#
# NAME
#   Check-Platform-SSO.sh
#
# DESCRIPTION
#   Verify Platform SSO (Azure AD/Entra ID) integration health
#   Report token status, SSO configuration, and authentication state
#
# USAGE
#   Deploy via JAMF Pro as compliance check
#   Run from Self Service for user troubleshooting
#
# REQUIREMENTS
#   - macOS Ventura 13.x or later
#   - Platform SSO configured via MDM/JAMF
#   - Extensible SSO extension installed (Microsoft or Okta)
#
# NOTES
#   - Platform SSO replaces traditional AD binding
#   - Enables seamless authentication to Azure AD resources
#   - Supports Touch ID/Face ID for authentication
#

# Variables
LOG_FILE="/var/log/platform-sso-check.log"
SSO_PLIST="/Library/Preferences/com.apple.security.enterprisesso.plist"

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "=== Platform SSO Health Check ==="

# Check macOS version (Platform SSO requires Ventura 13.x+)
os_version=$(sw_vers -productVersion | awk -F. '{print $1}')
os_full_version=$(sw_vers -productVersion)

log_message "macOS version: $os_full_version"

if [ "$os_version" -lt 13 ]; then
    log_message "ERROR: Platform SSO requires macOS Ventura 13.x or later"
    osascript -e "display dialog \"Platform SSO is not available on macOS $os_full_version.\n\nRequires: macOS Ventura 13.0 or later\n\nCurrent version does not support Platform SSO.\" buttons {\"OK\"} default button 1 with icon stop with title \"Platform SSO Not Supported\""
    exit 1
fi

# Check if Platform SSO plist exists
if [ -f "$SSO_PLIST" ]; then
    log_message "Platform SSO configuration file found"
    
    # Read SSO configuration
    sso_enabled=$(defaults read "$SSO_PLIST" SSOEnabled 2>/dev/null)
    
    if [ "$sso_enabled" = "1" ]; then
        log_message "Platform SSO is ENABLED"
    else
        log_message "Platform SSO configuration exists but may not be active"
    fi
else
    log_message "WARNING: Platform SSO configuration file not found"
    log_message "Platform SSO may not be configured on this device"
fi

# Check for SSO extension using app-sso command (macOS 13+)
if command -v app-sso >/dev/null 2>&1; then
    log_message "Checking Platform SSO status via app-sso command..."
    
    sso_status=$(app-sso platform -s 2>&1)
    
    if echo "$sso_status" | grep -iq "configured"; then
        log_message "Platform SSO is CONFIGURED"
        log_message "$sso_status"
        
        # Check if user is signed in
        if echo "$sso_status" | grep -iq "signed in\|authenticated"; then
            log_message "User is SIGNED IN to Platform SSO"
            
            osascript -e 'display dialog "Platform SSO Status: Active ✓\n\nYou are signed in to Azure AD/Entra ID.\n\nSeamless authentication is enabled for:\n- Microsoft 365\n- Corporate web apps\n- Windows file shares (SMB)\n- Conditional Access compliance" buttons {"OK"} default button 1 with icon note with title "Platform SSO: Healthy"'
            exit 0
        else
            log_message "WARNING: Platform SSO configured but user not signed in"
            
            osascript -e 'display dialog "Platform SSO is configured but you are not signed in.\n\nPlease sign in to enable seamless authentication.\n\nGo to:\nSystem Settings > Users & Groups > [Your Account]" buttons {"OK"} default button 1 with icon caution with title "Platform SSO: Sign-In Required"'
            exit 2
        fi
    else
        log_message "Platform SSO is NOT configured"
        log_message "$sso_status"
        
        osascript -e 'display dialog "Platform SSO is not configured on this Mac.\n\nTo enable Azure AD/Entra ID integration:\n1. Contact IT to deploy Platform SSO profile via JAMF\n2. Requires Extensible SSO configuration profile\n3. Enables seamless authentication to Microsoft 365 and corporate resources" buttons {"OK"} default button 1 with icon caution with title "Platform SSO: Not Configured"'
        exit 3
    fi
else
    log_message "WARNING: app-sso command not available"
    log_message "This is unexpected on macOS Ventura+"
fi

# Check for Microsoft Company Portal (common SSO extension provider)
company_portal_installed=$(ls /Applications/ | grep -i "Company Portal")

if [ -n "$company_portal_installed" ]; then
    log_message "Microsoft Company Portal installed: $company_portal_installed"
    
    # Check if extension is loaded
    extension_loaded=$(pluginkit -m -A -D -i com.microsoft.CompanyPortalMac.ssoextension 2>/dev/null)
    
    if [ -n "$extension_loaded" ]; then
        log_message "Company Portal SSO extension is loaded"
    else
        log_message "WARNING: Company Portal installed but extension may not be active"
    fi
else
    log_message "WARNING: Microsoft Company Portal not installed"
    log_message "Platform SSO typically requires Company Portal for Azure AD integration"
fi

# Check MDM enrollment (Platform SSO requires MDM)
mdm_enrolled=$(profiles status -type enrollment 2>/dev/null | grep "Enrolled via DEP")

if [ -n "$mdm_enrolled" ]; then
    log_message "Device is enrolled in MDM via DEP/ADE"
else
    log_message "WARNING: Device may not be enrolled via DEP/ADE"
    log_message "Platform SSO works best with DEP/ADE enrollment"
fi

# Check for installed SSO profiles
sso_profiles=$(profiles list 2>/dev/null | grep -i "sso\|extensible")

if [ -n "$sso_profiles" ]; then
    log_message "SSO-related profiles found:"
    log_message "$sso_profiles"
else
    log_message "WARNING: No SSO-related configuration profiles detected"
fi

# Test Azure AD connectivity
log_message "Testing Azure AD connectivity..."
if curl -s --max-time 5 https://login.microsoftonline.com >/dev/null; then
    log_message "Azure AD login endpoint is reachable"
else
    log_message "WARNING: Cannot reach Azure AD login endpoint"
    log_message "This may indicate network connectivity issues"
fi

# Summary report
log_message "=== Platform SSO Health Check Complete ==="

# Provide detailed report to user
osascript -e "display dialog \"Platform SSO Health Check Complete\n\nDetailed results written to:\n$LOG_FILE\n\nReview the log for troubleshooting information.\" buttons {\"OK\"} default button 1 with icon note with title \"Platform SSO Check\""

exit 0
