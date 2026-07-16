---
name: issue-driven-gitflow
description: >-
  Enforces an issue-driven GitHub Flow with multi-agent planning. Use this skill
  when the user wants to START or CARRY OUT development work in a git repository
  — implement a feature, fix a bug, make or change code, kick off a new project,
  or open/land a PR — including when they don't say "issue", "branch", or
  "gitflow" (e.g. "let's build X", "fix this bug", "add a feature", "start on
  Y", "get this project going"). It guarantees every change traces to a GitHub
  issue, gets a reviewed-and-approved plan before any code is written, lands on
  a `type/description` branch via a squash-merged PR with Conventional Commits,
  and never edits `main` directly. Do NOT
  trigger for purely informational or read-only requests that change nothing —
  e.g. "what's the git command for X", "explain this function", "show me the
  diff", "what branch am I on" — just answer those directly.
license: MIT
metadata:
  author: andybaran
  version: "1.0"
---

# Issue-Driven GitHub Flow

This skill encodes a disciplined development workflow: **nothing gets coded
until a GitHub issue exists and a plan for it has been reviewed and approved.**
The goal is that every line of code is traceable to a tracked, planned, and
reviewed unit of work — which keeps `main` clean, history meaningful, and
review load low.

The workflow has two layers that always apply together:

1. **The gitflow** — how branches, commits, and PRs are shaped (mechanical, fast).
2. **The orchestration** — how an issue becomes a reviewed plan and then code,
   using three distinct agent roles (the part that prevents half-baked work).

## The non-negotiables (and why)

These few rules are what make the workflow trustworthy. Everything else is
mechanism in service of them.

- **`main` is never edited directly.** If you're on `main` and the user asks for
  a code change, silently create the correct branch first (see below) and tell
  them you did. Editing `main` defeats PR review and makes rollbacks painful.
- **Every change starts from a GitHub issue.** The issue is the source of truth
  for *what* and *why*; the code is just the *how*. No issue → make one before
  touching code.
- **No code before an approved plan.** A planning agent proposes, a review agent
  critiques, and only an explicit approval unblocks implementation. This catches
  design mistakes while they're still cheap (a comment) instead of expensive (a
  diff). The loop is worth running even for small changes — a sound one-line plan
  gets approved in a single round, and the discipline is what keeps the big
  changes honest.
- **Automated verification is the goal.** A change you can't prove with a test is
  a change you're trusting on faith — and squash-and-merge means there's no easy
  unwind. So a plan's test strategy should be *automated*. If you discover the
  repo has no test harness at all, don't quietly settle for "manual verification"
  — **stop and ask the user** whether they'd like a test harness set up first.
  That's a real decision with cost, and it's theirs to make.

**When NOT to use this:** purely informational or read-only requests — "what's
the git command to list branches", "explain this code", "what changed in this
diff". Those change nothing in the repo; just answer them. The workflow below is
for requests that actually create or modify code.

## Step 0 — Orient

Before anything, find out where you are. Run these and read the result:

```bash
git rev-parse --is-inside-work-tree 2>/dev/null   # are we even in a repo?
git branch --show-current                          # what branch?
gh repo view --json nameWithOwner,defaultBranchRef -q '.nameWithOwner, .defaultBranchRef.name'
gh issue list --state open --json number --jq 'length'   # how many open issues?
```

Decide:
- **Not a git repo / no GitHub remote?** Tell the user what's missing and offer
  to `git init` / `gh repo create`. Don't fabricate a workflow on top of nothing.
- **More than 3 open issues?** This work belongs in a **GitHub Project** (see
  "Projects" below) so the issues are tracked together, not scattered.

## Step 1 — Ensure an issue exists

If the user's request doesn't reference an existing issue, create one. The
issue **description must fully capture the task** — a future agent (or person)
should be able to act on it without re-reading the chat.

Pass the body on **stdin via a quoted heredoc** (`<<'EOF'`) rather than `--body "..."`. The
description is markdown — code fences, backticks, `$`, quotes — and a quoted heredoc passes all of it
through literally, where an inline `--body "..."` lets the shell mangle it or end the string early.

```bash
gh issue create --title "<concise imperative title>" --body-file - <<'EOF'
<full task description: context, goal, acceptance criteria>
EOF
```

If the user pointed at an existing issue (e.g. "work on #42"), read it first
with `gh issue view 42 --comments` so you inherit the full context and any prior
discussion.

## Step 2 — Plan → Review → Approve (the agent loop)

This is the heart of the workflow. Three roles, kept deliberately separate so
the reviewer brings genuinely fresh eyes rather than defending the author's
choices. Dispatch each as its own subagent — see
`references/agent-prompts.md` for the full role prompts to hand each one.

The loop, all conducted **in the issue's comments** (so the reasoning is durable
and visible, not trapped in a chat):

1. **Planning agent** reads the issue and posts a comment containing a concrete
   plan: files to touch, approach, risks, and an **automated test strategy**.
   Prefix the comment so the role is legible, e.g. `## 🗺️ Plan (planning agent)`.
   If the repo has no test harness to hang an automated test on, the plan should
   say so and flag that the user needs to decide whether to add one (see the
   "Automated verification" non-negotiable) rather than defaulting to manual checks.
2. **Review agent** reads the issue + the plan and posts a critique:
   what's underspecified, what could break, what's missing. Prefix
   `## 🔍 Review (review agent)`. It ends with an explicit verdict line:
   `**Verdict: APPROVED**` or `**Verdict: CHANGES REQUESTED**`.
3. If changes are requested, the planning agent revises in a new comment. Repeat
   until the review agent posts `**Verdict: APPROVED**`.

Post comments by piping the body on **stdin via a quoted heredoc** — plans and reviews are full of
code fences, backticks, and `$`, and `--body "..."` would let the shell expand or truncate them. The
quoted `<<'EOF'` delimiter disables all expansion, so the markdown lands exactly as written:

```bash
gh issue comment <number> --body-file - <<'EOF'
<the plan or review — markdown, code blocks, and $vars all literal>
EOF
```

Don't skip the loop even for "small" changes — the review agent approving a
one-line plan in a single round costs almost nothing, and the discipline is what
keeps the *big* changes honest. Cap it at ~3 rounds; if they can't converge,
stop and bring the disagreement to the user.

## Step 3 — Implement

Only once the issue carries an approved plan. Use a **separate implementation
agent** (fresh context, told to follow the approved plan verbatim — see
`references/agent-prompts.md`). The implementation agent owns the mechanical
gitflow, and the mechanical parts are scripted so they can't drift.

### Use the bundled helper

`scripts/gitflow.sh` encapsulates the three fiddly, repeated steps — cutting a
correctly-named branch off an up-to-date default branch, committing with a
Conventional Commit, and opening a squash-ready PR. It validates its inputs
(rejects a malformed branch name or a non-Conventional commit) so mistakes fail fast
instead of landing in history. Reach for it rather than retyping raw `git`/`gh`:

```bash
SKILL=path/to/issue-driven-gitflow        # this skill's directory

# 1. Branch — syncs the default branch, then cuts type/description off it
"$SKILL/scripts/gitflow.sh" branch feat/add-csv-export

# ... make the changes the approved plan describes, then write/run the tests ...
git add -A

# 2. Commit — Conventional message + "Closes #42."
"$SKILL/scripts/gitflow.sh" commit "feat(export): add CSV export for reports" 42

# 3. PR — pushes and opens a squash-ready PR (title is the squash commit)
"$SKILL/scripts/gitflow.sh" pr "feat(export): add CSV export for reports" 42
```

Pick `type` (∈ `feat|fix|chore|docs|refactor|test|perf`) to match the work and a
hyphenated description that reads cleanly: `feat/oauth-login`,
`fix/null-deref-on-empty-cart`, `chore/bump-deps`. To supply a richer PR body,
pass a file: `gitflow.sh pr "<title>" 42 /tmp/pr-body.md`.

Before opening the PR, **run the tests** the plan called for and confirm they
pass — the PR's test plan should describe a green automated check, not a promise.

## Step 4 — Land and clean up

Squash-merge, then leave the repo tidy and ready for the next issue:

```bash
gh pr merge --squash --delete-branch
git switch main && git pull --ff-only
```

Confirm the linked issue closed (the `Closes #N` does this automatically on
merge). If it didn't, close it with a comment pointing at the merged PR.

## Projects (when >3 open issues)

Scattered issues lose their shared thread. When open issues exceed 3, group the
work under a GitHub Project so status is visible at a glance:

```bash
# Create once, then add issues to it
gh project create --owner "@me" --title "<workstream name>"
gh project item-add <project-number> --owner "@me" --url <issue-url>
```

Tell the user the project URL. New issues in this workstream get added to the
project as they're created. See `references/projects.md` for moving items across
status columns and linking the project to the repo.

## Quick reference

| Situation | Do this |
|---|---|
| On `main`, asked to edit | Auto-create `type/description` branch, then proceed |
| Request with no issue | `gh issue create` with full task body first |
| >3 open issues | Create/append to a GitHub Project |
| Plan written | Hand to review agent; iterate until `Verdict: APPROVED` |
| Approved plan | Dispatch implementation agent |
| Code done | Conventional commit → squash-merge PR |
| PR merged | `--delete-branch`, sync `main` |

The detailed role prompts for the three agents live in
`references/agent-prompts.md` — read it before dispatching them. The mechanical
git/gh steps are bundled in `scripts/gitflow.sh` (branch / commit / pr); the
implementation agent should use it rather than retyping raw commands.
