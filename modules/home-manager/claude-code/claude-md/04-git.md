## Git

- **Commits**: always commit as the default git author. Never add `Co-Authored-By: Claude` (or any Claude attribution) lines or trailers.
- **Pull requests**: when asked to open a PR, create a new branch first unless told to use the current one. Stage and commit only the changes relevant to this conversation — if other files are modified or staged, ask before including them. Open the PR with the `gh` CLI. The PR body must not contain any Claude attribution either.
