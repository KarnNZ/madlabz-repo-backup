# Releasing MadLabz Repo Backup

## First public release

The repository is intended to be:

```text
https://github.com/KarnNZ/madlabz-repo-backup
```

Licence: MIT.

Before tagging:

```bash
./VALIDATE-PACKAGE.cmd
```

Then confirm the GitHub `Validate` workflow passes on `main`.

Create an annotated release tag:

```bash
git tag -a v0.6.2 -m "MadLabz Repo Backup v0.6.2"
git push origin v0.6.2
```

The `Release` workflow then:

1. runs the Windows PowerShell package validator
2. verifies the Git tag matches `$ScriptVersion`
3. builds `madlabz-repo-backup-v0.6.2-windows.zip`
4. generates its SHA256 file
5. generates `release-manifest.json`
6. creates the GitHub Release

After release:

```bash
repo-backup update check
```

should resolve the live GitHub release channel.
