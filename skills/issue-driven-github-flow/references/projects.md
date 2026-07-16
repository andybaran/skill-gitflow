# GitHub Projects: grouping issues when work scales

When a repo has more than 3 open issues, scattered issues lose their shared
thread — it's hard to see what's in flight, blocked, or done. A GitHub Project
(the newer "Projects v2", board view) gives the workstream a single status
surface.

## Create a project (once per workstream)

```bash
gh project create --owner "@me" --title "<workstream name>"
# → returns a project number, e.g. 7, and a URL. Tell the user the URL.
```

For an org-owned repo, use `--owner <org>` instead of `@me`.

## Add issues to it

```bash
gh project item-add <project-number> --owner "@me" --url <issue-url>
```

Add every issue in the workstream — both pre-existing ones (which is why you
create the project the moment you cross the >3 threshold) and new ones as they're
filed.

## Move items across status columns

Status updates are required workflow bookkeeping when a Project exists, but they
must never block implementation or merge. If there is no linked Project, treat status updates as a clean no-op.
If `gh` is unavailable or the active token lacks the `project` scope, print the
problem, continue the workflow, and let the user refresh auth later with
`gh auth refresh -s project`.

Projects v2 status is a custom single-select field. To set it you need the
Project ID, the Status field ID, the option ID, and the Project item ID for the
issue. These IDs are dynamic, so resolve them every time rather than hard-coding
them:

```bash
PROJECT_NUMBER=<project-number>
ISSUE_NUMBER=<issue-number>
OWNER="@me" # for org-owned repos, use the org login instead

# Resolve the Project id.
gh project view <project-number> --owner "@me" --format json
PROJECT_ID="$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" --format json --jq '.id')"

# Resolve the Status field id and its option ids (Todo / In Progress / Done).
gh project field-list <project-number> --owner "@me" --format json
STATUS_FIELD_ID="$(
  gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json \
    --jq '.fields[] | select(.name == "Status") | .id'
)"
TODO_OPTION_ID="$(
  gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json \
    --jq '.fields[] | select(.name == "Status") | .options[] | select(.name == "Todo") | .id'
)"
IN_PROGRESS_OPTION_ID="$(
  gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json \
    --jq '.fields[] | select(.name == "Status") | .options[] | select(.name == "In Progress") | .id'
)"
DONE_OPTION_ID="$(
  gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" --format json \
    --jq '.fields[] | select(.name == "Status") | .options[] | select(.name == "Done") | .id'
)"

# Resolve the Project item id for this issue; map via .content.number.
gh project item-list <project-number> --owner "@me" --limit 100 --format json
ITEM_ID="$(
  gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 100 --format json \
    --jq ".items[] | select(.content.number == $ISSUE_NUMBER) | .id"
)"

# Set the status by choosing the desired option id.
# Command shape:
# gh project item-edit --id <item-id> --project-id <project-id> --field-id <status-field-id> --single-select-option-id <option-id>
OPTION_ID="$IN_PROGRESS_OPTION_ID" # or "$TODO_OPTION_ID" / "$DONE_OPTION_ID"
gh project item-edit \
  --id "$ITEM_ID" \
  --project-id "$PROJECT_ID" \
  --field-id "$STATUS_FIELD_ID" \
  --single-select-option-id "$OPTION_ID"
```

Use those commands for these transitions:

- Move to **In Progress** when Step 3 cuts the implementation branch.
- Move to **Done** after Step 4 squash-merges the PR.

This keeps the board honest without manual bookkeeping by the user.

## Linking the project to the repo

So the project shows up under the repo's Projects tab:

```bash
gh project link <project-number> --owner "@me" --repo <owner>/<repo>
```

## Keep it lightweight

The point of the project is *visibility*, not ceremony. Don't invent elaborate
custom fields or automation the user didn't ask for — Todo / In Progress / Done
plus the linked issues is plenty unless they want more.
