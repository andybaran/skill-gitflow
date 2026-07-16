# issue-driven-gitflow

A reusable **agent skill** that enforces a
disciplined, **issue-driven GitHub Flow**: nothing gets coded until there's a
GitHub issue and a *reviewed, approved plan* for it. Every change lands on a
short-lived `type/description` branch via a squash-merged PR with Conventional
Commits — and `main` is never edited directly.

It's meant to be dropped into any project so the whole team gets the same
workflow automatically whenever they ask their coding agent to build, fix, or
ship code.

## What it does

When you ask your coding agent to do development work ("add a dark-mode
toggle", "fix the NaN on an empty cart", "let's start a new service"), the
skill drives this loop:

1. **Ensure an issue exists.** The GitHub issue is the source of truth for the
   task; its body holds the spec. No issue → one is created first.
2. **Plan → Review → Approve.** A *planning agent* comments a concrete plan on
   the issue; a separate *review agent* critiques it with fresh eyes; they
   iterate in the issue comments until the reviewer posts `Verdict: APPROVED`.
3. **Implement.** A separate *implementation agent* follows the approved plan,
   on a properly-named branch, with an automated test, landing as a PR.
4. **Land & clean up.** Squash-merge, delete the branch, sync `main`.

When a repo accumulates **more than 3 open issues**, the work is grouped under a
**GitHub Project** so status stays visible.

## The non-negotiables

- **`main` is never edited directly.** On `main` and asked to change code →
  the agent creates the right branch first.
- **Every change starts from a GitHub issue.**
- **No code before an approved plan** — the plan/review loop runs even for small
  changes (a sound one-line plan is approved in a single round).
- **Automated verification is preferred.** If a repo has no test harness, the
  agent stops and asks whether to set one up rather than silently falling back
  to manual checks.

For purely informational/read-only requests ("what's the git command for…",
"explain this function", "show me the diff"), the skill deliberately stays out
of the way and just answers.

## Works with

This skill is a single standard `SKILL.md` folder using the [Agent Skills open
standard](https://agentskills.io). It needs no per-tool conversion.

- **Claude Code** — `~/.claude/skills/<name>/` (personal) or
  `.claude/skills/<name>/` (project). Native.
- **GitHub Copilot** (CLI, VS Code, github.com) — scans `.github/skills/`,
  `.claude/skills/`, `.agents/skills/` (project) and `~/.copilot/skills/`,
  `~/.agents/skills/` (personal). Native.
- **Cursor** — `.cursor/skills/`, `.agents/skills/` (project) or
  `~/.cursor/skills/`, `~/.agents/skills/` (personal); also reads
  `.claude/skills/` for compatibility. Native.
- **IBM Bob** — `.bob/skills/<name>/` (project) or `~/.bob/skills/<name>/`
  (global). Same `SKILL.md` format; Bob only scans its own `.bob/skills/`
  path.

## Install

Use Vercel's official `vercel-labs/skills` package, invoked as `npx skills`:

```bash
# Install into the current project (auto-detects your agent):
npx skills add andybaran/skill-gitflow

# Install just this skill, or target a specific agent / scope:
npx skills add andybaran/skill-gitflow --skill issue-driven-gitflow
```

For IBM Bob, or any agent that only scans its own path, target it explicitly
(`npx skills add andybaran/skill-gitflow --agent bob`) or copy the folder into
`.bob/skills/`.

As a fallback, this is a plain folder skill: copy `issue-driven-gitflow/` into
any agent's skills directory, such as a personal `~/.claude/skills/` directory
or a project-level skills directory:

```bash
# From a packaged .skill (a zip), choose the directory your agent scans:
unzip issue-driven-gitflow.skill -d <agent-skills-dir>/

# Or copy the folder directly:
cp -r issue-driven-gitflow <agent-skills-dir>/
```

Then start or reload your agent session. The skill triggers automatically on
development requests based on its description — you don't invoke it by name.

## Requirements

- **`git`** and the **GitHub CLI (`gh`)**, authenticated: `gh auth login`.
- For the multi-agent planning loop, an agent that can dispatch subagents;
  without subagents, the agent plays the roles in sequence and still leaves the
  durable issue/PR trail.

## What's in here

| Path | Purpose |
|------|---------|
| `SKILL.md` | The workflow the agent follows (the skill itself). |
| `references/agent-prompts.md` | Role prompts for the planning / review / implementation agents. |
| `references/projects.md` | How and when to group issues under a GitHub Project. |
| `scripts/gitflow.sh` | Bundled helper for the mechanical git/gh steps. |

## The helper script

`scripts/gitflow.sh` encapsulates the three fiddly, repeated steps so branch
naming and PR shape can't drift. It validates its inputs (rejects a malformed
branch name or a non-Conventional commit):

```bash
# 1. Branch — syncs the default branch, then cuts type/description off it
scripts/gitflow.sh branch feat/add-csv-export

#    ...make changes, write & run the automated test, then: git add -A

# 2. Commit — Conventional message + "Closes #42."
scripts/gitflow.sh commit "feat(export): add CSV export for reports" 42

# 3. PR — pushes and opens a squash-ready PR (title becomes the squash commit)
scripts/gitflow.sh pr "feat(export): add CSV export for reports" 42
```

`type` ∈ `feat | fix | chore | docs | refactor | test | perf`.

## Customizing

The conventions are intentionally explicit in `SKILL.md` and `gitflow.sh` so you
can adapt them to a team's house style — branch `type`s, the PR body
template, and the >3-issues Project threshold are all easy to change in those
two files.
