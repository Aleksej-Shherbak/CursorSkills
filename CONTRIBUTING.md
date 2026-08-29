# Contributing to CursorSkills

This repository contains **one skill** — `dotnet-clean-architecture` — a complete framework guide for .NET backends on Clean Architecture.

Most contributions extend that skill rather than adding new ones.

## Extending dotnet-clean-architecture

1. Keep `SKILL.md` under 500 lines — add detail to `reference/` or `examples.md`.
2. Link reference files only one level deep from `SKILL.md`.
3. Follow existing stack: Controllers, MediatR, Dapper, PostgreSQL, Docker.
4. Do **not** place skills in `~/.cursor/skills-cursor/` — reserved for Cursor built-in skills.

## Layout

```
skills/dotnet-clean-architecture/
├── SKILL.md              # core rules and checklist
├── examples.md           # end-to-end scenarios
└── reference/            # detailed topics (Dapper, MediatR, Docker, …)
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

Checks: `SKILL.md` line count, `disable-model-invocation: true`, flat use-case folder paths (no `Commands/` subfolder), required reference files.

## Pull Request Checklist

- [ ] `.\scripts\validate.ps1` passes
- [ ] Changes fit inside `dotnet-clean-architecture` (new reference file or section, not a separate skill)
- [ ] `SKILL.md` stays under 500 lines; large additions go to `reference/`
- [ ] Examples in `examples.md` updated if behavior changes
- [ ] Consistent with MediatR, Dapper, Controllers, PostgreSQL, Docker conventions

## Adding a Separate Skill (rare)

Only if the team explicitly decides to split a major topic into its own skill:

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`).
2. Update README to document why it is separate from `dotnet-clean-architecture`.
3. Install script picks it up automatically (scans `skills/`).

## Attribution

If content is adapted from another project, credit the original in `SKILL.md` and/or README.
