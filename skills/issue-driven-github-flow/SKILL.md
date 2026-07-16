---
name: issue-driven-github-flow
description: >-
  Enforces an issue-driven GitHub Flow with multi-agent planning. Use this skill
  when the user wants to START or CARRY OUT development work in a git repository
  — implement a feature, fix a bug, make or change code, kick off a new project,
  or open/land a PR — including when they don't say "issue", "branch", or
  "gitflow" (e.g. "let's build X", "fix this bug", "add a feature", "start on
  Y", "get this project going"). It guarantees every change traces to a GitHub
  issue, gets a reviewed-and-approved plan before any code is written, lands on
  a `type/description` branch via a squash-merged PR with Conventional Commits,
  and never edits `main` directly. Do NOT trigger for purely informational or
  read-only requests that change nothing — e.g. "what's the git command for X",
  "explain this function", "show me the diff", "what branch am I on" — just
  answer those directly.
allowed-tools:
  - "Bash(git:*)"
  - "Bash(gh:*)"
  - "Bash(./gitflow.sh:*)"
  - "Bash(./skills/issue-driven-github-flow/scripts/gitflow.sh:*)"
compatibility:
  required-tools:
    - git
    - gh
  note: "Requires an authenticated GitHub CLI (`gh`) and a git repository with a GitHub remote."
license: MIT
metadata:
  author: andybaran
  version: "1.1"
---

# Issue-Driven GitHub Flow

This skill encodes a disciplined development workflow: **nothing gets coded
until a GitHub issue exists and a plan for it has been reviewed and approved.**
The goal is that every line of code is traceable to a tracked, planned, and
reviewed unit of work — which keeps `main` clean, history meaningful, and
review load low.

The workflow has two layers that always apply together:

1. **The gitflow** — how branches, commits, PRs, CI gates, and rollback are
   shaped (mechanical, fast).
2. **The orchestration** — how an issue becomes a reviewed plan, reviewed code,
   and then a human-approved merge using distinct agent roles.

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
- **Verification before completion.** Never claim "tests pass", "fixed", "done",
  "CI is green", or any equivalent success state unless you have just run the
  relevant check and can show the real output. No proof → not done. If a check
  cannot be run, report that fact instead of implying success.
- **Never commit secrets.** Do not commit API keys, tokens, passwords, private
  keys, `.env` files containing credentials, or generated secret material. Use
  environment variables, GitHub Actions Secrets, Dependabot/organization secrets,
  or an approved secret manager. Recommend secret-scanning push protection; see
  [security.md](references/security.md).

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

Also inspect repository governance before changing files:

```bash
# CODEOWNERS can live in any of these standard locations.
for f in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
  [ -f "$f" ] && echo "CODEOWNERS: $f"
done

# Detect default-branch protection without mutating settings.
default="$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name')"
if gh api "repos/{owner}/{repo}/branches/$default/protection" --silent >/dev/null 2>&1; then
  echo "default branch '$default' has branch protection"
else
  echo "default branch '$default' has no detected branch protection"
fi
```

Decide:

- **Not a git repo / no GitHub remote?** Tell the user what's missing and offer
  to `git init` / `gh repo create`. Don't fabricate a workflow on top of nothing.
- **CODEOWNERS found?** Warn that paths matching `CODEOWNERS` require code-owner
  review before merge. This repository's ownership file is
  [../../.github/CODEOWNERS](../../.github/CODEOWNERS) when present.
- **Default branch unprotected?** Document the risk and **offer** to apply
  sensible branch protection — PR review, required status checks, code-owner
  review when CODEOWNERS exists, and blocked force-push/deletion — but do not
  change settings without explicit user consent. Use
  [branch-protection.md](references/branch-protection.md) for the exact commands.
- **More than 3 open issues?** This work belongs in a **GitHub Project** (see
  "Projects" below) so the issues are tracked together, not scattered.

## Step 1 — Ensure an issue exists

If the user's request doesn't reference an existing issue, create one. The
issue **description must fully capture the task** — a future agent (or person)
should be able to act on it without re-reading the chat.

Pass the body on **stdin via a quoted heredoc** (`<<'EOF'`) rather than
`--body "..."`. The description is markdown — code fences, backticks, `$`,
quotes — and a quoted heredoc passes all of it through literally, where an
inline `--body "..."` lets the shell mangle it or end the string early.

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
[agent-prompts.md](references/agent-prompts.md) for the full role prompts to
hand each one.

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
   until the review agent posts `**Verdict: APPROVED**` or a hard stop below
   forces human escalation.

**Orchestrator loop bound:** the orchestrator owns enforcement, not the
subagents. Maintain a visible counter in the issue comments or dispatch notes
(`Plan-review round 1/3`, then `2/3`, then `3/3`). One round is one planning
comment plus the review verdict for it. The plan ↔ review loop is capped at
**max 3 rounds**; never start a fourth review round.

Stop early and escalate instead of burning remaining rounds when there is no
substantive progress. Compare the latest plan/review against the prior round:
if the reviewer repeats the same objection without new information, or the
planner's revision does not materially change the plan in response, treat the
loop as non-converged. This is a judgment about substantive change, not exact
text equality.

On cap hit or no-progress, STOP and post a concise issue comment prefixed, for
example, `## ⛔ Escalation: plan review did not converge`. Summarize the
unresolved disagreement, include the final round counter (`3/3` when capped),
and hand off to the human for a decision. Never silently loop, silently give up,
or begin implementation without an approved plan or explicit human direction.

Post comments by piping the body on **stdin via a quoted heredoc** — plans and
reviews are full of code fences, backticks, and `$`, and `--body "..."` would let
the shell expand or truncate them. The quoted `<<'EOF'` delimiter disables all
expansion, so the markdown lands exactly as written:

```bash
gh issue comment <number> --body-file - <<'EOF'
<the plan or review — markdown, code blocks, and $vars all literal>
EOF
```

Don't skip the loop even for "small" changes — the review agent approving a
one-line plan in a single round costs almost nothing, and the discipline is what
keeps the *big* changes honest. Keep the counter visible even when you expect a
single round.

## Step 3 — Implement

Only once the issue carries an approved plan. Use a **separate implementation
agent** (fresh context, told to follow the approved plan verbatim — see
[agent-prompts.md](references/agent-prompts.md)). The implementation agent owns
the mechanical gitflow, and the mechanical parts are scripted so they can't drift.

### Use the bundled helper

`scripts/gitflow.sh` encapsulates the fiddly, repeated steps — cutting a
correctly named branch, committing with a Conventional Commit, opening a draft
PR, marking it ready later, and packaging the diff for review. It validates its
inputs so mistakes fail fast instead of landing in history. Reach for it rather
than retyping raw `git`/`gh`:

```bash
SKILL=skills/issue-driven-github-flow

# Branch — syncs the default branch, then cuts type/N-desc off it.
"$SKILL/scripts/gitflow.sh" branch feat/42-add-csv-export

# ... make only the changes the approved plan describes, then write/run tests ...
git add -A

# Commit — Conventional message + "Closes #42." + Copilot co-author trailer.
"$SKILL/scripts/gitflow.sh" commit "feat(export): add CSV export for reports" 42

# PR — fetches origin, refuses if this branch is behind the default branch,
# pushes, and opens a DRAFT PR by default.
"$SKILL/scripts/gitflow.sh" pr "feat(export): add CSV export for reports" 42
```

Move the linked GitHub Project item to **In Progress** after the branch is cut;
use [projects.md](references/projects.md) for the ID-resolution recipe, and
no-op cleanly if no Project exists or Project auth is unavailable.

Pick `type` (∈ `feat|fix|chore|docs|refactor|test|perf`) to match the work and a
hyphenated description that reads cleanly. Prefer issue-numbered branch names:
`feat/42-oauth-login`, `fix/87-null-deref-on-empty-cart`,
`chore/105-bump-deps`. The helper still accepts legacy `type/description`, but
`type/N-desc` is the durable convention.

The helper's `pr` subcommand is intentionally conservative: it fetches the
remote default branch and stops if the work branch is behind it. Sync with rebase
or merge, resolve conflicts, re-run verification, and only then retry the PR.
It opens a **draft** PR; do not mark it ready until Step 3.5 is satisfied. To
supply a richer body, pass a project-local body file that you delete before
commit (for example `.gitflow-pr-body.md`) rather than writing under `/tmp`.

Before opening the PR, **run the tests** the plan called for and capture the real
output. The PR's test plan should describe a green automated check, not a promise.

## Step 3.5 — Code review

After implementation and local verification, dispatch the blocking **🔬
code-review agent** on the PR diff before marking the PR ready or merging. Use
[code-reviewer.md](references/code-reviewer.md) and the role in
[agent-prompts.md](references/agent-prompts.md) instead of recreating the prompt.

Suggested review package flow:

```bash
base="$(git merge-base HEAD origin/$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'))"
head="$(git rev-parse HEAD)"
skills/issue-driven-github-flow/scripts/gitflow.sh review-package "$base" "$head" .gitflow-review-package.txt
```

`.gitflow-review-package.txt` is scratch review material, not source. Delete it
before any later `git add -A` / commit in the re-review loop, or choose an
explicit output path outside the working tree when your environment provides one.

The code-review agent posts a PR review with `**Verdict: APPROVED**` or
`**Verdict: CHANGES REQUESTED**`.

- **Critical** or **Important** findings are blocking. They loop back to the
  implementation agent for the smallest safe fix, followed by the relevant
  verification and another code-review pass.
- **Minor** findings are non-blocking unless the human decides otherwise.
- The implementer uses [receiving-code-review.md](references/receiving-code-review.md)
  to triage feedback rigorously rather than blindly applying suggestions.
- The orchestrator tracks the code-review ↔ implement loop with a visible
  counter (`Code-review fix round 1/3`, `2/3`, `3/3`). One round is one
  code-review verdict plus the implementer's response/fix attempt. The loop is
  capped at **max 3 rounds**; never request a fourth code-review pass for the
  same unresolved Critical/Important findings.
- If the implementation agent reports `BLOCKED` or `NEEDS_CONTEXT`, stop
  immediately and escalate to the human instead of using another round.
- If a round produces no substantive progress, stop early and escalate. Compare
  the latest diff, implementer status, and review against the prior round: an
  implementer making no material edit, or a reviewer repeating the same blocking
  objection against an unchanged diff, is non-convergence. This is substantive
  comparison, not exact text equality.
- On cap hit, `BLOCKED`, `NEEDS_CONTEXT`, or no-progress, STOP and post a
  concise PR comment prefixed, for example, `## ⛔ Escalation: code review did
  not converge`. Summarize unresolved Critical/Important findings or the missing
  context, include the final round counter when applicable, and hand off to the
  human. Do not mark the PR ready until the human resolves or explicitly waives
  the blockers.
- The human gives final merge approval. An agent may prepare the PR, but it does
  not override human approval.

Only after no Critical or Important findings remain — or the human explicitly
waives them on the PR — may the PR be marked ready:

```bash
skills/issue-driven-github-flow/scripts/gitflow.sh ready
```

## Step 4 — Land and clean up

Before squash-merge, require evidence that the PR is safe to land:

1. The PR template checklist is complete; see
   [../../.github/pull_request_template.md](../../.github/pull_request_template.md).
2. The code-review agent has an approving verdict or every blocking finding has
   an explicit human waiver.
3. If the repository has CI, the checks are green. This repository's CI workflow
   is [../../.github/workflows/ci.yml](../../.github/workflows/ci.yml); check names
   are repo-specific, so use `gh pr checks` to read the actual current contexts.

```bash
gh pr checks --watch
# Only after green checks and human approval:
gh pr merge --squash --delete-branch
```

Move the linked GitHub Project item to **Done** after the squash merge; use
[projects.md](references/projects.md) for the ID-resolution recipe, and no-op
cleanly if no Project exists or Project auth is unavailable.

After merge, sync the default branch and confirm the linked issue closed (the
`Closes #N` footer does this automatically on merge). If it didn't, close it with
a comment pointing at the merged PR.

```bash
git switch main && git pull --ff-only
```

Rollback is by revert, not force-push. If the squash commit must be undone, cut a
new branch, run `git revert <squash-sha>`, verify, and open a revert PR for
review. Never force-push or rewrite `main` to roll back a landed PR.

## Parallel execution with worktrees

When multiple approved issues can proceed independently, use separate git
worktrees so each issue has its own branch, working tree, verification output,
and PR. Follow [worktrees.md](references/worktrees.md): run baseline tests on the
clean branch first, ensure project-local worktree directories are gitignored, and
only clean up worktrees that this skill created.

## Definition of done

A change is done only when all of these are true:

- The issue exists and the implementation traces to it.
- The plan-review loop ended with `**Verdict: APPROVED**`.
- Local verification was run and real output is available.
- A draft PR exists with a Conventional Commit title and `Closes #N`.
- The 🔬 code-review step produced an approving verdict, or all Critical /
  Important findings were fixed or explicitly waived by the human.
- CI is green when the repository has CI (`gh pr checks`).
- The [PR template checklist](../../.github/pull_request_template.md) is complete,
  including code review, tests/CI, no secrets, and squash-merge intent.
- The human has approved merge.

## Projects (when >3 open issues)

Scattered issues lose their shared thread. When open issues exceed 3, group the
work under a GitHub Project so status is visible at a glance:

```bash
# Create once, then add issues to it
gh project create --owner "@me" --title "<workstream name>"
gh project item-add <project-number> --owner "@me" --url <issue-url>
```

Tell the user the project URL. New issues in this workstream get added to the
project as they're created. See [projects.md](references/projects.md) for moving
items across status columns and linking the project to the repo.

## Quick reference

| Situation | Do this |
|---|---|
| On `main`, asked to edit | Auto-create `type/N-desc` branch, then proceed |
| Request with no issue | `gh issue create` with full task body first |
| CODEOWNERS exists | Warn that owned paths require code-owner review |
| Default branch unprotected | Offer branch protection from [branch-protection.md](references/branch-protection.md); require consent before mutation |
| >3 open issues | Create/append to a GitHub Project |
| Multiple independent issues | Use worktrees via [worktrees.md](references/worktrees.md) |
| Plan written | Hand to review agent; track visible `Plan-review round N/3`; stop after max 3 rounds or no-progress and escalate to the human |
| Approved plan | Dispatch implementation agent |
| Step 3 branch cut | Move Project item to **In Progress** via [projects.md](references/projects.md); no-op cleanly if no Project exists or Project auth is unavailable |
| Code done | Run verification, commit, open a draft PR |
| Draft PR open | Dispatch 🔬 code-review agent; require a verdict |
| Implementer reports `BLOCKED` / `NEEDS_CONTEXT` | Stop the loop immediately; post the blocker/context gap and hand off to the human |
| Critical/Important review finding | Loop back to implementation with visible `Code-review fix round N/3`; re-verify and re-review, but stop after max 3 rounds or no-progress and escalate |
| PR ready to land | Require human approval and green `gh pr checks` when CI exists |
| PR squash-merged | Move Project item to **Done** via [projects.md](references/projects.md); no-op cleanly if no Project exists or Project auth is unavailable |
| PR merged | `--delete-branch`, sync `main`, confirm issue closed |
| Bad squash merge | `git revert <squash-sha>` on a new branch; open a revert PR |
| Secret requested | Refuse to commit it; use [security.md](references/security.md) |

The detailed role prompts for the agents live in
[agent-prompts.md](references/agent-prompts.md) — read it before dispatching
them. The mechanical git/gh steps are bundled in
[scripts/gitflow.sh](scripts/gitflow.sh) (`branch`, `commit`, `pr`, `ready`,
`review-package`); the implementation agent should use it rather than retyping
raw commands.
