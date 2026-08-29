# CursorSkills

Cursor Agent Skills for .NET development — architecture guide and verification pipeline. Install once and stop re-explaining stack, conventions, and test workflows in every new project.

## Skills

### dotnet-clean-architecture

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

### dotnet-tester

**[skills/dotnet-tester/SKILL.md](skills/dotnet-tester/SKILL.md)** — verification agent for .NET solutions:

| Phase | What it does |
|-------|--------------|
| Build | `dotnet restore` + `dotnet build`, fix report on errors |
| Unit tests | `dotnet test`, failure analysis |
| Docker | `docker compose up`, health + log report |
| OpenAPI | Fetch spec, test plan per Web API |
| Curl smoke | Hit main endpoints, create `ai-e2e-tests/` scenarios |
| ai-e2e-tests | Execute saved scenarios, update results |

Discovers **all Web API projects** in the solution. Scenarios stored in `ai-e2e-tests/{ApiProjectName}/` at solution root.

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

Restart Cursor after installation or upgrade.

The install script compares `version` in each skill's `SKILL.md`:

| Installed | Source | Action |
|-----------|--------|--------|
| missing | any | install |
| no version | any | remove + reinstall |
| 1.0.0 | 1.1.0 | remove + reinstall |
| 1.1.0 | 1.0.0 | skip (no downgrade) |
| 1.0.0 | 1.0.0 | skip |

Check installed version:

```powershell
Select-String -Path "$env:USERPROFILE\.cursor\skills\dotnet-tester\SKILL.md" -Pattern '^version:'
```

Validate after changes:

```powershell
.\scripts\validate.ps1
```

### B. Project-level

For team sharing inside a specific repository:

```powershell
git submodule add https://github.com/<your-org>/CursorSkills.git .cursor/skills-shared
# Symlink skills/* → .cursor/skills/
```

### C. Manual copy

```powershell
Copy-Item -Recurse skills\dotnet-clean-architecture "$env:USERPROFILE\.cursor\skills\"
Copy-Item -Recurse skills\dotnet-tester "$env:USERPROFILE\.cursor\skills\"
```

## Using in Cursor Agent

Both skills use `disable-model-invocation: true` — invoke explicitly via `/`:

| Skill | Version | Invoke | When |
|-------|---------|--------|------|
| `dotnet-clean-architecture` | 1.0.0 | `/dotnet-clean-architecture` | Scaffolding, refactoring, reviewing .NET backends |
| `dotnet-tester` | 1.0.0 | `/dotnet-tester` | Verify project works: build, tests, docker, API smoke |

Example workflow:

1. Build feature with `/dotnet-clean-architecture`
2. Verify with `/dotnet-tester проверь solution end-to-end`
3. After `git pull`, run `.\scripts\install.ps1` to upgrade skills when version bumped

## Repository Structure

```
CursorSkills/
├── README.md
├── LICENSE
├── CONTRIBUTING.md
├── skills/
│   ├── dotnet-clean-architecture/    ← architecture & conventions
│   │   ├── SKILL.md
│   │   ├── examples.md
│   │   └── reference/
│   └── dotnet-tester/                ← verification pipeline
│       ├── SKILL.md
│       ├── examples.md
│       └── reference/
└── scripts/
    ├── install.ps1
    ├── install.sh
    ├── validate.ps1
    └── validate.sh
```

## Attribution

Inspired by [codewithmukesh/dotnet-claude-kit](https://github.com/codewithmukesh/dotnet-claude-kit), adapted for Cursor Agent with MediatR, Dapper, PostgreSQL, classic Controllers, and Docker.

## License

MIT — see [LICENSE](LICENSE).
