---
description: Markdown scenario format and ai-e2e-tests folder structure. Use when creating or executing E2E test scenarios.
globs: "**/ai-e2e-tests/**"
---

# ai-e2e-tests Format

Scenarios live at **solution root** — one subfolder per Web API project:

```
ai-e2e-tests/
├── README.md
├── Orders.Api/
│   ├── _manifest.md
│   ├── smoke-swagger.md
│   ├── orders-list.md
│   ├── orders-create-happy-path.md
│   └── orders-get-not-found.md
└── Billing.Api/
    ├── _manifest.md
    └── ...
```

## README.md (solution root index)

Create once at `ai-e2e-tests/README.md`:

```markdown
# AI E2E Tests

Auto-generated and maintained by /dotnet-tester.

| Api | Scenarios | Last run |
|-----|-----------|----------|
| Orders.Api | 5 | 2026-08-29 PASS |
| Billing.Api | 3 | pending |

Run: invoke `/dotnet-tester rerun ai-e2e-tests`
```

## Scenario File — Markdown + YAML Frontmatter

Filename: `{feature}-{case}.md` (kebab-case), e.g. `orders-create-happy-path.md`.

```markdown
---
id: orders-create-happy-path
api: Orders.Api
method: POST
path: /api/orders
expectedStatus: 201
tags: [smoke, orders, crud]
lastRun: null
lastResult: pending
lastError: null
---

# Create order — happy path

## Preconditions

- API running at http://localhost:8080
- Database migrated

## Request

```bash
curl.exe -s -w "\nHTTP_CODE:%{http_code}" -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -d "{\"customerId\":\"test-001\",\"items\":[{\"productId\":\"p1\",\"quantity\":1,\"unitPrice\":10.00}]}"
```

## Expected

- HTTP status 201
- Response body contains a GUID `id` field

## Variables

Capture `id` from response for use in `orders-get-by-id.md`.

## Notes

Created from OpenAPI on 2026-08-29.
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `id` | yes | Unique scenario id (matches filename without .md) |
| `api` | yes | Web API project name (e.g. `Orders.Api`) |
| `method` | yes | HTTP method |
| `path` | yes | URL path without host |
| `expectedStatus` | yes | Expected HTTP status code |
| `tags` | no | smoke, crud, error, etc. |
| `lastRun` | no | ISO date or null — updated by Phase 6 |
| `lastResult` | no | `pending`, `pass`, `fail` |
| `lastError` | no | Short error on fail |

## _manifest.md (per Api folder)

`ai-e2e-tests/Orders.Api/_manifest.md`:

```markdown
# Orders.Api — Scenario Manifest

**Base URL:** http://localhost:8080
**Last full run:** 2026-08-29T10:00:00Z — 4/5 PASS

| Scenario | Tags | Last result |
|----------|------|-------------|
| smoke-swagger | smoke | pass |
| orders-create-happy-path | smoke, crud | pass |
| orders-get-not-found | error | fail |
```

Update after Phase 5 (new scenarios) and Phase 6 (run results).

## Phase 5 — Creating Scenarios

Rules:

1. Create folder `ai-e2e-tests/{ApiProjectName}/` if missing.
2. Generate smoke scenarios first: swagger, GET list.
3. Add CRUD scenarios from test plan (Phase 4).
4. Add at least one error case (404 or 422).
5. **Never overwrite** existing `.md` files unless user said "regenerate scenarios".
6. Use `curl.exe` on Windows in all Request blocks.

## Phase 6 — Executing Scenarios

For each `ai-e2e-tests/**/*.md` except `README.md` and `_manifest.md`:

1. Parse frontmatter → `expectedStatus`, `api`, `path`.
2. Extract curl command from fenced `## Request` block.
3. Execute command; parse `HTTP_CODE:` from output.
4. Validate status matches `expectedStatus`.
5. Validate `## Expected` bullets (body contains field, etc.).
6. Update frontmatter:

```yaml
lastRun: 2026-08-29T10:15:00Z
lastResult: pass
lastError: null
```

On failure:

```yaml
lastRun: 2026-08-29T10:15:00Z
lastResult: fail
lastError: "Expected 201, got 500 — NullReferenceException in handler"
```

## Scenario Dependencies

When scenario B needs output from scenario A:

- Document in A's `## Variables` section
- In B, use placeholder `{orderId}` and replace before curl execution
- Or run scenarios in dependency order (create before get)

## Do Not

- Commit automatically — user decides
- Store secrets or real credentials in scenarios — use test data
- Use PowerShell `Invoke-WebRequest` instead of curl
