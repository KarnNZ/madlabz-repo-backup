# Quick Start

## Install

Extract the release ZIP and run:

```text
INSTALL.cmd
```

Then open a new terminal:

```bash
repo-backup version
repo-backup onboard
```

## First real backup

Preview first:

```bash
repo-backup backup -DryRun
```

If the result is clean:

```bash
repo-backup backup
```

## Automatic backup

During onboarding, choose a schedule only for repos you actually want automated.

Or later:

```bash
repo-backup schedule "Website" hourly
repo-backup schedule install
repo-backup schedule test
```

## Daily use

```bash
repo-backup
```

That is normally all you need.
