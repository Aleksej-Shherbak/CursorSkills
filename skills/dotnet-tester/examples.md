# Examples

End-to-end usage scenarios for `/dotnet-tester`.

## Example 1: Full End-to-End Verification

**User prompt:** `/dotnet-tester проверь Orders solution end-to-end`

**Agent steps:**

1. **Phase 0** — Discover `Orders.slnx`, Web APIs: `Orders.Api`, compose: `SolutionItems/docker-compose.yml`, verify `curl.exe`.
2. **Phase 1** — `dotnet restore` + `dotnet build Orders.slnx`.
3. **Phase 2** — `dotnet test Orders.slnx --no-build`.
4. **Phase 3** — `docker compose -f SolutionItems/docker-compose.yml up --build -d`, verify postgres/migrator/api.
5. **Phase 4** — Fetch OpenAPI for `Orders.Api`, publish test plan (12 endpoints).
6. **Phase 5** — curl smoke on main endpoints; create `ai-e2e-tests/Orders.Api/*.md`.
7. **Phase 6** — Run all scenarios, update frontmatter.
8. **Verdict** — `Verification Verdict: PASS` or `FAIL` with fixes.

**Expected output structure:**

```markdown
## Discovery
| Solution | Orders.slnx |
| Web APIs | Orders.Api |

## Phase 1: Build — PASS
...

## Verification Verdict: PASS
```

## Example 2: Unit Tests Only

**User prompt:** `/dotnet-tester only unit tests`

**Agent steps:**

1. Phase 0 — discovery
2. Phase 1 — build (required before test)
3. Phase 2 — `dotnet test`
4. Skip Phases 3–6
5. Verdict with Build + Unit tests rows only; others SKIP

```markdown
## Verification Verdict: PASS

| Phase | Status | Notes |
|-------|--------|-------|
| Build | PASS | |
| Unit tests | PASS | 40/40 |
| Docker | SKIP | user request |
| OpenAPI | SKIP | |
| Curl smoke | SKIP | |
| ai-e2e-tests | SKIP | |
```

## Example 3: Rerun ai-e2e-tests Only

**User prompt:** `/dotnet-tester rerun ai-e2e-tests`

**Prerequisite:** API running (docker or `dotnet run`), `ai-e2e-tests/` folder exists.

**Agent steps:**

1. Phase 0 — discovery, curl preflight, resolve base URLs
2. Verify API reachable: `curl.exe -s -o NUL -w "%{http_code}" http://localhost:8080/swagger/index.html`
3. Phase 6 only — execute all scenarios in `ai-e2e-tests/**/*.md`
4. Update `_manifest.md` and frontmatter
5. Verdict focused on ai-e2e-tests phase

```markdown
## Phase 6: ai-e2e-tests — FAIL

| Scenario | Expected | Actual | Result |
|----------|----------|--------|--------|
| orders-get-not-found | 404 | 404 | PASS |
| orders-create-happy-path | 201 | 500 | FAIL |

### Suggested fixes
1. Check CreateOrderHandler logs — 500 indicates unhandled exception
```

## Example 4: Solution with Two Web APIs

**User prompt:** `/dotnet-tester verify Platform.slnx`

**Discovery:**

```
Web APIs: Orders.Api, Billing.Api
Compose: SolutionItems/docker-compose.yml (single stack, both apis or one compose per service)
```

**Agent steps:**

- Phases 1–3 once per solution (shared build/test/docker)
- Phase 4 — separate test plan for `Orders.Api` and `Billing.Api`
- Phase 5 — create scenarios in both folders:

```
ai-e2e-tests/
├── Orders.Api/
│   ├── _manifest.md
│   └── orders-create-happy-path.md
└── Billing.Api/
    ├── _manifest.md
    └── invoices-list.md
```

- Phase 6 — run scenarios in both folders
- Verdict includes **Per-Api Summary** table

```markdown
### Per-Api Summary

| Api | OpenAPI | Curl smoke | ai-e2e-tests |
|-----|---------|------------|--------------|
| Orders.Api | PASS | PASS | PASS 5/5 |
| Billing.Api | PASS | PASS | FAIL 2/3 |
```

## Example 5: Build Failure with Fix Guidance

**User prompt:** `/dotnet-tester check if project builds`

**Agent steps:**

1. Phase 0 + Phase 1 only
2. Build fails with CS0246

**Report:**

```markdown
## Phase 1: Build — FAIL

| File | Line | Error | Suggested fix |
|------|------|-------|---------------|
| CreateOrderHandler.cs | 12 | CS0246: IOrderRepository | Add ProjectReference to Application or add using |

## Verification Verdict: FAIL

### Blocking issues
1. Solution does not build — 1 error

### Suggested fixes
1. Add `using Orders.Application.Common.Interfaces;` in CreateOrderHandler.cs
```

Pipeline stops — Phases 2–6 not run.

## Example 6: Docker Failure

**User prompt:** `/dotnet-tester full verify`

**Phase 3 fails** — migrator exit 1.

```markdown
## Phase 3: Docker — FAIL

| Service | Status | Notes |
|---------|--------|-------|
| postgres | healthy | |
| migrator | exited (1) | SQL script 0004 failed |
| api | not started | depends on migrator |

### Suggested fixes
1. Read migrator logs — fix SQL in Infrastructure/Persistence/Sql/0004_*.sql
2. Re-run: docker compose down && docker compose up --build -d
```

Phases 4–6 skipped (API not running). Verdict: FAIL.

## Example 7: curl Preflight Failure

**Windows without curl.exe:**

```markdown
## Discovery

| curl | FAIL — PowerShell alias only |

## Verification Verdict: FAIL

### Blocking issues
1. curl.exe not available — Phases 5–6 cannot run

### Suggested fixes
1. Use `curl.exe` explicitly (Windows 10+) or install curl
```

Phases 1–4 may still run if user requested full verify; verdict remains FAIL until curl works.
