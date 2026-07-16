#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/issue-driven-github-flow/scripts/gitflow.sh"
SCRATCH="$ROOT/.test-tmp/run-$$"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cleanup() {
  rm -rf "$SCRATCH"
  rmdir "$ROOT/.test-tmp" 2>/dev/null || true
}
trap cleanup EXIT

assert_contains() {
  file="$1"
  text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    echo "--- $file ---" >&2
    cat "$file" >&2
    fail "expected '$text' in $file"
  fi
}

expect_fail() {
  out="$1"
  shift
  if "$@" >"$out" 2>&1; then
    echo "--- unexpected success output ---" >&2
    cat "$out" >&2
    fail "expected command to fail: $*"
  fi
}

init_repo() {
  name="$1"
  repo="$SCRATCH/$name/repo"
  origin="$SCRATCH/$name/origin.git"
  mkdir -p "$(dirname "$repo")"
  git init --bare --initial-branch=main "$origin" >/dev/null
  git init --initial-branch=main "$repo" >/dev/null
  (
    cd "$repo"
    git config user.name "Test User"
    git config user.email "test@example.com"
    git config core.hooksPath /dev/null
    echo "initial" > file.txt
    git add file.txt
    git commit -m "chore: initial" >/dev/null
    git remote add origin "$origin"
    git push -u origin main >/dev/null 2>&1
    git remote set-head origin main >/dev/null
  )
  printf '%s\n' "$repo"
}

test_rejects_malformed_branch_name() {
  out="$SCRATCH/malformed-branch.out"
  expect_fail "$out" "$SCRIPT" branch "feature/nope"
  assert_contains "$out" "branch must be"

  repo="$(init_repo malformed-branch)"
  spaced_out="$SCRATCH/malformed-branch-space.out"
  (
    cd "$repo"
    expect_fail "$spaced_out" "$SCRIPT" branch "feat/bad name"
  )
  assert_contains "$spaced_out" "branch must be"
}

test_accepts_numbered_and_legacy_branch_names() {
  repo="$(init_repo branch-names)"
  (
    cd "$repo"
    "$SCRIPT" branch "feat/42-add-export" >/dev/null 2>&1
    current="$(git branch --show-current)"
    test "$current" = "feat/42-add-export" || fail "expected numbered branch, got $current"
    git switch main >/dev/null 2>&1
    "$SCRIPT" branch "fix/repair-login" >/dev/null 2>&1
    current="$(git branch --show-current)"
    test "$current" = "fix/repair-login" || fail "expected legacy branch, got $current"
  )
}

test_rejects_non_conventional_commit() {
  repo="$(init_repo non-conventional)"
  out="$SCRATCH/non-conventional.out"
  (
    cd "$repo"
    echo "change" >> file.txt
    git add file.txt
    expect_fail "$out" "$SCRIPT" commit "update file" 4
  )
  assert_contains "$out" "Conventional Commit"
}

test_rejects_empty_stage() {
  repo="$(init_repo empty-stage)"
  out="$SCRATCH/empty-stage.out"
  (
    cd "$repo"
    expect_fail "$out" "$SCRIPT" commit "fix: no changes" 4
  )
  assert_contains "$out" "nothing staged"
}

test_commit_message_contains_issue_and_coauthor() {
  repo="$(init_repo commit-message)"
  log="$SCRATCH/commit-message.log"
  (
    cd "$repo"
    echo "change" >> file.txt
    git add file.txt
    "$SCRIPT" commit "fix: record attribution" 4 >/dev/null
    git log -1 --pretty=%B > "$log"
  )
  assert_contains "$log" "Closes #4."
  assert_contains "$log" "Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
}

test_review_package_contains_stat_and_hunks() {
  repo="$(init_repo review-package)"
  outfile="$SCRATCH/review-package.txt"
  (
    cd "$repo"
    base="$(git rev-parse HEAD)"
    echo "review package change" >> file.txt
    git add file.txt
    git commit -m "feat: change file" >/dev/null
    head="$(git rev-parse HEAD)"
    "$SCRIPT" review-package "$base" "$head" "$outfile" >/dev/null
  )
  assert_contains "$outfile" "Commit list"
  assert_contains "$outfile" "file.txt |"
  assert_contains "$outfile" "@@"
  assert_contains "$outfile" "+review package change"
}

test_project_status_docs_are_wired_into_workflow() {
  skill_doc="$ROOT/skills/issue-driven-github-flow/SKILL.md"
  project_doc="$ROOT/skills/issue-driven-github-flow/references/projects.md"

  assert_contains "$project_doc" 'gh project view <project-number> --owner "@me" --format json'
  assert_contains "$project_doc" 'gh project field-list <project-number> --owner "@me" --format json'
  assert_contains "$project_doc" 'gh project item-list <project-number> --owner "@me" --limit 100 --format json'
  assert_contains "$project_doc" 'gh project item-edit'
  assert_contains "$project_doc" '--project-id <project-id>'
  assert_contains "$project_doc" '--single-select-option-id <option-id>'
  assert_contains "$project_doc" 'Move to **In Progress** when Step 3 cuts the implementation branch'
  assert_contains "$project_doc" 'Move to **Done** after Step 4 squash-merges the PR'
  assert_contains "$project_doc" 'If there is no linked Project, treat status updates as a clean no-op'

  assert_contains "$skill_doc" 'Move the linked GitHub Project item to **In Progress**'
  assert_contains "$skill_doc" 'Move the linked GitHub Project item to **Done**'
  assert_contains "$skill_doc" '| Step 3 branch cut | Move Project item to **In Progress** via [projects.md](references/projects.md); no-op cleanly if no Project exists or Project auth is unavailable |'
  assert_contains "$skill_doc" '| PR squash-merged | Move Project item to **Done** via [projects.md](references/projects.md); no-op cleanly if no Project exists or Project auth is unavailable |'
}

main() {
  rm -rf "$SCRATCH"
  mkdir -p "$SCRATCH"
  test -x "$SCRIPT" || fail "script is not executable: $SCRIPT"

  test_rejects_malformed_branch_name
  test_accepts_numbered_and_legacy_branch_names
  test_rejects_non_conventional_commit
  test_rejects_empty_stage
  test_commit_message_contains_issue_and_coauthor
  test_review_package_contains_stat_and_hunks
  test_project_status_docs_are_wired_into_workflow

  echo "All smoke tests passed"
}

main "$@"
