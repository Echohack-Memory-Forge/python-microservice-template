# pre-commit-config.yaml

Pre-commit is a Python package which can be used to create 'git' hooks which scan can prior to checkins.
The included configuration focuses on python actions which will help to prevent users from commiting code which will fail during builds.
In general, only formatting actions are automatiicaly performed. These include auto-formatting with 'black', or sorting dependacies with 'isort'. 
Linting actions are left to the discretion of the user.

## Secret scanning with Nix

The Nix flake includes `ripsecrets` and `trufflehog`. Run both over the
repository with:

```sh
nix run
```

Entering the development shell with `nix develop` installs a Git
`pre-commit` hook that scans staged files with both tools. The hook is
installed only if a `pre-commit` hook does not already exist, so it will not
replace a hook installed by another tool. In that case, add
`scan-secrets --staged` to the existing hook (while inside `nix develop`) to
enable secret scanning.

`ripsecrets` respects `.secretsignore`. Trufflehog reports verified and
unknown results and makes scan errors fail the scan.
