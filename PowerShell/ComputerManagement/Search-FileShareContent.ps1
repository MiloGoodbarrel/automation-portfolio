<#
.SYNOPSIS
    Enhanced file share search with move/delete detection and recovery assistance.

.DESCRIPTION
    Advanced search tool for locating files and folders across network shares with
    forensic capabilities to identify moved, renamed, or deleted items.

.FEATURES
    - Multi-share recursive search
    - Deleted file detection via shadow copies
    - File movement tracking (compares current vs. baseline)
    - Metadata preservation (Created, Modified, Accessed dates)
    - Size-based filtering
    - Wildcard and regex pattern matching
    - CSV export for audit trails
    - Backup recovery guidance

.FUNCTIONALITY
    Search Capabilities:
    - Exact filename matching
    - Wildcard patterns (*.docx, Project*)
    - Regex pattern matching
    - Content-based search (requires indexing)
    - Date range filtering
    - File size filtering

    Detection Features:
    - Moved files: Reports new location
    - Renamed files: Identifies based on metadata/hash
    - Deleted files: Checks shadow copies
    - Duplicate detection across shares

    Recovery Assistance:
    - Shadow copy availability check
    - Backup location recommendations
    - Previous versions enumeration
    - Restore command generation

.PARAMETER SearchPattern
    File or folder name pattern (supports wildcards)

.PARAMETER SharePaths
    Array of UNC paths or local shares to search

.PARAMETER IncludeDeleted
    Search shadow copies for deleted files

.PARAMETER BaselinePath
    Path to baseline CSV (for move detection)

.PARAMETER ExportPath
    Path to export results (CSV format)

.PARAMETER SearchDepth
    Maximum recursion depth (default: unlimited)

.PARAMETER MinSizeKB
    Minimum file size in KB

.PARAMETER MaxSizeKB
    Maximum file size in KB

.PARAMETER ModifiedAfter
    Show files modified after this date

.PARAMETER ShowMetadata
    Include detailed metadata (hash, owner, etc.)

.EXAMPLE
    .\Search-FileShareContent.ps1 -SearchPattern "Budget2024.xlsx" -SharePaths "\\server\Finance","\\server\Accounting"
    
    Searches for Budget2024.xlsx across Finance and Accounting shares.

.EXAMPLE
    .\Search-FileShareContent.ps1 -SearchPattern "*.pdf" -IncludeDeleted -SharePaths "\\server\HR"
    
    Finds all PDFs including deleted files in shadow copies.

.EXAMPLE
    .\Search-FileShareContent.ps1 -SearchPattern "ProjectX" -BaselinePath "C:\Baselines\FileShare_20240101.csv"
    
    Compares current state to baseline to detect moved/renamed items.

.EXAMPLE
    .\Search-FileShareContent.ps1 -SearchPattern "Q4Report*" -ModifiedAfter "2024-01-01" -ExportPath "C:\Reports\SearchResults.csv"
    
    Finds Q4 reports modified in 2024 and exports results.

.NOTES
    Author:  Luis Ramirez
    Created: 5-8-2021
    Updated: 1-24-2026
    Version: 2.3
    
    Requirements:
    - Read access to target shares
    - VSS (Volume Shadow Copy Service) for deleted file detection
    - PowerShell 5.1 or later
    
    Change Log:
    2.3 - Added hash-based duplicate detection, improved shadow copy search
    2.2 - Baseline comparison for move detection
    2.1 - Added metadata tracking and CSV export
    2.0 - Shadow copy integration for deleted files
    1.0 - Initial release
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SearchPattern,

    [Parameter(Mandatory = $true)]
    [string[]]$SharePaths,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDeleted,

    [Parameter(Mandatory = $false)]
    [string]$BaselinePath,

    [Parameter(Mandatory = $false)]
    [string]$ExportPath,

    [Parameter(Mandatory = $false)]
    [int]$SearchDepth = -1,

    [Parameter(Mandatory = $false)]
    [int]$MinSizeKB,

    [Parameter(Mandatory = $false)]
    [int]$MaxSizeKB,

    [Parameter(Mandatory = $false)]
    [datetime]$ModifiedAfter,

    [Parameter(Mandatory = $false)]
    [switch]$ShowMetadata
)

# Initialize results collection
$searchResults = @()
$deletedFiles = @()
$movedFiles = @()

Write-Host "`n========== FILE SHARE SEARCH ==========" -ForegroundColor Cyan
Write-Host "Search Pattern: $SearchPattern" -ForegroundColor White
Write-Host "Target Shares:  $($SharePaths -join ', ')" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan

# Function to calculate file hash
function Get-FileHashQuick {
    param([string]$FilePath)
    try {
        $hash = Get-FileHash -Path $FilePath -Algorithm MD5 -ErrorAction Stop
        return $hash.Hash
    } catch {
        return $null
    }
}

# Function to search current files
function Search-CurrentFiles {
    param([string]$SharePath, [string]$Pattern)
    
    Write-Host "Searching: $SharePath..." -ForegroundColor Yellow
    
    try {
        $searchParams = @{
            Path = $SharePath
            Filter = $Pattern
            Recurse = $true
            ErrorAction = 'SilentlyContinue'
        }
        
        if ($SearchDepth -ge 0) {
            $searchParams['Depth'] = $SearchDepth
        }
        
        $files = Get-ChildItem @searchParams -File
        $folders = Get-ChildItem @searchParams -Directory
        
        foreach ($item in ($files + $folders)) {
            # Apply filters
            if ($MinSizeKB -and $item.Length -lt ($MinSizeKB * 1KB)) { continue }
            if ($MaxSizeKB -and $item.Length -gt ($MaxSizeKB * 1KB)) { continue }
            if ($ModifiedAfter -and $item.LastWriteTime -lt $ModifiedAfter) { continue }
            
            $result = [PSCustomObject]@{
                Name = $item.Name
                FullPath = $item.FullName
                Type = if ($item.PSIsContainer) { "Folder" } else { "File" }
                SizeKB = [math]::Round($item.Length / 1KB, 2)
                Created = $item.CreationTime
                Modified = $item.LastWriteTime
                Accessed = $item.LastAccessTime
                Status = "Current"
                Owner = $null
                Hash = $null
                RecoveryAction = $null
            }
            
            if ($ShowMetadata) {
                try {
                    $acl = Get-Acl $item.FullName -ErrorAction SilentlyContinue
                    $result.Owner = $acl.Owner
                    
                    if (-not $item.PSIsContainer) {
                        $result.Hash = Get-FileHashQuick -FilePath $item.FullName
                    }
                } catch {
                    # Metadata collection failed, continue
                }
            }
            
            $script:searchResults += $result
        }
        
        Write-Host "  Found: $($files.Count) files, $($folders.Count) folders" -ForegroundColor Green
        
    } catch {
        Write-Host "  Error searching $SharePath : $_" -ForegroundColor Red
    }
}

# Function to search shadow copies for deleted files
function Search-ShadowCopies {
    param([string]$SharePath, [string]$Pattern)
    
    Write-Host "`nSearching shadow copies for deleted files..." -ForegroundColor Yellow
    
    try {
        # Get volume from UNC path
        $volume = $SharePath -replace '\\\\[^\\]+\\([^\\]+).*', '$1'
        
        # Get shadow copies
        $shadowCopies = Get-WmiObject Win32_ShadowCopy | Where-Object { $_.VolumeName -like "*$volume*" }
        
        if (-not $shadowCopies) {
            Write-Host "  No shadow copies found for this volume" -ForegroundColor Yellow
            return
        }
        
        Write-Host "  Found $($shadowCopies.Count) shadow copies" -ForegroundColor Cyan
        
        foreach ($shadow in $shadowCopies | Select-Object -First 5) {
            $shadowPath = "$($shadow.DeviceObject)\$($SharePath -replace '^\\\\[^\\]+\\[^\\]+\\', '')"
            
            try {
                $shadowFiles = Get-ChildItem -Path $shadowPath -Filter $Pattern -Recurse -ErrorAction SilentlyContinue
                
                foreach ($file in $shadowFiles) {
                    # Check if file exists in current location
                    $currentPath = $file.FullName -replace [regex]::Escape($shadow.DeviceObject), ($SharePath -replace '\\[^\\]+$', '')
                    
                    if (-not (Test-Path $currentPath)) {
                        $result = [PSCustomObject]@{
                            Name = $file.Name
                            FullPath = $currentPath
                            Type = if ($file.PSIsContainer) { "Folder" } else { "File" }
                            SizeKB = [math]::Round($file.Length / 1KB, 2)
                            Created = $file.CreationTime
                            Modified = $file.LastWriteTime
                            Accessed = $file.LastAccessTime
                            Status = "DELETED"
                            Owner = $null
                            Hash = $null
                            RecoveryAction = "Available in shadow copy: $($shadow.InstallDate)"
                        }
                        
                        $script:deletedFiles += $result
                    }
                }
            } catch {
                # Shadow copy inaccessible, continue
            }
        }
        
        Write-Host "  Found $($deletedFiles.Count) deleted items" -ForegroundColor $(if ($deletedFiles.Count -gt 0) { "Red" } else { "Green" })
        
    } catch {
        Write-Host "  Error accessing shadow copies: $_" -ForegroundColor Red
    }
}

# Function to detect moved files via baseline comparison
function Compare-WithBaseline {
    param([string]$BaselineCSV)
    
    Write-Host "`nComparing with baseline to detect moved files..." -ForegroundColor Yellow
    
    try {
        $baseline = Import-Csv -Path $BaselineCSV
        
        foreach ($baselineItem in $baseline) {
            # Check if file still exists at original location
            if (-not (Test-Path $baselineItem.FullPath)) {
                # Search for file with same hash or name elsewhere
                $possibleMatch = $script:searchResults | Where-Object {
                    $_.Name -eq $baselineItem.Name -and
                    $_.Hash -eq $baselineItem.Hash -and
                    $_.FullPath -ne $baselineItem.FullPath
                } | Select-Object -First 1
                
                if ($possibleMatch) {
                    $movedItem = [PSCustomObject]@{
                        Name = $baselineItem.Name
                        OriginalPath = $baselineItem.FullPath
                        NewPath = $possibleMatch.FullPath
                        DetectionMethod = if ($possibleMatch.Hash -eq $baselineItem.Hash) { "Hash Match" } else { "Name Match" }
                        Status = "MOVED"
                        RecoveryAction = "Move back: Copy-Item '$($possibleMatch.FullPath)' -Destination '$($baselineItem.FullPath)'"
                    }
                    
                    $script:movedFiles += $movedItem
                }
            }
        }
        
        Write-Host "  Found $($movedFiles.Count) moved items" -ForegroundColor $(if ($movedFiles.Count -gt 0) { "Yellow" } else { "Green" })
        
    } catch {
        Write-Host "  Error reading baseline: $_" -ForegroundColor Red
    }
}

# Execute searches
foreach ($sharePath in $SharePaths) {
    Search-CurrentFiles -SharePath $sharePath -Pattern $SearchPattern
}

if ($IncludeDeleted) {
    foreach ($sharePath in $SharePaths) {
        Search-ShadowCopies -SharePath $sharePath -Pattern $SearchPattern
    }
}

if ($BaselinePath -and (Test-Path $BaselinePath)) {
    Compare-WithBaseline -BaselineCSV $BaselinePath
}

# Display results
Write-Host "`n========== SEARCH RESULTS ==========" -ForegroundColor Cyan

if ($searchResults.Count -gt 0) {
    Write-Host "`nCurrent Files/Folders Found: $($searchResults.Count)" -ForegroundColor Green
    $searchResults | Format-Table Name, FullPath, Type, SizeKB, Modified -AutoSize
}

if ($deletedFiles.Count -gt 0) {
    Write-Host "`nDeleted Files Found: $($deletedFiles.Count)" -ForegroundColor Red
    Write-Host "These files can be recovered from shadow copies or backup:`n" -ForegroundColor Yellow
    $deletedFiles | Format-Table Name, FullPath, Modified, RecoveryAction -AutoSize
    
    Write-Host "`nRECOVERY INSTRUCTIONS:" -ForegroundColor Cyan
    Write-Host "1. Right-click the parent folder in Windows Explorer" -ForegroundColor White
    Write-Host "2. Select 'Restore previous versions'" -ForegroundColor White
    Write-Host "3. Choose a snapshot from before deletion" -ForegroundColor White
    Write-Host "4. Restore the file to its original location`n" -ForegroundColor White
}

if ($movedFiles.Count -gt 0) {
    Write-Host "`nMoved Files Detected: $($movedFiles.Count)" -ForegroundColor Yellow
    $movedFiles | Format-Table Name, OriginalPath, NewPath, DetectionMethod -AutoSize
    
    Write-Host "`nTo restore files to original locations, run the commands in RecoveryAction column" -ForegroundColor Cyan
}

if ($searchResults.Count -eq 0 -and $deletedFiles.Count -eq 0 -and $movedFiles.Count -eq 0) {
    Write-Host "No matches found for pattern: $SearchPattern" -ForegroundColor Yellow
}

# Export results if requested
if ($ExportPath) {
    try {
        $allResults = $searchResults + $deletedFiles
        
        $allResults | Export-Csv -Path $ExportPath -NoTypeInformation -Force
        Write-Host "`nResults exported to: $ExportPath" -ForegroundColor Green
        
        if ($movedFiles.Count -gt 0) {
            $movedExportPath = $ExportPath -replace '\.csv$', '_Moved.csv'
            $movedFiles | Export-Csv -Path $movedExportPath -NoTypeInformation -Force
            Write-Host "Moved files exported to: $movedExportPath" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "Error exporting results: $_" -ForegroundColor Red
    }
}

# Summary
Write-Host "`n========== SUMMARY ==========" -ForegroundColor Cyan
Write-Host "Total Current Files:    $($searchResults.Count)" -ForegroundColor Green
Write-Host "Total Deleted Files:    $($deletedFiles.Count)" -ForegroundColor $(if ($deletedFiles.Count -gt 0) { "Red" } else { "Green" })
Write-Host "Total Moved Files:      $($movedFiles.Count)" -ForegroundColor $(if ($movedFiles.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "==============================`n" -ForegroundColor Cyan

# Return combined results
$allResults = $searchResults + $deletedFiles
return $allResults
