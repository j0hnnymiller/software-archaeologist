---
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
source: "Existing README; verification skill documentation update; model identity unavailable"
---

# Software Archaeologist

This repository packages a read-only codebase overview agent and evidence
guidance for analyzing a separate codebase stored in a Git submodule.

## Concept

- This repository contains the analysis agent and instructions.
- A sub-repository contains the codebase being analyzed.
- An AI coding assistant uses the tooling and guidance from this repository to
  explore and explain the codebase in the sub-repository.

The overview covers a project's purpose, structure, entry points, dependencies,
runtime requirements, and documented build, test, and run commands. Findings
should cite target files and distinguish observations from hypotheses.

## Status

This is an exploratory project, not a production-ready analysis framework.
The workspace customization is designed for GitHub Copilot in VS Code and the
Copilot CLI. Other assistants may require different customization locations or
invocation steps; their behavior has not been verified here.

## Target repository

The [target](target/) directory is a Git submodule containing
[sa-test](https://github.com/j0hnnymiller/sa-test), the sample codebase to analyze.

Clone this repository with its target:

```powershell
git clone --recurse-submodules https://github.com/j0hnnymiller/software-archaeologist.git
```

For an existing clone, initialize the target with:

```powershell
git submodule update --init --recursive
```

## Run a codebase overview

Open the **top-level `software-archaeologist` folder** as your VS Code
workspace, not the `target/` submodule by itself. Confirm the target is
initialized:

```powershell
git submodule status --recursive
```

If the target is missing or the submodule status begins with `-`, run
`git submodule update --init --recursive` from the workspace root.

In GitHub Copilot Chat, select **codebase-analyst** from the agent picker and
ask for an overview of the target codebase. With GitHub Copilot CLI, run this
from the workspace root:

```powershell
copilot --agent codebase-analyst
```

Then ask for a repository overview. The agent has read and search tools only;
it should not execute commands or modify files. It reports documented commands
but does not run them. Review file citations against the target source before
relying on the findings. A clean Git status before and after analysis is a
useful check that the target was not changed.

The custom agent is in
[`.github/agents/codebase-analyst.agent.md`](.github/agents/codebase-analyst.agent.md)
and its evidence rules are in
[`.github/instructions/codebase-analysis.instructions.md`](.github/instructions/codebase-analysis.instructions.md).
Customization discovery has been exercised with Copilot CLI; VS Code Chat
discovery and invocation have not yet been independently verified.

## Verify the proof of concept

Use the repository-local [verify-poc skill](.github/skills/verify-poc/SKILL.md)
to rerun the CLI checks described in [feasibility](docs/feasibility.md).
Ask Copilot to "verify the POC", or run the bundled script directly:

```powershell
pwsh -NoProfile -File .github\skills\verify-poc\scripts\verify-poc.ps1
```

Requires PowerShell 7, Git, an authenticated Copilot CLI, access to the target
remote, and authorization to send target contents to the configured AI service.
The workflow uses the configured model and may consume paid requests.
It tests committed `HEAD` in disposable clones, not uncommitted customizations.
Three overview runs and an uninitialized-target run check discovery, report
structure, citation/read evidence, restricted tool use, and unchanged file/Git
state. Evidence and source copies remain in a unique directory outside this
working tree; the script prints its location and exits nonzero on failure.

Automated checks do not prove that claims are supported by their citations.
Review the retained reports against their source before accepting the POC.
VS Code Chat behavior and unfamiliar-user onboarding remain manual checks.
See the skill for evidence retention, runner tests, and CLI compatibility.
The [authoring and validation record](ai-logs/2026/10/23/f80ec142-dec0-4aa2-901c-89f1e9a26b16/summary.md)
documents the checks performed when adding this skill.
