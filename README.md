# CursorSkills

Cursor Agent Skill for building .NET applications on **Clean Architecture** — one skill, one framework guide. Install once and stop re-explaining stack and conventions in every new project.

## Skill: dotnet-clean-architecture

**[skills/dotnet-clean-architecture/SKILL.md](skills/dotnet-clean-architecture/SKILL.md)** — complete instruction set for how we build .NET backends:

| Topic | Covered in |
|-------|------------|
| Clean Architecture (4 layers) | `SKILL.md`, `reference/project-layout.md` |
| Rich domain entities | `reference/domain-entities.md` |
| MediatR (handlers, pipeline behaviors) | `SKILL.md`, `reference/mediatr-setup.md` |
| Classic Controllers + `ISender` | `reference/controllers.md` |
| Dapper + PostgreSQL | `reference/dapper-persistence.md` |
| SQL migrations + Migrator | `reference/migrations.md` |
| Error handling (Error, ErrorKind, HTTP mapping) | `reference/error-handling.md` |
| Logging (Serilog JSONL, inbound/outbound/message) | `reference/logging.md` |
| Result pattern | `reference/result-pattern.md` |
| Docker + docker-compose | `reference/docker.md` |
| Team conventions (DTO spacing, secrets, versioning) | `reference/team-conventions.md` |
| Program.cs, per-use-case DI | `reference/program-and-di.md` |
| End-to-end scenarios | `examples.md` |

Dapper, Result, Docker, versioning and the rest are **sections inside this one skill**, not separate skills.

## Installation

### A. Personal (recommended)

Works across all your Cursor projects.

```powershell
git clone https://github.com/<your-org>/CursorSkills.git
cd CursorSkills
.\scripts\install.ps1
```

macOS / Linux:

```bash
git clone https://github.com/<your-org>/CursorSkills.git
cd CursorSkills
./scripts/install.sh
```

Restart Cursor after installation.

### B. Project-level

For team sharing inside a specific repository:

```powershell
git submodule add https://github.com/<your-org>/CursorSkills.git .cursor/skills-shared
# Symlink skills/dotnet-clean-architecture → .cursor/skills/dotnet-clean-architecture
```

### C. Manual copy

```powershell
Copy-Item -Recurse skills\dotnet-clean-architecture "$env:USERPROFILE\.cursor\skills\"
```

## Using in Cursor Agent

1. Skill installed under `~/.cursor/skills/dotnet-clean-architecture/` or `.cursor/skills/dotnet-clean-architecture/`.
2. In Agent chat:
   - `@dotnet-clean-architecture`
   - or: "Use the dotnet-clean-architecture skill to scaffold this API"
3. With `disable-model-invocation: true`, the skill loads when you name it explicitly.

## Repository Structure

```
CursorSkills/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── skills/
│   └── dotnet-clean-architecture/    ← the only skill
│       ├── SKILL.md
│       ├── examples.md
│       └── reference/
└── scripts/
    ├── install.ps1
    └── install.sh
```

## Attribution

Inspired by [codewithmukesh/dotnet-claude-kit](https://github.com/codewithmukesh/dotnet-claude-kit), adapted for Cursor Agent with MediatR, Dapper, PostgreSQL, classic Controllers, and Docker.

## License

MIT — see [LICENSE](LICENSE).
