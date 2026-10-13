# Local status window for MadLabz Repo Backup. Windows PowerShell 5.1.
# Read-only by default. Close at any time; the scheduled task is independent.
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$dataDir = Join-Path $env:LOCALAPPDATA "MadLabz\RepoBackup"
$configFile = Join-Path $dataDir "repos.json"
$logFile = Join-Path $dataDir "auto-runs.jsonl"
$engine = Join-Path $PSScriptRoot "repo-backup.ps1"
$form = New-Object System.Windows.Forms.Form
$form.Text = "MadLabz Repo Backup - Status"
$form.ClientSize = New-Object System.Drawing.Size(930,630)
$form.MinimumSize = New-Object System.Drawing.Size(760,550)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(247,249,249)
$form.Font = New-Object System.Drawing.Font("Segoe UI",10)
$form.AutoScaleMode = "Dpi"
function Label($text,$y,$height,$size,$strong) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point(24,$y)
    $label.Size = New-Object System.Drawing.Size(870,$height)
    $label.Anchor = "Top,Left,Right"
    $weight = if ($strong) { "Bold" } else { "Regular" }
    $label.Font = New-Object System.Drawing.Font("Segoe UI",$size,$weight)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(25,39,42)
    $form.Controls.Add($label)
    return $label
}
$title = Label "Repo Backup" 14 44 24 $true
$subtitle = Label "Local backup status and diagnostics" 60 26 10 $false
$headline = Label "Checking local settings..." 97 33 14 $true
$summary = Label "" 137 53 10 $false
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(24,202)
$grid.Size = New-Object System.Drawing.Size(882,250)
$grid.Anchor = "Top,Bottom,Left,Right"
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.RowHeadersVisible = $false
$grid.MultiSelect = $false
$grid.SelectionMode = "FullRowSelect"
$grid.AutoSizeColumnsMode = "Fill"
$grid.Columns.Add("name","Repository") | Out-Null
$grid.Columns.Add("enabled","Enabled") | Out-Null
$grid.Columns.Add("schedule","Schedule") | Out-Null
$grid.Columns.Add("run","Last auto run") | Out-Null
$grid.Columns.Add("result","Last result") | Out-Null
$grid.Columns.Add("attention","Attention") | Out-Null
$grid.Columns[0].FillWeight=170
$grid.Columns[1].FillWeight=65
$grid.Columns[2].FillWeight=85
$grid.Columns[3].FillWeight=125
$grid.Columns[4].FillWeight=120
$grid.Columns[5].FillWeight=125
$form.Controls.Add($grid)
$details = Label "Select a repository to see its last recorded issue." 462 56 10 $false
$details.Anchor = "Bottom,Left,Right"
$details.Top = 468
$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.Location = New-Object System.Drawing.Point(24,537)
$buttons.Size = New-Object System.Drawing.Size(882,42)
$buttons.Anchor = "Bottom,Left,Right"
$buttons.AutoScroll = $true
$buttons.WrapContents = $false
$form.Controls.Add($buttons)
function Button($title,$width) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text=$title
    $b.Size=New-Object System.Drawing.Size($width,34)
    $b.Margin=New-Object System.Windows.Forms.Padding(0,0,7,0)
    $b.FlatStyle="Flat"
    $b.BackColor=[System.Drawing.Color]::White
    $buttons.Controls.Add($b)
    return $b
}
$refresh = Button "Refresh" 105
$doctor = Button "Health check" 120
$logs = Button "Recent logs" 120
$settings = Button "Settings" 100
$dryRun = Button "Safe dry run" 130
$test = Button "Test scheduler" 132
$footer = Label "Close this window whenever you like. Auto backups continue through Windows Task Scheduler." 591 28 9 $false
$footer.Anchor="Bottom,Left,Right"
function Stamp($value) {
    if (-not $value) { return "-" }
    try { return ([DateTimeOffset]::Parse([string]$value)).LocalDateTime.ToString("dd MMM HH:mm") }
    catch { return "-" }
}
function Has-Issue($p) {
    if (-not $p.lastAutoFailureAt) { return $false }
    if (-not $p.lastAutoSuccessAt) { return $true }
    try { return ([DateTimeOffset]::Parse([string]$p.lastAutoFailureAt)) -gt ([DateTimeOffset]::Parse([string]$p.lastAutoSuccessAt)) }
    catch { return $true }
}
function Last-Run {
    if (-not (Test-Path -LiteralPath $logFile -PathType Leaf)) { return $null }
    $lines = @(Get-Content -LiteralPath $logFile -Tail 40 -ErrorAction SilentlyContinue)
    for ($i=$lines.Count-1; $i -ge 0; $i--) {
        try {
            $event = $lines[$i] | ConvertFrom-Json
            if ($event.type -eq "RUN" -and $event.status -ne "STARTED") { return $event }
        }
        catch { }
    }
    return $null
}
function Task-Health($taskName) {
    try {
        $svc=New-Object -ComObject "Schedule.Service"
        $svc.Connect()
        $task=$svc.GetFolder("\").GetTask($taskName)
        if ($null -eq $task) { return "Not installed" }
        if ($task.State -eq 1) { return "Disabled" }
        if ($task.State -eq 4) { return "Running" }
        return "Installed (last exit: $($task.LastTaskResult))"
    }
    catch { return "Not installed or inaccessible" }
}
function Refresh-Status {
    $grid.Rows.Clear()
    if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
        $headline.Text="Setup required"
        $summary.Text="No local configuration found. Run repo-backup onboard before using scheduled backups."
        return
    }
    try { $cfg=Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json }
    catch {
        $headline.Text="Could not read settings"
        $summary.Text=$_.Exception.Message
        return
    }
    $enabled=0; $scheduled=0; $issues=0
    foreach($p in @($cfg.projects)) {
        $isEnabled=($p.enabled -ne $false)
        $issue=Has-Issue $p
        if($isEnabled) { $enabled++ }
        if($isEnabled -and $p.autoSchedule -in @("hourly","6h","daily")) { $scheduled++ }
        if($issue) { $issues++ }
        $name=if($p.alias) {[string]$p.alias} else {[string]$p.name}
        $frequency=switch([string]$p.autoSchedule) { "hourly" {"Hourly"} "6h" {"6 hours"} "daily" {"Daily"} default {"Manual"} }
        $warning=if($issue) {[string]$p.lastAutoFailureStatus} else {"None recorded"}
        $index=$grid.Rows.Add($name,$(if($isEnabled) {"Yes"} else {"No"}),$frequency,(Stamp $p.lastAutoRunAt),$(if($p.lastAutoStatus){[string]$p.lastAutoStatus}else{"-"}),$warning)
        $grid.Rows[$index].Tag=$p
        if($issue) {$grid.Rows[$index].DefaultCellStyle.ForeColor=[System.Drawing.Color]::Firebrick}
    }
    $taskName=if($cfg.defaults.schedulerTaskName) {[string]$cfg.defaults.schedulerTaskName} else {"MadLabz Repo Backup Auto"}
    $health=Task-Health $taskName
    $last=Last-Run
    $lastText=if($null -eq $last) {"No completed run recorded"} else {"$(Stamp $last.timestamp) - $($last.status)"}
    $summary.Text="$enabled enabled | $scheduled scheduled | $issues unresolved issues"+[Environment]::NewLine+"Scheduler: $health | Latest run: $lastText"
    if($issues -gt 0) { $headline.Text="$issues automatic backup issue(s) need attention"; $headline.ForeColor=[System.Drawing.Color]::Firebrick }
    elseif($scheduled -gt 0 -and $health -match "Not installed|Disabled") { $headline.Text="Scheduled backups require attention"; $headline.ForeColor=[System.Drawing.Color]::DarkGoldenrod }
    else { $headline.Text="No unresolved automatic backup issues"; $headline.ForeColor=[System.Drawing.Color]::DarkCyan }
    $details.Text="Select a repository. These are saved results; use Health check for a fresh local Git inspection."
}
function Open-Command($commandLine) {
    if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("Missing application engine: $engine","Repo Backup") | Out-Null
        return
    }
    # Arguments here are hardcoded UI actions, never read from config.
    $scriptPath='"'+$engine+'"'
    $full="powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptPath $commandLine"
    Start-Process -FilePath "cmd.exe" -ArgumentList @("/k",$full) | Out-Null
}
$refresh.Add_Click({ Refresh-Status })
$doctor.Add_Click({ Open-Command "doctor" })
$logs.Add_Click({ Open-Command "auto log 40" })
$settings.Add_Click({ Open-Command "schedule" })
$dryRun.Add_Click({ Open-Command "backup -DryRun" })
$test.Add_Click({
    $message="This starts the REAL Windows scheduled task. If a repository is due, this may create and push a backup commit. Continue?"
    $answer=[System.Windows.Forms.MessageBox]::Show($message,"Scheduler test","YesNo","Warning")
    if($answer -eq [System.Windows.Forms.DialogResult]::Yes) { Open-Command "schedule test" }
})
$grid.Add_SelectionChanged({
    if($grid.SelectedRows.Count -lt 1) { return }
    $p=$grid.SelectedRows[0].Tag
    if($null -eq $p) { return }
    if(Has-Issue $p) {
        $message=if($p.lastAutoFailureDetails) {[string]$p.lastAutoFailureDetails} else {[string]$p.lastAutoFailureStatus}
        $details.Text="Issue: $message | $(Stamp $p.lastAutoFailureAt)"
    }
    else { $details.Text="No unresolved issue. Last successful backup: $(Stamp $p.lastAutoSuccessAt)" }
})
$form.Add_Shown({ Refresh-Status })
[void]$form.ShowDialog()
