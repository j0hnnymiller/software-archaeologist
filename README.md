# Software Archaeologist

This repository is a proof of concept for packaging the skills, agents, and
instructions needed to analyze a codebase stored in a separate sub-repository.
The goal is to keep the analysis tooling and guidance alongside the target
codebase without mixing the two.

## Concept

- This repository contains the analysis skills, agents, and instructions.
- A sub-repository contains the codebase being analyzed.
- An AI coding assistant uses the tooling and guidance from this repository to
  explore and explain the codebase in the sub-repository.

The analysis may cover a project's structure, architecture, key components,
dependencies, and development workflows. The exact capabilities depend on the
skills, agents, and instructions added as this proof of concept evolves.

## Status

This is an exploratory project, not a production-ready analysis framework.
Its purpose is to test how repository-level AI guidance can support analysis
of a separate codebase.

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
