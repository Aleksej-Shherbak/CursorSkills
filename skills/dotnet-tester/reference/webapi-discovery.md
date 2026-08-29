---
description: Discover .NET solution, Web API projects, test projects, and docker-compose paths. Use at the start of every dotnet-tester run.
alwaysApply: true
---

# Web API Discovery

Run at **Phase 0** before any build or test commands.

## Find Solution

Search order:

1. `**/*.slnx` in workspace (prefer closest to changed files or user-mentioned path)
2. `**/*.sln` if no `.slnx`

If multiple solutions exist, prefer the one the user named; otherwise pick the solution whose root contains `src/` and `*.Api.csproj`.

Report: `Solution: <path>`

## Find Web API Projects

A project is a **Web API** when **any** of:

| Signal | Check |
|--------|-------|
| Sdk | `<Project Sdk="Microsoft.NET.Sdk.Web">` |
| Naming | Project file matches `*.Api.csproj` |
| Output | `<OutputType>Exe</OutputType>` + AspNetCore reference |

Search: `src/**/*.Api.csproj` or any `**/*.csproj` with `Microsoft.NET.Sdk.Web`.

**Exclude:** `*.Migrator.csproj`, `*Tests*.csproj`, worker/console apps without controllers.

For each Api report:

```
- Orders.Api  → src/Orders.Api/Orders.Api.csproj
- Billing.Api → src/Billing.Api/Billing.Api.csproj
```

All discovered Web APIs are tested in Phases 4–6. Each gets `ai-e2e-tests/{ProjectName}/`.

## Find Test Projects

| Pattern | Example |
|---------|---------|
| `tests/**/*.csproj` | `tests/Orders.Unit.Tests/` |
| `**/*Tests.csproj` | `Orders.Architecture.Tests.csproj` |
| `**/*Test.csproj` | rare singular form |

Report count and paths. `dotnet test` on the solution runs all of them.

## Find docker-compose

Search order (relative to solution root):

1. `SolutionItems/docker-compose.yml`
2. `SolutionItems/docker-compose*.yml`
3. `docker-compose.yml` in solution root

Report: `Compose: <path>` or `Compose: not found (skip Phase 3 or use dotnet run)`.

## Resolve Base URL per Web API

| Source | How |
|--------|-----|
| docker-compose | `ports:` mapping for `api` service (e.g. `"8080:8080"` → `http://localhost:8080`) |
| launchSettings | `Properties/launchSettings.json` → first `applicationUrl` with `http://` |
| Fallback | `http://localhost:5000`, `http://localhost:8080` |

## Discovery Report Template

```markdown
## Discovery

| Item | Value |
|------|-------|
| Solution | Orders.slnx |
| Web APIs | Orders.Api, Billing.Api |
| Test projects | 3 found |
| docker-compose | SolutionItems/docker-compose.yml |
| curl | curl.exe 8.x OK |
```
