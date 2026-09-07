# Safety Model

Repo Backup is a checkpoint utility, not a Git conflict resolver.

## It will not

- pull automatically
- merge automatically
- rebase automatically
- force-push
- resolve conflicts
- silently switch branches

## It checks

- repository is a direct Git root
- current branch is valid
- no merge/rebase/cherry-pick operation is active
- remote state after a fresh fetch
- remote-ahead/diverged conditions
- tracked sensitive filenames
- changed content for obvious literal secrets
- first-push Git history for sensitive filenames
- dangerous generated/dependency directories
- automatic idle window before unattended checkpoints

## A block is a successful safety outcome

When Repo Backup says `BLOCKED`, it means it deliberately refused to guess.

Resolve the Git or secret issue yourself, then run the backup again.
