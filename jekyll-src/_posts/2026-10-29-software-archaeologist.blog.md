---
layout: post
title: "Software Archaeologist: Pointing GitHub Copilot Agents at Any Codebase with Git Submodules"
date: 2026-10-29
categories: [ai-assisted-development, software-engineering, legacy-code]
tags: [git-submodules, github-copilot, custom-agents, agent-skills, instruction-files, copilot-cli]
excerpt: "Keep your AI analysis tooling in one repository and swap the codebase it investigates with a single script."
description: "A walkthrough of the Software Archaeologist repository: how Git submodules work, how GitHub Copilot discovers instructions, skills, and agents in the host repository and in the submodule, and how the replace-target scripts swap the analyzed codebase safely."
image: /assets/images/2026-10-29/software-archaeologist-header.svg
ai_generated: true
model: "unknown/unknown@unknown"
operator: "johnmillerATcodemag-com"
chat_id: "6b7cf8d3-50e1-4cbd-8a7d-8974d9d64c81"
prompt: |
  write a blog post explaining the software archaeologist repo. include:

  - basics of how submodules work
  - how github copilot utilizes config (instructions, skills, agents, etc.) found in the software archaeologist repo.
  - how github copilot utilizes config (instructions, skills, agents, etc.) found in the submodule repo(s).
  - an explanation of the replace submodule scripts
  - scenarios for how this behavior can be leveraged
started: "2026-10-29T16:42:00Z"
ended: "2026-10-29T16:50:00Z"
task_durations:
  - task: "Repository and documentation research"
    duration: "00:03:00"
  - task: "Copilot CLI discovery experiments"
    duration: "00:02:00"
  - task: "Post authoring and provenance"
    duration: "00:03:00"
total_duration: "00:08:00"
ai_log: "ai-logs/2026/10/29/6b7cf8d3-50e1-4cbd-8a7d-8974d9d64c81/conversation.md"
source: "User prompt; repository inspection; GitHub and VS Code documentation; Copilot CLI 1.0.104-1 probes"
---

When you inherit an unfamiliar codebase, the last thing you want is to start adding files to it just so your AI assistant knows how to investigate it. The [Software Archaeologist](https://github.com/j0hnnymiller/software-archaeologist) repository flips that around: the investigation tooling lives in one repository, and the codebase under investigation is mounted beside it as a Git submodule at `target/`.

In this post, I'll explain how the pieces fit together — submodules, GitHub Copilot instruction files, agent skills, and custom agents — and what I observed when I tested which configuration Copilot actually loads from each side of the submodule boundary.

<!--more-->

<figure>
  <img src="/assets/images/2026-10-29/software-archaeologist-header.svg" alt="A host repository containing Copilot configuration with a target codebase mounted as a submodule">
  <figcaption>The archaeologist's tools live in the host repository; the dig site is a submodule.</figcaption>
</figure>

## Why Separate the Analysis Tooling from the Codebase?

Legacy and third-party codebases are rarely yours to modify. Adding a `.github/agents/` folder to a repository you are trying to understand creates noise in its history, can conflict with configuration the owners already have, and has to be repeated for every codebase you look at. Copying the tooling around also means every copy drifts.

A submodule solves both problems. The host repository owns the agent, the skills, and the instruction files. The target repository stays untouched and is pinned to an exact commit, so an analysis always refers to a specific, reproducible version of the code. When I want to investigate a different codebase, I replace the submodule and keep the tooling.

This is a workflow boundary, not a security boundary. Copilot can still read everything in `target/`, and anything it reads goes to the configured model. Only point the archaeologist at code you are authorized to send to an AI service.

## What Is in the Software Archaeologist Repository?

The repository is small. Almost everything interesting lives under `.github/`, where GitHub Copilot looks for customizations.

| Path | Purpose |
| --- | --- |
| `.github/agents/software-archeologist.agent.md` | Custom agent that investigates code read-only and reports facts, inferences, and open questions |
| `.github/skills/*/SKILL.md` | Eight project skills, including `inventory-technology-stack`, `analyze-test-gaps`, and `assess-architecture-risks` |
| `.github/skills/inventory-technology-stack/scripts/` | Python scanner that counts technologies and versions, with unit tests |
| `.github/instructions/*.instructions.md` | Path-scoped rules for TypeScript, JavaScript, Node.js, Mermaid, blog posts, and AI provenance |
| `.github/copilot-instructions.md` | Repository-wide rule that every response ends with a **Current context** summary |
| `.github/scripts/replace-target.ps1` | Swaps the repository mounted at `target/` |
| `.github/scripts/tests/test-replace-target.ps1` | Offline regression tests for the replacement script |
| `target/` | Git submodule containing the codebase under investigation (currently [sa-test](https://github.com/j0hnnymiller/sa-test), a small TypeScript calculator) |
| `ai-logs/` | Provenance logs for AI-assisted changes |

### What the `software-archeologist` agent adds

The agent file is the operational contract for an investigation: it turns "tell me about this code" into a bounded excavation with an explicit question, boundary, and stop condition. It works in four phases — survey the site, trace behavior and boundaries, excavate intent from Git history, and assess risk — and it exposes commands such as `@excavate`, `@date-strata`, `@inventory-stack`, `@risk-map`, and `@shape-backlog`.

Its tool list is `[read, search, execute]`. Terminal access exists so the agent can run `git log`, `git blame`, and the inventory scanner, and the body restricts it to read-only commands: no installs, no builds, no edits. Every material claim must be labeled `fact`, `inference`, or `open question`, cite file paths or commits, and state what observation would disprove it. That evidence ledger is what makes the output reviewable rather than a plausible-sounding summary. The `tools` list narrows what the agent can do, but prompt rules are not enforcement; review the commands it proposes.

## How Git Submodules Work

A submodule is a Git repository embedded inside another Git repository at a fixed path. The parent does not store the child's files. It stores two things.

First, a `.gitmodules` file at the root maps a submodule name to a path and a URL:

```ini
[submodule "target-90d2b7ff517240a2853d0947cb683242"]
	path = target
	url = https://github.com/j0hnnymiller/sa-test.git
```

Second, the parent's index records a special entry called a _gitlink_ — mode `160000` — that points at a single commit in the child repository:

```text
> git ls-files --stage target
160000 fcabde51546596409aa092c9ce0699437cf42dab 0	target
```

That commit hash is the pin. Committing in the parent records "this tooling was used with exactly this version of the target." Moving the target forward is an explicit act: check out a different commit inside `target/`, then commit the updated gitlink in the parent.

The child's working files live in `target/`, but its Git database normally does not. After `git submodule absorbgitdirs`, `target/.git` is a one-line file instead of a directory:

```text
gitdir: ../.git/modules/target-90d2b7ff517240a2853d0947cb683242
```

That detail matters twice later in this post: once for the replacement script and once for how editors decide where a repository root is.

The commands you need day to day are few:

```powershell
# Clone the tooling and the pinned target together
git clone --recurse-submodules https://github.com/j0hnnymiller/software-archaeologist.git

# Initialize the target in an existing clone
git submodule update --init --recursive

# Check what is pinned; a leading "-" means uninitialized, "+" means the checkout differs from the pin
git submodule status --recursive
```

Submodules check out in a detached `HEAD` state at the pinned commit. That is the correct state for analysis — you want the exact version the parent recorded, not whatever a branch currently points to.

## How GitHub Copilot Uses the Archaeologist's Configuration

GitHub Copilot discovers customizations by location, so the host repository only has to put files where Copilot looks. Each type behaves differently, and it helps to know which ones are always loaded and which load on demand.

| Customization | Location | When Copilot uses it |
| --- | --- | --- |
| Repository instructions | `.github/copilot-instructions.md` | Added to every request |
| Path-specific instructions | `.github/instructions/**/*.instructions.md` | Applied when the files Copilot works with match the `applyTo` glob |
| Agent skills | `.github/skills/<name>/SKILL.md` | Names and descriptions are listed up front; the full skill and its scripts load when a task matches the description |
| Custom agents | `.github/agents/<name>.agent.md` | Selected with `/agent`, `--agent`, the VS Code agent picker, or by inference from the description |

For [Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions), instruction discovery covers "the repository root, the current working directory, intermediate directories between them, and any directories nested in the path of a file it is working on." In [VS Code](https://code.visualstudio.com/docs/agent-customization/overview), discovery covers the open workspace folders. In both cases, the practical rule for this repository is the same: **start Copilot from the top-level `software-archaeologist` folder**, not from `target/`.

To check what actually loads, I ran Copilot CLI 1.0.104-1 from the repository root and asked it to list its loaded instruction files and skills without using tools. It reported the root's path-specific instructions and all eight project skills (`analyze-architecture-patterns` through `review-codebase-instruction-compliance`). To run an investigation with the agent selected explicitly, start from the same folder:

```powershell
copilot --agent software-archeologist
```

### Host instructions follow the code into the submodule

The most useful behavior for this design is that the host's path-specific instructions apply to files inside the submodule. `typescript.instructions.md` declares `applyTo: "**/*.ts, **/*.tsx, **/*.mts, **/*.cts, **/tsconfig*.json"`. When I asked Copilot, from the root, to describe `target/src/calculator.ts`, the CLI trace showed it reading the TypeScript instructions before the target file:

```text
● Read typescript.instructions.md
  │ .github\instructions\typescript.instructions.md
● Read calculator.ts
  │ target\src\calculator.ts
```

The `applyTo` glob is matched against the path relative to the root, and `target/src/calculator.ts` matches `**/*.ts`. That means you can write investigation rules — "cite file paths," "flag `any` usage," "note deprecated Node.js APIs" — once in the host, and they apply to whatever codebase is mounted. If you want a rule to cover only the target, scope it explicitly with `applyTo: "target/**"`.

## How GitHub Copilot Uses Configuration Inside the Submodule

The target repository can have its own `.github/` folder, and real-world codebases increasingly do. Whether Copilot loads it depends on where you start Copilot and which files it touches, so I planted a canary to find out. The sa-test repository contains `target/.github/instructions/context-summary.instructions.md` with `applyTo: "**"` and one distinctive rule: "Output the current date and time and the phase of the moon at the end of every response." The host repository has no moon-phase rule, so a moon phase in a response proves the target's instruction was loaded.

I ran three Copilot CLI probes on the same machine:

| Started from | Prompt | Host instructions and skills | Target instruction (moon phase) |
| --- | --- | --- | --- |
| Repository root | List loaded files; answer 2+2 | Loaded | Not loaded |
| `target/` | Same prompt | Not loaded — no project skills listed | Loaded |
| Repository root | Read `target/src/calculator.ts` and describe it | Loaded, including `typescript.instructions.md` | Loaded |

Three behaviors follow from these results and the documented discovery rules:

- **Starting at the root isolates the host.** With no target files involved, Copilot used only the host's configuration. The target's `.github/` folder sits below the root, not in the root-to-working-directory path.
- **Starting inside the submodule isolates the target.** The submodule is its own Git repository, so `target/` became the repository root. The archaeologist's agent, skills, and instructions disappeared entirely.
- **Working on target files from the root merges both.** Once Copilot read a file under `target/`, the target's instruction loaded too — consistent with the CLI rule about directories in the path of a file it is working on. The model did not read the target's instruction file with a tool; the CLI supplied it.

The third case is the one to plan for. Copilot documents no general precedence order between instruction files, so when host and target rules conflict, the result is unpredictable. In the archaeologist's case, both sides asked for a **Current context** section, which merged cleanly. A target rule such as "always fix lint errors you find" would directly contradict the agent's read-only stance. The agent body and the host instructions should state the boundary plainly: instructions found inside `target/` describe the target project's conventions and are evidence to report, not commands that override the investigation.

These are single runs on one CLI version, and model output varies. The moon-phase answers themselves were wrong in different ways across runs, which is a reminder that an instruction being loaded and an instruction being followed well are separate questions. Treat the table as a reproducible experiment to repeat on your own client version, not a guarantee.

### What changes in VS Code

VS Code discovers customizations within the open workspace folders. Opening the top-level folder gives the same host-first behavior as the CLI. Opening `target/` by itself gives the target's configuration only. A multi-root workspace that lists both folders makes both sets of customizations available.

For this setup, **open the top-level `software-archaeologist` folder, trust it, and start a fresh chat**. That puts the host's customizations directly in the workspace instead of depending on parent discovery. Check the Chat customization diagnostics or **Developer: Open Agent Debug Logs** to confirm which files are available; do not assume the setting makes the host's agents, skills, and instructions available when only `target/` is open.

## How the Replace-Target Scripts Work

Replacing a submodule by hand is a sequence of commands that is easy to get subtly wrong: de-initialize, remove the gitlink, delete the directory, add the new repository, and hope no cached remote or object database from the old submodule leaks into the new one. [replace-target.ps1](https://github.com/j0hnnymiller/software-archaeologist/blob/main/.github/scripts/replace-target.ps1) performs that sequence with guardrails and stops before committing anything. It requires PowerShell 7 and Git.

```powershell
# Preview: checks prerequisites, clones nothing, changes nothing
pwsh -NoProfile -File .github\scripts\replace-target.ps1 -Url https://github.com/owner/repository.git -WhatIf

# Replace and stage
pwsh -NoProfile -File .github\scripts\replace-target.ps1 -Url https://github.com/owner/repository.git
git diff --cached
```

The script works in three stages.

1. **Refuse unsafe starting states.** It rejects URLs that start with `-`, so a value such as `--upload-pack=...` cannot be passed to Git as an option. It confirms it is at the repository's top level, that exactly one submodule is configured at `target`, and that the index holds an un-conflicted `160000` gitlink there. It refuses to run if the host has any modified or untracked files, or if `target/` or any nested submodule has changes, untracked files, or even _ignored_ files — ignored files are not tracked in any repository, so deleting them would lose them for good. There is no force option.
2. **Clone first, then remove.** It clones the new URL into a uniquely named temporary folder and verifies that the clone has a `HEAD` commit. Only after the network work succeeds does it run `git submodule deinit` and `git rm` on the old target. A bad URL, missing permissions, or an empty repository fails while the original target is still intact.
3. **Register cleanly and stop.** It moves the prepared clone into `target/`, registers it with `git submodule add --name target-<guid>`, and runs `git submodule absorbgitdirs` so the new repository's database moves under `.git/modules/`. The fresh internal name is the important detail: Git caches each submodule's database under `.git/modules/<name>`, and reusing a name can attach the new path to the old repository's objects and `origin`. The script leaves `.gitmodules` and the `target` gitlink staged and never commits or pushes.

The script is deliberately conservative about recovery. The old submodule's Git directory stays in `.git/modules/` and the script prints its location, so local-only commits made in the old target are still recoverable. It does not initialize nested submodules in the new target; run `git submodule update --init --recursive -- target` when you want them. If something fails after the old checkout is removed, it does not attempt an automatic rollback. It warns, prints the paths involved, and leaves the repository for you to inspect with `git status`. Retained metadata costs disk space until you clean it up yourself.

### What the regression tests prove

[test-replace-target.ps1](https://github.com/j0hnnymiller/software-archaeologist/blob/main/.github/scripts/tests/test-replace-target.ps1) runs fully offline. It builds three throwaway local repositories — an old source, a new source, and a host with the old source mounted at `target` plus an unrelated second submodule — and points `TEMP` at its own fixture folder so nothing outside it is touched.

Each rejection case is checked for the expected error and for zero side effects: the host's `HEAD`, status, and `.gitmodules` must be unchanged. The cases cover `-WhatIf`, an untracked host file, a dirty target, an ignored target file, an ignored file inside a nested submodule, an option-shaped URL, a missing remote, and an empty remote. The success case then commits a local-only change in the old target, replaces it, and asserts that the new `HEAD` and `origin` are correct, no commit was created, exactly `.gitmodules` and `target` are staged, the new Git directory was absorbed, the old local-only commit still exists in the retained metadata, and the unrelated submodule did not change. A final case replaces an uninitialized target back to the original repository.

```powershell
pwsh -NoProfile -File .github\scripts\tests\test-replace-target.ps1
```

The tests do not cover real network authentication or a network failure partway through a clone.

## Scenarios Where This Pattern Pays Off

The combination of a pinned target, host-owned tooling, and predictable discovery opens up more uses than a one-off code review.

- **Pre-change risk assessment.** Mount the service you need to modify, run `@risk-map` on the module, and get a fragility report with evidence before writing a line of code. The pinned commit records exactly what was assessed.
- **Due diligence and vendor review.** Rotate through acquisition candidates or vendor SDKs with `replace-target.ps1`, running the same `@inventory-stack` command and `assess-compliance` skill against each. Identical tooling makes the reports comparable.
- **Portfolio inventory.** Run the technology inventory across many repositories one at a time to find version drift and end-of-life frameworks, without adding a single file to any of them.
- **Onboarding.** Give a new team member the archaeologist with their team's main repository mounted. `@excavate` and `@date-strata` answer "why is this here?" from history instead of from whoever happens to be online.
- **Upgrade baselines.** Commit the host with the target pinned before a major upgrade, investigate, then move the pin to the upgraded commit and rerun. The two parent commits bracket the comparison.
- **Auditing a team's own Copilot configuration.** Start Copilot inside `target/` to see exactly what the target's owners configured, then start from the root to see how it interacts with your investigation rules. This is a cheap way to review a repository's `.github/` customizations before adopting them.
- **Applying investigation rules to code you do not own.** Because host `applyTo` globs match paths inside `target/`, technology rules in the host — TypeScript, Node.js, Mermaid — apply to whatever you mount, giving consistent review criteria across codebases.
- **Canary checks for configuration drift.** The moon-phase trick generalizes: plant a harmless, distinctive instruction in a test target to confirm which configuration a new Copilot client version loads before you trust it with a real investigation.

## Caveats Before You Rely on It

The repository is an exploratory proof of concept, and a few limits are worth stating plainly. Discovery behavior differs between Copilot CLI, VS Code, and other clients, and it changes across versions; the experiments here used Copilot CLI 1.0.104-1. Model citations and summaries can be wrong, and the agent's evidence ledger exists precisely so a human can check them. The target's own instructions can enter the context whenever Copilot works on its files, so an untrusted target is also a potential source of prompt injection. Review what the target's `.github/` folder contains before mounting it.

## What's Next?

The next step is to verify the remaining VS Code behavior from the top-level workspace: whether the agent picker exposes `software-archeologist` and whether nested target instructions load when the agent opens target files. The target-only check did not show host configuration loading with `chat.useCustomizationsInParentRepositories` enabled; a diagnostic capture is still needed to establish exactly why. I also plan to add an explicit host instruction that ranks target-supplied instructions as evidence rather than direction, then rerun the canary to measure whether it holds.

## Feedback Loop

Feedback is always welcome. Send your thoughts to [AIPractitioner@pdata.com](mailto:AIPractitioner@pdata.com).

## Disclaimer

AI contributed to the writing of this post, but humans reviewed it, refined it, enhanced it, and gave it soul.

Prompts:

- Write the post from this prompt: "write a blog post explaining the software archaeologist repo. include: - basics of how submodules work - how github copilot utilizes config (instructions, skills, agents, etc.) found in the software archaeologist repo. - how github copilot utilizes config (instructions, skills, agents, etc.) found in the submodule repo(s). - an explanation of the replace submodule scripts - scenarios for how this behavior can be leveraged"
- Probe Copilot CLI from the repository root and from `target/`: "Without using any tools, list the file paths of every custom instruction, agent, and skill file loaded into your context. Then answer: what is 2+2?"
- Probe nested discovery from the repository root: "Read target/src/calculator.ts and describe it in one sentence. Follow every custom instruction that applies."
- Update the VS Code findings after checking parent discovery from the target-only workspace: "update the blog post to reflect these findings"
