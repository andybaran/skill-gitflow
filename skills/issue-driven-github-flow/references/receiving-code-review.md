# Receiving code review

Use this guidance when the implementation agent receives code-review feedback.
The goal is to evaluate review comments rigorously, not to blindly implement
whatever was suggested. See [agent-prompts.md](agent-prompts.md) for the
blocking review loop and [code-reviewer.md](code-reviewer.md) for the reviewer
prompt shape.

## Triage each comment

1. Re-read the issue, approved plan, and reviewed diff before changing code.
2. Classify the comment:
   - **Critical / Important:** treat as blocking unless clearly incorrect or
     explicitly waived by the human.
   - **Minor:** fix if low-risk and in-scope; otherwise acknowledge as a
     follow-up.
3. Apply a YAGNI check: does the requested change satisfy the approved plan or
   prevent a concrete defect, or is it speculative future-proofing?

## When to push back

Push back when the suggestion conflicts with the issue, approved plan, existing
project conventions, or verified behavior. Reply with technical reasoning, not
preference:

- cite the relevant issue/plan requirement;
- reference code paths, tests, or command output;
- explain the trade-off and the smaller safe alternative, if any;
- ask the human to waive or decide only when the disagreement affects a
  Critical or Important blocking finding.

## Replying and re-requesting review

- Keep discussion on the PR thread so the decision trail is durable.
- For accepted feedback, make the smallest change that resolves the finding and
  re-run the relevant verification.
- Reply to each blocking thread with what changed and the verification result.
- If a finding is intentionally not changed, reply with the rationale and wait
  for reviewer agreement or explicit human waiver.
- After all Critical and Important findings are resolved or waived, push the
  updates and re-request review. Do not mark ready or merge yourself unless the
  human explicitly approves.
