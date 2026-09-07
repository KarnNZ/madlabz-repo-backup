# MadLabz Repo Backup — Complete How-to-Use Guide

> **One command. Every repo safely checkpointed.**

This guide is for someone using MadLabz Repo Backup for the first time. You do not need to be a Git expert.

Repo Backup is a Windows developer utility that helps you checkpoint multiple Git repositories from one place. It discovers repositories, lets you choose which ones to protect, checks for unsafe Git states, creates timestamped checkpoint commits when files changed, and pushes only when the configured remote state is safe.

Repo Backup is deliberately conservative. It does not auto-pull, auto-merge, rebase, switch branches, resolve conflicts, or force-push.

Current public release: **v0.6.2**.

---

## 1. What you need

Before installing Repo Backup, make sure you have:

- Windows 10 or Windows 11
- Git installed
- Windows PowerShell 5.1 or newer
- at least one Git repository on your computer

Git Bash is supported and is a good terminal choice if you already use it.

If you want Repo Backup to push checkpoints off your machine, your project should already have a normal working Git remote. GitHub works, but Repo Backup is not limited to GitHub.

---

## 2. Download Repo Backup

Open the latest release page:

https://github.com/KarnNZ/madlabz-repo-backup/releases/latest

Under **Assets**, download the Windows release ZIP:

```text
madlabz-repo-backup-v0.6.2-windows.zip
```

For a normal installation, use the Windows release ZIP rather than GitHub's automatically generated source-code ZIP.

---

## 3. Extract the ZIP

1. Open your Downloads folder.
2. Right-click the downloaded ZIP.
3. Choose **Extract All**.
4. Open the extracted folder.

You should see files including:

```text
VALIDATE-PACKAGE.cmd
INSTALL.cmd
repo-backup.ps1
```

---

## 4. Validate the package before installing

Double-click:

```text
VALIDATE-PACKAGE.cmd
```

You want both checks to pass:

```text
ASCII source compatibility: PASS
PowerShell parse: PASS
```

If either check fails, do not install that package.

---

## 5. Install Repo Backup

Double-click:

```text
INSTALL.cmd
```

Let the installer finish.

Repo Backup installs its application files under:

```text
%LOCALAPPDATA%\MadLabz\RepoBackup\App
```

Persistent repository configuration and logs are stored separately, so future application updates do not replace your setup.

---

## 6. Open a new terminal

After installation, close any Git Bash or PowerShell windows that were already open.

Then open a fresh **Git Bash** or **PowerShell** window.

Check the installation:

```bash
repo-backup version
```

For this release you should see version `0.6.2` reported.

If the command is not found, close the terminal completely and open a new one before trying again.

---

## 7. Optional: try the read-only demo first

If you want to see Repo Backup without touching your real repositories, run:

```bash
repo-backup demo
```

The demo is read-only.

---

## 8. Run the onboarding wizard

For first-time setup, run:

```bash
repo-backup onboard
```

This is the easiest way to configure Repo Backup.

The onboarding flow will:

1. scan common development folders
2. show the Git repositories it finds
3. keep newly discovered repositories disabled until you explicitly select them
4. let you use friendly aliases when repository folder names are confusing or duplicated
5. review Git state, sensitive files, obvious secret risks, and generated directories
6. preserve existing schedules when re-running onboarding
7. let you choose Manual, Hourly, Every 6 hours, or Daily scheduling
8. let you run a dry-run through the real backup safety engine
9. configure or refresh Windows Task Scheduler when automatic schedules are enabled

---

## 9. Choose which repositories to protect

Discovery does not automatically enable every repository on your machine.

Select only the repositories you want Repo Backup to manage.

A simple setup might look like:

```text
[x] Main Website
[x] API
[x] Ecommerce Store
[ ] Old Prototype
[ ] Archived Project
```

You can add, disable, enable, rename, or remove repositories later.

---

## 10. Let the safety review run

Before checkpointing, Repo Backup checks for situations where automatic Git action would be risky.

It can block on conditions such as:

- detached HEAD
- merge, rebase, or cherry-pick in progress
- remote branch ahead
- diverged local and remote history
- tracked sensitive files such as `.env`
- suspicious changed content that looks like a literal secret
- sensitive filenames present in first-push Git history
- dangerous broad Git roots
- unignored dependency or build output such as `node_modules` or `.next`

A blocked backup is intentional. Repo Backup would rather stop and tell you what needs attention than guess how your Git history should be changed.

For more detail, see [SAFETY.md](SAFETY.md).

---

## 11. Choose a schedule for each repository

Each repository can be configured independently:

```text
Manual
Hourly
Every 6 hours
Daily
```

A sensible starting configuration is:

```text
Main active project      Hourly
Other important project Every 6 hours
Experiments              Manual
Archived work            Manual or disabled
```

You do not need to back up every repository every hour.

---

## 12. Run a Dry Run first

Before your first real checkpoint, run:

```bash
repo-backup backup -DryRun
```

A Dry Run previews the real backup flow and runs the safety checks without performing the actual checkpoint.

Use Dry Run whenever you are uncertain about what Repo Backup will do.

---

## 13. Run your first real backup

Once the Dry Run looks correct, run:

```bash
repo-backup backup
```

Repo Backup processes enabled repositories independently.

When files changed and the repository is safe, it can create a timestamped checkpoint commit and push it to that repository's configured remote.

Clean repositories are skipped. Repo Backup does not create empty junk commits simply because a schedule ran.

---

## 14. Your normal everyday command

Most of the time, just run:

```bash
repo-backup
```

This opens the dashboard.

A dashboard can look like:

```text
MADLABZ REPO BACKUP  v0.6.2  |  DASHBOARD

Protected repos         : 12
Local changes           : 2
Unpushed commits        : 0
Git attention           : 0
Auto issues             : 0
Auto schedules          : 2
Scheduler               : Healthy
```

For detailed repository-by-repository state, run:

```bash
repo-backup status
```

---

## 15. Automatic backups

If you selected Hourly, Every 6 hours, or Daily, Repo Backup can use Windows Task Scheduler.

Repo Backup installs a single hourly scheduler trigger. The tool then decides which repositories are actually due.

For example:

```text
Website    Hourly
API        Every 6 hours
Prototype  Manual
```

The hourly Windows trigger does not mean a new commit is created every hour.

Repo Backup skips:

- clean repositories
- repositories that are not yet due
- repositories that fail a safety check

Automatic mode uses the same safety engine as manual backups and waits for an idle window before checkpointing active edits.

---

## 16. Test the automatic scheduler

After enabling automatic schedules, run:

```bash
repo-backup schedule test
```

This verifies that Windows can launch Repo Backup through Task Scheduler without you manually opening a terminal.

---

## 17. View or change schedules

Show current schedules:

```bash
repo-backup schedule
```

Set a repository to Hourly:

```bash
repo-backup schedule "Website" hourly
```

Set Every 6 hours:

```bash
repo-backup schedule "API" 6h
```

Set Daily:

```bash
repo-backup schedule "Shop" daily
```

Return a repository to Manual:

```bash
repo-backup schedule "Prototype" manual
```

---

## 18. Check automatic backup history

Show recent automatic runs:

```bash
repo-backup auto log
```

Show a specific number of recent runs:

```bash
repo-backup auto log 20
```

This is useful for confirming that unattended backups have actually been running.

---

## 19. Windows notifications

Enable automatic-run notifications:

```bash
repo-backup schedule notify on
```

Disable them:

```bash
repo-backup schedule notify off
```

---

## 20. Add another project later

You can safely run onboarding again at any time:

```bash
repo-backup onboard
```

Or scan for repositories:

```bash
repo-backup scan
```

Scan a specific folder:

```bash
repo-backup scan "C:\Users\YourName\Desktop\Projects"
```

Add a known repository directly:

```bash
repo-backup add "C:\Users\YourName\Desktop\my-project"
```

Then enable it if needed:

```bash
repo-backup enable "my-project"
```

---

## 21. Give a repository a friendly name

If a technical folder name is hard to recognize, assign an alias:

```bash
repo-backup alias "madlabz-v2" "MadLabz Website"
```

You can then use the friendly name in commands:

```bash
repo-backup schedule "MadLabz Website" hourly
```

---

## 22. Temporarily disable a repository

Disable it:

```bash
repo-backup disable "Prototype"
```

Enable it again later:

```bash
repo-backup enable "Prototype"
```

---

## 23. Remove a repository from Repo Backup

Run:

```bash
repo-backup remove "Prototype"
```

This removes the repository from Repo Backup's configuration. It does not delete the actual project directory.

---

## 24. Check installation health

Run:

```bash
repo-backup doctor
```

Use this when you want to check the installation, configuration, environment, or Git access.

---

## 25. Check for updates

Run:

```bash
repo-backup update check
```

This is read-only. It checks the public release channel and tells you whether a newer version is available.

---

## 26. Update Repo Backup

For the current v0.6 release series, upgrades remain explicit.

1. Download the newer Windows release ZIP.
2. Extract it.
3. Run `VALIDATE-PACKAGE.cmd`.
4. Confirm:

```text
ASCII source compatibility: PASS
PowerShell parse: PASS
```

5. Run:

```text
UPDATE.cmd
```

6. Open a new terminal.
7. Verify:

```bash
repo-backup version
```

Program updates replace the application directory, not your persistent repository configuration or logs.

---

## 27. If Repo Backup blocks a repository

Do not immediately try to bypass the block.

Read the reason Repo Backup gives you.

For example:

- If a `.env` file is tracked, fix the repository so the sensitive file is no longer tracked.
- If the remote is ahead, decide how you want to synchronize the branch using normal Git tools.
- If branches diverged, decide whether your project requires a merge, rebase, or another deliberate Git operation.
- If a merge or rebase is already in progress, finish or cancel that operation normally before running Repo Backup again.

Then preview again:

```bash
repo-backup backup -DryRun
```

Repo Backup intentionally does not make those Git-history decisions for you.

---

## 28. If `repo-backup` says command not found

1. Close the terminal completely.
2. Open a new Git Bash or PowerShell window.
3. Run:

```bash
repo-backup version
```

Terminals that were already open before installation can still have the old PATH environment.

---

## 29. If a project is not found

Run onboarding again:

```bash
repo-backup onboard
```

Or scan the folder that contains the project:

```bash
repo-backup scan "C:\path\to\your\projects"
```

If you know the exact path:

```bash
repo-backup add "C:\path\to\your\repo"
```

---

## 30. The commands most people need

You do not need to memorize the full command surface.

```bash
# Dashboard
repo-backup

# First-time setup
repo-backup onboard

# Read-only demo
repo-backup demo

# Detailed status
repo-backup status

# Preview a safe checkpoint
repo-backup backup -DryRun

# Run a real backup
repo-backup backup

# View schedules
repo-backup schedule

# Test unattended scheduling
repo-backup schedule test

# View automatic-run history
repo-backup auto log

# Check installation health
repo-backup doctor

# Show installed version
repo-backup version

# Check for a newer release
repo-backup update check
```

---

## Recommended setup for most developers

If you just want a sensible setup and do not want to think about every option:

```text
1. Download and extract Repo Backup
2. Run VALIDATE-PACKAGE.cmd
3. Run INSTALL.cmd
4. Open a new terminal
5. Run repo-backup onboard
6. Select your active repositories
7. Set your main project to Hourly
8. Set other important projects to Every 6 hours
9. Leave experiments and old projects Manual or disabled
10. Run the safety review
11. Run repo-backup backup -DryRun
12. Run repo-backup backup
13. Run repo-backup schedule test
14. Keep coding
```

After that, check the dashboard whenever you want reassurance:

```bash
repo-backup
```

---

## Simplest possible version

```text
DOWNLOAD
↓
EXTRACT
↓
VALIDATE-PACKAGE.cmd
↓
INSTALL.cmd
↓
OPEN A NEW TERMINAL
↓
repo-backup onboard
↓
CHOOSE YOUR REPOS
↓
CHOOSE YOUR SCHEDULES
↓
RUN THE SAFETY CHECK
↓
repo-backup backup -DryRun
↓
repo-backup backup
↓
repo-backup schedule test
↓
DONE
```

Then keep working normally and use:

```bash
repo-backup
```

when you want to see the current state of your protected repositories.

---

## Full command reference

```text
repo-backup
repo-backup onboard
repo-backup demo

repo-backup status
repo-backup backup [repo]
repo-backup backup -DryRun
repo-backup list
repo-backup doctor
repo-backup version

repo-backup schedule
repo-backup schedule <repo> <manual|hourly|6h|daily>
repo-backup schedule test
repo-backup schedule notify <on|off>

repo-backup auto
repo-backup auto log [count]

repo-backup scan [folder]
repo-backup add <path>
repo-backup enable <name|path>
repo-backup disable <name|path>
repo-backup alias <repo> <friendly-name>
repo-backup remove <name|path>

repo-backup update check
repo-backup update
repo-backup help
```

---

## License

MadLabz Repo Backup is free and open source under the [MIT License](../LICENSE).
