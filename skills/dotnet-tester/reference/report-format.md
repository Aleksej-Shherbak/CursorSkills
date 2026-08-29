---
description: Phase report tables and final Verification Verdict template. Use when reporting results from any dotnet-tester phase.
alwaysApply: true
---

# Report Format

Every `/dotnet-tester` run produces structured reports per phase and a final verdict.

## Phase Status Values

| Status | Meaning |
|--------|---------|
| PASS | Phase completed successfully |
| FAIL | Phase failed — blocking unless user said continue |
| SKIP | Phase skipped (user request or prerequisite missing) |

## Phase 1 — Build Report

```markdown
## Phase 1: Build — FAIL

| File | Line | Error | Suggested fix |
|------|------|-------|---------------|
| Orders.Application/Handlers/CreateOrderHandler.cs | 8 | CS0246 | Add using for IOrderRepository |
```

PASS variant:

```markdown
## Phase 1: Build — PASS

Built Orders.slnx successfully (0 warnings, 0 errors).
```

## Phase 2 — Unit Tests Report

```markdown
## Phase 2: Unit Tests — FAIL

**Summary:** 38 passed, 2 failed, 40 total

### Failed tests

#### CreateOrderHandlerTests.Handle_returns_success
- **Message:** Assert.True() Failure
- **File:** tests/Orders.Unit.Tests/CreateOrderHandlerTests.cs:52
- **Suggested fix:** Check mock repository setup
```

## Phase 3 — Docker Report

```markdown
## Phase 3: Docker — PASS

| Service | Status | Notes |
|---------|--------|-------|
| postgres | healthy | port 5432 |
| migrator | exited (0) | migrations applied |
| api | running | port 8080 |
```

## Phase 4 — OpenAPI Report

```markdown
## Phase 4: OpenAPI — PASS

| Api | Endpoints | Spec URL |
|-----|-----------|----------|
| Orders.Api | 12 | /swagger/v1/swagger.json |
| Billing.Api | 8 | /swagger/v1/swagger.json |
```

Include full Test Plan per Api (see [openapi-discovery.md](openapi-discovery.md)).

## Phase 5 — Curl Smoke Report

```markdown
## Phase 5: Curl Smoke — PASS

| Api | Endpoint | Status | Result |
|-----|----------|--------|--------|
| Orders.Api | GET /swagger/v1/swagger.json | 200 | PASS |
| Orders.Api | GET /api/orders | 200 | PASS |
| Orders.Api | POST /api/orders | 201 | PASS |

**Scenarios created:** 4 new files in ai-e2e-tests/Orders.Api/
```

## Phase 6 — ai-e2e-tests Report

```markdown
## Phase 6: ai-e2e-tests — FAIL

| Scenario | Api | Expected | Actual | Result |
|----------|-----|----------|--------|--------|
| smoke-swagger | Orders.Api | 200 | 200 | PASS |
| orders-create-happy-path | Orders.Api | 201 | 201 | PASS |
| orders-get-not-found | Orders.Api | 404 | 500 | FAIL |
```

## Final Verdict

Always end the response with:

```markdown
## Verification Verdict: FAIL

| Phase | Status | Notes |
|-------|--------|-------|
| Build | PASS | |
| Unit tests | PASS | 40/40 |
| Docker | PASS | all services up |
| OpenAPI | PASS | 2 APIs, 20 endpoints |
| Curl smoke | PASS | 6/6 |
| ai-e2e-tests | FAIL | 4/5 scenarios |

### Blocking issues

1. `orders-get-not-found` returns 500 instead of 404 — unhandled exception in GetOrderHandler

### Suggested fixes

1. Add null check in GetOrderHandler when order not found; return `Result.Failure(Error.NotFound(...))`
2. Re-run: `/dotnet-tester rerun ai-e2e-tests`
```

### PASS Criteria

**Verification Verdict: PASS** only when **every executed phase** is PASS.

Skipped phases do not block PASS (mark as SKIP in table).

### FAIL Criteria

Any executed phase with FAIL → overall FAIL. List all blocking issues and actionable fixes.

## Monorepo Summary

When multiple Web APIs in one solution, add:

```markdown
### Per-Api Summary

| Api | OpenAPI | Curl smoke | ai-e2e-tests |
|-----|---------|------------|--------------|
| Orders.Api | PASS | PASS | FAIL 4/5 |
| Billing.Api | PASS | PASS | PASS 3/3 |
```
