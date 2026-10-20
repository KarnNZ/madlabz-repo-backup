# MadLabz Repo Backup v0.7.0

**One command. Every repo safely checkpointed. Now with an optional desktop status dashboard.**

## What is new

- A lightweight Windows dashboard, launched by double-clicking `OPEN-STATUS-DASHBOARD.cmd`.
- Review enabled repositories, schedules, latest automatic runs and historical warnings without a terminal.
- Set Manual, Hourly, Every 6 hours or Daily schedules for individual repositories or selected groups.
- Use Check enabled and Clear checks to manage bulk selections.
- Run Health check, inspect automatic-run logs, and preview a Safe dry run.
- An information button explains Safe dry run. The actual scheduler test always asks for confirmation because it can create and push Git checkpoints.
- Historical remote-ahead failures remain visible but are distinguished from current scheduled alerts.
- Windows Scheduler errors (including launch-refused result 0x800710E0) are labelled as warnings rather than shown as healthy.

## Safety and compatibility

- **The desktop window is optional.** Closing it never stops Windows scheduled backups.
- Existing Git safety controls are unchanged: never auto-pull, merge, rebase, resolve conflicts, or force-push.
- Repositories with unresolved previous automatic-backup failures cannot be re-enabled automatically through the dashboard without resolving the issue.
- All dashboard status data stays on the local machine. No MadLabz cloud account or telemetry is required.
- v0.7.0 preserves the user configuration, backup history, and automatic-run logs outside the installed program folder.
- Windows 10/11, Git and Windows PowerShell 5.1 or later.

## Install (new users)

1. Download `madlabz-repo-backup-v0.7.0-windows.zip`, extract it, and run `VALIDATE-PACKAGE.cmd`.
2. Verify the engine and dashboard source pass PowerShell parsing and ASCII compatibility checks.
3. Run `INSTALL.cmd`.
4. To configure repositories, run `repo-backup onboard` in PowerShell or Git Bash.
5. Open the desktop dashboard with `OPEN-STATUS-DASHBOARD.cmd` in `%LOCALAPPDATA%\MadLabz\RepoBackup\App`.

## Update from v0.6.2

1. Download and extract the v0.7.0 ZIP.
2. Run `VALIDATE-PACKAGE.cmd` and then `UPDATE.cmd` from the extracted folder.
3. Check `repo-backup version` reports v0.7.0 and double-click the installed `OPEN-STATUS-DASHBOARD.cmd`.
4. Verify schedules and repository status. The update does not enable new schedules or reset existing configuration.

The website also offers an **interactive browser demo** with fictitious sample data. It is distinct from the installed desktop app and cannot access local Git repositories or Windows tasks.
