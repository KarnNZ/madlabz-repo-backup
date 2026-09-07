param(
    [string]$Repository = "KarnNZ/madlabz-repo-backup"
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host "[FAIL] $Message" -ForegroundColor Red
    exit 1
}

function Ok([string]$Message) {
    Write-Host "[OK]   $Message" -ForegroundColor Green
}

function Info([string]$Message) {
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Fail "Git is not available."
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail "GitHub CLI (gh) is not installed. Use the connected GitHub workflow instead or install gh."
}

Info "Checking GitHub authentication..."
& gh auth status
if ($LASTEXITCODE -ne 0) {
    Fail "GitHub CLI is not authenticated."
}

Info "Validating Repo Backup package source..."
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "VALIDATE-PACKAGE.ps1")
if ($LASTEXITCODE -ne 0) {
    Fail "Package validation failed."
}
Ok "Package validation passed."

$existing = $false
& gh repo view $Repository --json nameWithOwner 1>$null 2>$null
if ($LASTEXITCODE -eq 0) {
    $existing = $true
}

if ($existing) {
    Fail "GitHub repository '$Repository' already exists. This first-publish helper will not overwrite or repurpose an existing repository."
}

if (Test-Path -LiteralPath (Join-Path $PSScriptRoot ".git")) {
    Fail "This source folder already contains .git. Use a clean extracted publish source folder."
}

Push-Location $PSScriptRoot
try {
    Info "Creating local Git repository..."
    & git init -b main
    if ($LASTEXITCODE -ne 0) { Fail "git init failed." }

    & git add .
    if ($LASTEXITCODE -ne 0) { Fail "git add failed." }

    & git commit -m "Release MadLabz Repo Backup v0.6.2"
    if ($LASTEXITCODE -ne 0) { Fail "Initial commit failed. Check your Git user.name/user.email." }

    Info "Creating public MIT-licensed GitHub repository..."
    & gh repo create $Repository `
        --public `
        --source . `
        --remote origin `
        --push `
        --description "Safely checkpoint multiple Git repositories from one local developer utility."
    if ($LASTEXITCODE -ne 0) { Fail "GitHub repository creation/push failed." }

    Ok "GitHub repository created and main pushed."

    Info "Creating release tag v0.6.2..."
    & git tag -a v0.6.2 -m "MadLabz Repo Backup v0.6.2"
    if ($LASTEXITCODE -ne 0) { Fail "Tag creation failed." }

    & git push origin v0.6.2
    if ($LASTEXITCODE -ne 0) { Fail "Tag push failed." }

    Ok "v0.6.2 tag pushed. GitHub Actions should now build the public release."
    Write-Host ""
    Info "Check:"
    Write-Host "  gh run list --repo $Repository --limit 5"
    Write-Host "  gh release view v0.6.2 --repo $Repository"
}
finally {
    Pop-Location
}
