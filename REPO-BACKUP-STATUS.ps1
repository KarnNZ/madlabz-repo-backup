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
if (-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
    # Standalone preview: use the currently installed v0.6.2 engine.
    $engine = Join-Path $dataDir "App\repo-backup.ps1"
}
$form = New-Object System.Windows.Forms.Form
$form.Text = "MadLabz Repo Backup - Status"
$form.ClientSize = [System.Drawing.Size]::new(930,720)
$form.MinimumSize = [System.Drawing.Size]::new(760,680)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(244,247,248)
$colorInk = [System.Drawing.Color]::FromArgb(22,40,46)
$colorMuted = [System.Drawing.Color]::FromArgb(89,108,114)
$colorTeal = [System.Drawing.Color]::FromArgb(0,184,166)
$colorPale = [System.Drawing.Color]::FromArgb(229,249,245)
$colorLine = [System.Drawing.Color]::FromArgb(221,230,233)
$colorHeader = [System.Drawing.Color]::FromArgb(16,30,36)
$form.Font = [System.Drawing.Font]::new("Segoe UI", [single]10, [System.Drawing.FontStyle]::Regular)
$form.AutoScaleMode = "Dpi"
function Label($text,$y,$height,$size,$strong) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = [System.Drawing.Point]::new(24,[int]$y)
    $label.Size = [System.Drawing.Size]::new(870,[int]$height)
    $label.Anchor = "Top,Left,Right"
    $weight = if ($strong) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular }
    $label.Font = [System.Drawing.Font]::new("Segoe UI", [single]$size, $weight)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(25,39,42)
    $form.Controls.Add($label)
    return $label
}
# A compact MadLabz header, separate from the scrollable repository view.
$header = New-Object System.Windows.Forms.Panel
$header.Location = [System.Drawing.Point]::new(0,0)
$header.Size = [System.Drawing.Size]::new(930,91)
$header.Anchor = "Top,Left,Right"
$header.BackColor = $colorHeader
$form.Controls.Add($header)
$headerAccent = New-Object System.Windows.Forms.Panel
$headerAccent.Location = [System.Drawing.Point]::new(0,88)
$headerAccent.Size = [System.Drawing.Size]::new(930,3)
$headerAccent.Anchor = "Left,Right,Bottom"
$headerAccent.BackColor = $colorTeal
$header.Controls.Add($headerAccent)
$title = Label "Repo Backup" 12 44 24 $true
$title.Parent = $header
$title.ForeColor = [System.Drawing.Color]::White
$subtitle = Label "Local backup status and diagnostics" 58 23 10 $false
$subtitle.Parent = $header
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(172,193,199)
$brand = Label "MADLABZ  /  DESKTOP" 36 24 9 $true
$brand.Parent = $header
$brand.Location = [System.Drawing.Point]::new(707,33)
$brand.Size = [System.Drawing.Size]::new(195,24)
$brand.TextAlign = "MiddleRight"
$brand.Anchor = "Top,Right"
$brand.ForeColor = [System.Drawing.Color]::FromArgb(105,219,205)

$statusCard = New-Object System.Windows.Forms.Panel
$statusCard.Location = [System.Drawing.Point]::new(24,108)
$statusCard.Size = [System.Drawing.Size]::new(882,84)
$statusCard.Anchor = "Top,Left,Right"
$statusCard.BackColor = [System.Drawing.Color]::White
$statusCard.BorderStyle = "FixedSingle"
$form.Controls.Add($statusCard)
$statusStripe = New-Object System.Windows.Forms.Panel
$statusStripe.Location = [System.Drawing.Point]::new(0,0)
$statusStripe.Size = [System.Drawing.Size]::new(4,84)
$statusStripe.Anchor = "Top,Bottom,Left"
$statusStripe.BackColor = $colorTeal
$statusCard.Controls.Add($statusStripe)
$headline = Label "Checking local settings..." 9 29 14 $true
$headline.Parent = $statusCard
$headline.Location = [System.Drawing.Point]::new(18,9)
$summary = Label "" 40 40 10 $false
$summary.Parent = $statusCard
$summary.Location = [System.Drawing.Point]::new(18,39)
$summary.ForeColor = $colorMuted
$reposHeader = Label "REPOSITORIES" 200 23 9 $true
$reposHeader.ForeColor = $colorMuted
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = [System.Drawing.Point]::new(24,228)
$grid.Size = [System.Drawing.Size]::new(882,254)
$grid.Anchor = "Top,Bottom,Left,Right"
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$grid.GridColor = $colorLine
$grid.CellBorderStyle = [System.Windows.Forms.DataGridViewCellBorderStyle]::SingleHorizontal
$grid.EnableHeadersVisualStyles = $false
$grid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
$grid.ColumnHeadersHeight = 35
$grid.ColumnHeadersDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(231,238,240)
$grid.ColumnHeadersDefaultCellStyle.ForeColor = $colorInk
$grid.ColumnHeadersDefaultCellStyle.Font = [System.Drawing.Font]::new("Segoe UI", [single]9, [System.Drawing.FontStyle]::Bold)
$grid.DefaultCellStyle.Font = [System.Drawing.Font]::new("Segoe UI", [single]9, [System.Drawing.FontStyle]::Regular)
$grid.DefaultCellStyle.ForeColor = $colorInk
$grid.DefaultCellStyle.SelectionBackColor = $colorPale
$grid.DefaultCellStyle.SelectionForeColor = $colorInk
$grid.AlternatingRowsDefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(248,251,251)
$grid.RowTemplate.Height = 29
$grid.AllowUserToResizeRows = $false
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
$grid.BringToFront()
$detailsPanel = New-Object System.Windows.Forms.Panel
$detailsPanel.Location = [System.Drawing.Point]::new(24,492)
$detailsPanel.Size = [System.Drawing.Size]::new(882,48)
$detailsPanel.Anchor = "Bottom,Left,Right"
$detailsPanel.BackColor = [System.Drawing.Color]::White
$detailsPanel.BorderStyle = "FixedSingle"
$form.Controls.Add($detailsPanel)
$details = Label "Select a repository to see its last recorded issue." 9 38 9 $false
$details.Parent = $detailsPanel
$details.Location = [System.Drawing.Point]::new(12,8)
$details.Size = [System.Drawing.Size]::new(850,34)
$details.ForeColor = $colorMuted
$buttons = New-Object System.Windows.Forms.FlowLayoutPanel
$buttons.Location = [System.Drawing.Point]::new(24,634)
$buttons.Size = [System.Drawing.Size]::new(882,42)
$buttons.Anchor = "Bottom,Left,Right"
$buttons.AutoScroll = $true
$buttons.WrapContents = $false
$form.Controls.Add($buttons)
function Button($title,$width) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text=$title
    $b.Size=[System.Drawing.Size]::new([int]$width,34)
    $b.Margin=[System.Windows.Forms.Padding]::new(0,0,7,0)
    $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor = $colorLine
    $b.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::FromArgb(232,247,245)
    $b.BackColor = [System.Drawing.Color]::White
    $b.ForeColor = $colorInk
    $b.Font = [System.Drawing.Font]::new("Segoe UI", [single]9, [System.Drawing.FontStyle]::Regular)
    $buttons.Controls.Add($b)
    return $b
}
$refresh = Button "Refresh" 98
$doctor = Button "Health check" 116
$logs = Button "Recent logs" 115
$settings = Button "Settings" 95
$dryRun = Button "Safe dry run" 116
$dryRun.FlatAppearance.BorderColor = $colorTeal
$dryRun.ForeColor = [System.Drawing.Color]::FromArgb(0,112,103)
$dryInfo = Button "i" 29
$dryInfo.Font = [System.Drawing.Font]::new("Segoe UI", [single]10, [System.Drawing.FontStyle]::Bold)
$dryInfo.BackColor = $colorPale
$dryInfo.ForeColor = [System.Drawing.Color]::FromArgb(0,102,95)
$dryInfo.Margin = [System.Windows.Forms.Padding]::new(0,0,13,0)
$dryInfo.AccessibleName = "What is Safe dry run?"
$dryRunInfoText = "Checks enabled repositories and previews what a backup would do." + [Environment]::NewLine +
    "It checks Git status, fetches the latest remote state, and runs safety checks." + [Environment]::NewLine +
    "It does NOT stage files, create commits, or push changes." + [Environment]::NewLine +
    "It may update remote-tracking references and append a local dry-run history record." + [Environment]::NewLine +
    "It does not create a backup. MadLabz Website stays on Manual."
$toolTips = New-Object System.Windows.Forms.ToolTip
$toolTips.AutoPopDelay = 20000
$toolTips.InitialDelay = 250
$toolTips.ReshowDelay = 150
$toolTips.ShowAlways = $true
$toolTips.SetToolTip($dryInfo, $dryRunInfoText)
$toolTips.SetToolTip($dryRun, "Preview backup actions without committing or pushing. Click the i for details.")
$dryInfo.Add_Click({
    [System.Windows.Forms.MessageBox]::Show(
        $dryRunInfoText, "About Safe dry run",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
})
$test = Button "Test scheduler" 129
$test.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(232,207,160)
$footer = Label "Local dashboard  |  Closing this window does not stop automatic backups." 690 23 9 $false
$footer.ForeColor = $colorMuted
$footer.Anchor = "Bottom,Left,Right"
$cadenceLabel = Label "BACKUP FREQUENCY  /  SELECTED REPOSITORY" 549 25 9 $true
$cadenceLabel.ForeColor = $colorMuted
$cadenceLabel.Anchor = "Bottom,Left,Right"
$cadence = New-Object System.Windows.Forms.ComboBox
$cadence.Location = [System.Drawing.Point]::new(24,577)
$cadence.Size = [System.Drawing.Size]::new(210,32)
$cadence.Anchor = "Bottom,Left"
$cadence.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cadence.Items.AddRange([object[]]@("Manual (off)","Hourly","Every 6 hours","Daily"))
$cadence.BackColor = [System.Drawing.Color]::White
$cadence.ForeColor = $colorInk
$form.Controls.Add($cadence)
$saveCadence = New-Object System.Windows.Forms.Button
$saveCadence.Text = "Save schedule"
$saveCadence.Location = [System.Drawing.Point]::new(244,574)
$saveCadence.Size = [System.Drawing.Size]::new(142,34)
$saveCadence.Anchor = "Bottom,Left"
$saveCadence.Enabled = $false
$saveCadence.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$saveCadence.FlatAppearance.BorderSize = 0
$saveCadence.BackColor = $colorTeal
$saveCadence.ForeColor = [System.Drawing.Color]::FromArgb(8,34,32)
$saveCadence.Font = [System.Drawing.Font]::new("Segoe UI", [single]9, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($saveCadence)
$cadenceHint = Label "Choose a frequency, then Save schedule." 397 579 30 9 $false
$cadenceHint.ForeColor = $colorMuted
$cadenceHint.Location = [System.Drawing.Point]::new(408,580)
$cadenceHint.Size = [System.Drawing.Size]::new(490,25)
$cadenceHint.Anchor = "Bottom,Left,Right"
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
    $cadence.SelectedIndex = -1
    $saveCadence.Enabled = $false
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
    $enabled=0; $scheduled=0; $issues=0; $pausedIssues=0
    foreach($p in @($cfg.projects)) {
        $isEnabled=($p.enabled -ne $false)
        $issue=Has-Issue $p
        if($isEnabled) { $enabled++ }
        if($isEnabled -and $p.autoSchedule -in @("hourly","6h","daily")) { $scheduled++ }
        if($issue) { if($isEnabled -and $p.autoSchedule -in @("hourly","6h","daily")) { $issues++ } else { $pausedIssues++ } }
        $name=if($p.alias) {[string]$p.alias} else {[string]$p.name}
        $frequency=switch([string]$p.autoSchedule) { "hourly" {"Hourly"} "6h" {"6 hours"} "daily" {"Daily"} default {"Manual"} }
        $warning=if($issue -and $p.autoSchedule -eq "manual") {"Historical (paused)"} elseif($issue) {[string]$p.lastAutoFailureStatus} else {"None recorded"}
        $index=$grid.Rows.Add($name,$(if($isEnabled) {"Yes"} else {"No"}),$frequency,(Stamp $p.lastAutoRunAt),$(if($p.lastAutoStatus){[string]$p.lastAutoStatus}else{"-"}),$warning)
        $grid.Rows[$index].Tag=$p
        if($issue -and $p.autoSchedule -ne "manual") {$grid.Rows[$index].DefaultCellStyle.ForeColor=[System.Drawing.Color]::Firebrick}
    }
    $taskName=if($cfg.defaults.schedulerTaskName) {[string]$cfg.defaults.schedulerTaskName} else {"MadLabz Repo Backup Auto"}
    $health=Task-Health $taskName
    $last=Last-Run
    $lastText=if($null -eq $last) {"No completed run recorded"} else {"$(Stamp $last.timestamp) - $($last.status)"}
    $summary.Text="$enabled enabled | $scheduled scheduled | $issues active alerts | $pausedIssues past/paused alerts"+[Environment]::NewLine+"Scheduler: $health | Latest run: $lastText"
    if($issues -gt 0) { $headline.Text="$issues automatic backup issue(s) need attention"; $headline.ForeColor=[System.Drawing.Color]::Firebrick }
    elseif($scheduled -gt 0 -and $health -match "Not installed|Disabled") { $headline.Text="Scheduled backups require attention"; $headline.ForeColor=[System.Drawing.Color]::DarkGoldenrod }
    else { $headline.Text="No active scheduled backup alerts"; $headline.ForeColor=[System.Drawing.Color]::DarkCyan }
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
$saveCadence.Add_Click({
    if($grid.SelectedRows.Count -ne 1 -or $cadence.SelectedIndex -lt 0) { return }
    $p = $grid.SelectedRows[0].Tag
    if($null -eq $p -or $p.enabled -eq $false) { return }
    $newSchedule = @("manual","hourly","6h","daily")[$cadence.SelectedIndex]
    $oldSchedule = if($p.autoSchedule) { [string]$p.autoSchedule } else { "manual" }
    if($oldSchedule -eq $newSchedule) { return }
    if($newSchedule -ne "manual" -and (Has-Issue $p)) {
        [System.Windows.Forms.MessageBox]::Show(
            "This repository has an unresolved backup failure. Keep it Manual until you reconcile the Git branch and run a successful check.",
            "Schedule blocked", "OK", "Warning"
        ) | Out-Null
        return
    }
    $projectName = if($p.alias) { [string]$p.alias } else { [string]$p.name }
    $message = "Change {0} from {1} to {2}?" -f $projectName, $oldSchedule, $newSchedule
    if($newSchedule -ne "manual") {
        $message += [Environment]::NewLine+[Environment]::NewLine+"Automatic backups may commit and push when due. The Windows scheduled task must also be installed."
    }
    $answer = [System.Windows.Forms.MessageBox]::Show($message,"Confirm backup schedule","YesNo","Question")
    if($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    if(-not (Test-Path -LiteralPath $engine -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("Repo Backup is not installed.","Repo Backup") | Out-Null
        return
    }
    # Only trusted fixed choices, and use the selected repo's explicit configured path.
    $target = [string]$p.path
    if(-not $target -or $target.Contains('"')) { return }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $engine + '" schedule "' + $target + '" ' + $newSchedule
    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $saveCadence.Enabled = $false
        $form.UseWaitCursor = $true
        $process = Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $response = ((Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) + [Environment]::NewLine + (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)).Trim()
        if($process.ExitCode -ne 0 -or $response -notmatch "\[OK\]") {
            [System.Windows.Forms.MessageBox]::Show("Could not confirm schedule change." + [Environment]::NewLine + $response,"Repo Backup","OK","Error") | Out-Null
        } else {
            Refresh-Status
            # Preserve the edited repository selection after reloading settings.
            $grid.ClearSelection()
            foreach($row in $grid.Rows) {
                if($row.Tag -and ([string]$row.Tag.path -eq $target)) {
                    $row.Selected = $true
                    $grid.CurrentCell = $row.Cells[0]
                    break
                }
            }
            [System.Windows.Forms.MessageBox]::Show(
                ("Saved: {0} is now {1}." -f $projectName, $newSchedule),
                "Schedule saved", "OK", "Information"
            ) | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,"Repo Backup","OK","Error") | Out-Null
    } finally {
        $form.UseWaitCursor = $false
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
        $saveCadence.Enabled = ($grid.SelectedRows.Count -gt 0)
    }
})
$grid.Add_SelectionChanged({
    if($grid.SelectedRows.Count -eq 1 -and $grid.SelectedRows[0].Tag) {
        $chosen = $grid.SelectedRows[0].Tag
        $cadence.SelectedIndex = switch([string]$chosen.autoSchedule) { "hourly" {1} "6h" {2} "daily" {3} default {0} }
        $saveCadence.Enabled = ($chosen.enabled -ne $false)
        $cadence.Enabled = ($chosen.enabled -ne $false)
    } else {
        $cadence.SelectedIndex = -1
        $saveCadence.Enabled = $false
    }

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
