# MadLabz Repo Backup v0.6.2

**One command. Every repo safely checkpointed.**

v0.6.2 is the first public-beta release of MadLabz Repo Backup.

## What it does

- protects multiple local Git repositories from one dashboard
- runs a safety review before checkpointing
- fetches before pushing and blocks remote-ahead/diverged states
- blocks active merge/rebase/cherry-pick operations
- checks sensitive filenames and obvious literal secrets
- supports Manual, Hourly, Every 6 hours and Daily schedules per repository
- uses one Windows Task Scheduler trigger for unattended checks
- skips clean repositories rather than creating junk commits
- includes a guided onboarding flow and read-only demo

## New in the release build

- stable AppData installation and upgrade architecture
- global `repo-backup` command in Git Bash / Windows
- guided `repo-backup onboard`
- concise default dashboard
- `repo-backup demo`
- `repo-backup update check`
- persistent automatic-run log and scheduler test
- package preflight with Windows PowerShell parser validation
- ASCII-only executable PowerShell source for Windows PowerShell 5.1 compatibility
- MIT licence

## Safety philosophy

Repo Backup does not auto-pull, auto-merge, rebase, resolve conflicts or force-push.

A `BLOCKED` result is deliberate: when Git history needs human judgement, Repo Backup stops instead of guessing.

## Install

1. Download `madlabz-repo-backup-v0.6.2-windows.zip`.
2. Extract it.
3. Run `VALIDATE-PACKAGE.cmd`.
4. Confirm:

```text
ASCII source compatibility: PASS
PowerShell parse: PASS
Version marker: 0.6.2
```

5. Run `INSTALL.cmd`.
6. Open a new terminal and run:

```bash
repo-backup onboard
```

Existing users can run `UPDATE.cmd` instead of `INSTALL.cmd`.

## Platform

Windows 10/11, Git, Windows PowerShell 5.1+. Git Bash is supported.
