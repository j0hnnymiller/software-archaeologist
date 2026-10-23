---
name: verify-poc
description: "Verify the Software Archaeologist proof of concept. Use when asked to verify the POC, rerun feasibility checks, test codebase-analyst discovery, check citations and repeatability, or validate missing-submodule and read-only behavior with Copilot CLI."
ai_generated: true
model: "unknown/unknown@unknown"
operator: "johnmillerATcodemag-com"
chat_id: "f80ec142-dec0-4aa2-901c-89f1e9a26b16"
prompt: |
  create a skill that automates the verification of the proof of concept
started: "2026-10-23T22:16:19Z"
ended: "2026-10-23T22:24:24Z"
task_durations:
  - task: "Skill authoring and automated verification"
    duration: "00:08:05"
total_duration: "00:08:05"
ai_log: "ai-logs/2026/10/23/f80ec142-dec0-4aa2-901c-89f1e9a26b16/conversation.md"
source: "User request; repository-local Copilot CLI verification confirmed; model identity unavailable"
---

# Verify the proof of concept

## Scope and prerequisites

Automate the CLI acceptance checks in [feasibility](../../../docs/feasibility.md).
This is not a VS Code Chat test, a build/test runner for the target, or proof of
semantic correctness or security isolation.

Use PowerShell 7 (`pwsh`), Git, and an authenticated Copilot CLI supporting
`--agent`, `--trust-folder`, `--available-tools`, and JSONL output (tested with
1.0.104-1). Git needs access to the configured submodule remote.
CLI runs use the operator's configured model and may consume paid requests.
Obtain authorization before sending target contents to the configured service.
Never install tools, authenticate, change permissions, or bypass failures silently.

## Procedure

1. Read the feasibility criteria and repository README. Confirm this is the
   top-level repository and that the operator may analyze the target.
2. Run the bundled [runner](./scripts/verify-poc.ps1) from the repository root:

   ```powershell
   pwsh -NoProfile -File .github\skills\verify-poc\scripts\verify-poc.ps1
   ```

   Default: three initialized-target runs and one uninitialized-target run.
   The script creates a unique evidence directory outside the repository and
   prints its path. To choose a parent directory or increase repeatability:

   ```powershell
   pwsh -NoProfile -File .github\skills\verify-poc\scripts\verify-poc.ps1 -Runs 5 -EvidenceParent C:\Temp\poc-evidence
   ```

   The runner tests committed `HEAD`, not uncommitted changes. It rejects
   uncommitted agent, evidence-rule, or submodule-configuration changes rather
   than silently testing stale customizations. Commit only with separate user
   authorization. It never changes or initializes the operator's target.
3. Inspect the generated `results.json`, reports, JSONL tool traces, stderr,
   and before/after snapshots. A nonzero exit means a failed check or blocked
   prerequisite, not success. Preserve failure evidence; do not weaken the
   checks or switch to unrestricted tools to obtain a pass.
4. Review **every** factual claim against its cited source in the retained
   initialized clone. Automation checks section shape, labels, existing cited
   files, successful file-read evidence, allowed tools, and unchanged files/Git
   state; it cannot determine whether a citation actually supports a claim.
   Review hypotheses and documented commands, especially any suggestion that
   a command passed. Compare facts and uncertainty quality across runs rather
   than requiring identical prose.
5. Report each acceptance criterion as pass, fail, blocked, or manual review
   pending, with evidence paths, CLI version, revision, and limitations.
   Automated success means **automated checks passed; manual review pending**.
   Do not call the whole POC verified until the claim review is complete.
   VS Code Chat discovery/invocation and unfamiliar-user onboarding remain
   manual checks; do not infer them from CLI success.
6. Keep evidence locally under the operator's retention policy. It includes
   source copies, reports, and potentially sensitive tool output. Do not commit,
   upload, or publish it. Disposable clones are retained for review; delete
   only the specific run directory after review and user authorization.

## Runner maintenance

Run the dependency-free regression checks after modifying the runner:

```powershell
pwsh -NoProfile -File .github\skills\verify-poc\scripts\test-verification.ps1
```

Then exercise the real CLI path. CLI event schemas and tool names can change;
unrecognized or missing evidence must fail explicitly, not fall back to a
passing result. Tool restrictions and disposable clones reduce accidental
changes; neither is a sandbox or a security boundary.
