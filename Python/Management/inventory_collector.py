#!/usr/bin/env python3

################################################
# Author: Luis Ramirez                         #
# Created: 7-22-2021                           #
# Updated: 1-23-2026                           #
################################################
"""
NAME
    inventory_collector.py

DESCRIPTION
    Cross-platform system inventory collector for Windows and macOS.
    Gathers hardware, OS, and software information for asset management.

USAGE
    python inventory_collector.py --output json
    python inventory_collector.py --output csv --file inventory.csv
    python inventory_collector.py --upload https://cmdb.company.com/api/inventory

NOTES
    - Works on Windows, macOS, and Linux
    - Outputs JSON or CSV format
    - Can POST to CMDB API
    - Gathers: hostname, OS, CPU, RAM, disk, serial, installed apps
    - JAMF/SCCM compatible output format
"""

import platform
import subprocess
import socket
import json
import csv
import argparse
import sys
from datetime import datetime
from pathlib import Path

try:
    import requests
except ImportError:
    requests = None


class InventoryCollector:
    """Cross-platform system inventory collector"""
    
    def __init__(self):
        self.system = platform.system()
        self.inventory = {}
        
    def collect_basic_info(self):
        """Collect basic system information"""
        self.inventory['timestamp'] = datetime.now().isoformat()
        self.inventory['hostname'] = socket.gethostname()
        self.inventory['fqdn'] = socket.getfqdn()
        self.inventory['os_type'] = self.system
        self.inventory['os_version'] = platform.version()
        self.inventory['os_release'] = platform.release()
        self.inventory['architecture'] = platform.machine()
        self.inventory['processor'] = platform.processor()
        
    def collect_mac_info(self):
        """Collect macOS-specific information"""
        try:
            # Get serial number
            result = subprocess.run(
                ['system_profiler', 'SPHardwareDataType'],
                capture_output=True,
                text=True
            )
            
            for line in result.stdout.split('\n'):
                if 'Serial Number' in line:
                    self.inventory['serial_number'] = line.split(':')[1].strip()
                elif 'Model Identifier' in line:
                    self.inventory['model'] = line.split(':')[1].strip()
                elif 'Total Number of Cores' in line:
                    self.inventory['cpu_cores'] = line.split(':')[1].strip()
                elif 'Memory' in line:
                    self.inventory['memory'] = line.split(':')[1].strip()
            
            # Get disk info
            result = subprocess.run(
                ['diskutil', 'info', '/'],
                capture_output=True,
                text=True
            )
            
            for line in result.stdout.split('\n'):
                if 'Disk Size' in line:
                    self.inventory['disk_size'] = line.split(':')[1].strip()
                elif 'Volume Free Space' in line:
                    self.inventory['disk_free'] = line.split(':')[1].strip()
                    
        except Exception as e:
            print(f"Error collecting macOS info: {e}", file=sys.stderr)
    
    def collect_windows_info(self):
        """Collect Windows-specific information"""
        try:
            # Get serial number
            result = subprocess.run(
                ['wmic', 'bios', 'get', 'serialnumber'],
                capture_output=True,
                text=True
            )
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1:
                self.inventory['serial_number'] = lines[1].strip()
            
            # Get model
            result = subprocess.run(
                ['wmic', 'computersystem', 'get', 'model'],
                capture_output=True,
                text=True
            )
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1:
                self.inventory['model'] = lines[1].strip()
            
            # Get CPU info
            result = subprocess.run(
                ['wmic', 'cpu', 'get', 'NumberOfCores'],
                capture_output=True,
                text=True
            )
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1:
                self.inventory['cpu_cores'] = lines[1].strip()
            
            # Get memory info (in GB)
            result = subprocess.run(
                ['wmic', 'computersystem', 'get', 'TotalPhysicalMemory'],
                capture_output=True,
                text=True
            )
            lines = result.stdout.strip().split('\n')
            if len(lines) > 1:
                memory_bytes = int(lines[1].strip())
                memory_gb = round(memory_bytes / (1024**3), 2)
                self.inventory['memory'] = f"{memory_gb} GB"
            
            # Get disk info
            result = subprocess.run(
                ['wmic', 'logicaldisk', 'where', 'DeviceID="C:"', 'get', 'Size,FreeSpace'],
                capture_output=True,
                text=True
            )
            lines = [l.strip() for l in result.stdout.strip().split('\n') if l.strip()]
            if len(lines) > 1:
                parts = lines[1].split()
                if len(parts) >= 2:
                    free_gb = round(int(parts[0]) / (1024**3), 2)
                    size_gb = round(int(parts[1]) / (1024**3), 2)
                    self.inventory['disk_free'] = f"{free_gb} GB"
                    self.inventory['disk_size'] = f"{size_gb} GB"
                    
        except Exception as e:
            print(f"Error collecting Windows info: {e}", file=sys.stderr)
    
    def collect_installed_apps(self):
        """Collect list of installed applications"""
        apps = []
        
        if self.system == 'Darwin':  # macOS
            try:
                result = subprocess.run(
                    ['system_profiler', 'SPApplicationsDataType', '-json'],
                    capture_output=True,
                    text=True
                )
                data = json.loads(result.stdout)
                
                for app in data.get('SPApplicationsDataType', []):
                    apps.append({
                        'name': app.get('_name'),
                        'version': app.get('version'),
                        'vendor': app.get('obtained_from')
                    })
            except Exception as e:
                print(f"Error collecting macOS apps: {e}", file=sys.stderr)
                
        elif self.system == 'Windows':
            try:
                result = subprocess.run(
                    ['wmic', 'product', 'get', 'Name,Version,Vendor'],
                    capture_output=True,
                    text=True,
                    timeout=30
                )
                
                lines = [l.strip() for l in result.stdout.split('\n') if l.strip()]
                # Skip header
                for line in lines[1:]:
                    parts = line.split(maxsplit=2)
                    if len(parts) >= 2:
                        apps.append({
                            'name': parts[0],
                            'version': parts[1],
                            'vendor': parts[2] if len(parts) > 2 else ''
                        })
            except subprocess.TimeoutExpired:
                print("Warning: WMIC timeout - some apps may not be listed", file=sys.stderr)
            except Exception as e:
                print(f"Error collecting Windows apps: {e}", file=sys.stderr)
        
        self.inventory['installed_apps_count'] = len(apps)
        self.inventory['installed_apps'] = apps[:50]  # Limit to first 50
    
    def collect_all(self):
        """Collect all inventory information"""
        print(f"Collecting inventory for {self.system} system...")
        
        self.collect_basic_info()
        
        if self.system == 'Darwin':
            self.collect_mac_info()
        elif self.system == 'Windows':
            self.collect_windows_info()
        
        self.collect_installed_apps()
        
        return self.inventory


def export_json(inventory, filename=None):
    """Export inventory to JSON format"""
    json_data = json.dumps(inventory, indent=2)
    
    if filename:
        with open(filename, 'w') as f:
            f.write(json_data)
        print(f"Inventory exported to {filename}")
    else:
        print(json_data)


def export_csv(inventory, filename='inventory.csv'):
    """Export inventory to CSV format"""
    # Flatten inventory for CSV (exclude apps list)
    flat_inventory = {k: v for k, v in inventory.items() if k != 'installed_apps'}
    
    with open(filename, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=flat_inventory.keys())
        writer.writeheader()
        writer.writerow(flat_inventory)
    
    print(f"Inventory exported to {filename}")


def upload_to_api(inventory, url, api_key=None):
    """Upload inventory to CMDB API"""
    if requests is None:
        print("Error: requests module required for API upload. Install: pip install requests")
        return False
    
    headers = {'Content-Type': 'application/json'}
    if api_key:
        headers['Authorization'] = f'Bearer {api_key}'
    
    try:
        response = requests.post(url, json=inventory, headers=headers, timeout=10)
        response.raise_for_status()
        print(f"Inventory uploaded successfully to {url}")
        return True
    except requests.RequestException as e:
        print(f"Error uploading inventory: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description='Cross-platform system inventory collector')
    parser.add_argument('--output', choices=['json', 'csv'], default='json',
                        help='Output format (default: json)')
    parser.add_argument('--file', help='Output filename')
    parser.add_argument('--upload', help='Upload to API endpoint URL')
    parser.add_argument('--api-key', help='API key for authentication')
    parser.add_argument('--no-apps', action='store_true',
                        help='Skip installed applications (faster)')
    
    args = parser.parse_args()
    
    # Collect inventory
    collector = InventoryCollector()
    inventory = collector.collect_all()
    
    if args.no_apps:
        inventory.pop('installed_apps', None)
        inventory.pop('installed_apps_count', None)
    
    # Output inventory
    if args.upload:
        upload_to_api(inventory, args.upload, args.api_key)
    elif args.output == 'json':
        export_json(inventory, args.file)
    elif args.output == 'csv':
        filename = args.file or 'inventory.csv'
        export_csv(inventory, filename)
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
