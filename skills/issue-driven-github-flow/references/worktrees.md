# Worktrees for parallel issue execution

Use git worktrees when two or more approved issues can be implemented in
parallel without sharing local state. Each issue gets its own branch, directory,
verification output, and PR.

## Safety rules

- **Only remove worktrees this skill created.** Keep a note in the issue or PR of
  the created path and branch. If provenance is unclear, leave the worktree alone.
- **Never run `git worktree remove` on a user's existing worktree.** A worktree
  not created by this workflow belongs to the user until they explicitly say
  otherwise.
- **Verify project-local worktree directories are ignored before use.** Use
  `.worktrees/` by default only if it is gitignored; otherwise ask before editing
  `.gitignore` or choose a user-approved external location.
- **Run baseline verification on the clean branch first.** If clean `main` fails,
  report the baseline failure before starting feature work so new failures are not
  blamed on the issue branch.

## Create a worktree

```bash
git switch main
git pull --ff-only
bash tests/run.sh   # or the repo's smallest baseline verification command

git check-ignore -q .worktrees || {
  echo ".worktrees is not ignored; get consent before using it or choose another location"
  exit 1
}

git worktree add .worktrees/7-skill-integration -b feat/7-skill-integration main
cd .worktrees/7-skill-integration
```

If the branch already exists, use that exact branch instead of creating another:

```bash
git worktree add .worktrees/7-skill-integration feat/7-skill-integration
```

## While working

- Keep one issue per worktree.
- Run the issue's local verification inside that worktree.
- Open one draft PR per issue.
- Do not share untracked scratch files across worktrees.

## Provenance-safe cleanup

Clean up only after the PR is merged or abandoned and only when the path is known
to have been created by this skill.

```bash
git worktree list
# Confirm the path and branch match the issue record before removing.
git worktree remove .worktrees/7-skill-integration
git worktree prune
```

If `git worktree list` shows a path you did not create, do not remove it. Ask the
owner to clean it up or leave it in place.
