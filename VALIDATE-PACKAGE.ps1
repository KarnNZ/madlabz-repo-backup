param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "repo-backup.ps1")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    Write-Host "[FAIL] repo-backup.ps1 was not found." -ForegroundColor Red
    exit 1
}

# Windows PowerShell 5.1 can misinterpret UTF-8-without-BOM script source.
# Repo Backup therefore keeps its executable PS1 source ASCII-only.
$scriptBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ScriptPath))
$nonAscii = @($scriptBytes | Where-Object { $_ -gt 127 })

if ($nonAscii.Count -gt 0) {
    Write-Host ""
    Write-Host "MADLABZ REPO BACKUP - PACKAGE VALIDATION" -ForegroundColor White
    Write-Host "ASCII source compatibility: FAIL" -ForegroundColor Red
    Write-Host ""
    Write-Host "repo-backup.ps1 contains non-ASCII bytes." -ForegroundColor Red
    Write-Host "For Windows PowerShell 5.1 compatibility, do NOT install this package." -ForegroundColor Yellow
    exit 1
}

$tokens = $null
$errors = $null

[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $ScriptPath),
    [ref]$tokens,
    [ref]$errors
)

if ($errors -and $errors.Count -gt 0) {
    Write-Host "" 
    Write-Host "MADLABZ REPO BACKUP - PACKAGE VALIDATION" -ForegroundColor White
    Write-Host "PowerShell parse: FAIL" -ForegroundColor Red
    Write-Host ""

    foreach ($errorItem in $errors) {
        $extent = $errorItem.Extent
        Write-Host ("Line {0}, column {1}: {2}" -f `
            $extent.StartLineNumber, `
            $extent.StartColumnNumber, `
            $errorItem.Message) -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Do NOT update the installed Repo Backup from this package." -ForegroundColor Yellow
    exit 1
}

# The graphical dashboard is a required part of the v0.7.0 Windows package.
# Validate it without launching any GUI or touching user configuration.
$packageDirectory = Split-Path -Parent $ScriptPath
$dashboardSource = Join-Path $packageDirectory "REPO-BACKUP-STATUS.ps1"
$dashboardLauncher = Join-Path $packageDirectory "OPEN-STATUS-DASHBOARD.cmd"
if (-not (Test-Path -LiteralPath $dashboardSource -PathType Leaf) -or
    -not (Test-Path -LiteralPath $dashboardLauncher -PathType Leaf)) {
    Write-Host "[FAIL] The GUI dashboard script or launcher is missing from the package." -ForegroundColor Red
    exit 1
}

$dashboardBytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $dashboardSource))
if (@($dashboardBytes | Where-Object { $_ -gt 127 }).Count -gt 0) {
    Write-Host "[FAIL] Desktop dashboard source contains non-ASCII bytes." -ForegroundColor Red
    exit 1
}

$dashboardTokens = $null
$dashboardErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $dashboardSource),
    [ref]$dashboardTokens,
    [ref]$dashboardErrors
)
if ($dashboardErrors -and $dashboardErrors.Count -gt 0) {
    foreach ($dashboardError in $dashboardErrors) {
        Write-Host $dashboardError.ToString() -ForegroundColor Red
    }
    Write-Host "[FAIL] Desktop dashboard PowerShell parse failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "MADLABZ REPO BACKUP - PACKAGE VALIDATION" -ForegroundColor White
Write-Host "ASCII source compatibility: PASS" -ForegroundColor Green
Write-Host "PowerShell parse: PASS" -ForegroundColor Green
Write-Host "Dashboard ASCII compatibility: PASS" -ForegroundColor Green
Write-Host "Dashboard PowerShell parse: PASS" -ForegroundColor Green
Write-Host "Version marker: " -NoNewline -ForegroundColor DarkGray

$source = Get-Content -LiteralPath $ScriptPath -Raw
if ($source -match '\$ScriptVersion\s*=\s*"([^"]+)"') {
    Write-Host $Matches[1] -ForegroundColor Green
}
else {
    Write-Host "not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "This check only validates that the package script parses correctly." -ForegroundColor DarkGray
exit 0
