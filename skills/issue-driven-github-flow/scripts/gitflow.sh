#!/usr/bin/env bash
# gitflow.sh — the repetitive, easy-to-get-wrong git/gh steps of the
# issue-driven GitHub Flow, in one place so every run doesn't reinvent them
# (and can't drift on branch naming or PR shape).
#
# Usage:
#   gitflow.sh branch <type>/<description>
#       Sync local default branch with origin, then cut a fresh branch off it.
#       Accepts <type>/<description> and prefers <type>/<issue-number>-<description>.
#
#   gitflow.sh commit "<type(scope): summary>" <issue-number>
#       Commit currently-staged changes with a Conventional Commit message, a
#       "Closes #<issue>." line, and a Copilot co-author trailer. Refuses a
#       message that isn't a Conventional Commit, or an empty stage.
#
#   gitflow.sh pr "<title>" <issue-number> [body-file]
#       Fetch origin, stop if the branch is behind the default branch, push the
#       current branch, and open a draft squash-ready PR that closes the issue.
#       Title should itself be a Conventional Commit (it becomes the squash
#       commit). Pass a body-file to supply your own PR body.
#
#   gitflow.sh ready
#       Mark the current branch's PR ready for review. CI should be green first.
#
#   gitflow.sh review-package <base> <head> [outfile]
#       Write commits, diff stat, and full diff for base..head to outfile.
#
set -euo pipefail

TYPES='feat|fix|chore|docs|refactor|test|perf'
DEFAULT_COAUTHOR='Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>'

die()      { echo "gitflow: $*" >&2; exit 1; }
need_repo(){ git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repo"; }

current_branch() {
  git symbolic-ref --quiet --short HEAD 2>/dev/null || die "not on a branch; checkout a branch and re-run"
}

default_branch() {
  default="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@' || true)"
  printf '%s\n' "${default:-main}"
}

fetch_default_branch() {
  default="$(default_branch)"
  git fetch origin "$default" >/dev/null 2>&1 || die "failed to fetch origin/$default; verify the remote/default branch"
  git show-ref --verify --quiet "refs/remotes/origin/$default" \
    || die "origin/$default not found after fetch; verify origin/HEAD or set the default branch"
  printf '%s\n' "$default"
}

validate_branch_name() {
  name="$1"
  [[ "$name" =~ ^($TYPES)/([0-9]+-)?[^[:space:]]+$ ]] \
    || die "branch must be <type>/<description> or <type>/<issue>-<description>, e.g. feat/42-add-login (got: $name)"
  git check-ref-format --branch "$name" >/dev/null 2>&1 \
    || die "branch is not a valid git ref name: $name"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  branch)
    name="${1:?usage: gitflow.sh branch <type>/<description>}"
    validate_branch_name "$name"
    need_repo
    default="$(default_branch)"
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
    coauthor="${GITFLOW_COAUTHOR-$DEFAULT_COAUTHOR}"
    git commit -m "$msg" -m "Closes #${issue}." -m "$coauthor"
    echo "gitflow: committed (Closes #${issue})"
    ;;

  pr)
    title="${1:?usage: gitflow.sh pr \"<title>\" <issue-number> [body-file]}"
    issue="${2:?missing issue number}"
    bodyfile="${3:-}"
    need_repo
    command -v gh >/dev/null || die "gh CLI not found"
    branch="$(current_branch)"
    default="$(fetch_default_branch)"
    git merge-base --is-ancestor "origin/$default" HEAD \
      || die "branch '$branch' is behind origin/$default; sync with rebase or merge, resolve conflicts, and re-run gitflow.sh pr"
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
    gh pr create --draft --title "$title" --body "$body"
    echo "gitflow: draft PR opened for '$title' (Closes #${issue})"
    ;;

  ready)
    need_repo
    command -v gh >/dev/null || die "gh CLI not found"
    branch="$(current_branch)"
    gh pr view "$branch" >/dev/null || die "no PR found for current branch '$branch'"
    gh pr ready "$branch"
    echo "gitflow: PR for '$branch' marked ready for review (ensure CI is green)"
    ;;

  review-package)
    base="${1:?usage: gitflow.sh review-package <base> <head> [outfile]}"
    head="${2:?missing head ref}"
    outfile="${3:-}"
    need_repo
    base_sha="$(git rev-parse --verify --quiet "${base}^{commit}")" || die "base ref not found: $base"
    head_sha="$(git rev-parse --verify --quiet "${head}^{commit}")" || die "head ref not found: $head"
    if [[ -z "$outfile" ]]; then
      repo_root="$(git rev-parse --show-toplevel)"
      outfile="$repo_root/.gitflow-review-package-$$.txt"
    fi
    {
      echo "# Review package"
      echo
      echo "Base: $base ($base_sha)"
      echo "Head: $head ($head_sha)"
      echo
      echo "## Commit list"
      git --no-pager log --oneline "$base_sha..$head_sha"
      echo
      echo "## Diff stat"
      git --no-pager diff --stat "$base_sha..$head_sha"
      echo
      echo "## Full diff"
      git --no-pager diff -U10 "$base_sha..$head_sha"
    } > "$outfile"
    echo "gitflow: review package written to $outfile"
    ;;

  *)
    die "unknown command '${cmd:-}' (expected: branch | commit | pr | ready | review-package)"
    ;;
esac
