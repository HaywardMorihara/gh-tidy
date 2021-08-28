# Github CLI Extension: Tidy

[Github CLI Extension](https://docs.github.com/en/github-cli/github-cli/creating-github-cli-extensions) for tidying your Git workspace!

## Installation
```sh
gh extension install HaywardMorihara/gh-tidy
```

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