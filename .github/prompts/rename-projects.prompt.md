---
name: rename-projects
description: Use when renaming the shell projects.
---

I want to rename all projects in the #src folder: replace the `AzdAspire` prefix with {new-prefix}.

Use `git mv` to rename the files, if available, otherwise use #fileSearch.

Use #textSearch to replace all occurences of `AzdAspire` inside the following files:
- [copilot-instructions.md](../copilot-instructions.md)
- [aspire-shell-cd.yml](../workflows/aspire-shell-cd.yml)
- [aspire-shell-ci.yml](../workflows/aspire-shell-ci.yml)
- [azure.yaml](../../azure.yaml)
- [README.md](../../README.md)
- [AGENTS.md](../../AGENTS.md)

Once all occurrences are replaced, use `dotnet build` to ensure the solution still builds.
