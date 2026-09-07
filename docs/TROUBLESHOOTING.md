# Troubleshooting

## `repo-backup: command not found`

Open a completely new terminal after installation.

Verify:

```bash
/c/Users/YOURNAME/AppData/Local/MadLabz/RepoBackup/bin/repo-backup.cmd version
```

Git Bash also receives a launcher under:

```text
%USERPROFILE%\bin\repo-backup
```

## Scheduler points at an older folder

Run:

```bash
repo-backup schedule install
repo-backup schedule test
```

Installed releases use the permanent AppData path.

## Repo is BLOCKED

Run:

```bash
repo-backup status
repo-backup backup -DryRun
```

Repo Backup does not automatically reconcile divergent Git history.

## See unattended activity

```bash
repo-backup auto log 40
repo-backup schedule
```

## Check installation health

```bash
repo-backup doctor
repo-backup version
```
