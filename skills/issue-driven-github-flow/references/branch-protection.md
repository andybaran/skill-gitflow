# Branch protection: document and offer

Branch protection is a repository policy change. The skill may detect missing
protection and recommend settings, but it must not mutate branch protection until
the user explicitly consents.

## Recommended settings

For the default branch:

- require pull requests before merging;
- require at least one approving review;
- require code-owner review when a `CODEOWNERS` file exists;
- dismiss stale approvals when new commits are pushed;
- require status checks to pass before merge;
- require branches to be up to date before merge (`strict` checks);
- block force pushes and branch deletion;
- keep rollback via revert PRs, not history rewrites.

This repository's CI workflow is named `CI` and its job display name is
`Validate skill` (`.github/workflows/ci.yml`). Use the real check context from
the repository, not a hard-coded guess, because Actions check names can vary by
workflow, job name, matrix, and branch policy.

## Detect current protection

```bash
owner_repo=andybaran/skill-github-flow
default=$(gh repo view "$owner_repo" --json defaultBranchRef -q '.defaultBranchRef.name')

gh api "repos/$owner_repo/branches/$default/protection" --jq '{required_status_checks, required_pull_request_reviews, allow_force_pushes, allow_deletions}'
```

If this returns a 404, protection is not configured for that branch.

Ruleset visibility commands are read-only:

```bash
gh ruleset list --repo "$owner_repo"
gh ruleset check "$default" --repo "$owner_repo"
```

## Discover required check contexts

Prefer a real PR's check names:

```bash
gh pr checks <pr-number> --repo "$owner_repo"
```

Or inspect recent check runs for a commit SHA:

```bash
sha=$(git rev-parse HEAD)
gh api "repos/$owner_repo/commits/$sha/check-runs" --jq '.check_runs[].name'
```

For this repository, the expected required check context from the workflow is:

```text
Validate skill
```

## Offer before applying

Say what will change, show the command, and wait for an explicit yes. Example:

> The default branch has no protection. I can require PR review, code-owner
> review, the `Validate skill` status check, up-to-date branches, and block force
> pushes/deletions. Should I apply that protection now?

## Apply with consent: classic branch protection API

Only run after explicit consent. Replace `contexts` with the repository-specific
check contexts discovered above.

```bash
owner_repo=andybaran/skill-github-flow
default=$(gh repo view "$owner_repo" --json defaultBranchRef -q '.defaultBranchRef.name')

gh api --method PUT "repos/$owner_repo/branches/$default/protection" \
  --input - <<'JSON'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Validate skill"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

## Apply with consent: repository ruleset API

`gh ruleset` can list/view/check rulesets in this GitHub CLI version; creation is
performed through `gh api`. Only run after explicit consent.

```bash
owner_repo=andybaran/skill-github-flow

gh api --method POST "repos/$owner_repo/rulesets" \
  --input - <<'JSON'
{
  "name": "Protect main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request", "parameters": {
      "required_approving_review_count": 1,
      "dismiss_stale_reviews_on_push": true,
      "require_code_owner_review": true,
      "require_last_push_approval": false,
      "required_review_thread_resolution": true
    }},
    { "type": "required_status_checks", "parameters": {
      "strict_required_status_checks_policy": true,
      "required_status_checks": [
        { "context": "Validate skill", "integration_id": null }
      ]
    }}
  ]
}
JSON
```

After applying, verify with:

```bash
gh ruleset check "$default" --repo "$owner_repo"
gh api "repos/$owner_repo/branches/$default/protection" --jq '{required_status_checks, required_pull_request_reviews}'
```
