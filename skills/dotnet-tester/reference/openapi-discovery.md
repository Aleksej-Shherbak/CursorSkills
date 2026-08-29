---
description: Fetch OpenAPI spec and produce test plan per Web API. Use in Phase 4 of dotnet-tester.
globs: "**/Properties/launchSettings.json, **/Program.cs, **/Controllers/**"
---

# OpenAPI Discovery (Phase 4)

For **each** discovered Web API project, fetch the OpenAPI document and publish a test plan.

## Resolve Base URL

1. If docker-compose is running → read `api` service `ports:` (host port)
2. Else → read `Properties/launchSettings.json`:

```json
"applicationUrl": "http://localhost:5089;https://localhost:7090"
```

Use the first `http://` URL.

Report: `Orders.Api → http://localhost:8080`

## Fetch OpenAPI Spec

Try URLs in order until one returns JSON:

| URL | Notes |
|-----|-------|
| `{base}/swagger/v1/swagger.json` | Swashbuckle default |
| `{base}/openapi/v1.json` | ASP.NET Core OpenAPI |
| `{base}/swagger/v1/swagger.yaml` | YAML variant |

Windows:

```powershell
curl.exe -s -w "`nHTTP_CODE:%{http_code}" http://localhost:8080/swagger/v1/swagger.json
```

If HTTP 404 on all → check if Swagger is disabled in Production; try `dotnet run` with Development environment or read controllers manually.

## Parse Spec

Extract per Api:

- `paths` — method + path + operationId
- `tags` — controller grouping
- Request body schema (required fields)
- Response codes (200, 201, 400, 404, 422, 409)

## Test Plan Template

Publish in agent response for each Web API:

```markdown
## Test Plan: Orders.Api

**Base URL:** http://localhost:8080
**OpenAPI:** /swagger/v1/swagger.json (12 endpoints)

### Smoke (run first)
| Method | Path | Expected | Notes |
|--------|------|----------|-------|
| GET | /swagger/index.html | 200 | UI reachable |
| GET | /api/orders | 200 | empty list OK |

### CRUD — Orders
| Method | Path | Expected | Depends on |
|--------|------|----------|------------|
| POST | /api/orders | 201 | — |
| GET | /api/orders/{id} | 200 | POST create |
| POST | /api/orders/{id}/cancel | 204 | POST create (pending order) |

### Error cases
| Method | Path | Body/Condition | Expected |
|--------|------|----------------|----------|
| GET | /api/orders/{random-guid} | — | 404 |
| POST | /api/orders/{id}/cancel | non-pending order | 422 |

### Auth-required (if any)
List endpoints with `[Authorize]` — mark as `manual / skip` unless test token provided.
```

## Expected Status Codes (Clean Architecture alignment)

| HTTP | Typical ErrorKind / cause |
|------|---------------------------|
| 200 | Success read |
| 201 | Created |
| 204 | Success no content (cancel, delete) |
| 400 | FluentValidation / bad input |
| 404 | NotFound |
| 409 | Conflict |
| 422 | Unprocessable (business rule) |
| 500 | Unexpected — investigate logs |

## Call Dependencies

Document chains for Phase 5 scenario creation:

```
1. POST /api/orders → capture response.id
2. GET /api/orders/{id} → verify same id
3. POST /api/orders/{id}/cancel → 204
4. GET /api/orders/{id} → status cancelled
```

Store captured IDs in scenario `## Variables` section or inline in curl with placeholder `{orderId}` replaced at runtime.

## Failure Report

```markdown
### OpenAPI failure: Orders.Api

- **URL tried:** http://localhost:8080/swagger/v1/swagger.json
- **Status:** connection refused
- **Likely cause:** Api not running
- **Suggested fix:** Start via docker compose or `dotnet run --project src/Orders.Api`
```
