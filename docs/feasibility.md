# Feasibility: Codebase Analysis POC

## Summary

This proof of concept is feasible with a small, repository-based setup. Keep
the analysis instructions, agents, and skills in this repository, and include
the codebase to analyze as a Git submodule. Open the containing repository as
the VS Code workspace so the assistant can use the tooling and inspect the
submodule in the same workspace.

The main uncertainty is not whether an assistant can read both repositories;
it is whether the chosen assistant discovers and applies customization files
from the tooling repository as expected. Skill and instruction discovery can
depend on the assistant, file location, and workspace configuration. The POC
should test that behavior early and explicitly, rather than assuming every
assistant uses the same conventions.

## Proposed layout

```text
software-archaeologist/
├── .github/
│   ├── agents/
│   │   └── codebase-analyst.agent.md
│   └── instructions/
│       └── codebase-analysis.instructions.md
├── skills/
│   └── codebase-overview/
│       └── SKILL.md
├── docs/
│   └── feasibility.md
├── target/                 # Git submodule: codebase under analysis
└── README.md
```

The exact names and locations should follow the conventions of the target AI
assistant. If those conventions require skills or instructions in another
location, configure or document that location as part of the POC.

## How it could work

1. Add a representative project as a Git submodule at `target/`.
2. Open the top-level repository in VS Code, and initialize the submodule
   after cloning (`git submodule update --init --recursive`).
3. Provide an analysis agent with a clear scope: inspect `target/`, treat it as
   read-only, cite relevant files in its findings, and do not change its
   contents.
4. Provide a focused skill with repeatable steps, such as identifying project
   languages, entry points, build and test commands, major components, and
   important dependencies.
5. Use workspace-level instructions for shared constraints and output
   expectations. Keep task-specific procedures in the skill and agent instead
   of duplicating them.
6. Ask the assistant to produce a concise overview and verify the results
   against the target repository.

The submodule keeps the target codebase at a pinned commit and makes the
separation between tooling and analyzed source explicit. The target can be
updated independently by changing the submodule reference.

## Feasibility considerations

| Area | Assessment | POC approach |
| --- | --- | --- |
| Access to both repositories | Feasible when both are present in the opened workspace. | Keep the target in a submodule and test file discovery from the workspace root. |
| Customization discovery | Assistant-dependent; must be verified. | Start with documented, supported file locations and run a small discovery test. |
| Repository separation | Feasible, but not a security boundary. | Use a read-only analysis scope and avoid modifying submodule files. |
| Repeatability | Feasible for a bounded set of analysis tasks. | Use a checklist and a stable report structure. |
| Portability | Depends on Git submodule support and assistant conventions. | Document clone/setup steps and record supported assistant versions or modes. |
| Analysis accuracy | Achievable only with source verification. | Require evidence and file references for substantive findings; review output manually. |

## Risks and mitigations

- **Instructions or skills are not loaded.** Verify discovery with a deliberately
  distinctive instruction and confirm that the assistant follows it. If
  necessary, use workspace configuration or an explicit prompt to expose the
  tooling files.
- **The target is missing after clone.** Document submodule initialization and
  make the analysis instructions check for an empty or unavailable `target/`
  directory before proceeding.
- **The assistant edits analyzed code.** State a read-only requirement, review
  the worktree after analysis, and keep any generated report outside the
  submodule.
- **Findings are unsupported or incomplete.** Require concrete file references
  and separate observed facts from hypotheses. Validate build and test
  instructions against the target's own documentation and configuration.
- **The setup is coupled to one assistant.** Treat discovery and execution
  conventions as an adapter layer; keep the analysis procedure itself as
  portable as practical.
- **The target contains sensitive or untrusted content.** Use only code the
  operator is authorized to analyze, and do not send private source to
  unapproved external services.

## Suggested implementation stages

1. **Validate workspace discovery.** Add a small example instruction and agent,
   place a sample repository in `target/`, and confirm that the assistant can
   see both the customization files and target source.
2. **Implement one useful skill.** Start with a repository overview: detect
   languages and frameworks, identify entry points, summarize directory
   structure, and locate documented build and test commands.
3. **Define evidence-based output.** Have the agent return a short report with
   project summary, architecture clues, development commands, and cited
   source-file paths. Mark uncertain conclusions as hypotheses.
4. **Test repeatability and boundaries.** Run the same task more than once;
   check for missing-target handling, citation quality, and unintended
   modifications.
5. **Document setup and limitations.** Record how to clone and initialize the
   submodule, open the workspace, invoke the analysis, and interpret results.

## Acceptance criteria

The POC is successful when a new user can:

- clone the tooling repository and initialize the target submodule;
- open the top-level workspace and confirm the analysis customization is
  available to the selected assistant;
- request a repository overview and receive findings grounded in the target's
  actual files;
- identify which conclusions are facts versus hypotheses; and
- complete the analysis without changes to the target submodule.

## Conclusion

The approach is practical for a bounded proof of concept. A Git submodule is a
simple way to colocate a pinned target codebase with repository-level analysis
guidance. The first implementation milestone should be a small end-to-end
discovery test, since assistant-specific customization loading is the largest
feasibility uncertainty. If that test passes, the remaining work is primarily
authoring, validating, and documenting a repeatable analysis procedure.
