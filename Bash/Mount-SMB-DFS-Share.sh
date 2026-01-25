#!/bin/bash

################################################
# Author: Luis Ramirez                         #
# Created: 1-25-2026                           #
# Updated: 1-25-2026                           #
################################################
#
# NAME
#   Mount-SMB-DFS-Share.sh
#
# DESCRIPTION
#   Auto-mount Windows DFS shares on macOS with Kerberos/Platform SSO support
#   Handles both AD-bound Macs and Platform SSO (Azure AD) authentication
#
# USAGE
#   Deploy via JAMF Pro as login policy
#   Automatically mounts corporate file shares at user login
#
# REQUIREMENTS
#   - macOS Ventura 13.x or later (SMB3 support)
#   - Active Directory binding OR Platform SSO configured
#   - Network connectivity to Windows file servers
#
# JAMF PARAMETERS
#   $4 - DFS path (e.g., //domain.local/dfs/shares)
#   $5 - Mount point name (e.g., CompanyShares)
#   $6 - AD domain (e.g., CORP)
#
# NOTES
#   - Prefers Kerberos authentication (no password prompt)
#   - Falls back to manual credentials if Kerberos unavailable
#   - Creates Desktop alias for easy access
#   - SMB3-only for security compliance
#

# Variables
DFS_PATH="${4:-//domain.local/dfs/shares}"
MOUNT_NAME="${5:-CompanyShares}"
AD_DOMAIN="${6:-DOMAIN}"
MOUNT_POINT="/Volumes/$MOUNT_NAME"
LOG_FILE="/var/log/smb-mount.log"

# Get current user
current_user=$(stat -f "%Su" /dev/console)
user_uid=$(id -u "$current_user")
user_home=$(eval echo "~$current_user")

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "=== Starting SMB DFS Share Mount ==="
log_message "User: $current_user"
log_message "DFS Path: $DFS_PATH"
log_message "Mount Point: $MOUNT_POINT"

# Enforce SMB3 for security
if [ ! -f "/etc/nsmb.conf" ]; then
    log_message "Creating /etc/nsmb.conf for SMB3 enforcement"
    cat > /etc/nsmb.conf << EOF
[default]
smb_neg=smb3_only
signing_required=yes
port445=both
EOF
else
    log_message "/etc/nsmb.conf already exists"
fi

# Check if already mounted
if mount | grep -q "$MOUNT_POINT"; then
    log_message "Share already mounted at $MOUNT_POINT"
    exit 0
fi

# Create mount point if needed
if [ ! -d "$MOUNT_POINT" ]; then
    log_message "Creating mount point: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
fi

# Check if Mac is AD-bound (Kerberos available)
ad_bound=$(dscl localhost -list . 2>/dev/null | grep "Active Directory")

if [ -n "$ad_bound" ]; then
    log_message "Mac is AD-bound - using Kerberos authentication"
    
    # Renew Kerberos ticket for current user
    su - "$current_user" -c "kinit -R" 2>/dev/null
    
    kerberos_ticket=$(su - "$current_user" -c "klist" 2>/dev/null)
    
    if [ -n "$kerberos_ticket" ]; then
        log_message "Kerberos ticket active - attempting passwordless mount"
        
        # Mount with Kerberos (no password prompt)
        mount_smbfs -o nobrowse "smb:$DFS_PATH" "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"
        
        if [ $? -eq 0 ]; then
            log_message "SUCCESS: Mounted via Kerberos authentication"
        else
            log_message "ERROR: Kerberos mount failed - falling back to manual auth"
            # Fall through to manual authentication
        fi
    else
        log_message "WARNING: No Kerberos ticket found - falling back to manual auth"
    fi
fi

# Check Platform SSO status (alternative to AD binding)
if [ -z "$ad_bound" ]; then
    log_message "Mac is NOT AD-bound - checking for Platform SSO"
    
    sso_status=$(app-sso platform -s 2>&1 | grep -i "configured")
    
    if [ -n "$sso_status" ]; then
        log_message "Platform SSO detected - attempting SSO-based mount"
        
        # Platform SSO can provide OAuth tokens for SMB access
        # This requires Windows Server 2019+ with Azure AD integration
        mount_smbfs -o nobrowse,sec=krb5 "smb:$DFS_PATH" "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"
        
        if [ $? -eq 0 ]; then
            log_message "SUCCESS: Mounted via Platform SSO"
        else
            log_message "WARNING: Platform SSO mount failed - trying manual auth"
        fi
    else
        log_message "WARNING: Neither AD binding nor Platform SSO configured"
    fi
fi

# If not mounted yet, try manual authentication
if ! mount | grep -q "$MOUNT_POINT"; then
    log_message "Attempting manual authentication"
    
    # Prompt user for credentials
    username=$(osascript -e "display dialog \"Enter your domain username for:\\n$DFS_PATH\" default answer \"$current_user\" buttons {\"Cancel\", \"Connect\"} default button 2" -e 'text returned of result' 2>/dev/null)
    
    if [ -z "$username" ]; then
        log_message "User cancelled authentication"
        exit 1
    fi
    
    password=$(osascript -e "display dialog \"Enter password for $username:\" default answer \"\" buttons {\"Cancel\", \"Connect\"} default button 2 with hidden answer" -e 'text returned of result' 2>/dev/null)
    
    if [ -z "$password" ]; then
        log_message "User cancelled password entry"
        exit 1
    fi
    
    # Mount with explicit credentials
    log_message "Mounting with explicit credentials for user: $username"
    
    mount_smbfs -o nobrowse "//$AD_DOMAIN;$username:$password@${DFS_PATH#//}" "$MOUNT_POINT" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_message "ERROR: Manual authentication failed"
        osascript -e "display dialog \"Failed to connect to:\\n$DFS_PATH\\n\\nPlease verify:\\n- Username and password are correct\\n- VPN is connected (if required)\\n- File server is accessible\" buttons {\"OK\"} default button 1 with icon stop with title \"SMB Mount Failed\""
        exit 2
    fi
fi

# Verify mount success
if mount | grep -q "$MOUNT_POINT"; then
    log_message "SUCCESS: Share mounted at $MOUNT_POINT"
    
    # Set ownership to user
    chown "$current_user" "$MOUNT_POINT" 2>/dev/null
    
    # Create Desktop alias for easy access
    desktop_alias="$user_home/Desktop/$MOUNT_NAME"
    
    if [ ! -e "$desktop_alias" ]; then
        log_message "Creating Desktop alias: $desktop_alias"
        su - "$current_user" -c "ln -s '$MOUNT_POINT' '$desktop_alias'" 2>/dev/null
    fi
    
    # Show success message
    osascript -e "display dialog \"Successfully connected to:\\n$DFS_PATH\\n\\nMounted at:\\n$MOUNT_POINT\\n\\nA shortcut has been added to your Desktop.\" buttons {\"OK\"} default button 1 with icon note with title \"SMB Mount Successful\"" &
    
    exit 0
else
    log_message "ERROR: Mount verification failed"
    exit 3
fi

log_message "=== SMB Mount Complete ==="
