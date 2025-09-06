###
### This script is mostly for my need of bundling the script
### and sending it off to a virtual machine for testing.
###
### Use this however you like ;)
###

Get-Content .env | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]+?)\s*=\s*(.*)$') {
        $name, $value = $matches[1], $matches[2]
        Set-Variable -Name $name -Value $value
    }
}

.\bundle.ps1 -Output ".\$SCRIPT_NAME"

if ($?) {
    scp -P "${SSH_PORT}" -p ".\$SCRIPT_NAME" "${SSH_USER}@${SSH_HOST}:${SSH_DIR}"
} else {
    Write-Error "bundle.ps1 failed. Aborting deployment."
}


### 🍉 wamterwemlon
### "You're not you when you're hungry."
###  - Snickers (2010)

### End of deploy_sandbox.ps1
