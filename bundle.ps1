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
#   Developed by Angel (GitHub: @4ngel2769)
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
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
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
    
    # Add header
    $allContent += "#!/bin/bash"
    $allContent += ""
    $allContent += "# Tor Hidden Service Setup Script - Bundled Version"
    $allContent += "# Auto-generated from modular components"
    $allContent += "# "
    $allContent += "# Generated on: $timestamp"
    $allContent += "# Generated by: $userName@$computerName"
    $allContent += "# Bundle method: PowerShell bundler (Unix line endings)"
    $allContent += "# Minified: $(if ($Minify) { 'Yes' } else { 'No' })"
    $allContent += "#"
    $allContent += "# This is a bundled version of the modular Tor setup script"
    $allContent += "# Original modules: utils.sh, funcs.sh, services.sh, main.sh"
    $allContent += "# "
    $allContent += "# For the latest version and source code, visit:"
    $allContent += "# https://github.com/4ngel2769/tor_autosetup"
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
        Write-Success "✅ Perfect! File uses Unix line endings only (LF)"
    } else {
        Write-Warning "⚠️  File contains non-Unix line endings - may need dos2unix"
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
    
    # Try to make executable if running on WSL/Linux subsystem
    if (Get-Command "wsl" -ErrorAction SilentlyContinue) {
        Write-Status "Setting executable permissions via WSL..." "Blue"
        try {
            wsl chmod +x $Output
            Write-Success "File permissions set via WSL"
            
            # Test syntax via WSL
            Write-Status "Testing script syntax via WSL..." "Blue"
            $syntaxTest = wsl bash -n $Output 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Syntax validation passed!"
            } else {
                Write-Warning "Syntax validation failed:"
                Write-Host $syntaxTest -ForegroundColor Red
            }
        } catch {
            Write-Warning "Could not set permissions via WSL: $($_.Exception.Message)"
        }
    } else {
        Write-Status "💡 To make executable on Linux, run:" "Yellow"
        Write-Host "   chmod +x $Output" -ForegroundColor White
        Write-Host "   # Test syntax with: bash -n $Output" -ForegroundColor Gray
    }
    
    Write-Success "Bundle complete! Transfer to Linux and run:"
    Write-Host "   ./$Output --help" -ForegroundColor White
    Write-Host "   ./$Output --list" -ForegroundColor White
    Write-Host "   ./$Output --test" -ForegroundColor White
    
} catch {
    Write-Error "Error creating bundle: $($_.Exception.Message)"
    Write-VerboseLog "Stack trace: $($_.Exception.StackTrace)"
    exit 1
}
# End of bundle.ps1
