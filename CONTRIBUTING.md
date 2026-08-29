# Contributing to CursorSkills

This repository contains Cursor Agent Skills for .NET development:

| Skill | Purpose |
|-------|---------|
| `dotnet-clean-architecture` | How we build .NET backends (Clean Architecture, MediatR, Dapper, Docker) |
| `dotnet-tester` | Verification pipeline (build, tests, docker, OpenAPI, ai-e2e-tests) |

## General Rules

1. Keep each `SKILL.md` under 500 lines — add detail to `reference/` or `examples.md`.
2. Link reference files only one level deep from `SKILL.md`.
3. Set `disable-model-invocation: true` on all skills (manual invoke only).
4. Set `version: x.y.z` in every `SKILL.md` frontmatter — bump on meaningful changes.
5. Do **not** place skills in `~/.cursor/skills-cursor/` — reserved for Cursor built-in skills.

## Versioning

Each skill has a semver `version` field in `SKILL.md` frontmatter:

```yaml
---
name: dotnet-tester
version: 1.0.0
description: ...
---
```

Bump rules:

- **patch** (1.0.0 → 1.0.1) — typo fixes, clarifications
- **minor** (1.0.0 → 1.1.0) — new reference sections, extended pipeline steps
- **major** (1.0.0 → 2.0.0) — breaking behavior or structure changes

`install.ps1` / `install.sh` reinstall a skill when source version is **higher** than installed, or when installed copy has **no version**. Equal or older source versions are skipped.

## Layout

```
skills/<skill-name>/
├── SKILL.md              # core rules and checklist
├── examples.md           # end-to-end scenarios
└── reference/            # detailed topics
    └── *.md
```

## Validation

Before opening a PR, run:

```powershell
.\scripts\validate.ps1
```

macOS / Linux:

```bash
./scripts/validate.sh
```

Validates **all** skills in `skills/*/`: line count, frontmatter, links, skill-specific rules.

## Extending dotnet-clean-architecture

1. Follow existing stack: Controllers, MediatR, Dapper, PostgreSQL, Docker.
2. Use flat use-case folders (`Orders/CreateOrder/`, not `Orders/Commands/CreateOrder/`).

## Extending dotnet-tester

1. Keep the 6-phase pipeline order in `SKILL.md`.
2. Document new scenario fields in `reference/ai-e2e-tests-format.md`.
3. Use `curl.exe` in all Windows examples.
4. Tester skill **overrides** clean-arch "no restore/build" — only when `/dotnet-tester` is invoked.

## Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `version`, `description`, `disable-model-invocation: true`).
2. Add `examples.md` and `reference/` as needed.
3. Update README to document the new skill.
4. Extend `scripts/validate.ps1` if skill-specific checks are required.
5. Install script picks it up automatically (scans `skills/`).

## Pull Request Checklist

- [ ] `.\scripts\validate.ps1` passes
- [ ] `SKILL.md` stays under 500 lines per skill
- [ ] `examples.md` updated if behavior changes
- [ ] README updated for new or changed skills

## Attribution

If content is adapted from another project, credit the original in `SKILL.md` and/or README.
