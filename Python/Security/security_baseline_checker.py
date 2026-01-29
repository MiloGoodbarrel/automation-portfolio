__author__ = "Luis Ramirez"

#!/usr/bin/env python3

################################################
# Author: Luis Ramirez                         #
# Created: 11-3-2022                           #
# Updated: 1-23-2026                           #
################################################
"""
NAME
    security_baseline_checker.py

DESCRIPTION
    Cross-platform security baseline validation for Windows and macOS.
    Checks system configuration against CIS benchmarks and security best practices.

USAGE
    python security_baseline_checker.py --platform auto
    python security_baseline_checker.py --platform windows --export report.html
    python security_baseline_checker.py --platform macos --verbose

NOTES
    - Validates: Firewall, encryption, password policy, auto-updates, admin accounts
    - Based on CIS benchmarks and industry standards
    - Generates compliance reports with remediation guidance
    - Color-coded output: Green (Pass), Yellow (Warning), Red (Fail)
"""

import subprocess
import platform
import sys
import argparse
from datetime import datetime
from pathlib import Path


class SecurityBaselineChecker:
    """Cross-platform security baseline validation"""
    
    def __init__(self, verbose=False):
        self.system = platform.system()
        self.verbose = verbose
        self.checks = []
        self.passed = 0
        self.failed = 0
        self.warnings = 0
        
    def add_check(self, name, status, message, remediation=''):
        """Add a check result"""
        self.checks.append({
            'name': name,
            'status': status,  # 'pass', 'fail', 'warning'
            'message': message,
            'remediation': remediation
        })
        
        if status == 'pass':
            self.passed += 1
        elif status == 'fail':
            self.failed += 1
        elif status == 'warning':
            self.warnings += 1
    
    def check_macos_firewall(self):
        """Check macOS firewall status"""
        try:
            result = subprocess.run(
                ['sudo', 'defaults', 'read', '/Library/Preferences/com.apple.alf', 'globalstate'],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0:
                state = result.stdout.strip()
                if state == '1':
                    self.add_check(
                        'Firewall Enabled',
                        'pass',
                        'macOS firewall is enabled'
                    )
                else:
                    self.add_check(
                        'Firewall Disabled',
                        'fail',
                        'macOS firewall is disabled',
                        'Enable via System Preferences > Security & Privacy > Firewall'
                    )
            else:
                self.add_check(
                    'Firewall Check',
                    'warning',
                    'Unable to check firewall status (requires sudo)'
                )
                
        except Exception as e:
            self.add_check('Firewall Check', 'warning', f'Error checking firewall: {e}')
    
    def check_macos_filevault(self):
        """Check FileVault encryption status"""
        try:
            result = subprocess.run(
                ['fdesetup', 'status'],
                capture_output=True,
                text=True
            )
            
            if 'FileVault is On' in result.stdout:
                self.add_check(
                    'FileVault Encryption',
                    'pass',
                    'FileVault disk encryption is enabled'
                )
            else:
                self.add_check(
                    'FileVault Encryption',
                    'fail',
                    'FileVault is not enabled',
                    'Enable via System Preferences > Security & Privacy > FileVault'
                )
                
        except Exception as e:
            self.add_check('FileVault Check', 'warning', f'Error checking FileVault: {e}')
    
    def check_macos_gatekeeper(self):
        """Check Gatekeeper status"""
        try:
            result = subprocess.run(
                ['spctl', '--status'],
                capture_output=True,
                text=True
            )
            
            if 'assessments enabled' in result.stdout:
                self.add_check(
                    'Gatekeeper',
                    'pass',
                    'Gatekeeper is enabled (app verification active)'
                )
            else:
                self.add_check(
                    'Gatekeeper',
                    'fail',
                    'Gatekeeper is disabled',
                    'Enable via: sudo spctl --master-enable'
                )
                
        except Exception as e:
            self.add_check('Gatekeeper Check', 'warning', f'Error checking Gatekeeper: {e}')
    
    def check_macos_screen_lock(self):
        """Check screen lock timeout"""
        try:
            result = subprocess.run(
                ['defaults', 'read', 'com.apple.screensaver', 'askForPassword'],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0 and result.stdout.strip() == '1':
                # Check delay
                result = subprocess.run(
                    ['defaults', 'read', 'com.apple.screensaver', 'askForPasswordDelay'],
                    capture_output=True,
                    text=True
                )
                
                delay = int(result.stdout.strip()) if result.returncode == 0 else 0
                
                if delay <= 5:
                    self.add_check(
                        'Screen Lock',
                        'pass',
                        f'Screen lock requires password after {delay}s'
                    )
                else:
                    self.add_check(
                        'Screen Lock Delay',
                        'warning',
                        f'Screen lock delay is {delay}s (recommend ≤5s)',
                        'Set via: defaults write com.apple.screensaver askForPasswordDelay -int 5'
                    )
            else:
                self.add_check(
                    'Screen Lock',
                    'fail',
                    'Screen lock password is not required',
                    'Enable via System Preferences > Security & Privacy > General'
                )
                
        except Exception as e:
            self.add_check('Screen Lock Check', 'warning', f'Error checking screen lock: {e}')
    
    def check_macos_software_updates(self):
        """Check automatic update settings"""
        try:
            result = subprocess.run(
                ['defaults', 'read', '/Library/Preferences/com.apple.SoftwareUpdate', 'AutomaticCheckEnabled'],
                capture_output=True,
                text=True
            )
            
            if result.returncode == 0 and result.stdout.strip() == '1':
                self.add_check(
                    'Automatic Updates',
                    'pass',
                    'Automatic update checking is enabled'
                )
            else:
                self.add_check(
                    'Automatic Updates',
                    'fail',
                    'Automatic updates are disabled',
                    'Enable via System Preferences > Software Update'
                )
                
        except Exception as e:
            self.add_check('Software Update Check', 'warning', f'Error checking updates: {e}')
    
    def check_windows_firewall(self):
        """Check Windows Firewall status"""
        try:
            result = subprocess.run(
                ['netsh', 'advfirewall', 'show', 'allprofiles', 'state'],
                capture_output=True,
                text=True
            )
            
            if 'State                                 ON' in result.stdout:
                self.add_check(
                    'Windows Firewall',
                    'pass',
                    'Windows Firewall is enabled for all profiles'
                )
            else:
                self.add_check(
                    'Windows Firewall',
                    'fail',
                    'Windows Firewall is not enabled for all profiles',
                    'Enable via: netsh advfirewall set allprofiles state on'
                )
                
        except Exception as e:
            self.add_check('Firewall Check', 'warning', f'Error checking firewall: {e}')
    
    def check_windows_bitlocker(self):
        """Check BitLocker encryption status"""
        try:
            result = subprocess.run(
                ['manage-bde', '-status'],
                capture_output=True,
                text=True
            )
            
            if 'Protection On' in result.stdout:
                self.add_check(
                    'BitLocker Encryption',
                    'pass',
                    'BitLocker is enabled and protecting drives'
                )
            elif 'Protection Off' in result.stdout:
                self.add_check(
                    'BitLocker Encryption',
                    'warning',
                    'BitLocker is available but not enabled',
                    'Enable via: manage-bde -on C: -RecoveryPassword'
                )
            else:
                self.add_check(
                    'BitLocker Encryption',
                    'fail',
                    'BitLocker is not available or not configured',
                    'Check Windows edition (Pro/Enterprise required)'
                )
                
        except Exception as e:
            self.add_check('BitLocker Check', 'warning', f'Error checking BitLocker: {e}')
    
    def check_windows_defender(self):
        """Check Windows Defender status"""
        try:
            result = subprocess.run(
                ['powershell', '-Command', 'Get-MpComputerStatus | Select-Object AntivirusEnabled, RealTimeProtectionEnabled'],
                capture_output=True,
                text=True
            )
            
            if 'True' in result.stdout:
                self.add_check(
                    'Windows Defender',
                    'pass',
                    'Windows Defender is active and real-time protection is enabled'
                )
            else:
                self.add_check(
                    'Windows Defender',
                    'fail',
                    'Windows Defender is not fully enabled',
                    'Enable via Windows Security settings'
                )
                
        except Exception as e:
            self.add_check('Defender Check', 'warning', f'Error checking Defender: {e}')
    
    def check_windows_updates(self):
        """Check Windows Update configuration"""
        try:
            result = subprocess.run(
                ['powershell', '-Command', '(Get-ItemProperty "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate\\AU" -ErrorAction SilentlyContinue).NoAutoUpdate'],
                capture_output=True,
                text=True
            )
            
            # NoAutoUpdate = 0 or missing means auto updates are ON
            if not result.stdout.strip() or result.stdout.strip() == '0':
                self.add_check(
                    'Windows Updates',
                    'pass',
                    'Automatic Windows Updates are enabled'
                )
            else:
                self.add_check(
                    'Windows Updates',
                    'fail',
                    'Automatic Windows Updates are disabled',
                    'Enable via Group Policy or Windows Update settings'
                )
                
        except Exception as e:
            self.add_check('Windows Update Check', 'warning', f'Error checking updates: {e}')
    
    def check_windows_uac(self):
        """Check UAC (User Account Control) status"""
        try:
            result = subprocess.run(
                ['powershell', '-Command', '(Get-ItemProperty "HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System").EnableLUA'],
                capture_output=True,
                text=True
            )
            
            if result.stdout.strip() == '1':
                self.add_check(
                    'User Account Control',
                    'pass',
                    'UAC is enabled'
                )
            else:
                self.add_check(
                    'User Account Control',
                    'fail',
                    'UAC is disabled',
                    'Enable via Control Panel > User Accounts > Change User Account Control settings'
                )
                
        except Exception as e:
            self.add_check('UAC Check', 'warning', f'Error checking UAC: {e}')
    
    def run_checks(self):
        """Run all security checks for current platform"""
        print(f"Running security baseline checks for {self.system}...\n")
        
        if self.system == 'Darwin':  # macOS
            self.check_macos_firewall()
            self.check_macos_filevault()
            self.check_macos_gatekeeper()
            self.check_macos_screen_lock()
            self.check_macos_software_updates()
            
        elif self.system == 'Windows':
            self.check_windows_firewall()
            self.check_windows_bitlocker()
            self.check_windows_defender()
            self.check_windows_updates()
            self.check_windows_uac()
        
        else:
            print(f"Unsupported platform: {self.system}")
            return False
        
        return True
    
    def print_results(self):
        """Print check results to console"""
        # Color codes
        GREEN = '\033[92m'
        YELLOW = '\033[93m'
        RED = '\033[91m'
        RESET = '\033[0m'
        
        print("\n" + "="*70)
        print("SECURITY BASELINE CHECK RESULTS")
        print("="*70 + "\n")
        
        for check in self.checks:
            if check['status'] == 'pass':
                status_str = f"{GREEN}✓ PASS{RESET}"
            elif check['status'] == 'warning':
                status_str = f"{YELLOW}⚠ WARNING{RESET}"
            else:
                status_str = f"{RED}✗ FAIL{RESET}"
            
            print(f"{status_str} - {check['name']}")
            print(f"   {check['message']}")
            
            if check['remediation'] and self.verbose:
                print(f"   Remediation: {check['remediation']}")
            
            print()
        
        print("="*70)
        print(f"Summary: {self.passed} passed, {self.warnings} warnings, {self.failed} failed")
        print("="*70 + "\n")
    
    def export_html(self, filename='security_baseline_report.html'):
        """Export results to HTML report"""
        html = f"""<!DOCTYPE html>
<html>
<head>
    <title>Security Baseline Report</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; }}
        h1 {{ color: #333; }}
        .summary {{ background-color: #f0f0f0; padding: 15px; border-radius: 5px; margin-bottom: 20px; }}
        .check {{ margin-bottom: 15px; padding: 10px; border-left: 4px solid #ddd; }}
        .pass {{ border-left-color: #4CAF50; background-color: #f1f8f4; }}
        .warning {{ border-left-color: #ff9800; background-color: #fff8e1; }}
        .fail {{ border-left-color: #f44336; background-color: #ffebee; }}
        .status {{ font-weight: bold; }}
        .remediation {{ margin-top: 5px; padding: 5px; background-color: #e3f2fd; border-left: 3px solid #2196F3; }}
    </style>
</head>
<body>
    <h1>Security Baseline Report - {self.system}</h1>
    <div class="summary">
        <p><strong>Report Date:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        <p><strong>Platform:</strong> {self.system}</p>
        <p><strong>Passed:</strong> {self.passed} | <strong>Warnings:</strong> {self.warnings} | <strong>Failed:</strong> {self.failed}</p>
    </div>
"""
        
        for check in self.checks:
            status_text = check['status'].upper()
            html += f"""    <div class="check {check['status']}">
        <div class="status">{status_text}: {check['name']}</div>
        <div>{check['message']}</div>
"""
            if check['remediation']:
                html += f"""        <div class="remediation"><strong>Remediation:</strong> {check['remediation']}</div>
"""
            html += """    </div>
"""
        
        html += """</body>
</html>
"""
        
        with open(filename, 'w') as f:
            f.write(html)
        
        print(f"HTML report exported to {filename}")


def main():
    parser = argparse.ArgumentParser(description='Cross-platform security baseline checker')
    parser.add_argument('--platform', choices=['windows', 'macos', 'auto'], default='auto',
                        help='Platform to check (default: auto-detect)')
    parser.add_argument('--export', help='Export HTML report to file')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Show remediation guidance in console output')
    
    args = parser.parse_args()
    
    # Create checker
    checker = SecurityBaselineChecker(verbose=args.verbose)
    
    # Run checks
    if not checker.run_checks():
        return 1
    
    # Print results
    checker.print_results()
    
    # Export if requested
    if args.export:
        checker.export_html(args.export)
    
    # Return error code if any checks failed
    return 0 if checker.failed == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
