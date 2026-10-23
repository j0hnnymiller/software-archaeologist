# Feasibility: Codebase Analysis POC

## Current implementation

This repository contains a workspace custom agent and evidence instructions
for generating a read-only overview of the Git submodule at `target/`.
The agent is available in `.github/agents/codebase-analyst.agent.md`; shared
analysis rules are in `.github/instructions/codebase-analysis.instructions.md`.
The agent is constrained to read and search tools, requires target-file
citations for factual claims, distinguishes observations from hypotheses, and
reports when the submodule is unavailable.

The intended workspace is the top-level repository. The submodule pins the
target source revision, keeping the analysis guidance and analyzed code
separate in Git. This is a workflow boundary, not a security boundary.

## Verification record

Checks below were performed on 2026-10-23 using the Copilot CLI on Windows.
They verify CLI behavior only; they do not establish equivalent behavior in
VS Code Chat or other assistants.

| Step | Outcome | Evidence and remaining limitation |
| --- | --- | --- |
| 1. Clean setup | Pass | A fresh recursive clone initialized `target/` at pinned commit `bb611ae9f46271bea5d36616667607a988353b15`. Environment: Node.js `v22.22.2`, npm `10.9.7`, VS Code `1.143.1`. |
| 2. Customization discovery | Pass for CLI | Copilot CLI `1.0.99-2` discovered temporary workspace instruction and skill probes and invoked a temporary named agent. Copilot CLI `1.0.104-1` discovered the implemented instruction and invoked `codebase-analyst`. VS Code Chat was not tested. |
| 3. Target access | Pass for CLI | Copilot CLI `1.0.104-1` identified target files and key project facts from the workspace root. The implemented agent was also tested in a checkout with an uninitialized submodule; it stopped, did not infer project details, and gave the initialization command. |
| 4. Bounded overview | Pass for the tested target | The implemented agent produced the required sections and file-path citations in three post-change runs. Reports were checked against target source and configuration. The earlier inaccurate line-number citations are avoided by not requesting line numbers. The agent reports documented commands but does not run them. |
| 5. Read-only boundary | Pass for tested runs | With write and shell tools denied, the CLI produced overviews. Root and target Git status and diffs were clean before and after; the target remained at the pinned commit. This does not prove the submodule is a security boundary. |
| 6. Repeatability | Pass for structure and citations; details vary | Three post-implementation CLI runs included every required section and had all findings labeled and cited. They agreed on the main project facts and commands, while the amount of detail varied. The reports were spot-checked against the target; human review remains necessary for future findings. |
| 7. Setup portability | Setup and CLI invocation pass; human onboarding incomplete | Fresh recursive clone and existing-clone submodule initialization both worked. The README, agent, and instruction are present; the CLI invocation and missing-submodule behavior were exercised in disposable checkouts. No genuinely unfamiliar tester has followed the updated instructions. VS Code Chat remains unverified. |

## Known limitations and risks

- Agent and instruction conventions are assistant-dependent. Copilot CLI
  discovery and invocation have been exercised; VS Code Chat discovery and
  invocation still require validation.
- Model-generated citations and summaries are not guaranteed correct. Check
  factual claims against cited target files, especially entry points and
  commands. The fixed output format does not guarantee consistent quality.
- Read/search-only agent tools reduce available actions but are not a security
  boundary. Do not analyze code or data that should not be exposed to the
  configured assistant.
- The target may contain untrusted or sensitive content. Use only material
  the operator is authorized to analyze, and follow organizational rules for
  external AI services.
- The overview reports documented commands but does not execute them. Build
  and test success must be validated separately.

## Acceptance criteria

The POC is considered usable for a bounded overview when:

- a clean clone can initialize the pinned target submodule;
- the documented assistant discovers and invokes the workspace agent;
- an initialized target yields a concise overview with factual claims cited
  to inspected target files;
- a missing or empty target is reported without invented project details;
- observations are distinguished from hypotheses and unverified commands are
  not described as passing; and
- target status is unchanged by the overview workflow.

Before claiming portability beyond the Copilot CLI, validate discovery and
invocation in VS Code Chat. Before claiming successful onboarding, have a user
unfamiliar with the repository follow the README from a clean environment.
Repeat the overview several times and evaluate citations and uncertainty
quality, not only agreement on headline facts.
