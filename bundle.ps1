#!/usr/bin/env pwsh

# ================================================================================
# Tor Setup Script Bundler
# ================================================================================
# 
# Description:
#   This PowerShell script bundles modular Tor hidden service setup scripts
#   into a single executable Bash script with Unix line endings. It combines
#   utils.sh, funcs.sh, services.sh, and main.sh into one file for easy
#   deployment on Linux systems.
# 
# Features:
#   - Combines multiple modules into one script
#   - Ensures Unix line endings (LF only)
#   - Standard minification option
#   - Verbose logging for debugging
#   - Syntax validation via WSL (if available)
# 
# Usage:
#   .\bundle.ps1 [-Verbose] [-Minify] [-Output <filename>] [-Help]
# 
# Credits:
#   Developed by Angel (GitHub: 4ngel2769)
#   Repository: https://github.com/4ngel2769/tor_autosetup
#
# ================================================================================

param(
    [switch]$Verbose = $false,
    [switch]$Minify = $false,
    [string]$Output = "torstp-bundled.sh",
    [switch]$Help = $false
)

if ($Help) {
    Write-Host @"
Tor Setup Script Bundler

USAGE:
    .\bundle.ps1 [-Verbose] [-Minify] [-Output <filename>] [-Help]

OPTIONS:
    -Verbose      Show detailed bundling process
    -Minify       Remove comments and empty lines (smaller file)
    -Output       Specify output filename (default: torstp-bundled.sh)
    -Help         Show this help message

MINIFICATION LEVELS:
    Normal        Keep all formatting and comments
    -Minify       Remove comments and empty lines (~30% smaller)

EXAMPLES:
    .\bundle.ps1                                # Basic bundle
    .\bundle.ps1 -Verbose                       # Verbose output
    .\bundle.ps1 -Minify                        # Standard minification
    .\bundle.ps1 -Minify -Output compact.sh     # Minified version
"@ -ForegroundColor Cyan
    exit 0
}

function Write-VerboseLog {
    param([string]$Message)
    if ($Verbose) {
        Write-Host "[VERBOSE] $Message" -ForegroundColor Gray
    }
}

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "🔧 $Message" -ForegroundColor $Color
}

function Write-Ready {
    param([string]$Message, [string]$Color = "Green")
    Write-Host "🚀 $Message" -ForegroundColor $Color
}

function Write-Info {
    param([string]$Message, [string]$Color = "Cyan")
    Write-Host "📡 $Message" -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️ $Message" -ForegroundColor Yellow
}

$minifyType = if ($Minify) { "STANDARD" } else { "NONE" }
Write-Status "Bundling Tor Setup Script modules with $minifyType minification..."

# Check if all required files exist
$requiredFiles = @("src/utils.sh", "src/funcs.sh", "src/services.sh", "src/main.sh")
$missingFiles = @()

Write-VerboseLog "Checking for required files in src/ directory..."
foreach ($file in $requiredFiles) {
    Write-VerboseLog "  Checking: $file"
    if (-not (Test-Path $file)) {
        $missingFiles += $file
        Write-VerboseLog "    ❌ Missing: $file"
    } else {
        Write-VerboseLog "    ✅ Found: $file"
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Error "Missing required files in src/ directory:"
    foreach ($file in $missingFiles) {
        Write-Host "  • $file" -ForegroundColor Yellow
    }
    Write-Error "Please ensure all module files are in the src/ directory."
    exit 1
}

Write-Status "Creating bundled script: $Output" "Blue"

try {
    # Resolve the full path for the output file
    $OutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
    Write-VerboseLog "Full output path: $OutputPath"
    
    # Test if we can write to the directory
    $outputDir = Split-Path -Parent $OutputPath
    if (-not $outputDir) {
        $outputDir = (Get-Location).Path
    }
    Write-VerboseLog "Output directory: $outputDir"
    
    if (-not (Test-Path $outputDir)) {
        Write-Error "Output directory does not exist: $outputDir"
        exit 1
    }
    
    # Create a simple test to verify write permissions
    $testFile = Join-Path $outputDir "test_write_permissions.tmp"
    try {
        "test" | Out-File -FilePath $testFile -Encoding utf8
        Remove-Item $testFile -Force
        Write-VerboseLog "Write permissions verified"
    } catch {
        Write-Error "No write permissions to directory: $outputDir"
        Write-Error "Error: $($_.Exception.Message)"
        exit 1
    }
    
    # Create header for bundled script
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $computerName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    
    $allContent = @()
    
    function Read-EnvFile {
        param([string]$Path = ".env")
        $envVars = @{}
        if (Test-Path $Path) {
            $content = Get-Content $Path -Encoding UTF8
            foreach ($line in $content) {
                if ($line -match '^\s*#' -or $line -match '^\s*$') { continue }
                if ($line -match '^([^=]+)=(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim() -replace '^["'']|["'']$', ''
                    $envVars[$key] = $value
                }
            }
        }
        return $envVars
    }

    # Load .env metadata
    $envVars = Read-EnvFile
    $scriptAuthor = $envVars['SCRIPT_AUTHOR']
    $scriptRepo = $envVars['SCRIPT_REPO']
    $scriptVersion = $envVars['SCRIPT_VERSION']
    if (-not $scriptVersion) { $scriptVersion = "0.0.0" }
    if (-not $scriptAuthor) { $scriptAuthor = "Unknown" }
    if (-not $scriptRepo) { $scriptRepo = "Unknown" }
    $buildDate = Get-Date -Format "yyyy.MM.dd"

    $allContent += "#!/bin/bash"
    $allContent += ""
    $allContent += "# ============================================================================="
    $allContent += "# Tor Hidden Service Setup Script - Bundled Version"
    $allContent += "# ============================================================================="
    $allContent += "# "
    $allContent += "# Auto-generated from modular components"
    $allContent += "# Generated on: $timestamp"
    $allContent += "# Generated by: $userName@$computerName"
    $allContent += "# Bundle method: PowerShell bundler (Unix line endings)"
    $allContent += "# Minification: $(if ($Minify) { 'Yes' } else { 'No' })"
    $allContent += "#"
    $allContent += "# Version: $scriptVersion (Build: $buildDate)"
    $allContent += "# Author: $scriptAuthor"
    $allContent += "# Repository: $scriptRepo"
    $allContent += "# License: MIT"
    $allContent += "#"
    $allContent += "# This is a bundled version of the modular Tor setup script"
    $allContent += "# Original modules: utils.sh, funcs.sh, services.sh, main.sh"
    $allContent += "# "
    $allContent += "# Features:"
    $allContent += "# • Automated Tor hidden service deployment"
    $allContent += "# • System service integration (systemd, OpenRC, runit, SysV, s6, dinit)"
    $allContent += "# • Multi-distribution support"
    $allContent += "# • Dynamic color schemes (STANDARD, HTB, PASTEL)"
    $allContent += "# • Comprehensive service management and monitoring"
    $allContent += "# • Combined flag support (-Vl, -rV, etc.)"
    $allContent += "# • Version and about information"
    $allContent += "#"
    $allContent += "# Usage Examples:"
    $allContent += "#   ./runme_tor.sh --version     # Show version"
    $allContent += "#   ./runme_tor.sh --about       # Show detailed info"
    $allContent += "#   ./runme_tor.sh -Vl           # Verbose list"
    $allContent += "#   ./runme_tor.sh -rV service   # Verbose remove"
    $allContent += "#"
    $allContent += "# For latest updates and source: $scriptRepo"
    $allContent += ""
    $allContent += "# ============================================================================="
    $allContent += "# SELF-SETUP: Handle execution permissions and common issues"
    $allContent += "# ============================================================================="
    $allContent += ""
    $allContent += "# Function to check and fix script permissions"
    $allContent += "fix_permissions() {"
    $allContent += "    local script_path=`"`$0`""
    $allContent += "    "
    $allContent += "    # Check if script is executable"
    $allContent += "    if [[ ! -x `"`$script_path`" ]]; then"
    $allContent += "        echo `"🔧 Script is not executable, attempting to fix...`""
    $allContent += "        "
    $allContent += "        # Try to make it executable"
    $allContent += "        if chmod +x `"`$script_path`" 2>/dev/null; then"
    $allContent += "            echo `"✅ Script permissions fixed successfully`""
    $allContent += "            echo `"🔄 Re-executing script with original arguments...`""
    $allContent += "            exec `"`$script_path`" `"`$@`""
    $allContent += "        else"
    $allContent += "            echo `"❌ Could not fix script permissions`""
    $allContent += "            echo `"💡 Please run manually: chmod +x `$script_path`""
    $allContent += "            echo `"   Then run: `$script_path `$*`""
    $allContent += "            exit 1"
    $allContent += "        fi"
    $allContent += "    fi"
    $allContent += "}"
    $allContent += ""
    $allContent += "# Run permission check (only if we're being executed, not sourced)"
    $allContent += "if [[ `"`${BASH_SOURCE[0]}`" == `"`${0}`" ]]; then"
    $allContent += "    fix_permissions `"`$@`""
    $allContent += "fi"
    $allContent += ""
    $allContent += "set -euo pipefail"
    $allContent += ""

    $totalSkipped = 0
    
    # Process each file and append content
    foreach ($file in $requiredFiles) {
        $fileName = Split-Path $file -Leaf
        Write-Status "Processing $fileName..." "Gray"
        Write-VerboseLog "  Reading file: $file"
        
        # Read file content as raw text and split on any line ending
        $rawContent = Get-Content $file -Raw -Encoding UTF8
        # Handle different line ending types properly
        $lines = $rawContent -split '\r\n|\r|\n'
        
        $linesSkipped = 0
        
        # Add separator comment (unless minifying)
        if (-not $Minify) {
            $allContent += ""
            $allContent += "# ============================================================================="
            $allContent += "# START OF: $fileName"
            $allContent += "# ============================================================================="
            $allContent += ""
        }
        
        foreach ($line in $lines) {
            # Skip empty lines at end of file
            if ([string]::IsNullOrWhiteSpace($line) -and $line -eq $lines[-1]) {
                continue
            }
            
            # Skip shebang lines (except in main.sh)
            if ($line -match "^#!/bin/bash" -and $fileName -ne "main.sh") {
                $linesSkipped++
                Write-VerboseLog "    Skipped shebang: $line"
                continue
            }
            
            # Skip all source-related lines
            if ($line -match "^# shellcheck source=" -or 
                $line -match "^source.*utils\.sh" -or
                $line -match "^source.*funcs\.sh" -or
                $line -match "^source.*services\.sh" -or
                $line -match "^source.*main\.sh" -or
                $line -match "^source.*\`".*dirname.*BASH_SOURCE" -or
                $line -match "^source.*\$.*dirname.*BASH_SOURCE" -or
                $line -match "^source.*\\\$.*SCRIPT_DIR") {
                $linesSkipped++
                Write-VerboseLog "    Skipped source line: $line"
                continue
            }
            
            # Skip SCRIPT_DIR definition since we're bundled
            if ($line -match "^SCRIPT_DIR=") {
                $linesSkipped++
                Write-VerboseLog "    Skipped SCRIPT_DIR definition: $line"
                continue
            }
            
            # Skip 'set -euo pipefail' in individual files (we have it in header)
            if ($line -match "^set -euo pipefail" -and $fileName -ne "main.sh") {
                $linesSkipped++
                Write-VerboseLog "    Skipped duplicate set statement: $line"
                continue
            }
            
            # Minify options
            if ($Minify) {
                # Skip comments (except important ones)
                if ($line -match "^\s*#" -and 
                    $line -notmatch "#!/bin/bash" -and
                    $line -notmatch "# filepath:" -and
                    $line -notmatch "# shellcheck disable") {
                    $linesSkipped++
                    continue
                }
                
                # Skip empty lines
                if ($line -match "^\s*$") {
                    $linesSkipped++
                    continue
                }
            }
            
            # Add the line
            $allContent += $line
        }
        
        # Add end separator (unless minifying)
        if (-not $Minify) {
            $allContent += ""
            $allContent += "# ============================================================================="
            $allContent += "# END OF: $fileName"
            $allContent += "# ============================================================================="
            $allContent += ""
        }
        
        Write-VerboseLog "  Lines processed: $($lines.Count), kept: $($allContent.Count), skipped: $linesSkipped"
        $totalSkipped += $linesSkipped
    }
    
    # Join all content with Unix line endings and write to file
    Write-VerboseLog "Combining $($allContent.Count) lines with Unix line endings..."
    $finalContent = $allContent -join "`n"
    $finalContent += "`n"  # Ensure file ends with newline
    
    # Convert to bytes with UTF-8 encoding (no BOM)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $bytes = $utf8NoBom.GetBytes($finalContent)
    
    Write-VerboseLog "Writing $($bytes.Length) bytes to $OutputPath"
    [System.IO.File]::WriteAllBytes($OutputPath, $bytes)
    
    # Verify the file was created
    if (-not (Test-Path $OutputPath)) {
        throw "Output file was not created successfully: $OutputPath"
    }
    
    Write-Success "Successfully created bundled script with $minifyType minification!"
    
    # Get file statistics
    $outputItem = Get-Item $OutputPath
    $fileSize = $outputItem.Length
    $fileSizeKB = [math]::Round($fileSize / 1024, 2)
    
    # Count lines and verify line endings
    $bundledBytes = [System.IO.File]::ReadAllBytes($OutputPath)
    $bundledContent = [System.Text.Encoding]::UTF8.GetString($bundledBytes)
    $lineCount = ($bundledContent -split '\n').Count
    
    # Check for Windows line endings (CRLF)
    $crlfCount = [regex]::Matches($bundledContent, "`r`n").Count
    $crCount = [regex]::Matches($bundledContent, "`r").Count
    $lfCount = [regex]::Matches($bundledContent, "`n").Count
    
    Write-Status "Bundle Statistics:" "Cyan"
    Write-Host "  • Output file: $Output" -ForegroundColor White
    Write-Host "  • File size: $fileSizeKB KB ($fileSize bytes)" -ForegroundColor White
    Write-Host "  • Line count: $lineCount" -ForegroundColor White
    Write-Host "  • Lines skipped: $totalSkipped (source statements, shebangs, etc.)" -ForegroundColor Yellow
    Write-Host "  • Modules bundled: $($requiredFiles.Count)" -ForegroundColor White
    Write-Host "  • Minification: $minifyType" -ForegroundColor $(if ($Minify) { "Yellow" } else { "White" })
    Write-Host "  • Created: $($outputItem.CreationTime)" -ForegroundColor White
    
    # Show line ending analysis
    Write-Status "Line Ending Analysis:" "Cyan"
    Write-Host "  • LF (Unix): $lfCount" -ForegroundColor $(if ($lfCount -gt 0) { "Green" } else { "White" })
    Write-Host "  • CRLF (Windows): $crlfCount" -ForegroundColor $(if ($crlfCount -eq 0) { "Green" } else { "Red" })
    Write-Host "  • CR (Mac): $crCount" -ForegroundColor $(if ($crCount -eq 0) { "Green" } else { "Yellow" })
    
    if ($crlfCount -eq 0 -and $crCount -eq 0) {
        Write-Success "Perfect! File uses Unix line endings only (LF)"
    } else {
        Write-Warning "File contains non-Unix line endings - may need dos2unix"
    }
    
    # Show compression savings
    if ($Minify) {
        $originalSize = ($requiredFiles | ForEach-Object { (Get-Item $_).Length } | Measure-Object -Sum).Sum
        $compressionRatio = [math]::Round((1 - ($fileSize / $originalSize)) * 100, 1)
        Write-Host "  • Size reduction: $compressionRatio% (from $([math]::Round($originalSize/1024, 2)) KB)" -ForegroundColor Green
    }
    
    # Check for remaining source statements
    if ($bundledContent -match "source.*\.sh") {
        Write-Warning "Warning: Bundle may still contain source statements"
        if ($Verbose) {
            $sourceLines = ($bundledContent -split '\n') | Where-Object { $_ -match "source.*\.sh" }
            foreach ($sourceLine in $sourceLines) {
                Write-Host "    Found: $sourceLine" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Success "Verified: No source statements found in bundle"
    }
    
    # Function to read .env file
    function Read-EnvFile {
        param([string]$Path = ".env")
        
        $envVars = @{}
        
        if (Test-Path $Path) {
            Write-VerboseLog "Reading .env file: $Path"
            $content = Get-Content $Path -Encoding UTF8
            
            foreach ($line in $content) {
                # Skip comments and empty lines
                if ($line -match '^\s*#' -or $line -match '^\s*$') {
                    continue
                }
                
                # Parse KEY=VALUE format
                if ($line -match '^([^=]+)=(.*)$') {
                    $key = $matches[1].Trim()
                    $value = $matches[2].Trim()
                    
                    # Remove quotes if present
                    $value = $value -replace '^["'']|["'']$', ''
                    
                    $envVars[$key] = $value
                    Write-VerboseLog "  Loaded: $key = $value"
                }
            }
        } else {
            Write-VerboseLog ".env file not found at: $Path"
        }
        
        return $envVars
    }

    # Function to set permissions for multiple users
    function Set-MultiUserPermissions {
        param(
            [string]$FileName,
            [string]$WSLUser,
            [string]$SSHUser
        )
        
        Write-VerboseLog "Setting permissions for file: $FileName"
        Write-VerboseLog "WSL User: $WSLUser"
        Write-VerboseLog "SSH User: $SSHUser"
        
        try {
            # Set basic 755 permissions first
            Write-Status "Setting basic executable permissions (755)..." "Blue"
            $chmodResult = & wsl.exe chmod 755 $FileName 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Basic chmod 755 failed: $chmodResult"
            }
            Write-Success "✅ Basic permissions set (755)"
            
            # Get current WSL user
            $currentWSLUser = & wsl.exe whoami 2>&1
            if ($LASTEXITCODE -eq 0) {
                $currentWSLUser = $currentWSLUser.Trim()
                Write-VerboseLog "Current WSL user: $currentWSLUser"
            } else {
                $currentWSLUser = $WSLUser
                Write-VerboseLog "Could not detect WSL user, using provided: $currentWSLUser"
            }
            
            # Set ownership for WSL user if different from current
            if ($WSLUser -and $WSLUser -ne $currentWSLUser) {
                Write-Status "Setting ownership for WSL user: $WSLUser" "Blue"
                $chownResult = & wsl.exe sudo chown "$WSLUser`:$WSLUser" $FileName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "✅ Ownership set for WSL user: $WSLUser"
                } else {
                    Write-Warning "⚠️  Could not set WSL ownership: $chownResult"
                    Write-VerboseLog "This is normal if sudo is not available or user doesn't exist"
                }
            }
            
            # Create a note file with permissions info for SSH transfer
            if ($SSHUser) {
                $noteFile = "$FileName.permissions.txt"
                $permissionsNote = @"
# File Transfer Permissions Guide
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

FILE: $FileName
TARGET_USER: $SSHUser
REQUIRED_PERMISSIONS: 755 (rwxr-xr-x)

# After transferring to target machine, run:
chmod +x $FileName

# Or for explicit permissions:
chmod 755 $FileName

# To set ownership for target user:
sudo chown $SSHUser`:$SSHUser $FileName

# Verify permissions:
ls -la $FileName

# Test the script:
./$FileName --version
"@
                
                Write-VerboseLog "Creating permissions note file: $noteFile"
                $permissionsNote | Out-File -FilePath $noteFile -Encoding UTF8
                Write-Status "Created permissions guide: $noteFile" "Cyan"
            }
            
            # Verify current permissions
            Write-Status "Verifying permissions..." "Blue"
            $permResult = & wsl.exe ls -la $FileName 2>&1
            if ($LASTEXITCODE -eq 0) {
                $permLine = ($permResult | Where-Object { $_ -match "^-" }) | Select-Object -First 1
                Write-VerboseLog "Current permissions: $permLine"
                
                if ($permLine -match "^-rwxr-xr-x") {
                    Write-Success "Verified: File is executable by everyone (755)"
                    return $true
                } elseif ($permLine -match "^-rwx") {
                    Write-Success "Verified: File is executable by owner"
                    Write-Warning "Note: May need chmod on target machine for other users"
                    return $true
                } else {
                    Write-Warning "Warning: File may not be executable - permissions: $permLine"
                    return $false
                }
            } else {
                Write-Warning "Could not verify permissions: $permResult"
                return $false
            }
            
        } catch {
            Write-Warning "Permission setting failed: $($_.Exception.Message)"
            return $false
        }
    }

    # Load environment variables
    $envVars = Read-EnvFile
    $sshUser = $envVars['SSH_USER']
    $sshHost = $envVars['SSH_HOST']
    $sshPort = $envVars['SSH_PORT']
    $sshKeyPath = $envVars['SSH_KEY_PATH']
    $sshDir = $envVars['SSH_DIR']
    
    Write-VerboseLog "Environment variables loaded:"
    Write-VerboseLog "  SSH_USER: $sshUser"
    Write-VerboseLog "  SSH_HOST: $sshHost"
    Write-VerboseLog "  SSH_PORT: $sshPort"
    Write-VerboseLog "  SSH_DIR: $sshDir"
    
    # Try to make executable if running on WSL/Linux subsystem
    if (Get-Command "wsl" -ErrorAction SilentlyContinue) {
        Write-Status "Setting executable permissions via WSL..." "Blue"
        try {
            # Change to the directory and use relative path
            $fileName = Split-Path -Leaf $OutputPath
            $directory = Split-Path -Parent $OutputPath
            
            Write-VerboseLog "Changing to directory: $directory"
            Write-VerboseLog "Working with file: $fileName"
            
            # Use pushd/popd to change directory in PowerShell, then run WSL commands
            Push-Location $directory
            try {
                # Get current Windows username (mapped to WSL)
                $windowsUser = $env:USERNAME.ToLower()
                
                # Set permissions for multiple users
                $permissionSuccess = Set-MultiUserPermissions -FileName $fileName -WSLUser $windowsUser -SSHUser $sshUser
                
                if ($permissionSuccess) {
                    # Test syntax
                    Write-Status "Testing script syntax via WSL..." "Blue"
                    $syntaxResult = & wsl.exe timeout 10 bash -n $fileName 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Syntax validation passed!"
                    } else {
                        Write-Warning "Syntax validation failed"
                        if ($syntaxResult) {
                            $syntaxResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
                        }
                    }
                }
                
            } finally {
                Pop-Location
            }
        } catch {
            Write-Warning "WSL setup failed: $($_.Exception.Message)"
            Write-Status "💡 Manual setup on Linux:" "Yellow"
            Write-Host "   chmod 755 $(Split-Path -Leaf $OutputPath)" -ForegroundColor White
            Write-Host "   bash -n $(Split-Path -Leaf $OutputPath)" -ForegroundColor Gray
        }
    } else {
        Write-Status "💡 To make executable on Linux, run:" "Yellow"
        Write-Host "   chmod +x `"$(Split-Path -Leaf $OutputPath)`"" -ForegroundColor White
        Write-Host "   # Or for everyone: chmod 755 `"$(Split-Path -Leaf $OutputPath)`"" -ForegroundColor Gray
        Write-Host "   # Test syntax with: bash -n `"$(Split-Path -Leaf $OutputPath)`"" -ForegroundColor Gray
    }
    
    # Enhanced completion message with transfer instructions
    Write-Success "Bundle complete!"
    Write-Host ""
    
    if ($sshUser -and $sshHost) {
        Write-Ready "Ready for deployment to $sshUser@$sshHost"
        Write-Host ""
        
        Write-Info "Transfer commands:"
        if ($sshKeyPath) {
            Write-Host "   -  scp -i $sshKeyPath $Output $sshUser@${sshHost}:$sshDir" -ForegroundColor Green
            Write-Host "   -  # or with rsync:" -ForegroundColor Gray
            Write-Host "   -  rsync -avz -e `"ssh -i $sshKeyPath`" $Output $sshUser@${sshHost}:$sshDir" -ForegroundColor Green
        } else {
            Write-Host "   -  scp $Output $sshUser@${sshHost}:$sshDir" -ForegroundColor Green
            Write-Host "   -  # or with rsync:" -ForegroundColor Gray
            Write-Host "   -  rsync -avz $Output $sshUser@${sshHost}:$sshDir" -ForegroundColor Green
        }
        
        if ($sshPort -and $sshPort -ne "22") {
            Write-Host "   -  # Custom port version:" -ForegroundColor Gray
            Write-Host "   -  scp -P $sshPort $Output $sshUser@${sshHost}:$sshDir" -ForegroundColor Yellow
        }
        
        Write-Host ""
        Write-Status "On target machine ($sshUser@$sshHost):" "Cyan"
        Write-Host "   chmod +x $Output" -ForegroundColor White
        Write-Host "   sudo $Output --version" -ForegroundColor Green
        Write-Host "   sudo $Output --help" -ForegroundColor Green
        
    } else {
        Write-Info "Transfer to target machine:"
        Write-Host "   scp $Output user@host:~/" -ForegroundColor White
        Write-Host "   rsync -avz $Output user@host:~/" -ForegroundColor Green
        Write-Host ""
        Write-Status "On target machine:" "Cyan"
        Write-Host "   chmod +x $Output" -ForegroundColor White
        Write-Host "   sudo $Output --version" -ForegroundColor Green
    }
    
    # Write-Host ""
    # Write-Status "Important Notes:" "Yellow"
    # Write-Host "   • File permissions set for WSL user: $($env:USERNAME.ToLower())" -ForegroundColor Gray
    # if ($sshUser) {
        # Write-Host "   • Target user from .env: $sshUser" -ForegroundColor Gray
        # Write-Host "   • chmod +x required after transfer (different user contexts)" -ForegroundColor Gray
    # }
    # Write-Host "   • Script has self-fixing permissions on first run" -ForegroundColor Gray
    # Write-Host "   • Use rsync -avz for better permission preservation" -ForegroundColor Gray
} catch {
    Write-Error "Error creating bundle: $($_.Exception.Message)"
    Write-VerboseLog "Stack trace: $($_.Exception.StackTrace)"
    exit 1
}

### 🍉 melwateron

### "That man is playing 4D chess while we're playing checkers."
###  - Neo, The Matrix (1999)

### End of bundle.ps1
