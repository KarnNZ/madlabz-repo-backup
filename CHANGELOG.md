# Changelog

## 0.6.2

- Fixed the V0.6.1 RC Windows PowerShell 5.1 encoding/parser failure.
- Removed Unicode arrow characters from executable `repo-backup.ps1`.
- Repo Backup executable PowerShell source is now intentionally ASCII-only.
- `VALIDATE-PACKAGE.cmd` now fails if `repo-backup.ps1` contains non-ASCII bytes.
- Package validation now reports both ASCII compatibility and PowerShell parse status.
- Backup, Git safety, secret safety, onboarding and scheduler core remain unchanged from the proven V0.5.1 baseline.


## 0.6.1

- Fixed the V0.6.0 RC PowerShell parser regression in the new help surface.
- Replaced the release-polish help here-string with ordinary string-array output.
- Added `VALIDATE-PACKAGE.cmd` / `VALIDATE-PACKAGE.ps1` so Windows PowerShell can parse-check a downloaded package before install/update.
- Tightened update-version tag stripping.
- Backup, remote-safety, secret-safety, onboarding and scheduler core remain unchanged from the proven V0.5.1 baseline.


## 0.5.1

- Fixed a Windows PowerShell parser error in the V0.5.0 onboarding output.
- Braced interpolated repository display names when immediately followed by `:`.
- V0.5.0 could not start at all, so failed V0.5.0 update attempts did not modify the installed application or user data.
- Preserves the V0.5.0 onboarding/dashboard feature set and the proven V0.4.2 installation/backup core.


## 0.5.0

- Added `repo-backup onboard` guided public-beta setup.
- Changed the default no-argument command from detailed `status` to the concise `dashboard`.
- Added explicit `repo-backup dashboard`.
- Dashboard summarizes protected repos, local changes, unpushed commits, Git attention, unresolved auto issues, automatic schedules, scheduler health, and latest auto activity.
- Onboarding scans configured roots plus common safe developer folders when they exist.
- Newly discovered repositories remain disabled until explicitly selected.
- Added numeric/range repository selection (`1,3-5`, `all`).
- Re-running onboarding can keep the existing enabled set by pressing Enter.
- Added duplicate-name friendly alias prompts during onboarding.
- Added onboarding safety review using the existing proven Git-operation, generated-directory, sensitive-file, and changed-content secret checks.
- Repositories with onboarding safety findings are kept on Manual scheduling.
- Existing schedules are preserved by default during onboarding; users can explicitly set one schedule for all or customize per repository.
- Onboarding treats non-ready Git states such as missing remotes as safety findings and keeps those repositories Manual.
- Added optional onboarding dry-run using the existing backup engine.
- Added optional Windows scheduler installation/update when automatic schedules are selected.
- Added `ONBOARD.cmd` and `DASHBOARD.cmd`.
- Added `onboardingCompleteAt` to config schema v5.
- Preserves the V0.4.2 stable installation/update architecture and the frozen backup safety core.


## 0.4.2

- Fixed V0.4.1 update failure caused by the invalid regex pattern `\`.
- Uses literal `String.Replace` for Windows-to-Git-Bash path conversion.
- Builds the Bash launcher from literal string elements, preserving Bash `"$@"`.
- Adds `%USERPROFILE%\bin\repo-backup` as a Git Bash-friendly launcher.
- Keeps `%LOCALAPPDATA%\MadLabz\RepoBackup\bin\repo-backup` and `repo-backup.cmd`.
- Broadcasts the Windows environment-change event on every install/update.
- Preserves the permanent app architecture and all repo config/history/logs.


## 0.4.1

- Added an extensionless `repo-backup` launcher for Git Bash.
- Retained `repo-backup.cmd` for CMD/PowerShell.
- Broadcasts the Windows environment change after adding the Repo Backup bin directory to the user's PATH.
- `version` now reports both command shim locations.
- Fixes installation succeeding while Git Bash still reports `repo-backup: command not found`.


## 0.4.0

- Added a permanent Windows application location: `%LOCALAPPDATA%\MadLabz\RepoBackup\App`.
- Added `repo-backup install` and `INSTALL.cmd`.
- Added local-package upgrade flow with `repo-backup update` and `UPDATE.cmd`.
- Installer stages and validates program files before replacing an existing installation.
- Keeps one previous installed application at `App.previous` during upgrades.
- User config, backup history, and automatic-run logs stay outside the replaceable `App` folder.
- Added `%LOCALAPPDATA%\MadLabz\RepoBackup\bin\repo-backup.cmd` command shim.
- Installer adds the Repo Backup bin folder to the current user's PATH without using `setx`.
- Added `repo-backup version` with running/installed version and location information.
- `doctor` now reports installation mode, installed version, PATH state, and scheduler target state.
- Windows Task Scheduler prefers the stable installed app path when one exists.
- Installing/updating refreshes an existing scheduler, or creates it when automatic repo schedules are already enabled.
- Git is no longer required merely to run `install`, `update`, `version`, `help`, or configuration-only commands.
- Preserves the proven V0.3.3 backup/safety/scheduling behavior.


## 0.3.3

- Added persistent automatic-run logging to `%LOCALAPPDATA%\MadLabz\RepoBackup\auto-runs.jsonl`.
- Added `repo-backup auto log [count]`.
- Added built-in `repo-backup schedule test` using the Windows Task Scheduler COM API.
- Added scheduler target-path detection so upgrades can identify tasks still pointing at older Repo Backup folders.
- Added `LastSuccess` and unresolved `LastIssue` visibility for automatic backups.
- Added per-repository last automatic failure status/details/timestamp tracking.
- Added best-effort Windows attention notifications only for automatic runs that fail or are blocked.
- Added `repo-backup schedule notify on|off`.
- Automatic runs with real failures/blocks now exit non-zero after recording state/logs, allowing Task Scheduler `Last Result` to reflect attention conditions.
- Added `AUTO-BACKUP-LOG.cmd`.
- Added `TEST-AUTO-BACKUP.cmd`.
- Upgraded machine config schema to v4 while preserving existing aliases, enabled state, and schedules.


## 0.3.2

- Fixed Windows PowerShell 5.1 `Argument types do not match` failure after a targeted automatic backup.
- Backup result handoff now converts `Generic.List[object]` explicitly with `ToArray()`.
- Simplified automatic-run result handling to avoid unnecessary array coercion.
- Preserves all V0.3.1 aliases, schedules, and machine configuration.


## 0.3.1

- Fixed false scheduler errors before the Windows scheduled task has been installed.
- A missing Task Scheduler entry is now treated as the normal `not installed` state.
- Scheduler detection locally suppresses `schtasks.exe` stderr instead of allowing strict PowerShell error handling to abort `schedule`.
- Existing aliases and per-repository schedules stored by V0.3.0 are preserved.


## 0.3.0

- Added friendly per-repository aliases.
- Added targeted backups by alias, original name, or full path.
- Added opt-in per-repository automatic schedules: Manual, Hourly, Every 6 hours, Daily.
- Added one-hour Windows Task Scheduler orchestration (`schedule install` / `schedule remove`).
- Added `auto` mode that only runs repositories whose configured cadence is due.
- Added a 5-minute automatic idle window to avoid checkpointing while files are actively changing.
- Automatic runs reuse the proven fetch/divergence/secret/history safety pipeline.
- Automatic commits use an `Auto Backup` prefix.
- Existing V0.2.x machine config is upgraded in place; automatic scheduling remains Manual by default.
- Added `AUTO-BACKUP-SETTINGS.cmd`.


## 0.2.5

- Fixed Windows safety-scan failures on Git-quoted or Unicode filenames.
- Git pathname-producing commands now use `core.quotepath=false`.
- Sensitive filename checks no longer pass Git path strings to `System.IO.Path.GetFileName`.
- Untracked-file extension detection now operates directly on Git path strings.
- Literal-path reads are used when inspecting untracked files.
- Uninspectable changed paths are blocked safely instead of crashing the backup run.


## 0.2.4

- Reduced secret-scan false positives for identifier and environment references such as `apiKey: API_KEY` and `apiKey: process.env.API_KEY`.
- Generic secret assignment detection now requires a literal-looking value.
- Added tracked sensitive-file checks.
- Added a first-push Git-history audit for sensitive filenames such as `.env.local`, private keys, and credential files.
- Added fast blocking for unignored dependency/build directories (`node_modules`, `.next`, `dist`, etc.) instead of recursively scanning them.
- Added visible safety-scan progress.


## 0.2.3

- Fixed safety scans for newly initialized repositories with no first commit (`HEAD` is unborn).
- Prevented benign Windows LF/CRLF warnings from aborting dry-run safety scans.
- Status now explicitly identifies repositories with missing `origin` remotes.
- Missing remotes now count as "need attention" in status/doctor output.
- Backup remote detection no longer leaks Git's raw "No such remote" error.


## 0.2.2

- Fixed a critical `add` safety bug where a non-repo project folder could resolve upward to a parent Git repository.
- `add` now requires a direct `.git` marker at the requested project root.
- Blocks Windows user-profile, Desktop, and drive roots as unsafe repository targets.
- `status` and `backup` now reject protected broad-root entries before running expensive Git scans.
- Re-adding an already configured disabled repo now enables it.

## 0.2.1

- Fixed status abort when a branch has no upstream.
- Added safe fallback comparison to a matching remote-tracking branch.
- Hardened new remote branch detection.
- Added `enable` and `disable`.
- New scan discoveries are disabled by default.
- Replaced staged-change exit-code probe with a filename-based check.


## 0.2.0

- Added `scan` command for automatic Git repo discovery.
- Added `status`, `list`, `doctor`, `add`, and `remove`.
- Added V0.1 config migration.
- Moved active config to `%LOCALAPPDATA%\MadLabz\RepoBackup`.
- Added persistent backup history.
- Added remote freshness check before commit/push.
- Added ahead/behind/divergence protection.
- Added support for pushing existing unpushed commits.
- Added detached-HEAD and in-progress Git-operation blocking.
- Added first-push remote branch creation.
- Improved secret checks.
- Added command wrapper and double-click Windows launchers.
