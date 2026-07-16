#!/usr/bin/env bash
# gitflow.sh — the repetitive, easy-to-get-wrong git/gh steps of the
# issue-driven GitHub Flow, in one place so every run doesn't reinvent them
# (and can't drift on branch naming or PR shape).
#
# Usage:
#   gitflow.sh branch <type>/<description>
#       Sync local default branch with origin, then cut a fresh branch off it.
#       Refuses names that aren't <type>/<description>.
#
#   gitflow.sh commit "<type(scope): summary>" <issue-number>
#       Commit currently-staged changes with a Conventional Commit message, a
#       "Closes #<issue>." line only. Refuses a
#       message that isn't a Conventional Commit, or an empty stage.
#
#   gitflow.sh pr "<title>" <issue-number> [body-file]
#       Push the current branch and open a squash-ready PR that closes the issue.
#       Title should itself be a Conventional Commit (it becomes the squash
#       commit). Pass a body-file to supply your own PR body.
#
set -euo pipefail

TYPES='feat|fix|chore|docs|refactor|test|perf'

die()      { echo "gitflow: $*" >&2; exit 1; }
need_repo(){ git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repo"; }

cmd="${1:-}"; shift || true
case "$cmd" in
  branch)
    name="${1:?usage: gitflow.sh branch <type>/<description>}"
    [[ "$name" =~ ^($TYPES)/.+ ]] \
      || die "branch must be <type>/<description>, e.g. feat/add-login (got: $name)"
    need_repo
    default="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
    default="${default:-main}"
    git switch "$default"
    git pull --ff-only
    git switch -c "$name"
    echo "gitflow: on new branch '$name' (off up-to-date '$default')"
    ;;

  commit)
    msg="${1:?usage: gitflow.sh commit \"<type(scope): summary>\" <issue-number>}"
    issue="${2:?missing issue number}"
    [[ "$msg" =~ ^($TYPES)(\(.+\))?!?:\  ]] \
      || die "message must be a Conventional Commit, e.g. 'feat(auth): add login' (got: $msg)"
    need_repo
    git diff --cached --quiet && die "nothing staged — 'git add' your changes first"
    git commit -m "$msg" -m "Closes #${issue}."
    echo "gitflow: committed (Closes #${issue})"
    ;;

  pr)
    title="${1:?usage: gitflow.sh pr \"<title>\" <issue-number> [body-file]}"
    issue="${2:?missing issue number}"
    bodyfile="${3:-}"
    need_repo
    command -v gh >/dev/null || die "gh CLI not found"
    git push -u origin HEAD
    if [[ -n "$bodyfile" && -f "$bodyfile" ]]; then
      body="$(cat "$bodyfile")"
    else
      body="## Summary
<what changed and why>

Closes #${issue}.

## Test plan
<how it was verified — prefer an automated test>
"
    fi
    gh pr create --title "$title" --body "$body"
    echo "gitflow: PR opened for '$title' (Closes #${issue})"
    ;;

  *)
    die "unknown command '${cmd:-}' (expected: branch | commit | pr)"
    ;;
esac
