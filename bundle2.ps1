#!/usr/bin/env pwsh

# ================================================================================
# Simple Tor Setup Script Bundler
# ================================================================================
# 
# Description:
#   This PowerShell script concatenates the module files into a single bash script
#   with Unix line endings (LF only). No minification is performed.
# 
# Usage:
#   .\bundle2.ps1 [OutputFile]
# ================================================================================

param(
    [string]$OutputFile = "torstp-bundled.sh"
)

# Define source files in correct order
$sourceFiles = @("src/utils.sh", "src/funcs.sh", "src/services.sh", "src/main.sh")

# Check if all source files exist
foreach ($file in $sourceFiles) {
    if (-not (Test-Path $file)) {
        Write-Host "Error: File not found: $file" -ForegroundColor Red
        exit 1
    }
}

try {
    # Create header
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $content = @"
#!/bin/bash

# Tor Hidden Service Setup Script - Bundled Version
# Generated on: $timestamp
# Original modules: utils.sh, funcs.sh, services.sh, main.sh

set -euo pipefail

"@

    # Append each file
    foreach ($file in $sourceFiles) {
        $fileName = Split-Path $file -Leaf
        Write-Host "Adding $fileName..." -ForegroundColor Gray
        
        $fileContent = Get-Content -Raw $file -ErrorAction Stop
        
        # Skip shebang line except in main.sh
        if ($fileName -ne "main.sh") {
            $fileContent = $fileContent -replace "#!/bin/bash", ""
        }
        
        # Remove source statements and script directory
        $fileContent = $fileContent -replace "source .*\.sh.*", ""
        $fileContent = $fileContent -replace "SCRIPT_DIR=.*BASH_SOURCE.*", ""
        
        # Remove shellcheck directives
        $fileContent = $fileContent -replace "# shellcheck.*", ""
        
        # Add file section marker
        $content += "`n# ============================================================`n"
        $content += "# $fileName`n"
        $content += "# ============================================================`n"
        $content += $fileContent
    }

    # Try to use Set-Content first, which is often more reliable
    Write-Host "Writing to $OutputFile..." -ForegroundColor Yellow
    
    # Create directory if it doesn't exist
    $directory = Split-Path -Path $OutputFile -Parent
    if ($directory -and -not (Test-Path $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Write-Host "Created directory: $directory" -ForegroundColor Yellow
    }
    
    # Use Out-File first (most compatible)
    $content | Out-File -FilePath $OutputFile -Encoding utf8 -NoNewline
    
    # Convert to Unix line endings separately
    if (Test-Path $OutputFile) {
        $fileContent = Get-Content -Raw $OutputFile
        $unixContent = $fileContent -replace "`r`n", "`n"
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $bytes = $utf8NoBom.GetBytes($unixContent)
        [System.IO.File]::WriteAllBytes($OutputFile, $bytes)
    }

    if (Test-Path $OutputFile) {
        $fileSize = (Get-Item $OutputFile).Length / 1KB
        Write-Host "Successfully created: $OutputFile ($([Math]::Round($fileSize, 2)) KB)" -ForegroundColor Green
        
        # Make executable if WSL is available
        if (Get-Command "wsl" -ErrorAction SilentlyContinue) {
            wsl chmod +x "$OutputFile"
            Write-Host "Made script executable via WSL" -ForegroundColor Green
        }
    } else {
        Write-Host "Failed to create output file using standard methods. Trying alternate approach..." -ForegroundColor Yellow
        
        # Try a simple approach as fallback
        $content | Add-Content -Path $OutputFile -Force
        
        if (Test-Path $OutputFile) {
            $fileSize = (Get-Item $OutputFile).Length / 1KB
            Write-Host "Created file using alternate method: $OutputFile ($([Math]::Round($fileSize, 2)) KB)" -ForegroundColor Green
        } else {
            Write-Host "All attempts to create output file failed!" -ForegroundColor Red
        }
    }
} 
catch {
    Write-Host "Error occurred: $_" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    
    # Try writing to a different location as a last resort
    try {
        $fallbackPath = ".\fallback-bundle.sh"
        Write-Host "Attempting to write to fallback location: $fallbackPath" -ForegroundColor Yellow
        $content | Out-File -FilePath $fallbackPath -Force
        
        if (Test-Path $fallbackPath) {
            Write-Host "Successfully wrote to fallback location: $fallbackPath" -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Fallback write also failed: $_" -ForegroundColor Red
    }
}
