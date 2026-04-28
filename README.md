# Github CLI Extension: Tidy

[Github CLI Extension](https://docs.github.com/en/github-cli/github-cli/creating-github-cli-extensions) for tidying your Git workspace!

![gh tidy demo](./gh-tidy-demo.gif)

`gh tidy` does several things:
* Checks out master/main and pulls the latest from remote origin
* Runs 'git gc' to clean up unnecessary files & optimize your local repo
* Checks your local branches for ones that show as merged to master, and asks for your permission to delete them
* Checks your local branches for ones that have their corresponding pull requests merged, and asks for your permission to delete them
* If flagged, rebases all your local branches to the latest master

## Installation
```sh
gh extension install HaywardMorihara/gh-tidy
```

## Updating
```sh
gh extension upgrade HaywardMorihara/gh-tidy
```

## Usage
Simply run
```sh
gh tidy
```
and it will checkout master/main, pull the latest, and clean up branches for you (with your permission, of course).

If your repo doesn't _have_ a master/main branch, you can specify your trunk branch with the `--trunk <branchname>` parameter

### Non-interactive use

For cron jobs, CI runners, post-merge git hooks, and other non-interactive contexts where the
interactive `(y/n)` prompts would hang, pass `--auto-delete-merged`:

```sh
gh tidy --auto-delete-merged --skip-update-check --skip-gc
```

Or set the environment variable to keep your scripts flag-free:

```sh
export GH_TIDY_AUTO_DELETE_MERGED=true
gh tidy
```

Example post-merge hook (`.git/hooks/post-merge`):

```sh
#!/usr/bin/env bash
GH_TIDY_AUTO_DELETE_MERGED=true gh tidy --skip-update-check --skip-gc
```

Merged branches are still protected by the same safety checks as interactive mode: trunk
branches, branches missing locally, and branches checked out in another worktree are never
deleted.

## Troubleshooting
If you get an error such as:
```sh
failed to run extension: fork/exec <USER_PATH>/.local/share/gh/extensions/gh-tidy/gh-tidy: permission denied
```
then try:
```sh
gh extension upgrade HaywardMorihara/gh-tidy
```

This was the result of file permissions being ignored by Git. I fixed this in the repo with:
```sh
git config core.fileMode true
```
See [here](https://stackoverflow.com/questions/1580596/how-do-i-make-git-ignore-file-mode-chmod-changes) for more details.
