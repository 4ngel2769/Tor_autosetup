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
#   - Multiple minification levels (Minify, Xtraminify)
#   - Verbose logging for debugging
#   - Syntax validation via WSL (if available)
# 
# Usage:
#   .\bundle.ps1 [-Verbose] [-Minify] [-Xtraminify] [-Output <filename>] [-Help]
# 
# Credits:
#   Developed by Angel (GitHub: @4ngel2769)
#   Repository: https://github.com/4ngel2769/tor_autosetup
#
# ================================================================================

param(
    [switch]$Verbose = $false,
    [switch]$Minify = $false,
    [switch]$Xtraminify = $false,
    [string]$Output = "torstp-bundled.sh",
    [switch]$Help = $false
)

if ($Help) {
    Write-Host @"
Tor Setup Script Bundler

USAGE:
    .\bundle.ps1 [-Verbose] [-Minify] [-Xtraminify] [-Output <filename>] [-Help]

OPTIONS:
    -Verbose      Show detailed bundling process
    -Minify       Remove comments and empty lines (smaller file)
    -Xtraminify   ULTRA compact - single-line functions, variable compression
    -Output       Specify output filename (default: torstp-bundled.sh)
    -Help         Show this help message

MINIFICATION LEVELS:
    Normal        Keep all formatting and comments
    -Minify       Remove comments and empty lines (~30% smaller)
    -Xtraminify   Ultra compact format (~50-60% smaller)
                  • Single-line functions where possible
                  • Compressed variable names
                  • Remove unnecessary whitespace
                  • Combine statements with semicolons

EXAMPLES:
    .\bundle.ps1                                # Basic bundle
    .\bundle.ps1 -Verbose                       # Verbose output
    .\bundle.ps1 -Minify                        # Standard minification
    .\bundle.ps1 -Xtraminify -Output ultra.sh   # Ultra compact version
    .\bundle.ps1 -Xtraminify -Verbose           # Ultra compact with logging

WARNING: -Xtraminify creates very compact but less readable code!
"@ -ForegroundColor Cyan
    exit 0
}

# If Xtraminify is set, automatically enable Minify
if ($Xtraminify) {
    $Minify = $true
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

# Function to write content with Unix line endings
function Write-UnixFile {
    param(
        [string]$FilePath,
        [string[]]$Content,
        [switch]$Append
    )
    
    # Join content with Unix line endings (\n only)
    $unixContent = ($Content -join "`n") + "`n"
    
    # Convert to bytes with UTF-8 encoding (no BOM)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $bytes = $utf8NoBom.GetBytes($unixContent)
    
    if ($Append) {
        [System.IO.File]::AppendAllText($FilePath, $unixContent, $utf8NoBom)
    } else {
        [System.IO.File]::WriteAllBytes($FilePath, $bytes)
    }
}

# Function to compress variable names for Xtraminify
function Compress-Variables {
    param([string]$Content)
    
    if (-not $Xtraminify) { return $Content }
    
    Write-VerboseLog "Applying variable compression..."
    
    # Variable mapping for compression
    $varMap = @{
        'VERBOSE' = 'V'
        'TORRC_FILE' = 'TF'
        'HIDDEN_SERVICE_BASE_DIR' = 'HBD'
        'HIDDEN_SERVICE_DIR' = 'HD'
        'TEST_SITE_BASE_PORT' = 'TBP'
        'TEST_SITE_PORT' = 'TP'
        'TEST_SITE_BASE_DIR' = 'TBD'
        'TEST_SITE_DIR' = 'TD'
        'SERVICES_FILE' = 'SF'
        'TORSTP_DIR' = 'TR'
        'PACKAGE_MANAGER' = 'PM'
        'INSTALL_CMD' = 'IC'
        'SERVICE_MANAGER' = 'SM'
        'service_name' = 'sn'
        'service_count' = 'sc'
        'port' = 'p'
        'onion' = 'o'
        'website' = 'w'
        'status' = 's'
        'created' = 'c'
        'directory' = 'd'
        'temp_file' = 'tf'
        'web_status' = 'ws'
        'pid_file' = 'pf'
    }
    
    foreach ($oldVar in $varMap.Keys) {
        $newVar = $varMap[$oldVar]
        # Replace variable assignments and references
        $Content = $Content -replace "\b$oldVar=", "$newVar="
        $Content = $Content -replace "\`$$oldVar\b", "`$$newVar"
        $Content = $Content -replace "\`$\{$oldVar\}", "`${$newVar}"
        Write-VerboseLog "  Compressed: $oldVar -> $newVar"
    }
    
    return $Content
}

# Function to compress function content for Xtraminify
function Compress-Functions {
    param([string[]]$Lines)
    
    if (-not $Xtraminify) { return $Lines }
    
    Write-VerboseLog "Applying function compression..."
    
    $compressedLines = @()
    $inFunction = $false
    $functionBuffer = @()
    $braceCount = 0
    
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        
        # Check if we're starting a function
        if ($line -match '^(\w+)\s*\(\)\s*\{?\s*$') {
            $inFunction = $true
            $functionName = $matches[1]
            $functionBuffer = @($line)
            
            # Count opening brace
            if ($line -match '\{') {
                $braceCount = 1
            } else {
                $braceCount = 0
            }
            continue
        }
        
        if ($inFunction) {
            $functionBuffer += $line
            
            # Count braces to detect function end
            $openBraces = ($line -split '\{').Count - 1
            $closeBraces = ($line -split '\}').Count - 1
            $braceCount += $openBraces - $closeBraces
            
            # If we've closed all braces, function is complete
            if ($braceCount -eq 0) {
                $compressedFunction = Compress-SingleFunction $functionBuffer $functionName
                $compressedLines += $compressedFunction
                $inFunction = $false
                $functionBuffer = @()
            }
        } else {
            $compressedLines += $line
        }
    }
    
    # Handle case where function wasn't properly closed
    if ($inFunction -and $functionBuffer.Count -gt 0) {
        $compressedLines += $functionBuffer
    }
    
    return $compressedLines
}

# Function to compress a single function
function Compress-SingleFunction {
    param([string[]]$FunctionLines, [string]$FunctionName)
    
    $bodyLines = $FunctionLines[1..($FunctionLines.Count-2)]  # Remove function declaration and closing brace
    
    # Simple functions that can be made into one-liners
    $simpleOneLiners = @(
        'verbose_log', 'print_colored', 'generate_random_string', 
        'get_pid_file', 'is_script_managed', 'check_root'
    )
    
    if ($FunctionName -in $simpleOneLiners -and $bodyLines.Count -le 3) {
        Write-VerboseLog "  Compressing simple function: $FunctionName"
        
        # Join non-empty body lines with semicolons
        $nonEmptyLines = $bodyLines | Where-Object { $_ -notmatch '^\s*$' }
        
        if ($nonEmptyLines.Count -eq 1) {
            return "$($FunctionLines[0]) $($nonEmptyLines[0]); }"
        } elseif ($nonEmptyLines.Count -le 3) {
            $joinedBody = ($nonEmptyLines -join '; ')
            return "$($FunctionLines[0]) $joinedBody; }"
        }
    }
    
    # For other functions, just remove extra whitespace and combine simple statements
    $compressedBody = @()
    
    for ($i = 0; $i -lt $bodyLines.Count; $i++) {
        $line = $bodyLines[$i].Trim()
        
        # Skip empty lines
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        
        # Try to combine simple assignments and short statements
        if ($line -match '^(local\s+\w+="[^"]*"|\w+="[^"]*"|\w+=\$\w+)$' -and 
            $i + 1 -lt $bodyLines.Count -and
            $bodyLines[$i + 1].Trim() -match '^(local\s+\w+="[^"]*"|\w+="[^"]*"|\w+=\$\w+)$') {
            
            # Combine consecutive simple assignments
            $combinedLine = $line
            $j = $i + 1
            while ($j -lt $bodyLines.Count -and 
                   $bodyLines[$j].Trim() -match '^(local\s+\w+="[^"]*"|\w+="[^"]*"|\w+=\$\w+)$') {
                $combinedLine += "; " + $bodyLines[$j].Trim()
                $j++
            }
            $compressedBody += "    $combinedLine"
            $i = $j - 1  # Skip the lines we just combined
        } else {
            $compressedBody += "    $line"
        }
    }
    
    Write-VerboseLog "  Compressed function body: $FunctionName ($($bodyLines.Count) -> $($compressedBody.Count) lines)"
    
    return @($FunctionLines[0]) + $compressedBody + @("}")
}

# Function to apply final compression passes
function Apply-FinalCompression {
    param([string]$Content)
    
    if (-not $Xtraminify) { return $Content }
    
    Write-VerboseLog "Applying final compression passes..."
    
    # Remove extra whitespace around operators
    $Content = $Content -replace '\s*=\s*', '='
    $Content = $Content -replace '\s*\|\|\s*', '||'
    $Content = $Content -replace '\s*&&\s*', '&&'
    
    # Compress common patterns
    $Content = $Content -replace 'if\s*\[\[\s*', 'if [['
    $Content = $Content -replace '\s*\]\];\s*then', ']]; then'
    $Content = $Content -replace 'else\s+', 'else '
    
    # Compress echo statements
    $Content = $Content -replace 'echo\s+-e\s+"', 'echo -e "'
    
    # Remove excessive spacing in arrays and parameter expansions
    $Content = $Content -replace '\$\{\s*', '${'
    $Content = $Content -replace '\s*\}', '}'
    
    Write-VerboseLog "Final compression completed"
    
    return $Content
}

$minifyType = if ($Xtraminify) { "ULTRA" } elseif ($Minify) { "STANDARD" } else { "NONE" }
Write-Status "Bundling Tor Setup Script modules with $minifyType minification..."

# Check if all required files exist
$requiredFiles = @("utils.sh", "funcs.sh", "services.sh", "main.sh")
$missingFiles = @()

Write-VerboseLog "Checking for required files..."
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
    Write-Error "Missing required files:"
    foreach ($file in $missingFiles) {
        Write-Host "  • $file" -ForegroundColor Yellow
    }
    Write-Error "Please ensure all module files are in the current directory."
    exit 1
}

Write-Status "Creating bundled script: $Output" "Blue"

try {
    # Create header for bundled script
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $computerName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    
    $headerLines = @(
        "#!/bin/bash",
        ""
    )
    
    # Add minimal header for Xtraminify, full header otherwise
    if ($Xtraminify) {
        $headerLines += @(
            "# Tor Setup Script - Ultra Compact Bundle",
            "# Generated: $timestamp | Minification: ULTRA",
            "# https://github.com/4ngel2769/tor_autosetup",
            ""
        )
    } else {
        $headerLines += @(
            "# Tor Hidden Service Setup Script - Bundled Version",
            "# Auto-generated from modular components",
            "# ",
            "# Generated on: $timestamp",
            "# Generated by: $userName@$computerName",
            "# Bundle method: PowerShell bundler (Unix line endings)",
            "# Minified: $(if ($Minify) { 'Yes' } else { 'No' })",
            "#",
            "# This is a bundled version of the modular Tor setup script",
            "# Original modules: utils.sh, funcs.sh, services.sh, main.sh",
            "# ",
            "# For the latest version and source code, visit:",
            "# https://github.com/4ngel2769/tor_autosetup",
            ""
        )
    }
    
    $headerLines += @("set -euo pipefail", "")

    # Write header with Unix line endings
    Write-VerboseLog "Writing header to $Output with Unix line endings"
    Write-UnixFile -FilePath $Output -Content $headerLines

    $totalLines = 0
    $processedLines = 0
    $totalSkipped = 0
    
    # First pass: count total lines for progress
    if ($Verbose) {
        foreach ($file in $requiredFiles) {
            $content = Get-Content $file -Raw
            $lines = $content -split '\r?\n'
            $totalLines += $lines.Count
        }
        Write-VerboseLog "Total lines to process: $totalLines"
    }

    # Collect all content first, then apply compression
    $allFilteredLines = @()

    # Process each file and collect content
    foreach ($file in $requiredFiles) {
        Write-Status "Processing $file..." "Gray"
        Write-VerboseLog "  Reading file: $file"
        
        # Read file content as raw text and split on any line ending
        $rawContent = Get-Content $file -Raw
        $lines = $rawContent -split '\r?\n'
        
        $filteredLines = @()
        $linesSkipped = 0
        
        # Add separator comment (unless minifying)
        if (-not $Minify) {
            $separatorLines = @(
                "",
                "# =============================================================================",
                "# START OF: $file",
                "# =============================================================================",
                ""
            )
            $filteredLines += $separatorLines
        }
        
        foreach ($line in $lines) {
            $processedLines++
            
            # Skip empty lines at end of file
            if ([string]::IsNullOrWhiteSpace($line) -and $line -eq $lines[-1]) {
                continue
            }
            
            # Skip shebang lines (except in main.sh)
            if ($line -match "^#!/bin/bash" -and $file -ne "main.sh") {
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
            if ($line -match "^set -euo pipefail" -and $file -ne "main.sh") {
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
            $filteredLines += $line
        }
        
        # Add end separator (unless minifying)
        if (-not $Minify) {
            $endSeparatorLines = @(
                "",
                "# =============================================================================",
                "# END OF: $file",
                "# =============================================================================",
                ""
            )
            $filteredLines += $endSeparatorLines
        }
        
        Write-VerboseLog "  Lines processed: $($lines.Count), kept: $($filteredLines.Count), skipped: $linesSkipped"
        $totalSkipped += $linesSkipped
        
        $allFilteredLines += $filteredLines
    }
    
    # Apply Xtraminify compression if enabled
    if ($Xtraminify) {
        Write-Status "Applying ULTRA compression..." "Yellow"
        
        # Step 1: Compress functions
        $allFilteredLines = Compress-Functions $allFilteredLines
        
        # Step 2: Join all content and compress variables
        $combinedContent = $allFilteredLines -join "`n"
        $combinedContent = Compress-Variables $combinedContent
        
        # Step 3: Apply final compression
        $combinedContent = Apply-FinalCompression $combinedContent
        
        # Split back into lines
        $allFilteredLines = $combinedContent -split '\n'
    }
    
    # Write the final content
    Write-UnixFile -FilePath $Output -Content $allFilteredLines -Append
    
    Write-Success "Successfully created bundled script with $minifyType minification!"
    
    # Get file statistics
    $outputItem = Get-Item $Output
    $fileSize = $outputItem.Length
    $fileSizeKB = [math]::Round($fileSize / 1024, 2)
    
    # Count lines
    $bundledContent = Get-Content $Output -Raw
    $lineCount = ($bundledContent -split '\n').Count
    
    Write-Status "Bundle Statistics:" "Cyan"
    Write-Host "  • Output file: $Output" -ForegroundColor White
    Write-Host "  • File size: $fileSizeKB KB ($fileSize bytes)" -ForegroundColor White
    Write-Host "  • Line count: $lineCount" -ForegroundColor White
    Write-Host "  • Lines skipped: $totalSkipped (source statements, shebangs, etc.)" -ForegroundColor Yellow
    Write-Host "  • Modules bundled: $($requiredFiles.Count)" -ForegroundColor White
    Write-Host "  • Minification: $minifyType" -ForegroundColor $(if ($Xtraminify) { "Magenta" } elseif ($Minify) { "Yellow" } else { "White" })
    Write-Host "  • Line endings: Unix (LF only)" -ForegroundColor Green
    Write-Host "  • Created: $($outputItem.CreationTime)" -ForegroundColor White
    
    # Show compression savings
    if ($Minify -or $Xtraminify) {
        $originalSize = ($requiredFiles | ForEach-Object { (Get-Item $_).Length } | Measure-Object -Sum).Sum
        $compressionRatio = [math]::Round((1 - ($fileSize / $originalSize)) * 100, 1)
        Write-Host "  • Size reduction: $compressionRatio% (from $([math]::Round($originalSize/1024, 2)) KB)" -ForegroundColor Green
    }
    
    # Verify line endings
    $sampleBytes = [System.IO.File]::ReadAllBytes($Output) | Select-Object -First 1000
    $hasCRLF = ($sampleBytes -contains 13)
    
    if ($hasCRLF) {
        Write-Warning "Warning: File may still contain Windows line endings"
    } else {
        Write-Success "Verified: File uses Unix line endings (LF only)"
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
    
    if ($Xtraminify) {
        Write-Status "🚀 ULTRA COMPACT bundle complete!" "Magenta"
        Write-Host "   WARNING: Code is highly compressed and may be harder to debug!" -ForegroundColor Yellow
    } else {
        Write-Success "Bundle complete! Transfer to Linux and run:"
    }
    
    Write-Host "   ./$Output --help" -ForegroundColor White
    Write-Host "   ./$Output --list" -ForegroundColor White
    Write-Host "   ./$Output --test" -ForegroundColor White
    
} catch {
    Write-Error "Error creating bundle: $($_.Exception.Message)"
    Write-VerboseLog "Stack trace: $($_.Exception.StackTrace)"
    exit 1
}
# End of bundle.ps1
