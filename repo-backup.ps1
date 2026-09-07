param(
    [Parameter(Position = 0)]
    [ValidateSet("dashboard", "onboard", "scan", "status", "backup", "list", "doctor", "add", "remove", "enable", "disable", "alias", "schedule", "auto", "install", "update", "version", "demo", "help")]
    [string]$Command = "dashboard",

    [Parameter(Position = 1)]
    [string]$Target,

    [Parameter(Position = 2)]
    [string]$Value,

    [string]$Config,

    [switch]$DryRun,

    [switch]$EnableDiscovered
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "0.6.2"
$DefaultReleaseApiUrl = "https://api.github.com/repos/KarnNZ/madlabz-repo-backup/releases/latest"

function Write-Info($Message) { Write-Host "[INFO]  $Message" -ForegroundColor Cyan }
function Write-Ok($Message)   { Write-Host "[OK]    $Message" -ForegroundColor Green }
function Write-Warn($Message) { Write-Host "[WARN]  $Message" -ForegroundColor Yellow }
function Write-Fail($Message) { Write-Host "[FAIL]  $Message" -ForegroundColor Red }

function Test-CommandExists($Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Normalize-Path([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        return [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
    }
    catch {
        return $Path.TrimEnd('\', '/')
    }
}

function Get-ProtectedBroadRootReason([string]$Path) {
    $normalized = Normalize-Path $Path
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }

    $protected = @()

    if ($env:USERPROFILE) {
        $protected += [pscustomobject]@{ Path = Normalize-Path $env:USERPROFILE; Label = "Windows user profile root" }
    }

    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        if ($desktop) {
            $protected += [pscustomobject]@{ Path = Normalize-Path $desktop; Label = "Desktop root" }
        }
    }
    catch { }

    foreach ($item in $protected) {
        if ($item.Path -and $normalized.Equals($item.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $item.Label
        }
    }

    try {
        $pathRoot = Normalize-Path ([System.IO.Path]::GetPathRoot($normalized))
        if ($pathRoot -and $normalized.Equals($pathRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return "drive root"
        }
    }
    catch { }

    return $null
}

function Test-DirectGitRepositoryRoot([string]$Path) {
    if (-not (Test-Path $Path -PathType Container)) { return $false }

    # A normal repo has a .git directory. Linked worktrees/submodules can have
    # a .git file, so Test-Path intentionally accepts either.
    return (Test-Path (Join-Path $Path ".git"))
}

function Get-DataDirectory {
    $base = $env:LOCALAPPDATA
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Join-Path $env:USERPROFILE "AppData\Local"
    }
    return Join-Path $base "MadLabz\RepoBackup"
}

$DataDirectory = Get-DataDirectory

if ([string]::IsNullOrWhiteSpace($Config)) {
    $Config = Join-Path $DataDirectory "repos.json"
}

$HistoryFile = Join-Path $DataDirectory "history.jsonl"
$AutoLogFile = Join-Path $DataDirectory "auto-runs.jsonl"
$InstalledAppDirectory = Join-Path $DataDirectory "App"
$PreviousAppDirectory = Join-Path $DataDirectory "App.previous"
$BinDirectory = Join-Path $DataDirectory "bin"
$InstalledScriptPath = Join-Path $InstalledAppDirectory "repo-backup.ps1"
$InstalledLauncherPath = Join-Path $InstalledAppDirectory "repo-backup.cmd"
$CommandShimPath = Join-Path $BinDirectory "repo-backup.cmd"
$BashCommandShimPath = Join-Path $BinDirectory "repo-backup"
$GitBashHomeBinDirectory = Join-Path $env:USERPROFILE "bin"
$GitBashHomeShimPath = Join-Path $GitBashHomeBinDirectory "repo-backup"
$InstallMetadataFile = Join-Path $DataDirectory "install.json"
$LegacyConfig = Join-Path $PSScriptRoot "repos.json"


function Test-IsInstalledCopy {
    $running = Normalize-Path $PSScriptRoot
    $installed = Normalize-Path $InstalledAppDirectory

    return $running -and $installed -and $running.Equals(
        $installed,
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Test-AppInstalled {
    return (Test-Path -LiteralPath $InstalledScriptPath -PathType Leaf) -and
           (Test-Path -LiteralPath $InstalledLauncherPath -PathType Leaf)
}

function Get-VersionFromScript([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }

    try {
        $content = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        $match = [regex]::Match($content, '\$ScriptVersion\s*=\s*"([^"]+)"')
        if ($match.Success) {
            return $match.Groups[1].Value
        }
    }
    catch { }

    return $null
}

function Get-InstalledVersion {
    return Get-VersionFromScript $InstalledScriptPath
}

function Get-PreferredSchedulerScriptPath {
    if (Test-AppInstalled) {
        return $InstalledScriptPath
    }

    return $PSCommandPath
}

function Test-BinOnUserPath {
    if ($env:OS -ne "Windows_NT") { return $false }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrWhiteSpace($userPath)) { return $false }

    $target = Normalize-Path $BinDirectory
    foreach ($segment in ($userPath -split ';')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }

        $candidate = Normalize-Path ([Environment]::ExpandEnvironmentVariables($segment.Trim()))
        if ($candidate -and $target -and $candidate.Equals($target, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Ensure-BinOnUserPath {
    if ($env:OS -ne "Windows_NT") { return $false }
    if (Test-BinOnUserPath) { return $false }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ([string]::IsNullOrWhiteSpace($userPath)) {
        $newPath = $BinDirectory
    }
    else {
        $newPath = $userPath.TrimEnd(';') + ";" + $BinDirectory
    }

    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    return $true
}


function Broadcast-EnvironmentChange {
    if ($env:OS -ne "Windows_NT") { return }

    try {
        if (-not ("MadLabz.NativeMethods" -as [type])) {
            Add-Type @"
using System;
using System.Runtime.InteropServices;

namespace MadLabz {
    public static class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd,
            uint Msg,
            UIntPtr wParam,
            string lParam,
            uint fuFlags,
            uint uTimeout,
            out UIntPtr lpdwResult
        );
    }
}
"@
        }

        $HWND_BROADCAST = [IntPtr]0xffff
        $WM_SETTINGCHANGE = 0x001A
        $SMTO_ABORTIFHUNG = 0x0002
        $result = [UIntPtr]::Zero

        [void][MadLabz.NativeMethods]::SendMessageTimeout(
            $HWND_BROADCAST,
            $WM_SETTINGCHANGE,
            [UIntPtr]::Zero,
            "Environment",
            $SMTO_ABORTIFHUNG,
            5000,
            [ref]$result
        )
    }
    catch {
        # Best-effort only. The persistent user PATH update has already been saved.
    }
}

function Write-CommandShim {
    if (-not (Test-Path -LiteralPath $BinDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $BinDirectory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $GitBashHomeBinDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $GitBashHomeBinDirectory -Force | Out-Null
    }

    $cmdShim = @"
@echo off
call "$InstalledLauncherPath" %*
"@

    Set-Content -LiteralPath $CommandShimPath -Value $cmdShim -Encoding ASCII

    # Convert the permanent Windows launcher path into Git Bash form.
    # String.Replace is literal; unlike -replace it does not parse backslash
    # as a regular expression.
    $bashTarget = $InstalledLauncherPath.Replace('\', '/')

    if ($bashTarget -match '^([A-Za-z]):/(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $rest = $Matches[2]
        $bashTarget = "/$drive/$rest"
    }

    # Build Bash text as literal PowerShell strings so "$@" remains Bash syntax.
    $bashShim = @(
        '#!/usr/bin/env bash',
        'exec "__MADLABZ_REPO_BACKUP_TARGET__" "$@"'
    ) -join "`n"

    $bashShim = $bashShim.Replace(
        "__MADLABZ_REPO_BACKUP_TARGET__",
        $bashTarget
    )

    # Windows/PATH-oriented Git Bash shim.
    Set-Content -LiteralPath $BashCommandShimPath -Value $bashShim -Encoding ASCII

    # Git Bash login shells commonly include ~/bin, making this independent
    # of whether the parent Windows process has refreshed its PATH yet.
    Set-Content -LiteralPath $GitBashHomeShimPath -Value $bashShim -Encoding ASCII
}

function Get-InstallableAppFiles {
    return @(
        "repo-backup.ps1",
        "repo-backup.cmd",
        "STATUS.cmd",
        "BACKUP-NOW.cmd",
        "SCAN-PROJECTS.cmd",
        "AUTO-BACKUP-SETTINGS.cmd",
        "AUTO-BACKUP-LOG.cmd",
        "TEST-AUTO-BACKUP.cmd",
        "ONBOARD.cmd",
        "DASHBOARD.cmd",
        "DEMO.cmd",
        "README.md",
        "CHANGELOG.md",
        "repos.example.json"
    )
}

function Write-InstallMetadata([string]$Action, [string]$PreviousVersion) {
    if (-not (Test-Path -LiteralPath $DataDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
    }

    $record = [pscustomobject]@{
        version = $ScriptVersion
        installedAt = [DateTimeOffset]::Now.ToString("o")
        action = $Action
        appPath = $InstalledAppDirectory
        commandShim = $CommandShimPath
        bashCommandShim = $BashCommandShimPath
        gitBashHomeShim = $GitBashHomeShimPath
        previousVersion = $PreviousVersion
    }

    $record | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $InstallMetadataFile -Encoding UTF8
}

function Invoke-Version {
    Show-Header "VERSION"

    Write-Ok "Running version: $ScriptVersion"
    Write-Info "Running from: $PSScriptRoot"

    if (Test-AppInstalled) {
        $installedVersion = Get-InstalledVersion
        Write-Ok "Installed version: $(if ($installedVersion) { $installedVersion } else { 'unknown' })"
        Write-Ok "Installed app: $InstalledAppDirectory"
        Write-Info "Windows command shim: $CommandShimPath"
        Write-Info "Git Bash PATH shim: $BashCommandShimPath"
        Write-Info "Git Bash home shim: $GitBashHomeShimPath"

        if (Test-IsInstalledCopy) {
            Write-Ok "Mode: Installed"
        }
        else {
            Write-Info "Mode: Download/update package (installed copy also exists)"
        }

        if (Test-BinOnUserPath) {
            Write-Ok "Command PATH: configured"
        }
        else {
            Write-Warn "Command PATH: not configured"
        }
    }
    else {
        Write-Info "Installed version: none"
        Write-Info "Mode: Portable/download package"
        Write-Info "Install with: repo-backup install   or double-click INSTALL.cmd"
    }
}

function Invoke-InstallPackage($Settings, [bool]$AsUpdate) {
    $title = if ($AsUpdate) { "UPDATE" } else { "INSTALL" }
    Show-Header $title

    if ($env:OS -ne "Windows_NT") {
        throw "V0.6.2 installer currently supports Windows only."
    }

    $sourceDirectory = Normalize-Path $PSScriptRoot
    $destinationDirectory = Normalize-Path $InstalledAppDirectory
    $previousVersion = Get-InstalledVersion
    $alreadyInstalledCopy = Test-IsInstalledCopy

    if ($alreadyInstalledCopy) {
        Write-Info "Repo Backup is already running from its permanent installed location."
        if ($AsUpdate) {
            Write-Warn "To update program files, run UPDATE.cmd from a newer downloaded Repo Backup package."
            return
        }
    }
    else {
        $activeTask = Get-SchedulerTaskObject $Settings
        if ($null -ne $activeTask -and $activeTask.State -eq 4) {
            throw "An automatic Repo Backup task is currently running. Wait for it to finish, then retry the install/update."
        }
        Write-Info "$(if ($AsUpdate) { 'Updating' } else { 'Installing' }) Repo Backup into its permanent application location..."
        Write-Info "App: $InstalledAppDirectory"
        Write-Info "Data: $DataDirectory"

        if (-not (Test-Path -LiteralPath $DataDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
        }

        $stageDirectory = Join-Path $DataDirectory ("App.stage." + [guid]::NewGuid().ToString("N"))

        try {
            New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null

            foreach ($file in Get-InstallableAppFiles) {
                $sourceFile = Join-Path $sourceDirectory $file
                if (Test-Path -LiteralPath $sourceFile -PathType Leaf) {
                    Copy-Item -LiteralPath $sourceFile -Destination (Join-Path $stageDirectory $file) -Force
                }
            }

            $stagedScript = Join-Path $stageDirectory "repo-backup.ps1"
            $stagedLauncher = Join-Path $stageDirectory "repo-backup.cmd"

            if (-not (Test-Path -LiteralPath $stagedScript -PathType Leaf) -or
                -not (Test-Path -LiteralPath $stagedLauncher -PathType Leaf)) {
                throw "Staged application is incomplete. Existing installation was not changed."
            }

            $stagedVersion = Get-VersionFromScript $stagedScript
            if ($stagedVersion -ne $ScriptVersion) {
                throw "Staged application version check failed. Existing installation was not changed."
            }

            if (Test-Path -LiteralPath $PreviousAppDirectory -PathType Container) {
                Remove-Item -LiteralPath $PreviousAppDirectory -Recurse -Force
            }

            if (Test-Path -LiteralPath $InstalledAppDirectory -PathType Container) {
                Move-Item -LiteralPath $InstalledAppDirectory -Destination $PreviousAppDirectory
            }

            try {
                Move-Item -LiteralPath $stageDirectory -Destination $InstalledAppDirectory
            }
            catch {
                if (-not (Test-Path -LiteralPath $InstalledAppDirectory) -and
                    (Test-Path -LiteralPath $PreviousAppDirectory -PathType Container)) {
                    Move-Item -LiteralPath $PreviousAppDirectory -Destination $InstalledAppDirectory
                }

                throw
            }
        }
        finally {
            if (Test-Path -LiteralPath $stageDirectory) {
                Remove-Item -LiteralPath $stageDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        Write-Ok "Application files installed: $InstalledAppDirectory"

        if ($previousVersion -and (Test-Path -LiteralPath $PreviousAppDirectory -PathType Container)) {
            Write-Info "Previous installed app preserved temporarily at: $PreviousAppDirectory"
        }
    }

    Write-CommandShim
    Write-Ok "Command shim: $CommandShimPath"

    $pathChanged = Ensure-BinOnUserPath
    Broadcast-EnvironmentChange

    if ($pathChanged) {
        Write-Ok "Added Repo Backup command folder to your user PATH."
    }
    else {
        Write-Ok "Repo Backup command folder is already on your user PATH."
    }

    Write-Ok "Git Bash launcher: $GitBashHomeShimPath"
    Write-Info "Windows was notified that the user environment changed."
    Write-Warn "Open a completely new terminal after installation/update before testing the global 'repo-backup' command."

    Write-InstallMetadata $(if ($AsUpdate) { "update" } else { "install" }) $previousVersion

    $hasScheduledRepos = @(
        $Settings.projects | Where-Object {
            $_.enabled -ne $false -and $null -ne (Get-ScheduleHours ([string]$_.autoSchedule))
        }
    ).Count -gt 0

    if ((Test-SchedulerInstalled $Settings) -or $hasScheduledRepos) {
        Write-Host ""
        Write-Info "Refreshing Windows auto-backup scheduler to the permanent application path..."
        Install-AutoScheduler $Settings $InstalledScriptPath $true
    }
    else {
        Write-Info "No automatic schedules are enabled, so no Windows scheduled task was created."
    }

    if (-not (Test-CommandExists "git")) {
        Write-Warn "Git is not currently available on PATH. Repo Backup is installed, but Git is required before backups can run."
    }

    Write-Host ""
    Write-Ok "Repo Backup v$ScriptVersion is installed."
    Write-Info "Your repository config and logs were not moved or replaced."
    Write-Info "Config: $Config"
    Write-Info "History: $HistoryFile"
    Write-Info "Auto log: $AutoLogFile"

    if ($pathChanged) {
        Write-Info "Next: open a new Git Bash/PowerShell window and run: repo-backup version"
    }
    else {
        Write-Info "Next: repo-backup version"
    }
}

function New-DefaultConfig {
    return [pscustomobject]@{
        version = 5
        defaults = [pscustomobject]@{
            remote = "origin"
            commitMessagePrefix = "Backup"
            autoBackupIdleMinutes = 5
            schedulerTaskName = "MadLabz Repo Backup Auto"
            notifyOnAutoAttention = $true
            scanRoots = @((Join-Path $env:USERPROFILE "Desktop"))
            excludedDirectories = @(
                "node_modules", ".next", "dist", "build", "coverage",
                ".venv", "venv", "vendor", ".turbo", ".cache"
            )
        }
        projects = @()
    }
}


function Ensure-ConfigShape($Settings) {
    $changed = $false
    $template = New-DefaultConfig

    if (-not $Settings.defaults) {
        $Settings | Add-Member -NotePropertyName defaults -NotePropertyValue $template.defaults -Force
        $changed = $true
    }

    foreach ($prop in $template.defaults.PSObject.Properties) {
        if (-not $Settings.defaults.PSObject.Properties[$prop.Name]) {
            $Settings.defaults | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
            $changed = $true
        }
    }

    if (-not $Settings.projects) {
        $Settings | Add-Member -NotePropertyName projects -NotePropertyValue @() -Force
        $changed = $true
    }

    foreach ($project in @($Settings.projects)) {
        if (-not $project.PSObject.Properties["autoSchedule"]) {
            $project | Add-Member -NotePropertyName autoSchedule -NotePropertyValue "manual" -Force
            $changed = $true
        }

        if (-not $project.PSObject.Properties["lastAutoRunAt"]) {
            $project | Add-Member -NotePropertyName lastAutoRunAt -NotePropertyValue $null -Force
            $changed = $true
        }

        if (-not $project.PSObject.Properties["lastAutoStatus"]) {
            $project | Add-Member -NotePropertyName lastAutoStatus -NotePropertyValue $null -Force
            $changed = $true
        }

        if (-not $project.PSObject.Properties["lastAutoSuccessAt"]) {
            $project | Add-Member -NotePropertyName lastAutoSuccessAt -NotePropertyValue $null -Force
            $changed = $true
        }

        if (-not $project.PSObject.Properties["lastAutoFailureAt"]) {
            $project | Add-Member -NotePropertyName lastAutoFailureAt -NotePropertyValue $null -Force
            $changed = $true
        }

        if (-not $project.PSObject.Properties["lastAutoFailureStatus"]) {
            $project | Add-Member -NotePropertyName lastAutoFailureStatus -NotePropertyValue $null -Force
            $changed = $true
        }

        if (-not $project.PSObject.Properties["lastAutoFailureDetails"]) {
            $project | Add-Member -NotePropertyName lastAutoFailureDetails -NotePropertyValue $null -Force
            $changed = $true
        }
    }

    if (-not $Settings.PSObject.Properties["onboardingCompleteAt"]) {
        $Settings | Add-Member -NotePropertyName onboardingCompleteAt -NotePropertyValue $null -Force
        $changed = $true
    }

    if (-not $Settings.PSObject.Properties["version"] -or [int]$Settings.version -lt 5) {
        if ($Settings.PSObject.Properties["version"]) {
            $Settings.version = 5
        }
        else {
            $Settings | Add-Member -NotePropertyName version -NotePropertyValue 5 -Force
        }
        $changed = $true
    }

    return $changed
}

function Get-ProjectDisplayName($Project) {
    if ($Project.PSObject.Properties["alias"] -and -not [string]::IsNullOrWhiteSpace([string]$Project.alias)) {
        return [string]$Project.alias
    }

    return [string]$Project.name
}

function Find-ProjectMatches($Settings, [string]$Selector) {
    if ([string]::IsNullOrWhiteSpace($Selector)) {
        return @()
    }

    $normalizedSelector = Normalize-Path $Selector

    return @(
        $Settings.projects | Where-Object {
            $nameMatches = ([string]$_.name).Equals($Selector, [System.StringComparison]::OrdinalIgnoreCase)
            $aliasMatches = $false

            if ($_.PSObject.Properties["alias"] -and $_.alias) {
                $aliasMatches = ([string]$_.alias).Equals($Selector, [System.StringComparison]::OrdinalIgnoreCase)
            }

            $projectPath = Normalize-Path ([string]$_.path)
            $pathMatches = $projectPath -and $normalizedSelector -and $projectPath.Equals($normalizedSelector, [System.StringComparison]::OrdinalIgnoreCase)

            $nameMatches -or $aliasMatches -or $pathMatches
        }
    )
}

function Get-CanonicalSchedule([string]$Schedule) {
    if ([string]::IsNullOrWhiteSpace($Schedule)) { return $null }

    switch ($Schedule.Trim().ToLowerInvariant()) {
        "off"     { return "manual" }
        "manual"  { return "manual" }
        "hourly"  { return "hourly" }
        "1h"      { return "hourly" }
        "6h"      { return "6h" }
        "6hour"   { return "6h" }
        "6hours"  { return "6h" }
        "daily"   { return "daily" }
        "24h"     { return "daily" }
        default   { return $null }
    }
}

function Get-ScheduleHours([string]$Schedule) {
    switch (Get-CanonicalSchedule $Schedule) {
        "hourly" { return 1.0 }
        "6h"     { return 6.0 }
        "daily"  { return 24.0 }
        default  { return $null }
    }
}

function Get-ScheduleLabel([string]$Schedule) {
    switch (Get-CanonicalSchedule $Schedule) {
        "hourly" { return "Hourly" }
        "6h"     { return "Every 6 hours" }
        "daily"  { return "Daily" }
        default  { return "Manual" }
    }
}

function Test-ProjectAutoDue($Project) {
    $hours = Get-ScheduleHours ([string]$Project.autoSchedule)
    if ($null -eq $hours) { return $false }

    if (-not $Project.lastAutoRunAt) {
        return $true
    }

    try {
        $last = [DateTimeOffset]::Parse([string]$Project.lastAutoRunAt)
        return (([DateTimeOffset]::Now - $last).TotalHours -ge $hours)
    }
    catch {
        return $true
    }
}

function Get-RepoIdleMinutes([string]$Path) {
    $changed = @(Get-ChangedFiles $Path)
    if ($changed.Count -eq 0) {
        return [double]::PositiveInfinity
    }

    $latest = $null

    foreach ($relative in $changed) {
        try {
            $full = Join-Path -Path $Path -ChildPath $relative -ErrorAction Stop
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

            $item = Get-Item -LiteralPath $full -ErrorAction Stop
            if ($null -eq $latest -or $item.LastWriteTimeUtc -gt $latest) {
                $latest = $item.LastWriteTimeUtc
            }
        }
        catch { }
    }

    if ($null -eq $latest) {
        return [double]::PositiveInfinity
    }

    return ([DateTime]::UtcNow - $latest).TotalMinutes
}

function Get-SchedulerTaskName($Settings) {
    if ($Settings.defaults.schedulerTaskName) {
        return [string]$Settings.defaults.schedulerTaskName
    }

    return "MadLabz Repo Backup Auto"
}

function Test-SchedulerInstalled($Settings) {
    # "Task not found" is the normal state before auto-backup is installed.
    # schtasks writes that condition to stderr, so suppress it locally rather
    # than allowing the script-wide ErrorActionPreference=Stop to treat it as
    # a fatal Repo Backup error.
    $command = Get-Command "schtasks.exe" -ErrorAction SilentlyContinue
    if (-not $command) { return $false }

    $taskName = Get-SchedulerTaskName $Settings
    $previousPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = "SilentlyContinue"
        & $command.Source /Query /TN $taskName *> $null
        $exitCode = $LASTEXITCODE
        return ($exitCode -eq 0)
    }
    catch {
        return $false
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Save-Config($Settings) {
    if (-not (Test-Path $DataDirectory)) {
        New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
    }

    $Settings | ConvertTo-Json -Depth 12 | Set-Content -Path $Config -Encoding UTF8
}

function Import-LegacyConfigIfAvailable {
    if (Test-Path $Config) { return }

    if (Test-Path $LegacyConfig) {
        try {
            $legacy = Get-Content $LegacyConfig -Raw | ConvertFrom-Json
            $new = New-DefaultConfig

            if ($legacy.remote) {
                $new.defaults.remote = [string]$legacy.remote
            }

            if ($legacy.commitMessagePrefix) {
                $new.defaults.commitMessagePrefix = [string]$legacy.commitMessagePrefix
            }

            $projects = @()
            foreach ($project in @($legacy.projects)) {
                if (-not $project.path) { continue }

                $projects += [pscustomobject]@{
                    name = if ($project.name) { [string]$project.name } else { Split-Path ([string]$project.path) -Leaf }
                    path = Normalize-Path ([string]$project.path)
                    enabled = if ($null -eq $project.enabled) { $true } else { [bool]$project.enabled }
                    remote = if ($project.remote) { [string]$project.remote } else { $null }
                    autoSchedule = "manual"
                    lastAutoRunAt = $null
                    lastAutoStatus = $null
                    lastAutoSuccessAt = $null
                    lastAutoFailureAt = $null
                    lastAutoFailureStatus = $null
                    lastAutoFailureDetails = $null
                }
            }

            $new.projects = $projects
            Save-Config $new
            Write-Ok "Imported your V0.1 repos.json into the V0.2 config."
            return
        }
        catch {
            Write-Warn "Found V0.1 repos.json but could not import it: $($_.Exception.Message)"
        }
    }

    Save-Config (New-DefaultConfig)
}

function Load-Config {
    Import-LegacyConfigIfAvailable

    try {
        $settings = Get-Content $Config -Raw | ConvertFrom-Json
    }
    catch {
        throw "Could not parse config '$Config': $($_.Exception.Message)"
    }

    if (-not $settings.defaults) {
        $settings | Add-Member -NotePropertyName defaults -NotePropertyValue (New-DefaultConfig).defaults -Force
    }

    if (-not $settings.projects) {
        $settings | Add-Member -NotePropertyName projects -NotePropertyValue @() -Force
    }

    if (Ensure-ConfigShape $settings) {
        Save-Config $settings
    }

    return $settings
}

function Resolve-RepoRoot([string]$Path) {
    if (-not (Test-Path $Path)) { return $null }

    try {
        $root = (& git -C $Path rev-parse --show-toplevel 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $root) { return $null }
        return Normalize-Path (($root | Select-Object -First 1).Trim())
    }
    catch {
        return $null
    }
}

function Get-GitDir([string]$Path) {
    try {
        $value = (& git -C $Path rev-parse --git-dir 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $value) { return $null }

        $gitDir = ($value | Select-Object -First 1).Trim()

        if ([System.IO.Path]::IsPathRooted($gitDir)) {
            return Normalize-Path $gitDir
        }

        return Normalize-Path (Join-Path $Path $gitDir)
    }
    catch {
        return $null
    }
}

function Get-LocalTrackingRef([string]$Path, [string]$Branch, [string]$Remote) {
    # `git rev-parse @{u}` writes a fatal error when a branch has no upstream.
    # for-each-ref returns an empty string instead, which is safe for status probes.
    $upstream = (& git -C $Path for-each-ref --format='%(upstream:short)' "refs/heads/$Branch" 2>$null | Select-Object -First 1)
    if ($upstream) {
        return $upstream.Trim()
    }

    # No configured upstream: if a matching remote-tracking branch exists, compare
    # against that for informational status only.
    $candidate = "$Remote/$Branch"
    $remoteTracking = (& git -C $Path for-each-ref --format='%(refname:short)' "refs/remotes/$Remote/$Branch" 2>$null | Select-Object -First 1)
    if ($remoteTracking) {
        return $candidate
    }

    return $null
}

function Test-RemoteTrackingBranchExists([string]$Path, [string]$Remote, [string]$Branch) {
    $remoteTracking = (& git -C $Path for-each-ref --format='%(refname:short)' "refs/remotes/$Remote/$Branch" 2>$null | Select-Object -First 1)
    return -not [string]::IsNullOrWhiteSpace($remoteTracking)
}

function Test-HeadExists([string]$Path) {
    # Safe for newly initialized repositories that do not have an initial commit yet.
    try {
        $branch = ((& git -C $Path branch --show-current 2>$null) | Select-Object -First 1)
        if (-not $branch) { return $false }

        $objectId = (& git -C $Path for-each-ref --format='%(objectname)' "refs/heads/$($branch.Trim())" 2>$null | Select-Object -First 1)
        return -not [string]::IsNullOrWhiteSpace($objectId)
    }
    catch {
        return $false
    }
}

function Get-RepoOperation([string]$Path) {
    $gitDir = Get-GitDir $Path
    if (-not $gitDir) { return $null }

    if (Test-Path (Join-Path $gitDir "MERGE_HEAD")) { return "merge" }
    if (Test-Path (Join-Path $gitDir "CHERRY_PICK_HEAD")) { return "cherry-pick" }
    if (Test-Path (Join-Path $gitDir "REVERT_HEAD")) { return "revert" }
    if (Test-Path (Join-Path $gitDir "rebase-merge")) { return "rebase" }
    if (Test-Path (Join-Path $gitDir "rebase-apply")) { return "rebase" }

    return $null
}

function Get-ChangedFiles([string]$Path) {
    $files = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    # core.safecrlf=false prevents harmless line-ending warnings from becoming
    # PowerShell error records while we are only inspecting filenames.
    foreach ($line in @(& git -c core.safecrlf=false -c core.quotepath=false -C $Path diff --name-only -- 2>$null)) {
        if ($line) { [void]$files.Add([string]$line) }
    }

    foreach ($line in @(& git -c core.safecrlf=false -c core.quotepath=false -C $Path diff --cached --name-only -- 2>$null)) {
        if ($line) { [void]$files.Add([string]$line) }
    }

    foreach ($line in @(& git -c core.quotepath=false -C $Path ls-files --others --exclude-standard 2>$null)) {
        if ($line) { [void]$files.Add([string]$line) }
    }

    return @($files)
}

function Test-SensitiveFileName([string]$RelativePath) {
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $null
    }

    # Git paths are slash-delimited strings, not Windows filesystem paths.
    # Do not feed them to System.IO.Path because Git may quote/escape a pathname
    # (especially a Unicode pathname) in a form that Windows considers invalid.
    $gitPath = $RelativePath.Trim()

    if ($gitPath.Length -ge 2 -and $gitPath.StartsWith('"') -and $gitPath.EndsWith('"')) {
        $gitPath = $gitPath.Substring(1, $gitPath.Length - 2)
    }

    $normalizedGitPath = $gitPath.Replace('\', '/')
    $parts = @($normalizedGitPath -split '/')
    $leaf = if ($parts.Count -gt 0) { [string]$parts[$parts.Count - 1] } else { $normalizedGitPath }
    $lowerLeaf = $leaf.ToLowerInvariant()

    $allowedEnvTemplates = @(".env.example", ".env.sample", ".env.template")

    if ($lowerLeaf -match '^\.env($|\.)' -and ($allowedEnvTemplates -notcontains $lowerLeaf)) {
        return "Sensitive environment file: $RelativePath"
    }

    if ($normalizedGitPath -match '(?i)(^|/)(id_rsa|id_ed25519)($|\.)') {
        return "Private SSH key filename: $RelativePath"
    }

    if ($normalizedGitPath -match '(?i)\.(pem|p12|pfx|key)$') {
        return "Potential private key/certificate file: $RelativePath"
    }

    if ($normalizedGitPath -match '(?i)(credentials|service[-_]?account).*\.json$') {
        return "Potential credentials file: $RelativePath"
    }

    return $null
}

function Get-SecretPatterns {
    # High-confidence token formats. Generic assignments are classified separately
    # so references such as "apiKey: API_KEY" or "apiKey: process.env.API_KEY"
    # are not mistaken for literal secrets.
    return @(
        @{ Name = "Private key"; Regex = '-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----' },
        @{ Name = "AWS access key"; Regex = '\bAKIA[0-9A-Z]{16}\b' },
        @{ Name = "GitHub token"; Regex = '\bgh[pousr]_[A-Za-z0-9]{30,}\b' },
        @{ Name = "GitHub fine-grained token"; Regex = '\bgithub_pat_[A-Za-z0-9_]{20,}\b' },
        @{ Name = "OpenAI-style secret key"; Regex = '\bsk-[A-Za-z0-9_-]{20,}\b' },
        @{ Name = "Stripe secret key"; Regex = '\bsk_(live|test)_[A-Za-z0-9]{16,}\b' }
    )
}

function Test-PlaceholderSecretValue([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }

    $lower = $Value.ToLowerInvariant()
    $markers = @(
        "your_", "your-", "<your", "example", "placeholder", "replace_me",
        "replace-me", "changeme", "change-me", "dummy", "xxxxx", "xxxx",
        "insert_", "insert-", "sample", "not-a-real", "fake_"
    )

    foreach ($marker in $markers) {
        if ($lower.Contains($marker)) { return $true }
    }

    return $false
}

function Test-LineForAssignedSecret([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }

    $match = [regex]::Match(
        $Line,
        '(?i)\b(api[_-]?key|secret[_-]?key|access[_-]?token|auth[_-]?token|password|client[_-]?secret|OPENAI_API_KEY|RESEND_API_KEY|SUPABASE_SERVICE_ROLE_KEY|STRIPE_SECRET_KEY|GITHUB_TOKEN)\b\s*[:=]\s*(.+)$'
    )

    if (-not $match.Success) { return $null }

    $rhs = $match.Groups[2].Value.Trim()
    $rhs = $rhs.TrimEnd(',', ';').Trim()

    # Environment/config references are safe references, not embedded values.
    if ($rhs -match '(?i)(process\.env|import\.meta\.env|deno\.env|os\.environ|getenv\s*\(|\$env:|environment\.)') {
        return $null
    }

    # An identifier/member reference such as API_KEY, config.apiKey, env.KEY.
    if ($rhs -match '^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*$') {
        return $null
    }

    # Template/env interpolation is a reference.
    if ($rhs -match '^\$\{[^}]+\}$') {
        return $null
    }

    $candidate = $rhs
    if (
        ($candidate.StartsWith('"') -and $candidate.EndsWith('"')) -or
        ($candidate.StartsWith("'") -and $candidate.EndsWith("'")) -or
        ($candidate.StartsWith('`') -and $candidate.EndsWith('`'))
    ) {
        if ($candidate.Length -ge 2) {
            $candidate = $candidate.Substring(1, $candidate.Length - 2)
        }
    }

    if (Test-PlaceholderSecretValue $candidate) {
        return $null
    }

    # Only block generic assignments when the RHS looks like a substantial literal
    # token/value. This intentionally avoids ordinary short configuration values.
    if ($candidate.Length -ge 16 -and $candidate -match '^[A-Za-z0-9_\-\/+=.:]+$') {
        return "Potential literal secret assignment"
    }

    return $null
}

function Test-TextForSecrets([string]$Text) {
    $findings = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    foreach ($pattern in (Get-SecretPatterns)) {
        if ($Text -match $pattern.Regex) {
            $findings.Add("Potential secret in changed content: $($pattern.Name)")
        }
    }

    foreach ($line in ($Text -split "`r?`n")) {
        $assignmentFinding = Test-LineForAssignedSecret $line
        if ($assignmentFinding) {
            $findings.Add("Potential secret in changed content: $assignmentFinding")
        }
    }

    return @($findings | Select-Object -Unique)
}

function Get-AddedDiffText([string]$Path) {
    # A freshly initialized repository has an unborn HEAD. All of its files are
    # untracked and are scanned separately below, so there is no HEAD diff to read.
    if (-not (Test-HeadExists $Path)) {
        return ""
    }

    $previousPreference = $ErrorActionPreference
    try {
        # Windows Git can emit benign LF/CRLF warnings to stderr while calculating
        # a diff. Do not let those warnings abort the safety scan.
        $ErrorActionPreference = "SilentlyContinue"
        $diffLines = @(& git -c core.safecrlf=false -C $Path diff HEAD --no-ext-diff --unified=0 -- 2>$null)
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    $added = foreach ($line in $diffLines) {
        if ($line.StartsWith("+") -and -not $line.StartsWith("+++")) {
            if ($line.Length -gt 1) { $line.Substring(1) } else { "" }
        }
    }

    return ($added -join "`n")
}


function Get-UnignoredGeneratedDirectories([string]$Path) {
    $heavyDirectories = @(
        "node_modules", ".next", "dist", "build", "coverage", ".turbo",
        ".cache", ".venv", "venv", "vendor", ".expo"
    )

    $findings = New-Object System.Collections.Generic.List[string]
    $statusLines = @(& git -c core.quotepath=false -C $Path status --porcelain=v1 --untracked-files=normal 2>$null)

    foreach ($line in $statusLines) {
        if (-not $line.StartsWith("?? ")) { continue }

        $relative = $line.Substring(3).Trim().Trim('"').Replace('\', '/')
        foreach ($dir in $heavyDirectories) {
            if ($relative -eq "$dir/" -or $relative.StartsWith("$dir/") -or $relative -match "(^|/)$([regex]::Escape($dir))/$") {
                $findings.Add("Unignored generated/dependency directory: $relative")
                break
            }
        }
    }

    return @($findings | Select-Object -Unique)
}

function Get-TrackedSensitiveFiles([string]$Path) {
    $findings = New-Object System.Collections.Generic.List[string]

    foreach ($file in @(& git -c core.quotepath=false -C $Path ls-files 2>$null)) {
        if (-not $file) { continue }

        $finding = Test-SensitiveFileName $file
        if ($finding) {
            $findings.Add("Tracked sensitive file: $file")
        }
    }

    return @($findings | Select-Object -Unique)
}

function Get-HistorySensitiveFiles([string]$Path) {
    $findings = New-Object System.Collections.Generic.List[string]

    if (-not (Test-HeadExists $Path)) {
        return @()
    }

    foreach ($entry in @(& git -c core.quotepath=false -C $Path rev-list --objects --all 2>$null)) {
        if (-not $entry) { continue }

        $space = $entry.IndexOf(" ")
        if ($space -lt 0 -or $space -ge ($entry.Length - 1)) { continue }

        $file = $entry.Substring($space + 1)
        $finding = Test-SensitiveFileName $file

        if ($finding) {
            $findings.Add("Sensitive file exists in Git history: $file")
        }
    }

    return @($findings | Select-Object -Unique)
}

function Test-WorkingTreeSecrets([string]$Path) {
    $findings = New-Object System.Collections.Generic.List[string]

    # Fail quickly instead of recursively scanning enormous dependency/build trees.
    foreach ($finding in @(Get-UnignoredGeneratedDirectories $Path)) {
        $findings.Add($finding)
    }

    if ($findings.Count -gt 0) {
        return @($findings | Select-Object -Unique)
    }

    foreach ($finding in @(Get-TrackedSensitiveFiles $Path)) {
        $findings.Add($finding)
    }

    $changedFiles = @(Get-ChangedFiles $Path)

    foreach ($file in $changedFiles) {
        $nameFinding = Test-SensitiveFileName $file
        if ($nameFinding) {
            $findings.Add($nameFinding)
        }
    }

    foreach ($finding in @(Test-TextForSecrets (Get-AddedDiffText $Path))) {
        $findings.Add($finding)
    }

    $untracked = @(& git -c core.quotepath=false -C $Path ls-files --others --exclude-standard 2>$null)
    $binaryExtensions = @(
        ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".pdf", ".zip", ".7z",
        ".exe", ".dll", ".woff", ".woff2", ".ttf", ".mp4", ".mov", ".mp3", ".wav"
    )

    foreach ($relative in $untracked) {
        if (-not $relative) { continue }

        try {
            $full = Join-Path -Path $Path -ChildPath $relative -ErrorAction Stop
        }
        catch {
            $findings.Add("Unable to safely inspect changed path: $relative")
            continue
        }

        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }

        # Derive the extension from Git's relative pathname rather than using
        # System.IO.Path on a potentially quoted/escaped Git path.
        $normalizedRelative = ([string]$relative).Replace('\', '/')
        $leafParts = @($normalizedRelative -split '/')
        $leaf = if ($leafParts.Count -gt 0) { [string]$leafParts[$leafParts.Count - 1] } else { $normalizedRelative }
        $dot = $leaf.LastIndexOf('.')
        $extension = if ($dot -ge 0) { $leaf.Substring($dot).ToLowerInvariant() } else { "" }

        if ($binaryExtensions -contains $extension) { continue }

        try {
            $info = Get-Item -LiteralPath $full -ErrorAction Stop
            if ($info.Length -gt 2097152) { continue }

            $content = Get-Content -LiteralPath $full -Raw -ErrorAction Stop
            foreach ($finding in @(Test-TextForSecrets $content)) {
                $findings.Add("$finding ($relative)")
            }
        }
        catch {
            # A transiently disappearing file is harmless. Other unsafe-path cases
            # are already caught above before content inspection.
        }
    }

    return @($findings | Select-Object -Unique)
}

function Find-GitRepositories([string]$Root, [string[]]$ExcludedDirectories) {
    $results = New-Object System.Collections.Generic.List[string]

    if (-not (Test-Path $Root)) {
        Write-Warn "Scan root does not exist: $Root"
        return @()
    }

    $resolved = (Resolve-Path $Root).Path
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($resolved)

    $excluded = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @($ExcludedDirectories)) {
        if ($name) { [void]$excluded.Add([string]$name) }
    }

    while ($stack.Count -gt 0) {
        $current = $stack.Pop()

        if (Test-Path (Join-Path $current ".git")) {
            $repoRoot = Resolve-RepoRoot $current
            if ($repoRoot) {
                $results.Add($repoRoot)
            }
            continue
        }

        try {
            $children = Get-ChildItem -LiteralPath $current -Directory -Force -ErrorAction SilentlyContinue
            foreach ($child in $children) {
                if ($excluded.Contains($child.Name)) { continue }

                if (($child.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                    continue
                }

                $stack.Push($child.FullName)
            }
        }
        catch {
            # Permission-denied folders are skipped.
        }
    }

    return @($results | Sort-Object -Unique)
}

function Get-ProjectRemote($Project, $Settings) {
    if ($Project.remote) { return [string]$Project.remote }
    if ($Settings.defaults.remote) { return [string]$Settings.defaults.remote }
    return "origin"
}

function Get-ProjectState($Project, $Settings) {
    $path = Normalize-Path ([string]$Project.path)

    $protectedReason = Get-ProtectedBroadRootReason $path
    if ($protectedReason) {
        return [pscustomobject]@{
            Name = Get-ProjectDisplayName $Project
            Path = $path
            Valid = $false
            Ready = $false
            Branch = "-"
            Changes = "-"
            Ahead = 0
            Behind = 0
            Remote = "-"
            Tracking = "-"
            Operation = "-"
            Note = "Blocked unsafe configured path: $protectedReason ($path)"
        }
    }

    $root = Resolve-RepoRoot $path

    if (-not $root) {
        return [pscustomobject]@{
            Name = Get-ProjectDisplayName $Project
            Path = $path
            Valid = $false
            Ready = $false
            Branch = "-"
            Changes = "-"
            Ahead = 0
            Behind = 0
            Remote = "-"
            Tracking = "-"
            Operation = "-"
            Note = "Not a Git repository or path missing"
        }
    }

    if ((Normalize-Path $root) -ne (Normalize-Path $path)) {
        return [pscustomobject]@{
            Name = Get-ProjectDisplayName $Project
            Path = $path
            Valid = $false
            Ready = $false
            Branch = "-"
            Changes = "-"
            Ahead = 0
            Behind = 0
            Remote = "-"
            Tracking = "-"
            Operation = "-"
            Note = "Configured path is not the repository root. Git root: $root"
        }
    }

    $branch = ((& git -C $path branch --show-current 2>$null) | Select-Object -First 1)
    if ($branch) { $branch = $branch.Trim() }

    $changes = @(& git -C $path status --porcelain=v1 2>$null).Count
    $remote = Get-ProjectRemote $Project $Settings
    $operation = Get-RepoOperation $path

    $remoteNames = @(& git -C $path remote 2>$null)
    $remoteConfigured = $remoteNames -contains $remote

    $ahead = 0
    $behind = 0
    $tracking = "-"
    $note = ""

    if (-not $remoteConfigured) {
        $note = "Remote '$remote' not configured"
    }
    elseif ($branch) {
        $trackingRef = Get-LocalTrackingRef $path $branch $remote

        if ($trackingRef -and (Test-HeadExists $path)) {
            $tracking = $trackingRef

            $aheadValue = (& git -C $path rev-list --count "$trackingRef..HEAD" 2>$null | Select-Object -First 1)
            if ($LASTEXITCODE -eq 0 -and $aheadValue) { $ahead = [int]$aheadValue }

            $behindValue = (& git -C $path rev-list --count "HEAD..$trackingRef" 2>$null | Select-Object -First 1)
            if ($LASTEXITCODE -eq 0 -and $behindValue) { $behind = [int]$behindValue }

            $configuredUpstream = (& git -C $path for-each-ref --format='%(upstream:short)' "refs/heads/$branch" 2>$null | Select-Object -First 1)
            if (-not $configuredUpstream) {
                $note = "No upstream configured; comparing local refs to $trackingRef"
            }
        }
        elseif (-not (Test-HeadExists $path)) {
            $note = "No commits yet; ready for initial checkpoint"
        }
        else {
            $note = "No upstream/remote-tracking branch yet"
        }
    }

    $ready = $remoteConfigured -and -not $operation -and -not [string]::IsNullOrWhiteSpace($branch)

    return [pscustomobject]@{
        Name = Get-ProjectDisplayName $Project
        Path = $path
        Valid = $true
        Ready = $ready
        Branch = if ($branch) { $branch } else { "(detached)" }
        Changes = $changes
        Ahead = $ahead
        Behind = $behind
        Remote = if ($remoteConfigured) { $remote } else { "(missing $remote)" }
        Tracking = $tracking
        Operation = if ($operation) { $operation } else { "-" }
        Note = $note
    }
}

function Write-History($Record) {
    if (-not (Test-Path $DataDirectory)) {
        New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
    }

    ($Record | ConvertTo-Json -Compress -Depth 8) | Add-Content -Path $HistoryFile -Encoding UTF8
}


function Write-AutoEvent(
    [string]$RunId,
    [string]$Type,
    [string]$Status,
    [string]$Message,
    [string]$Project = $null,
    [string]$Details = $null,
    [bool]$IsDryRun = $false
) {
    if (-not (Test-Path $DataDirectory)) {
        New-Item -ItemType Directory -Path $DataDirectory -Force | Out-Null
    }

    $record = [pscustomobject]@{
        timestamp = [DateTimeOffset]::Now.ToString("o")
        version = $ScriptVersion
        runId = $RunId
        type = $Type
        status = $Status
        project = $Project
        message = $Message
        details = $Details
        dryRun = $IsDryRun
    }

    ($record | ConvertTo-Json -Compress -Depth 6) | Add-Content -Path $AutoLogFile -Encoding UTF8
}

function Format-ShortAutoTime([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return "-" }

    try {
        return ([DateTimeOffset]::Parse($Value)).ToLocalTime().ToString("yyyy-MM-dd HH:mm")
    }
    catch {
        return $Value
    }
}

function Test-ProjectHasUnresolvedAutoIssue($Project) {
    if (-not $Project.lastAutoFailureAt) { return $false }

    try {
        $failure = [DateTimeOffset]::Parse([string]$Project.lastAutoFailureAt)

        if (-not $Project.lastAutoSuccessAt) {
            return $true
        }

        $success = [DateTimeOffset]::Parse([string]$Project.lastAutoSuccessAt)
        return ($failure -gt $success)
    }
    catch {
        return $true
    }
}

function Show-AutoLog([int]$Count = 20) {
    Show-Header "AUTO LOG"

    if ($Count -lt 1) { $Count = 20 }
    if ($Count -gt 200) { $Count = 200 }

    if (-not (Test-Path $AutoLogFile -PathType Leaf)) {
        Write-Info "No automatic-run log exists yet."
        Write-Info "Log path: $AutoLogFile"
        return
    }

    $rows = New-Object System.Collections.Generic.List[object]

    foreach ($line in @(Get-Content -Path $AutoLogFile -Tail $Count -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
            $entry = $line | ConvertFrom-Json
            $rows.Add([pscustomobject]@{
                Time = Format-ShortAutoTime ([string]$entry.timestamp)
                Type = [string]$entry.type
                Project = if ($entry.project) { [string]$entry.project } else { "-" }
                Status = [string]$entry.status
                Message = [string]$entry.message
            })
        }
        catch { }
    }

    if ($rows.Count -eq 0) {
        Write-Info "No readable automatic-run records found."
    }
    else {
        $rows.ToArray() | Format-Table -AutoSize -Wrap
    }

    Write-Info "Log path: $AutoLogFile"
}

function Get-SchedulerTaskObject($Settings) {
    try {
        $service = New-Object -ComObject "Schedule.Service"
        $service.Connect()
        $folder = $service.GetFolder("\")
        return $folder.GetTask((Get-SchedulerTaskName $Settings))
    }
    catch {
        return $null
    }
}

function Test-SchedulerTargetsCurrentScript($Settings) {
    $task = Get-SchedulerTaskObject $Settings
    if ($null -eq $task) { return $false }

    try {
        $actions = $task.Definition.Actions
        if ($actions.Count -lt 1) { return $false }

        $action = $actions.Item(1)
        $arguments = [string]$action.Arguments
        $preferredPath = Get-PreferredSchedulerScriptPath
        return ($arguments.IndexOf($preferredPath, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
    }
    catch {
        return $false
    }
}

function Show-AutoAttentionNotification([string]$Message) {
    if ($env:OS -ne "Windows_NT") { return }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop

        $notify = New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon = [System.Drawing.SystemIcons]::Warning
        $notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Warning
        $notify.BalloonTipTitle = "MadLabz Repo Backup needs attention"
        $notify.BalloonTipText = $Message
        $notify.Visible = $true
        $notify.ShowBalloonTip(8000)

        # Give Windows enough time to enqueue/display the balloon before disposal.
        Start-Sleep -Seconds 3
        $notify.Dispose()
    }
    catch {
        # Notifications are best-effort. Never turn a safe backup result into a failure.
    }
}

function Invoke-SchedulerTest($Settings) {
    Show-Header "SCHEDULE TEST"

    if (-not (Test-SchedulerInstalled $Settings)) {
        throw "Windows auto-backup scheduler is not installed. Run 'repo-backup schedule install' first."
    }

    if (-not (Test-SchedulerTargetsCurrentScript $Settings)) {
        throw "The Windows task does not point at the preferred Repo Backup application path. Run 'repo-backup schedule install', then test again."
    }

    $taskName = Get-SchedulerTaskName $Settings
    $task = Get-SchedulerTaskObject $Settings
    if ($null -eq $task) {
        throw "Could not open Windows scheduled task '$taskName'."
    }

    $before = $task.LastRunTime

    Write-Info "Starting Windows scheduled task '$taskName'..."
    $null = $task.Run($null)

    $deadline = (Get-Date).AddSeconds(30)
    $completed = $false

    do {
        Start-Sleep -Milliseconds 500
        $task = Get-SchedulerTaskObject $Settings

        if ($null -eq $task) { break }

        # Task Scheduler states: 3 = Ready, 4 = Running.
        if ($task.State -ne 4 -and $task.LastRunTime -gt $before) {
            $completed = $true
            break
        }
    } while ((Get-Date) -lt $deadline)

    if (-not $completed) {
        Write-Warn "The scheduled task was started but is still running or did not report completion within 30 seconds."
        return
    }

    $result = [int]$task.LastTaskResult

    Write-Info "Last run: $($task.LastRunTime)"
    Write-Info "Next run: $($task.NextRunTime)"

    if ($result -eq 0) {
        Write-Ok "Scheduled execution completed successfully (Last Result: 0)."
    }
    else {
        throw "Scheduled execution completed with Windows result code $result. Check 'repo-backup auto log 40'."
    }
}

function Show-Header([string]$Title) {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host " MADLABZ REPO BACKUP  v$ScriptVersion  |  $Title" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor DarkGray
}


function Invoke-UpdateCheck {
    Show-Header "UPDATE CHECK"

    $apiUrl = if (-not [string]::IsNullOrWhiteSpace($env:MADLABZ_REPO_BACKUP_RELEASE_API)) {
        $env:MADLABZ_REPO_BACKUP_RELEASE_API
    }
    else {
        $DefaultReleaseApiUrl
    }

    Write-Info "Current version: $ScriptVersion"
    Write-Info "Release channel: $apiUrl"

    try {
        $release = Invoke-RestMethod `
            -Uri $apiUrl `
            -Headers @{
                "User-Agent" = "MadLabz-Repo-Backup/$ScriptVersion"
                "Accept" = "application/vnd.github+json"
            } `
            -TimeoutSec 15
    }
    catch {
        Write-Warn "Could not reach the release channel."
        Write-Info "Your installed Repo Backup is unchanged."
        Write-Info "Once the public GitHub release channel is live, retry with: repo-backup update check"
        return
    }

    $tag = [string]$release.tag_name
    if ([string]::IsNullOrWhiteSpace($tag)) {
        Write-Warn "The release channel did not return a version tag."
        return
    }

    $latestText = $tag.TrimStart([char[]]"vV")

    try {
        $currentVersion = [version]$ScriptVersion
        $latestVersion = [version]$latestText
    }
    catch {
        Write-Warn "Could not compare current version '$ScriptVersion' with release tag '$tag'."
        return
    }

    if ($latestVersion -gt $currentVersion) {
        Write-Warn "Update available: $latestText"

        if ($release.name) {
            Write-Info "Release: $($release.name)"
        }

        if ($release.html_url) {
            Write-Info "Release page: $($release.html_url)"
        }

        $zipAsset = @(
            $release.assets | Where-Object {
                ([string]$_.name).ToLowerInvariant().EndsWith(".zip")
            }
        ) | Select-Object -First 1

        if ($zipAsset -and $zipAsset.browser_download_url) {
            Write-Info "Package: $($zipAsset.browser_download_url)"
        }

        Write-Host ""
        Write-Host "Update flow:" -ForegroundColor White
        Write-Host "  1. Download and extract the newer release package." -ForegroundColor DarkGray
        Write-Host "  2. Run UPDATE.cmd, or ./repo-backup.cmd update from that package." -ForegroundColor DarkGray
        Write-Host "  3. Verify with: repo-backup version" -ForegroundColor DarkGray
    }
    elseif ($latestVersion -eq $currentVersion) {
        Write-Ok "You are on the latest published version ($ScriptVersion)."
    }
    else {
        Write-Info "Installed version $ScriptVersion is newer than the latest published release $latestText."
    }
}

function Invoke-Demo {
    Show-Header "FIRST-RUN DEMO"

    Write-Host "A read-only preview of the Repo Backup experience." -ForegroundColor White
    Write-Info "This demo does not scan, commit, push, modify config, or create a scheduler."
    Write-Host ""

    Write-Host "1. Discover" -ForegroundColor White
    Write-Host "   [OK] Found 4 Git repositories" -ForegroundColor Green
    Write-Host "        Storefront" -ForegroundColor DarkGray
    Write-Host "        API Service" -ForegroundColor DarkGray
    Write-Host "        Marketing Site" -ForegroundColor DarkGray
    Write-Host "        Prototype" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "2. Choose what to protect" -ForegroundColor White
    Write-Host "   [*] Storefront        Every 6 hours" -ForegroundColor White
    Write-Host "   [*] API Service       Hourly" -ForegroundColor White
    Write-Host "   [*] Marketing Site    Manual" -ForegroundColor White
    Write-Host "   [ ] Prototype         Not protected" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "3. Safety review" -ForegroundColor White
    Write-Host "   [OK] 3 selected repositories passed" -ForegroundColor Green
    Write-Host "   [OK] No tracked .env files" -ForegroundColor Green
    Write-Host "   [OK] No remote divergence" -ForegroundColor Green
    Write-Host "   [OK] No active merge/rebase operations" -ForegroundColor Green
    Write-Host ""

    Write-Host "4. Dashboard" -ForegroundColor White
    Write-Host "   Protected repos       : 3" -ForegroundColor DarkGray
    Write-Host "   Local changes         : 1" -ForegroundColor Yellow
    Write-Host "   Unpushed commits      : 0" -ForegroundColor Green
    Write-Host "   Automatic schedules   : 2" -ForegroundColor White
    Write-Host "   Scheduler             : Healthy" -ForegroundColor Green
    Write-Host "   Auto issues           : 0" -ForegroundColor Green
    Write-Host ""

    Write-Host "5. When a backup is due" -ForegroundColor White
    Write-Host "   Fetch remote state" -ForegroundColor DarkGray
    Write-Host "        |" -ForegroundColor DarkGray
    Write-Host "   Run safety checks" -ForegroundColor DarkGray
    Write-Host "        |" -ForegroundColor DarkGray
    Write-Host "   Commit only if files changed" -ForegroundColor DarkGray
    Write-Host "        |" -ForegroundColor DarkGray
    Write-Host "   Push only when remote state is safe" -ForegroundColor DarkGray
    Write-Host ""

    Write-Ok "Demo complete."
    Write-Info "Real setup: repo-backup onboard"
}

function Show-Help {
    Show-Header "HELP"

    $helpLines = @(
        'Safely checkpoint multiple Git repositories.',
        '',
        'Everyday:',
        '  repo-backup                     Concise protection dashboard',
        '  repo-backup onboard             Guided setup',
        '  repo-backup backup -DryRun      Preview a safe checkpoint',
        '  repo-backup backup [repo]       Checkpoint one/all protected repos',
        '  repo-backup schedule            Automatic-backup settings',
        '  repo-backup demo                Read-only first-run walkthrough',
        '',
        'Management:',
        '  repo-backup scan [folder]       Discover Git repos for review',
        '  repo-backup status              Show branch, changes, ahead/behind state',
        '  repo-backup backup [repo]       Safety-check, commit changed repos, push',
        '  repo-backup backup -DryRun      Preview a backup without changing anything',
        '  repo-backup list                List configured repositories',
        '  repo-backup doctor              Check Git/config/install/tool health',
        '  repo-backup version             Show running + installed version/location',
        '  repo-backup install             Install this package to a permanent Windows location',
        '  repo-backup update              Upgrade from this downloaded package',
        '  repo-backup update check        Check the public release channel for a newer version',
        '  repo-backup add <path>          Add one standalone repository root',
        '  repo-backup enable <name|path>  Include a discovered repo in backups',
        '  repo-backup disable <name|path> Exclude a repo without deleting it',
        '  repo-backup alias <repo> <name> Set a friendly display name',
        '  repo-backup schedule            Show per-repo automatic backup settings',
        '  repo-backup schedule <repo> <manual|hourly|6h|daily>',
        '                                 Set a repository automatic backup cadence',
        '  repo-backup schedule install    Install/update the hourly Windows scheduler trigger',
        '  repo-backup schedule test       Test the Windows scheduler end-to-end',
        '  repo-backup schedule remove     Remove the Windows scheduler trigger',
        '  repo-backup schedule notify on|off',
        '                                 Enable/disable attention notifications',
        '  repo-backup auto                Run only repositories whose schedule is due',
        '  repo-backup auto log [count]    Show recent automatic-run records',
        '  repo-backup remove <name|path>  Remove one repository from the config',
        '  repo-backup help                Show this help',
        '',
        'Release safety:',
        '  - update check is read-only; it never replaces program files.',
        '  - Updates are installed from a downloaded release package so the current',
        '    running process never overwrites itself in place.',
        '',
        'Backup safety rules:',
        '  - Never auto-pulls, auto-merges, rebases or force-pushes.',
        '  - Blocks detached HEADs and active merge/rebase/cherry-pick operations.',
        '  - Fetches before backup and blocks if the remote branch is ahead.',
        '  - Scans changed content and suspicious filenames for obvious secrets.',
        '  - Pushes existing unpushed commits even when there are no new file changes.',
        '  - Refuses broad roots (user profile/Desktop/drive) and parent-repo fallbacks.',
        '  - Automatic mode uses the same fetch/divergence/secret checks as manual mode.',
        '  - Automatic mode waits for a short idle window before checkpointing active edits.',
        '',
        'Public beta onboarding:',
        '  Run repo-backup onboard after installation. Discovery never enables new',
        '  repositories automatically. The wizard asks which repositories to protect,',
        '  reviews safety checks, configures schedules, and can run a dry-run.',
        '',
        'Installation:',
        "  Installed app: $InstalledAppDirectory",
        "  Command shims: $BinDirectory",
        '',
        '  Config/history/logs remain outside the replaceable App folder.',
        '',
        'Automatic backup:',
        '  One Windows Task Scheduler trigger runs hourly. Each repository can be Manual,',
        '  Hourly, Every 6 hours, or Daily. The scheduler targets the permanent App path.',
        '',
        "Default config: $Config",
        "History:        $HistoryFile",
        "Auto log:       $AutoLogFile"
    )

    foreach ($line in $helpLines) {
        Write-Host $line
    }
}

function Get-LastAutoLogEntry {
    if (-not (Test-Path -LiteralPath $AutoLogFile -PathType Leaf)) {
        return $null
    }

    $lines = @(Get-Content -LiteralPath $AutoLogFile -Tail 20 -ErrorAction SilentlyContinue)

    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }

        try {
            return ($lines[$i] | ConvertFrom-Json)
        }
        catch { }
    }

    return $null
}

function Invoke-Dashboard($Settings) {
    Show-Header "DASHBOARD"

    $configured = @($Settings.projects)
    $enabled = @($configured | Where-Object { $_.enabled -ne $false })
    $scheduled = @(
        $enabled | Where-Object {
            $null -ne (Get-ScheduleHours ([string]$_.autoSchedule))
        }
    )

    if ($configured.Count -eq 0) {
        Write-Info "No repositories are configured yet."
        Write-Host ""
        Write-Host "  Start here: repo-backup onboard" -ForegroundColor White
        return
    }

    $gitAvailable = Test-CommandExists "git"
    $dirty = 0
    $ahead = 0
    $gitAttention = 0
    $states = @()

    if ($gitAvailable -and $enabled.Count -gt 0) {
        $states = @($enabled | ForEach-Object { Get-ProjectState $_ $Settings })
        $dirty = @($states | Where-Object { $_.Valid -and [int]$_.Changes -gt 0 }).Count
        $ahead = @($states | Where-Object { $_.Valid -and [int]$_.Ahead -gt 0 }).Count
        $gitAttention = @($states | Where-Object { -not $_.Ready }).Count
    }

    $autoIssues = @($Settings.projects | Where-Object { Test-ProjectHasUnresolvedAutoIssue $_ }).Count
    $schedulerInstalled = Test-SchedulerInstalled $Settings
    $schedulerHealthy = $schedulerInstalled -and (Test-SchedulerTargetsCurrentScript $Settings)

    Write-Host " Protected repos         : " -NoNewline -ForegroundColor DarkGray
    Write-Host $enabled.Count -ForegroundColor White

    Write-Host " Local changes          : " -NoNewline -ForegroundColor DarkGray
    Write-Host $dirty -ForegroundColor $(if ($dirty -gt 0) { "Yellow" } else { "Green" })

    Write-Host " Unpushed commits       : " -NoNewline -ForegroundColor DarkGray
    Write-Host $ahead -ForegroundColor $(if ($ahead -gt 0) { "Yellow" } else { "Green" })

    Write-Host " Git attention          : " -NoNewline -ForegroundColor DarkGray
    Write-Host $gitAttention -ForegroundColor $(if ($gitAttention -gt 0) { "Yellow" } else { "Green" })

    Write-Host " Auto issues            : " -NoNewline -ForegroundColor DarkGray
    Write-Host $autoIssues -ForegroundColor $(if ($autoIssues -gt 0) { "Red" } else { "Green" })

    Write-Host " Auto schedules          : " -NoNewline -ForegroundColor DarkGray
    Write-Host $scheduled.Count -ForegroundColor White

    Write-Host " Scheduler              : " -NoNewline -ForegroundColor DarkGray
    if ($schedulerHealthy) {
        Write-Host "Healthy" -ForegroundColor Green
    }
    elseif ($schedulerInstalled) {
        Write-Host "Needs refresh" -ForegroundColor Yellow
    }
    else {
        Write-Host "Not installed" -ForegroundColor DarkGray
    }

    $lastAuto = Get-LastAutoLogEntry
    Write-Host " Last auto run           : " -NoNewline -ForegroundColor DarkGray

    if ($null -eq $lastAuto) {
        Write-Host "-" -ForegroundColor DarkGray
    }
    else {
        $lastTime = Format-ShortAutoTime ([string]$lastAuto.timestamp)
        $lastStatus = [string]$lastAuto.status
        Write-Host "$lastTime - $lastStatus" -ForegroundColor White
    }

    if (-not $gitAvailable) {
        Write-Host ""
        Write-Warn "Git is not available on PATH, so repository state could not be checked."
    }

    $attentionRows = @(
        $states | Where-Object {
            (-not $_.Ready) -or ([int]$_.Changes -gt 0) -or ([int]$_.Ahead -gt 0)
        }
    )

    if ($attentionRows.Count -gt 0) {
        Write-Host ""
        Write-Host "Needs a look" -ForegroundColor White
        $attentionRows |
            Select-Object Name, Changes, Ahead, Behind, Branch, Note |
            Format-Table -AutoSize
    }

    Write-Host ""
    if ($autoIssues -gt 0 -or $gitAttention -gt 0) {
        Write-Warn "Run 'repo-backup status' and 'repo-backup schedule' for details."
    }
    elseif ($dirty -gt 0 -or $ahead -gt 0) {
        Write-Info "Run 'repo-backup backup -DryRun' to preview a safe checkpoint."
    }
    else {
        Write-Ok "Everything currently looks healthy."
    }
}

function Get-OnboardingScanRoots($Settings, [string]$RequestedRoot) {
    $roots = New-Object System.Collections.Generic.List[string]
    $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)

    function Add-OnboardingRoot([string]$Candidate) {
        if ([string]::IsNullOrWhiteSpace($Candidate)) { return }

        $normalized = Normalize-Path $Candidate
        if (-not $normalized) { return }
        if (-not (Test-Path -LiteralPath $normalized -PathType Container)) { return }

        if ($seen.Add($normalized)) {
            $roots.Add($normalized)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        Add-OnboardingRoot $RequestedRoot
    }

    foreach ($existing in @($Settings.defaults.scanRoots)) {
        Add-OnboardingRoot ([string]$existing)
    }

    try { Add-OnboardingRoot ([Environment]::GetFolderPath("Desktop")) } catch { }
    try { Add-OnboardingRoot ([Environment]::GetFolderPath("MyDocuments")) } catch { }

    foreach ($name in @("projects", "Projects", "src", "source", "dev", "code")) {
        Add-OnboardingRoot (Join-Path $env:USERPROFILE $name)
    }

    return $roots.ToArray()
}

function Add-DiscoveredRepositories($Settings, [string[]]$Roots) {
    $known = @{}
    foreach ($project in @($Settings.projects)) {
        $key = (Normalize-Path ([string]$project.path)).ToLowerInvariant()
        $known[$key] = $true
    }

    $newCount = 0

    foreach ($root in @($Roots)) {
        Write-Info "Scanning: $root"
        $repos = @(Find-GitRepositories $root @($Settings.defaults.excludedDirectories))

        foreach ($repo in $repos) {
            $normalized = Normalize-Path $repo
            $key = $normalized.ToLowerInvariant()

            if ($known.ContainsKey($key)) { continue }

            $Settings.projects = @($Settings.projects) + [pscustomobject]@{
                name = Split-Path $normalized -Leaf
                path = $normalized
                enabled = $false
                remote = $null
                autoSchedule = "manual"
                lastAutoRunAt = $null
                lastAutoStatus = $null
                lastAutoSuccessAt = $null
                lastAutoFailureAt = $null
                lastAutoFailureStatus = $null
                lastAutoFailureDetails = $null
            }

            $known[$key] = $true
            $newCount++
        }
    }

    Save-Config $Settings
    return $newCount
}

function Convert-OnboardingSelection([string]$InputText, [int]$Maximum) {
    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return @()
    }

    $trimmed = $InputText.Trim().ToLowerInvariant()

    if ($trimmed -eq "all") {
        if ($Maximum -lt 1) { return @() }
        return @(1..$Maximum)
    }

    if ($trimmed -in @("none", "cancel", "q", "quit")) {
        return @()
    }

    $selected = New-Object System.Collections.Generic.HashSet[int]
    $tokens = @($trimmed -split ',')

    foreach ($tokenRaw in $tokens) {
        $token = $tokenRaw.Trim()
        if (-not $token) { continue }

        if ($token -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]

            if ($start -gt $end) {
                $tmp = $start
                $start = $end
                $end = $tmp
            }

            foreach ($index in $start..$end) {
                if ($index -ge 1 -and $index -le $Maximum) {
                    [void]$selected.Add($index)
                }
            }

            continue
        }

        $number = 0
        if ([int]::TryParse($token, [ref]$number)) {
            if ($number -ge 1 -and $number -le $Maximum) {
                [void]$selected.Add($number)
            }
        }
    }

    return @($selected | Sort-Object)
}

function Get-OnboardingSafetyReview($Project, $Settings) {
    $state = Get-ProjectState $Project $Settings
    $findings = @()

    if (-not $state.Valid) {
        $findings += [string]$state.Note
    }
    else {
        if (-not $state.Ready) {
            $readinessNote = if (-not [string]::IsNullOrWhiteSpace([string]$state.Note)) {
                [string]$state.Note
            }
            else {
                "Repository is not ready for backup (check branch, remote, or Git operation state)."
            }

            $findings += $readinessNote
        }

        $operation = Get-RepoOperation ([string]$Project.path)
        if ($operation) {
            $findings += "Git operation in progress: $operation"
        }

        foreach ($finding in @(Test-WorkingTreeSecrets ([string]$Project.path))) {
            $findings += [string]$finding
        }
    }

    return [pscustomobject]@{
        State = $state
        Findings = @($findings | Select-Object -Unique)
        Safe = ($findings.Count -eq 0)
    }
}

function Resolve-OnboardingDuplicateAliases($Settings, $SelectedProjects) {
    $groups = @($SelectedProjects | Group-Object { [string]$_.name } | Where-Object { $_.Count -gt 1 })

    if ($groups.Count -eq 0) { return }

    Write-Host ""
    Write-Host "Friendly names" -ForegroundColor White
    Write-Info "Some selected repositories have duplicate folder names."

    foreach ($group in $groups) {
        Write-Host ""
        Write-Host "Duplicate name: $($group.Name)" -ForegroundColor Yellow

        foreach ($project in @($group.Group)) {
            Write-Host "  $($project.path)" -ForegroundColor DarkGray

            $parent = Split-Path ([string]$project.path) -Parent
            $parentLeaf = Split-Path $parent -Leaf
            $suggestion = if ($parentLeaf -and $parentLeaf -ne $project.name) {
                "$($project.name) - $parentLeaf"
            }
            else {
                [string]$project.name
            }

            $current = Get-ProjectDisplayName $project
            $defaultAlias = if ($current -ne $project.name) { $current } else { $suggestion }

            $answer = Read-Host "Friendly name [$defaultAlias]"
            $alias = if ([string]::IsNullOrWhiteSpace($answer)) { $defaultAlias } else { $answer.Trim() }

            if (-not [string]::IsNullOrWhiteSpace($alias)) {
                if ($project.PSObject.Properties["alias"]) {
                    $project.alias = $alias
                }
                else {
                    $project | Add-Member -NotePropertyName alias -NotePropertyValue $alias -Force
                }
            }
        }
    }

    Save-Config $Settings
}

function Get-OnboardingScheduleChoice([string]$PromptText, [string]$Default = "manual") {
    while ($true) {
        $answer = Read-Host "$PromptText [$Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return (Get-CanonicalSchedule $Default)
        }

        $canonical = Get-CanonicalSchedule $answer
        if ($canonical) {
            return $canonical
        }

        Write-Warn "Choose: manual, hourly, 6h, or daily."
    }
}

function Invoke-Onboard($Settings, [string]$RequestedRoot) {
    Show-Header "ONBOARD"

    if (-not (Test-CommandExists "git")) {
        throw "Git is required for onboarding and was not found on PATH."
    }

    Write-Host "MadLabz Repo Backup setup" -ForegroundColor White
    Write-Info "This wizard discovers repositories, lets you choose what to protect, then reviews safety before any real backup."
    Write-Info "Nothing is force-pushed, merged, rebased, or automatically enabled just because it was discovered."

    if (-not (Test-AppInstalled)) {
        Write-Warn "Repo Backup is currently running in portable/package mode."
        Write-Info "For the normal public-beta experience, install first with: repo-backup install"
    }

    Write-Host ""
    Write-Host "1. Discover repositories" -ForegroundColor White

    $roots = @(Get-OnboardingScanRoots $Settings $RequestedRoot)
    if ($roots.Count -eq 0) {
        throw "No safe scan locations were found. Run: repo-backup onboard <project-parent-folder>"
    }

    $newCount = Add-DiscoveredRepositories $Settings $roots
    Write-Ok "Discovery complete: $newCount new repository/repositories added for review."

    $projects = @(
        $Settings.projects |
            Sort-Object @{ Expression = { if ($_.enabled -eq $false) { 1 } else { 0 } } },
                        @{ Expression = { Get-ProjectDisplayName $_ } }
    )

    if ($projects.Count -eq 0) {
        Write-Warn "No Git repositories were found."
        Write-Info "You can retry with: repo-backup onboard <project-parent-folder>"
        return
    }

    Write-Host ""
    Write-Host "2. Choose repositories to protect" -ForegroundColor White
    Write-Info "Existing enabled repositories are marked with '*'. Blank keeps your current enabled set."

    for ($i = 0; $i -lt $projects.Count; $i++) {
        $project = $projects[$i]
        $marker = if ($project.enabled -eq $false) { " " } else { "*" }
        $number = $i + 1

        Write-Host (" {0,2}. [{1}] {2}" -f $number, $marker, (Get-ProjectDisplayName $project)) -ForegroundColor White
        Write-Host ("      {0}" -f $project.path) -ForegroundColor DarkGray
    }

    $selectionText = Read-Host "Enter numbers (example 1,3-5), 'all', or press Enter to keep current enabled repos"
    $selectedProjects = @()

    if ([string]::IsNullOrWhiteSpace($selectionText)) {
        $selectedProjects = @($projects | Where-Object { $_.enabled -ne $false })
    }
    else {
        $indices = @(Convert-OnboardingSelection $selectionText $projects.Count)

        foreach ($index in $indices) {
            $project = $projects[$index - 1]
            $project.enabled = $true
            $selectedProjects += $project
        }

        Save-Config $Settings
    }

    if ($selectedProjects.Count -eq 0) {
        Write-Warn "No repositories are currently selected for protection."
        Write-Info "Nothing else was changed."
        return
    }

    Resolve-OnboardingDuplicateAliases $Settings $selectedProjects

    Write-Host ""
    Write-Host "3. Safety review" -ForegroundColor White

    $safeProjects = New-Object System.Collections.Generic.List[object]
    $blockedProjects = New-Object System.Collections.Generic.List[object]

    foreach ($project in $selectedProjects) {
        $displayName = Get-ProjectDisplayName $project
        Write-Info "Checking $displayName..."

        $review = Get-OnboardingSafetyReview $project $Settings

        if ($review.Safe) {
            $safeProjects.Add($project)
            Write-Ok "${displayName}: safety review passed."
        }
        else {
            $blockedProjects.Add($project)
            $project.autoSchedule = "manual"

            Write-Warn "${displayName}: kept Manual until these findings are resolved:"
            foreach ($finding in @($review.Findings)) {
                Write-Host "  - $finding" -ForegroundColor Yellow
            }
        }
    }

    Save-Config $Settings

    Write-Host ""
    Write-Host "4. Choose automatic backup schedule" -ForegroundColor White
    Write-Info "Press Enter to keep every selected repository's current schedule."

    $scheduleAnswer = Read-Host "Set one schedule for all safety-cleared repos? keep/manual/hourly/6h/daily [keep]"
    $applyOneSchedule = $false
    $chosenSchedule = $null

    if (-not [string]::IsNullOrWhiteSpace($scheduleAnswer) -and
        $scheduleAnswer.Trim().ToLowerInvariant() -ne "keep") {
        $chosenSchedule = Get-CanonicalSchedule $scheduleAnswer

        while (-not $chosenSchedule) {
            Write-Warn "Choose: keep, manual, hourly, 6h, or daily."
            $scheduleAnswer = Read-Host "Schedule [keep]"

            if ([string]::IsNullOrWhiteSpace($scheduleAnswer) -or
                $scheduleAnswer.Trim().ToLowerInvariant() -eq "keep") {
                break
            }

            $chosenSchedule = Get-CanonicalSchedule $scheduleAnswer
        }

        if ($chosenSchedule) {
            $applyOneSchedule = $true
        }
    }

    if ($applyOneSchedule) {
        foreach ($project in $safeProjects.ToArray()) {
            $project.autoSchedule = $chosenSchedule
        }
    }

    $customize = Read-Host "Customize schedules per repo? [y/N]"
    $customizePerRepo = $customize -match '^(?i)y(es)?$'

    if ($customizePerRepo) {
        foreach ($project in $safeProjects.ToArray()) {
            $current = Get-CanonicalSchedule ([string]$project.autoSchedule)
            if (-not $current) { $current = "manual" }

            $project.autoSchedule = Get-OnboardingScheduleChoice (
                "Schedule for $(Get-ProjectDisplayName $project)"
            ) $current
        }
    }

    Save-Config $Settings

    Write-Host ""
    Write-Host "5. Dry-run safety test" -ForegroundColor White
    $runDry = Read-Host "Run a dry-run now? [Y/n]"

    if ($runDry -notmatch '^(?i)n(o)?$') {
        $oldDryRun = [bool]$DryRun

        try {
            $script:DryRun = $true

            foreach ($project in $safeProjects.ToArray()) {
                Invoke-Backup $Settings ([string]$project.path)
            }
        }
        finally {
            $script:DryRun = $oldDryRun
        }
    }
    else {
        Write-Info "Dry-run skipped. You can run it later with: repo-backup backup -DryRun"
    }

    $automaticProjects = @(
        $selectedProjects | Where-Object {
            $_.enabled -ne $false -and
            $null -ne (Get-ScheduleHours ([string]$_.autoSchedule))
        }
    )

    if ($automaticProjects.Count -gt 0) {
        Write-Host ""
        Write-Host "6. Windows automation" -ForegroundColor White

        $schedulerQuestion = Read-Host "Install/update the hourly Windows scheduler for $($automaticProjects.Count) automatic repo(s)? [Y/n]"

        if ($schedulerQuestion -notmatch '^(?i)n(o)?$') {
            Install-AutoScheduler $Settings
        }
        else {
            Write-Warn "Automatic schedules are configured, but the Windows scheduler was not installed."
            Write-Info "Install it later with: repo-backup schedule install"
        }
    }

    $Settings.onboardingCompleteAt = [DateTimeOffset]::Now.ToString("o")
    Save-Config $Settings

    Write-Host ""
    Show-Header "ONBOARDING COMPLETE"

    Write-Ok "$($selectedProjects.Count) repository/repositories selected for protection."
    Write-Ok "$($safeProjects.Count) passed the onboarding safety review."

    if ($blockedProjects.Count -gt 0) {
        Write-Warn "$($blockedProjects.Count) selected repo(s) have safety findings and were kept Manual."
    }

    Write-Info "$($automaticProjects.Count) automatic schedule(s) configured."

    if ($automaticProjects.Count -gt 0 -and (Test-SchedulerInstalled $Settings)) {
        Write-Ok "Windows automatic backup scheduler is installed."
    }

    Write-Host ""
    Write-Host "Next commands:" -ForegroundColor White
    Write-Host "  repo-backup" -ForegroundColor Cyan
    Write-Host "  repo-backup status" -ForegroundColor Cyan
    Write-Host "  repo-backup backup -DryRun" -ForegroundColor Cyan
}

function Invoke-Scan($Settings, [string]$RequestedRoot) {
    Show-Header "SCAN"

    $roots = @()
    if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
        $roots = @(Normalize-Path $RequestedRoot)

        $knownRoots = @($Settings.defaults.scanRoots)
        if ($knownRoots -notcontains $roots[0]) {
            $Settings.defaults.scanRoots = @($knownRoots + $roots[0])
        }
    }
    else {
        $roots = @($Settings.defaults.scanRoots)
    }

    if ($roots.Count -eq 0) {
        $roots = @((Join-Path $env:USERPROFILE "Desktop"))
    }

    $known = @{}
    foreach ($project in @($Settings.projects)) {
        $known[(Normalize-Path ([string]$project.path)).ToLowerInvariant()] = $true
    }

    $newProjects = 0

    foreach ($root in $roots) {
        Write-Info "Scanning: $root"
        $repos = @(Find-GitRepositories $root @($Settings.defaults.excludedDirectories))

        foreach ($repo in $repos) {
            $key = (Normalize-Path $repo).ToLowerInvariant()
            $name = Split-Path $repo -Leaf

            if ($known.ContainsKey($key)) {
                Write-Host "  = $name" -ForegroundColor DarkGray
                continue
            }

            $Settings.projects = @($Settings.projects) + [pscustomobject]@{
                name = $name
                path = Normalize-Path $repo
                enabled = [bool]$EnableDiscovered
                remote = $null
                autoSchedule = "manual"
                lastAutoRunAt = $null
                lastAutoStatus = $null
                lastAutoSuccessAt = $null
                lastAutoFailureAt = $null
                lastAutoFailureStatus = $null
                lastAutoFailureDetails = $null
            }

            $known[$key] = $true
            $newProjects++
            if ($EnableDiscovered) {
                Write-Ok "Added + enabled: $name  ($repo)"
            }
            else {
                Write-Ok "Discovered: $name  ($repo) [disabled until reviewed]"
            }
        }
    }

    Save-Config $Settings

    Write-Host ""
    if ($newProjects -eq 0) {
        Write-Ok "No new Git repositories found."
    }
    else {
        Write-Ok "Added $newProjects new repository/repositories."
    }

    Write-Info "Run 'repo-backup list' to review discovered repos, then enable the ones you want checkpointed."
}

function Invoke-List($Settings) {
    Show-Header "REPOSITORIES"

    $rows = foreach ($project in @($Settings.projects)) {
        [pscustomobject]@{
            Enabled = if ($project.enabled -eq $false) { "No" } else { "Yes" }
            Project = Get-ProjectDisplayName $project
            Schedule = Get-ScheduleLabel ([string]$project.autoSchedule)
            Path = [string]$project.path
        }
    }

    if (-not $rows) {
        Write-Warn "No repositories configured. Run 'repo-backup scan'."
        return
    }

    $rows | Format-Table -AutoSize
}

function Invoke-Status($Settings) {
    Show-Header "STATUS"

    $enabled = @($Settings.projects | Where-Object { $_.enabled -ne $false })
    if ($enabled.Count -eq 0) {
        Write-Warn "No enabled repositories. Run 'repo-backup scan'."
        return
    }

    $rows = foreach ($project in $enabled) {
        Get-ProjectState $project $Settings
    }

    $rows |
        Select-Object Name, Branch, Changes, Ahead, Behind, Remote, Tracking, Operation, Note |
        Format-Table -AutoSize

    $attention = @($rows | Where-Object { -not $_.Ready }).Count
    $dirty = @($rows | Where-Object { $_.Valid -and [int]$_.Changes -gt 0 }).Count
    $ahead = @($rows | Where-Object { $_.Valid -and [int]$_.Ahead -gt 0 }).Count

    $autoIssues = @($Settings.projects | Where-Object { Test-ProjectHasUnresolvedAutoIssue $_ }).Count

    Write-Host ""
    Write-Info "$($rows.Count) repo(s) | $dirty with file changes | $ahead with unpushed commit(s) | $attention Git attention | $autoIssues unresolved auto issue(s)"
    Write-Warn "Ahead/behind here uses your current local tracking refs. 'backup' performs a fresh fetch before deciding whether a push is safe."
}

function Invoke-Doctor($Settings) {
    Show-Header "DOCTOR"

    $gitAvailable = Test-CommandExists "git"
    if ($gitAvailable) {
        $version = (& git --version)
        Write-Ok "$version"
    }
    else {
        Write-Fail "Git is not installed or not on PATH."
    }

    Write-Ok "Config: $Config"
    Write-Ok "History: $HistoryFile"
    Write-Ok "Auto log: $AutoLogFile"

    if (Test-AppInstalled) {
        $installedVersion = Get-InstalledVersion
        Write-Ok "Installed app: $InstalledAppDirectory (v$(if ($installedVersion) { $installedVersion } else { 'unknown' }))"

        if (Test-BinOnUserPath) {
            Write-Ok "Command PATH configured: $BinDirectory"
        }
        else {
            Write-Warn "Command PATH is not configured for: $BinDirectory"
        }

        if (Test-IsInstalledCopy) {
            Write-Ok "Running from permanent installed app."
        }
        else {
            Write-Info "Running from package: $PSScriptRoot"
        }
    }
    else {
        Write-Info "Repo Backup is running in portable/package mode."
        Write-Info "Install with: repo-backup install"
    }

    if (Test-SchedulerInstalled $Settings) {
        if (Test-SchedulerTargetsCurrentScript $Settings) {
            Write-Ok "Windows auto-backup scheduler installed and targeting the preferred application path."
        }
        else {
            Write-Warn "Windows auto-backup scheduler does not target the preferred application path."
        }
    }
    else {
        Write-Info "Windows auto-backup scheduler not installed."
    }

    if (Test-CommandExists "gitleaks") {
        Write-Ok "Gitleaks detected (future deep-scan integration available)."
    }
    else {
        Write-Info "Gitleaks not installed. Built-in lightweight secret checks remain active."
    }

    $enabled = @($Settings.projects | Where-Object { $_.enabled -ne $false })
    Write-Info "$($enabled.Count) enabled repository/repositories."

    if ($gitAvailable) {
        foreach ($project in $enabled) {
            $state = Get-ProjectState $project $Settings
            if (-not $state.Valid) {
                Write-Fail "$($state.Name): $($state.Note)"
            }
            elseif (-not $state.Ready) {
                Write-Warn "$($state.Name): $($state.Note)"
            }
            else {
                Write-Ok "$($state.Name): $($state.Branch)"
            }
        }
    }
    else {
        Write-Warn "Repository health checks skipped because Git is unavailable."
    }
}

function Invoke-Add($Settings, [string]$Path) {
    Show-Header "ADD"

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Usage: repo-backup add <path>"
    }

    $requested = Normalize-Path $Path

    if (-not (Test-Path $requested -PathType Container)) {
        throw "Folder does not exist: $requested"
    }

    $protectedReason = Get-ProtectedBroadRootReason $requested
    if ($protectedReason) {
        throw "Refusing unsafe repository root '$requested' ($protectedReason). Add a specific standalone project repository instead."
    }

    if (-not (Test-DirectGitRepositoryRoot $requested)) {
        $parentRoot = Resolve-RepoRoot $requested
        if ($parentRoot) {
            throw "'$requested' is NOT a standalone Git repository. Git currently inherits parent repository '$parentRoot'. Repo Backup will not add the parent automatically. Initialize/connect this project as its own repo, or point Repo Backup at the project's actual .git root."
        }

        throw "'$requested' is not a Git repository. No direct .git marker was found. Initialize/connect it first, then add it."
    }

    $root = Resolve-RepoRoot $requested
    if (-not $root) {
        throw "Could not resolve Git repository root for: $requested"
    }

    if (-not $root.Equals($requested, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to add '$requested' because its Git root is '$root'. Add the exact repository root instead."
    }

    foreach ($project in @($Settings.projects)) {
        if ((Normalize-Path ([string]$project.path)) -eq $root) {
            if ($project.enabled -eq $false) {
                $project.enabled = $true
                Save-Config $Settings
                Write-Ok "Already configured; enabled: $root"
            }
            else {
                Write-Ok "Already configured: $root"
            }
            return
        }
    }

    $Settings.projects = @($Settings.projects) + [pscustomobject]@{
        name = Split-Path $root -Leaf
        path = $root
        enabled = $true
        remote = $null
        autoSchedule = "manual"
        lastAutoRunAt = $null
        lastAutoStatus = $null
        lastAutoSuccessAt = $null
        lastAutoFailureAt = $null
        lastAutoFailureStatus = $null
        lastAutoFailureDetails = $null
    }

    Save-Config $Settings
    Write-Ok "Added: $root"
}

function Set-ProjectEnabled($Settings, [string]$Selector, [bool]$Enabled) {
    $verb = if ($Enabled) { "ENABLE" } else { "DISABLE" }
    Show-Header $verb

    if ([string]::IsNullOrWhiteSpace($Selector)) {
        throw "Usage: repo-backup $($verb.ToLowerInvariant()) <name|path>"
    }

$matches = @(Find-ProjectMatches $Settings $Selector)

    if ($matches.Count -eq 0) {
        Write-Warn "No configured repository matched '$Selector'."
        return
    }

    if ($matches.Count -gt 1) {
        Write-Warn "More than one repository has that name. Use the full path instead."
        foreach ($match in $matches) { Write-Host "  $($match.path)" }
        return
    }

    $matches[0].enabled = $Enabled
    Save-Config $Settings

    if ($Enabled) {
        Write-Ok "Enabled: $(Get-ProjectDisplayName $matches[0])"
    }
    else {
        Write-Ok "Disabled: $(Get-ProjectDisplayName $matches[0])"
    }
}

function Invoke-Remove($Settings, [string]$Selector) {
    Show-Header "REMOVE"

    if ([string]::IsNullOrWhiteSpace($Selector)) {
        throw "Usage: repo-backup remove <name|path>"
    }

    $before = @($Settings.projects)
    $matches = @(Find-ProjectMatches $Settings $Selector)

    if ($matches.Count -eq 0) {
        Write-Warn "No configured repository matched '$Selector'."
        return
    }

    if ($matches.Count -gt 1) {
        Write-Warn "More than one repository matched '$Selector'. Use the full path or a unique alias."
        foreach ($match in $matches) { Write-Host "  $($match.path)" }
        return
    }

    $removePath = Normalize-Path ([string]$matches[0].path)
    $after = @(
        $before | Where-Object {
            (Normalize-Path ([string]$_.path)) -ne $removePath
        }
    )

    $Settings.projects = $after
    Save-Config $Settings
    Write-Ok "Removed from Repo Backup config. No project files were deleted."
}


function Invoke-Alias($Settings, [string]$Selector, [string]$NewAlias) {
    Show-Header "ALIAS"

    if ([string]::IsNullOrWhiteSpace($Selector) -or [string]::IsNullOrWhiteSpace($NewAlias)) {
        throw "Usage: repo-backup alias <name|path> <friendly-name>"
    }

    $matches = @(Find-ProjectMatches $Settings $Selector)
    if ($matches.Count -eq 0) {
        Write-Warn "No configured repository matched '$Selector'."
        return
    }

    if ($matches.Count -gt 1) {
        Write-Warn "More than one repository matched '$Selector'. Use the full path."
        foreach ($match in $matches) { Write-Host "  $($match.path)" }
        return
    }

    if ($NewAlias.Trim().ToLowerInvariant() -in @("clear", "none", "-")) {
        if ($matches[0].PSObject.Properties["alias"]) {
            $matches[0].alias = $null
        }
        Write-Ok "Alias cleared. Display name is now '$($matches[0].name)'."
    }
    else {
        if ($matches[0].PSObject.Properties["alias"]) {
            $matches[0].alias = $NewAlias.Trim()
        }
        else {
            $matches[0] | Add-Member -NotePropertyName alias -NotePropertyValue $NewAlias.Trim() -Force
        }

        Write-Ok "Alias set: $(Get-ProjectDisplayName $matches[0])"
    }

    Save-Config $Settings
}

function Install-AutoScheduler($Settings, [string]$ScriptPathOverride = $null, [bool]$Embedded = $false) {
    if (-not $Embedded) {
        Show-Header "SCHEDULE INSTALL"
    }

    if (-not (Test-CommandExists "schtasks.exe")) {
        throw "Windows Task Scheduler command 'schtasks.exe' is unavailable."
    }

    $taskName = Get-SchedulerTaskName $Settings
    $scriptPath = if (-not [string]::IsNullOrWhiteSpace($ScriptPathOverride)) {
        $ScriptPathOverride
    }
    else {
        Get-PreferredSchedulerScriptPath
    }

    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Scheduler target does not exist: $scriptPath"
    }

    $startTime = (Get-Date).AddMinutes(2).ToString("HH:mm")
    $taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" auto"

    Write-Info "Installing hourly scheduler trigger..."
    Write-Info "Scheduler target: $scriptPath"
    Write-Info "Per-repo cadence is controlled by 'repo-backup schedule'."

    & schtasks.exe /Create /TN $taskName /SC HOURLY /MO 1 /ST $startTime /TR $taskCommand /F
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create Windows scheduled task '$taskName'."
    }

    Write-Ok "Installed Windows task: $taskName"
    Write-Info "The scheduler checks hourly; repos set to 6h/daily are only backed up when due."

    if (Test-AppInstalled) {
        Write-Ok "Scheduler uses the permanent installed application path."
    }
    else {
        Write-Warn "Scheduler currently targets this portable/download folder. Run 'repo-backup install' to move it to a permanent application path."
    }
}

function Remove-AutoScheduler($Settings) {
    Show-Header "SCHEDULE REMOVE"

    if (-not (Test-CommandExists "schtasks.exe")) {
        throw "Windows Task Scheduler command 'schtasks.exe' is unavailable."
    }

    $taskName = Get-SchedulerTaskName $Settings

    if (-not (Test-SchedulerInstalled $Settings)) {
        Write-Info "Scheduled task is not installed."
        return
    }

    & schtasks.exe /Delete /TN $taskName /F
    if ($LASTEXITCODE -ne 0) {
        throw "Could not remove Windows scheduled task '$taskName'."
    }

    Write-Ok "Removed Windows task: $taskName"
}

function Show-Schedule($Settings) {
    Show-Header "AUTO BACKUP SETTINGS"

    $rows = foreach ($project in @($Settings.projects)) {
        $lastIssue = "-"
        if (Test-ProjectHasUnresolvedAutoIssue $project) {
            $lastIssue = "$($project.lastAutoFailureStatus) $(Format-ShortAutoTime ([string]$project.lastAutoFailureAt))"
        }

        [pscustomobject]@{
            Enabled = if ($project.enabled -eq $false) { "No" } else { "Yes" }
            Project = Get-ProjectDisplayName $project
            Schedule = Get-ScheduleLabel ([string]$project.autoSchedule)
            LastAuto = Format-ShortAutoTime ([string]$project.lastAutoRunAt)
            LastResult = if ($project.lastAutoStatus) { [string]$project.lastAutoStatus } else { "-" }
            LastSuccess = Format-ShortAutoTime ([string]$project.lastAutoSuccessAt)
            LastIssue = $lastIssue
        }
    }

    if ($rows) {
        $rows | Format-Table -AutoSize
    }

    Write-Host ""
    $installed = Test-SchedulerInstalled $Settings
    if ($installed) {
        if (Test-SchedulerTargetsCurrentScript $Settings) {
            if (Test-AppInstalled) {
                Write-Ok "Windows hourly scheduler trigger is installed and targets the permanent Repo Backup app."
            }
            else {
                Write-Ok "Windows hourly scheduler trigger is installed and targets this portable package."
                Write-Info "For stable upgrades, install Repo Backup with: repo-backup install"
            }
        }
        else {
            Write-Warn "Windows scheduler is installed but does not target the preferred Repo Backup application path."
            Write-Info "Refresh it with: repo-backup schedule install"
        }
    }
    else {
        Write-Info "Windows hourly scheduler trigger is not installed."
        Write-Info "After choosing schedules, run: repo-backup schedule install"
    }

    $notifications = if ($Settings.defaults.notifyOnAutoAttention -eq $false) { "Off" } else { "On" }
    Write-Info "Idle window before automatic checkpoint: $($Settings.defaults.autoBackupIdleMinutes) minute(s)."
    Write-Info "Attention notifications: $notifications"
    Write-Info "Auto log: $AutoLogFile"

    $unresolved = @($Settings.projects | Where-Object { Test-ProjectHasUnresolvedAutoIssue $_ })
    foreach ($project in $unresolved) {
        Write-Warn "$(Get-ProjectDisplayName $project) unresolved auto issue: $($project.lastAutoFailureStatus) - $($project.lastAutoFailureDetails)"
    }
}

function Invoke-Schedule($Settings, [string]$Selector, [string]$ScheduleValue) {
    if ([string]::IsNullOrWhiteSpace($Selector)) {
        Show-Schedule $Settings
        return
    }

    switch ($Selector.Trim().ToLowerInvariant()) {
        "install" {
            Install-AutoScheduler $Settings
            return
        }
        "test" {
            Invoke-SchedulerTest $Settings
            return
        }
        "remove" {
            Remove-AutoScheduler $Settings
            return
        }
        "uninstall" {
            Remove-AutoScheduler $Settings
            return
        }
        "notify" {
            Show-Header "SCHEDULE NOTIFICATIONS"

            $mode = if ($ScheduleValue) { $ScheduleValue.Trim().ToLowerInvariant() } else { "" }
            switch ($mode) {
                "on"  { $Settings.defaults.notifyOnAutoAttention = $true }
                "off" { $Settings.defaults.notifyOnAutoAttention = $false }
                default { throw "Usage: repo-backup schedule notify <on|off>" }
            }

            Save-Config $Settings
            Write-Ok "Attention notifications: $(if ($Settings.defaults.notifyOnAutoAttention) { 'On' } else { 'Off' })"
            return
        }
    }

    Show-Header "SCHEDULE"

    $canonical = Get-CanonicalSchedule $ScheduleValue
    if (-not $canonical) {
        throw "Usage: repo-backup schedule <name|path> <manual|hourly|6h|daily>"
    }

    $matches = @(Find-ProjectMatches $Settings $Selector)
    if ($matches.Count -eq 0) {
        Write-Warn "No configured repository matched '$Selector'."
        return
    }

    if ($matches.Count -gt 1) {
        Write-Warn "More than one repository matched '$Selector'. Use the full path or set aliases first."
        foreach ($match in $matches) { Write-Host "  $($match.path)" }
        return
    }

    $project = $matches[0]
    $project.autoSchedule = $canonical
    $project.lastAutoRunAt = $null
    $project.lastAutoStatus = $null
    Save-Config $Settings

    Write-Ok "$(Get-ProjectDisplayName $project): $(Get-ScheduleLabel $canonical)"
    if ($canonical -ne "manual" -and -not (Test-SchedulerInstalled $Settings)) {
        Write-Info "Run 'repo-backup schedule install' once to enable Windows automatic runs."
    }
}

function Invoke-Auto($Settings, [string]$AutoAction = $null, [string]$AutoValue = $null) {
    if ($AutoAction -and $AutoAction.Trim().ToLowerInvariant() -eq "log") {
        $count = 20
        if ($AutoValue) {
            $parsed = 0
            if ([int]::TryParse($AutoValue, [ref]$parsed)) {
                $count = $parsed
            }
        }

        Show-AutoLog $count
        return
    }

    Show-Header $(if ($DryRun) { "AUTO DRY RUN" } else { "AUTO" })

    $runId = [guid]::NewGuid().ToString("N").Substring(0, 10)
    $issues = New-Object System.Collections.Generic.List[object]

    Write-AutoEvent $runId "RUN" "STARTED" "Automatic backup run started." $null $null ([bool]$DryRun)

    $scheduled = @(
        $Settings.projects | Where-Object {
            $_.enabled -ne $false -and $null -ne (Get-ScheduleHours ([string]$_.autoSchedule))
        }
    )

    if ($scheduled.Count -eq 0) {
        Write-Info "No enabled repositories have an automatic schedule."
        Write-AutoEvent $runId "RUN" "UP TO DATE" "No enabled repositories have an automatic schedule." $null $null ([bool]$DryRun)
        return
    }

    $due = @($scheduled | Where-Object { Test-ProjectAutoDue $_ })
    if ($due.Count -eq 0) {
        Write-Ok "Nothing is due yet."
        Write-AutoEvent $runId "RUN" "UP TO DATE" "Nothing is due yet." $null $null ([bool]$DryRun)
        return
    }

    $idleThreshold = if ($Settings.defaults.autoBackupIdleMinutes -ne $null) {
        [double]$Settings.defaults.autoBackupIdleMinutes
    }
    else {
        5.0
    }

    Write-Info "$($due.Count) repository/repositories due for automatic checkpoint."
    Write-AutoEvent $runId "RUN" "DUE" "$($due.Count) repository/repositories due." $null $null ([bool]$DryRun)

    foreach ($project in $due) {
        $displayName = Get-ProjectDisplayName $project
        $path = Normalize-Path ([string]$project.path)

        $changes = @(& git -C $path status --porcelain=v1 2>$null)
        if ($changes.Count -gt 0 -and $idleThreshold -gt 0) {
            $idleMinutes = Get-RepoIdleMinutes $path
            if (-not [double]::IsPositiveInfinity($idleMinutes) -and $idleMinutes -lt $idleThreshold) {
                $message = "$displayName skipped: files changed $([math]::Round($idleMinutes, 1)) minute(s) ago; waiting for $idleThreshold minute(s) idle."
                Write-Warn $message
                Write-AutoEvent $runId "PROJECT" "SKIPPED ACTIVE" $message $displayName $path ([bool]$DryRun)
                continue
            }
        }

        Write-Info "$displayName is due ($(Get-ScheduleLabel ([string]$project.autoSchedule)))."
        Write-AutoEvent $runId "PROJECT" "STARTED" "Automatic checkpoint started." $displayName $path ([bool]$DryRun)

        Invoke-Backup $Settings ([string]$project.path) "Auto Backup"

        $result = $script:LastBackupResults | Select-Object -First 1
        $resultStatus = if ($null -ne $result) { [string]$result.Status } else { "UNKNOWN" }
        $resultDetails = if ($null -ne $result) { [string]$result.Details } else { "No backup result was returned." }

        Write-AutoEvent $runId "PROJECT" $resultStatus "Automatic checkpoint completed." $displayName $resultDetails ([bool]$DryRun)

        if (-not $DryRun) {
            $now = [DateTimeOffset]::Now.ToString("o")
            $project.lastAutoRunAt = $now
            $project.lastAutoStatus = $resultStatus

            if ($resultStatus -in @("BACKED UP", "UP TO DATE")) {
                $project.lastAutoSuccessAt = $now
            }
            elseif ($resultStatus -in @("FAILED", "BLOCKED", "UNKNOWN")) {
                $project.lastAutoFailureAt = $now
                $project.lastAutoFailureStatus = $resultStatus
                $project.lastAutoFailureDetails = $resultDetails

                $issues.Add([pscustomobject]@{
                    Project = $displayName
                    Status = $resultStatus
                    Details = $resultDetails
                })
            }

            Save-Config $Settings
        }
    }

    if ($issues.Count -gt 0) {
        $summary = "$($issues.Count) automatic backup issue(s) need attention."
        Write-AutoEvent $runId "RUN" "ATTENTION" $summary $null (($issues | ForEach-Object { "$($_.Project): $($_.Status) - $($_.Details)" }) -join " | ") $false

        if ($Settings.defaults.notifyOnAutoAttention -ne $false) {
            $names = ($issues | ForEach-Object { "$($_.Project) [$($_.Status)]" }) -join ", "
            Show-AutoAttentionNotification "$summary $names"
        }

        throw "$summary Run 'repo-backup schedule' or 'repo-backup auto log 40' for details."
    }

    Write-AutoEvent $runId "RUN" "SUCCESS" "Automatic backup run completed successfully." $null $null ([bool]$DryRun)
}

function Invoke-Backup($Settings, [string]$Selector = $null, [string]$CommitPrefixOverride = $null) {
    Show-Header $(if ($DryRun) { "BACKUP DRY RUN" } else { "BACKUP" })

    $enabled = @($Settings.projects | Where-Object { $_.enabled -ne $false })

    if (-not [string]::IsNullOrWhiteSpace($Selector)) {
        $matches = @(Find-ProjectMatches $Settings $Selector)
        $enabledPaths = @{}
        foreach ($candidate in $enabled) {
            $enabledPaths[(Normalize-Path ([string]$candidate.path)).ToLowerInvariant()] = $candidate
        }

        $selected = @(
            $matches | Where-Object {
                $key = (Normalize-Path ([string]$_.path)).ToLowerInvariant()
                $enabledPaths.ContainsKey($key)
            }
        )

        if ($selected.Count -eq 0) {
            Write-Warn "No enabled repository matched '$Selector'."
            $script:LastBackupResults = @()
            return
        }

        if ($selected.Count -gt 1) {
            Write-Warn "More than one enabled repository matched '$Selector'. Use the full path or a unique alias."
            foreach ($match in $selected) { Write-Host "  $($match.path)" }
            $script:LastBackupResults = @()
            return
        }

        $enabled = $selected
    }

    if ($enabled.Count -eq 0) {
        Write-Warn "No enabled repositories. Run 'repo-backup scan'."
        $script:LastBackupResults = @()
        return
    }

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($project in $enabled) {
        $name = Get-ProjectDisplayName $project
        $path = Normalize-Path ([string]$project.path)
        $remote = Get-ProjectRemote $project $Settings

        Write-Host ""
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " $name" -ForegroundColor White
        Write-Host " $path" -ForegroundColor DarkGray
        Write-Host "------------------------------------------------------------" -ForegroundColor DarkGray

        $status = "FAILED"
        $details = ""

        try {
            $protectedReason = Get-ProtectedBroadRootReason $path
            if ($protectedReason) {
                throw "Blocked unsafe configured path: $protectedReason ($path). Remove this entry from Repo Backup and add a specific standalone project repository."
            }

            $root = Resolve-RepoRoot $path
            if (-not $root) {
                throw "Path missing or not a Git repository."
            }

            if ((Normalize-Path $root) -ne (Normalize-Path $path)) {
                throw "Configured path is not the repository root. Git root is '$root'."
            }

            $operation = Get-RepoOperation $path
            if ($operation) {
                throw "Active Git $operation detected. Finish or abort it before backup."
            }

            $branch = ((& git -C $path branch --show-current 2>$null) | Select-Object -First 1)
            if ($branch) { $branch = $branch.Trim() }

            if ([string]::IsNullOrWhiteSpace($branch)) {
                throw "Detached HEAD detected. Checkout a branch before backup."
            }

            $remoteNames = @(& git -C $path remote 2>$null)
            if ($remoteNames -notcontains $remote) {
                throw "Remote '$remote' is not configured."
            }

            Write-Info "Fetching '$remote' to check remote state..."
            & git -C $path fetch $remote --prune
            if ($LASTEXITCODE -ne 0) {
                throw "Fetch failed. Nothing was committed or pushed."
            }

            $remoteBranchExists = Test-RemoteTrackingBranchExists $path $remote $branch

            # Before the first push of an existing local history, ensure sensitive
            # filenames are not hiding in older commits even if they are ignored now.
            if (-not $remoteBranchExists -and (Test-HeadExists $path)) {
                $historyFindings = @(Get-HistorySensitiveFiles $path)
                if ($historyFindings.Count -gt 0) {
                    Write-Fail "First-push history audit blocked this repository."
                    foreach ($finding in $historyFindings) {
                        Write-Host "       - $finding" -ForegroundColor Red
                    }

                    $status = "BLOCKED"
                    $details = "$($historyFindings.Count) sensitive file(s) in Git history"
                    continue
                }
            }

            $ahead = 0
            $behind = 0

            if ($remoteBranchExists) {
                $remoteShort = "$remote/$branch"

                $behindValue = (& git -C $path rev-list --count "HEAD..$remoteShort" 2>$null)
                if ($LASTEXITCODE -eq 0 -and $behindValue) { $behind = [int]$behindValue }

                $aheadValue = (& git -C $path rev-list --count "$remoteShort..HEAD" 2>$null)
                if ($LASTEXITCODE -eq 0 -and $aheadValue) { $ahead = [int]$aheadValue }

                if ($behind -gt 0) {
                    if ($ahead -gt 0) {
                        throw "Local and remote have diverged ($ahead ahead / $behind behind). Repo Backup will not merge or rebase automatically."
                    }
                    else {
                        throw "Remote branch is $behind commit(s) ahead. Pull/reconcile manually before backup."
                    }
                }
            }

            $changes = @(& git -C $path status --porcelain=v1 2>$null)
            $changeCount = $changes.Count

            if ($changeCount -gt 0) {
                Write-Info "$changeCount changed/untracked item(s) found."

                Write-Info "Safety scanning $changeCount change(s)..."
                $secretFindings = @(Test-WorkingTreeSecrets $path)
                if ($secretFindings.Count -gt 0) {
                    Write-Fail "Safety scan blocked this repository."
                    foreach ($finding in $secretFindings) {
                        Write-Host "       - $finding" -ForegroundColor Red
                    }

                    $status = "BLOCKED"
                    $details = "$($secretFindings.Count) safety finding(s)"
                    continue
                }

                Write-Ok "Safety scan passed."

                if ($DryRun) {
                    Write-Warn "Dry run: would stage, commit, and push branch '$branch'."
                    $status = "DRY RUN"
                    $details = "$changeCount file-state change(s); $ahead existing unpushed commit(s)"
                    continue
                }

                Write-Info "Staging all changes..."
                & git -C $path add -A
                if ($LASTEXITCODE -ne 0) {
                    throw "git add failed."
                }

                $stagedFiles = @(& git -C $path diff --cached --name-only -- 2>$null)
                $hasStagedChanges = ($stagedFiles.Count -gt 0)

                if ($hasStagedChanges) {
                    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    $prefix = if (-not [string]::IsNullOrWhiteSpace($CommitPrefixOverride)) {
                        $CommitPrefixOverride
                    }
                    elseif ($Settings.defaults.commitMessagePrefix) {
                        [string]$Settings.defaults.commitMessagePrefix
                    }
                    else {
                        "Backup"
                    }

                    $message = "$prefix $timestamp"

                    Write-Info "Creating commit: $message"
                    & git -C $path commit -m $message
                    if ($LASTEXITCODE -ne 0) {
                        throw "git commit failed."
                    }

                    $ahead++
                }
            }
            elseif ($DryRun -and $ahead -gt 0) {
                Write-Warn "Dry run: no file changes, but would push $ahead existing unpushed commit(s)."
                $status = "DRY RUN"
                $details = "$ahead existing unpushed commit(s)"
                continue
            }
            elseif ($DryRun) {
                Write-Ok "Already fully checkpointed."
                $status = "UP TO DATE"
                $details = "No file changes or unpushed commits"
                continue
            }

            if (-not $remoteBranchExists) {
                Write-Info "Remote branch does not exist yet. Creating '$remote/$branch'..."
                & git -C $path push -u $remote $branch
                if ($LASTEXITCODE -ne 0) {
                    throw "Push failed. Local commits remain safe."
                }

                Write-Ok "Backup complete."
                $status = "BACKED UP"
                $details = "$changeCount file-state change(s); created remote branch $branch"
            }
            else {
                $aheadNowValue = (& git -C $path rev-list --count "$remote/$branch..HEAD" 2>$null)
                $aheadNow = if ($LASTEXITCODE -eq 0 -and $aheadNowValue) { [int]$aheadNowValue } else { 0 }

                if ($aheadNow -gt 0) {
                    Write-Info "Pushing $aheadNow commit(s) to '$remote/$branch'..."
                    & git -C $path push $remote $branch
                    if ($LASTEXITCODE -ne 0) {
                        throw "Push failed. Local commits remain safe."
                    }

                    Write-Ok "Backup complete."
                    $status = "BACKED UP"
                    $details = "$changeCount file-state change(s); $aheadNow commit(s) pushed"
                }
                else {
                    Write-Ok "Already fully checkpointed."
                    $status = "UP TO DATE"
                    $details = "No file changes or unpushed commits"
                }
            }
        }
        catch {
            Write-Fail $_.Exception.Message
            $status = "FAILED"
            $details = $_.Exception.Message
        }
        finally {
            $record = [pscustomobject]@{
                timestamp = (Get-Date).ToString("o")
                version = $ScriptVersion
                project = $name
                path = $path
                status = $status
                details = $details
                dryRun = [bool]$DryRun
            }

            Write-History $record

            $results.Add([pscustomobject]@{
                Project = $name
                Status = $status
                Details = $details
            })
        }
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host " SUMMARY" -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor DarkGray
    $results | Format-Table -AutoSize

    $problemCount = @($results | Where-Object { $_.Status -in @("FAILED", "BLOCKED") }).Count
    if ($problemCount -gt 0) {
        Write-Warn "$problemCount project(s) need attention. Healthy projects were still processed independently."
    }
    else {
        Write-Ok "All enabled repositories checked successfully."
    }

    # Windows PowerShell 5.1 can throw "Argument types do not match" when
    # wrapping a Generic.List[object] directly in @(...). Convert explicitly.
    $script:LastBackupResults = $results.ToArray()
}

try {
    $settings = Load-Config

    $gitRequiredCommands = @("dashboard", "onboard", "scan", "status", "backup", "add", "auto")
    if ($Command -in $gitRequiredCommands -and -not (Test-CommandExists "git")) {
        throw "Git is not installed or is not available on PATH."
    }

    switch ($Command) {
        "dashboard" { Invoke-Dashboard $settings }
        "onboard"   { Invoke-Onboard $settings $Target }
        "scan"      { Invoke-Scan $settings $Target }
        "status"   { Invoke-Status $settings }
        "backup"   { Invoke-Backup $settings $Target }
        "list"     { Invoke-List $settings }
        "doctor"   { Invoke-Doctor $settings }
        "version"  { Invoke-Version }
        "install"  { Invoke-InstallPackage $settings $false }
        "update"   {
            if ($Target -and $Target.Trim().ToLowerInvariant() -eq "check") {
                Invoke-UpdateCheck
            }
            else {
                Invoke-InstallPackage $settings $true
            }
        }
        "demo"     { Invoke-Demo }
        "add"      { Invoke-Add $settings $Target }
        "enable"   { Set-ProjectEnabled $settings $Target $true }
        "disable"  { Set-ProjectEnabled $settings $Target $false }
        "alias"    { Invoke-Alias $settings $Target $Value }
        "schedule" { Invoke-Schedule $settings $Target $Value }
        "auto"     { Invoke-Auto $settings $Target $Value }
        "remove"   { Invoke-Remove $settings $Target }
        "help"     { Show-Help }
    }
}
catch {
    Write-Fail $_.Exception.Message
    exit 1
}
