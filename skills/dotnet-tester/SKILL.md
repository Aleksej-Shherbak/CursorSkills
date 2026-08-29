---
name: dotnet-tester
version: 1.0.0
description: >
  Verifies .NET solutions end-to-end: build, unit tests, docker-compose, OpenAPI
  analysis, curl smoke tests, and ai-e2e-tests scenario execution. Discovers all
  Web API projects in the solution. Use when the user invokes /dotnet-tester,
  asks to verify a project works, run E2E checks, smoke test APIs, or validate
  docker-compose and test scenarios.
disable-model-invocation: true
---

# .NET Tester Agent

Apply this skill when the user explicitly invokes `/dotnet-tester` to verify that a .NET solution **builds, tests pass, docker-compose works, and APIs respond correctly**.

**Goal:** deliver a clear **Verification Verdict: PASS | FAIL** so the user can say "yes, the project works — and works correctly."

## Overrides

When this skill is active, the agent **may and should** run:

- `dotnet restore`, `dotnet build`, `dotnet test`
- `docker compose up/down`, `docker compose logs`
- `curl.exe` / `curl` against running APIs

This overrides `dotnet-clean-architecture` agent constraints ("do not run restore/build") **only while this skill is invoked**.

Do **not** auto-commit `ai-e2e-tests/` — create/update files; user decides whether to commit.

## Reference Routing

| When working on… | Read |
|------------------|------|
| Any task | [report-format.md](reference/report-format.md) |
| Finding solution / Web API projects | [webapi-discovery.md](reference/webapi-discovery.md) |
| Build errors / unit test failures | [build-and-unit-tests.md](reference/build-and-unit-tests.md) |
| docker-compose up/down / logs | [docker-compose.md](reference/docker-compose.md) |
| curl availability / syntax | [curl-prerequisites.md](reference/curl-prerequisites.md) |
| OpenAPI / test plan | [openapi-discovery.md](reference/openapi-discovery.md) |
| ai-e2e-tests folder / scenarios | [ai-e2e-tests-format.md](reference/ai-e2e-tests-format.md) |

## Pipeline Overview

Run phases **in order**. A **blocking failure** stops the pipeline (Phase 6 partial fail → overall FAIL, but still run remaining scenarios).

```
Phase 0: Discovery
Phase 1: Build
Phase 2: Unit tests
Phase 3: docker-compose
Phase 4: OpenAPI + test plan (per Web API)
Phase 5: curl smoke + create ai-e2e-tests scenarios
Phase 6: Execute ai-e2e-tests scenarios
Final:   Verification Verdict
```

User may skip phases explicitly (e.g. "skip docker", "only unit tests", "rerun ai-e2e-tests only").

## Phase 0 — Discovery

Before any commands, discover and report:

| Item | How |
|------|-----|
| Solution | `*.slnx` (priority) or `*.sln` nearest to workspace focus |
| Web API projects | All `*.Api.csproj` with `Microsoft.NET.Sdk.Web` — see [webapi-discovery.md](reference/webapi-discovery.md) |
| Test projects | `tests/**/*.csproj`, `**/*Tests.csproj` |
| docker-compose | `SolutionItems/docker-compose.yml`, then solution-root `docker-compose.yml` |
| curl | **Mandatory preflight** — see [curl-prerequisites.md](reference/curl-prerequisites.md) |

Report discovered paths in the response. Test **all Web API projects** in the solution. Each Api gets its own subfolder under `ai-e2e-tests/{ApiProjectName}/`.

## Phase 1 — Build

```powershell
dotnet restore "<SolutionPath>"
dotnet build "<SolutionPath>" --no-restore
```

On failure: produce fix report — see [build-and-unit-tests.md](reference/build-and-unit-tests.md).

**Stop** if build fails (unless user said skip).

## Phase 2 — Unit Tests

```powershell
dotnet test "<SolutionPath>" --no-build --verbosity normal
```

Report each failed test: name, message, likely cause, suggested fix. Architecture tests (`*Architecture.Tests*`) run automatically.

**Stop** if any test fails (unless user said continue on test failure).

## Phase 3 — docker-compose

Skip if no compose file found or user said "skip docker".

```powershell
docker compose -f "<ComposePath>" up --build -d
docker compose -f "<ComposePath>" ps
docker compose -f "<ComposePath>" logs migrator --tail 50
docker compose -f "<ComposePath>" logs api --tail 50
```

Verify: postgres healthy, migrator exited 0, api listening. Full guide: [docker-compose.md](reference/docker-compose.md).

Run `docker compose down` **only** if user did not ask to keep the stack running.

## Phase 4 — OpenAPI + Test Plan

For **each** discovered Web API:

1. Resolve base URL (docker port mapping or `Properties/launchSettings.json`).
2. Fetch OpenAPI spec via curl.
3. Publish a **Test Plan** in the response: endpoints by tag, smoke vs CRUD, call dependencies, expected status codes.

Guide: [openapi-discovery.md](reference/openapi-discovery.md).

## Phase 5 — curl Smoke + Create Scenarios

**Preflight:** verify real curl — [curl-prerequisites.md](reference/curl-prerequisites.md). On Windows always use `curl.exe`.

Create/update at **solution root**:

```
ai-e2e-tests/
├── README.md
├── Orders.Api/
│   ├── _manifest.md
│   └── *.md scenarios
└── Billing.Api/
    └── ...
```

Rules:

- Hit main endpoints: health/swagger, GET list, GET by id, POST create.
- **Do not overwrite** existing scenario files without explicit user command — append only.
- Update `_manifest.md` after creating scenarios.

Format: [ai-e2e-tests-format.md](reference/ai-e2e-tests-format.md).

## Phase 6 — Execute ai-e2e-tests Scenarios

1. Read all `ai-e2e-tests/**/*.md` except `README.md` and `_manifest.md`.
2. Execute curl from each scenario's `## Request` section.
3. Compare `expectedStatus` and `## Expected` bullets with actual response.
4. Update frontmatter: `lastRun`, `lastResult: pass|fail`, `lastError`.
5. Update `_manifest.md` summary.

Partial scenario failure → Phase status FAIL, but run all scenarios.

## Final Verdict

Always end with the verdict block from [report-format.md](reference/report-format.md):

```markdown
## Verification Verdict: PASS | FAIL

| Phase | Status | Notes |
|-------|--------|-------|
| Build | PASS/FAIL/SKIP | |
| Unit tests | PASS/FAIL/SKIP | |
| Docker | PASS/FAIL/SKIP | |
| OpenAPI | PASS/FAIL/SKIP | |
| Curl smoke | PASS/FAIL/SKIP | |
| ai-e2e-tests | PASS/FAIL/SKIP | |

### Blocking issues
1. ...

### Suggested fixes
1. ...
```

**PASS** only when all executed phases are PASS.

## Workflow Checklist

```
- [ ] Phase 0: discover solution, all Web API projects, compose file, curl
- [ ] Phase 1: dotnet restore + build — fix report on failure
- [ ] Phase 2: dotnet test — failure details on fail
- [ ] Phase 3: docker compose up — health + logs report
- [ ] Phase 4: OpenAPI fetched + test plan per Web API
- [ ] Phase 5: curl smoke — scenarios written to ai-e2e-tests/{ApiName}/
- [ ] Phase 6: existing scenarios executed — frontmatter updated
- [ ] Final: Verification Verdict published
```

## Partial Runs

| User says | Run |
|-----------|-----|
| "full verify" / "end-to-end" | Phases 0–6 |
| "only build" | Phase 0–1 |
| "only unit tests" | Phase 0–2 (build if needed) |
| "only docker" | Phase 0, 3 |
| "only openapi" / "test plan" | Phase 0, 4 (requires running API) |
| "rerun ai-e2e-tests" | Phase 0, 6 (ensure API is up) |
| "skip docker" | Phases 1–2, 4–6 using `dotnet run` or existing URL |

End-to-end examples: [examples.md](examples.md)

## Additional Resources

- [webapi-discovery.md](reference/webapi-discovery.md) — find Web API projects in solution
- [build-and-unit-tests.md](reference/build-and-unit-tests.md) — build/test commands, error parsing
- [docker-compose.md](reference/docker-compose.md) — compose lifecycle, health checks
- [curl-prerequisites.md](reference/curl-prerequisites.md) — curl.exe vs PowerShell alias
- [openapi-discovery.md](reference/openapi-discovery.md) — swagger URL, test plan template
- [ai-e2e-tests-format.md](reference/ai-e2e-tests-format.md) — scenario markdown spec
- [report-format.md](reference/report-format.md) — phase reports and final verdict
