---
description: docker-compose lifecycle, health checks, log analysis for dotnet-tester Phase 3. Use when starting or diagnosing containers.
globs: "**/docker-compose*.yml, **/SolutionItems/**"
---

# docker-compose (Phase 3)

## Locate Compose File

Priority (relative to solution root):

1. `SolutionItems/docker-compose.yml`
2. `SolutionItems/docker-compose*.yml`
3. `docker-compose.yml`

If not found → skip Phase 3, note in verdict `Docker | SKIP | no compose file`. Use `dotnet run` for Phases 4–6.

## Start Stack

```powershell
docker compose -f "<ComposePath>" up --build -d
```

Wait for services to stabilize (10–30 s), then inspect:

```powershell
docker compose -f "<ComposePath>" ps
docker compose -f "<ComposePath>" logs postgres --tail 20
docker compose -f "<ComposePath>" logs migrator --tail 50
docker compose -f "<ComposePath>" logs api --tail 50
```

## Expected State (Clean Architecture convention)

| Service | Expected |
|---------|----------|
| postgres | `healthy` or `running`, port 5432 mapped |
| migrator | `exited (0)` — ran once, applied SQL scripts |
| api | `running`, port mapped (e.g. 8080) |

Typical startup order: `postgres` → `migrator` → `api` (depends_on + healthcheck).

## Health Verification

```powershell
# Postgres ready
docker compose -f "<ComposePath>" exec postgres pg_isready -U myapp -d myapp

# Api responding
curl.exe -s -o NUL -w "%{http_code}" http://localhost:8080/swagger/index.html
```

Adjust user/db/port to match compose environment variables.

## Failure Report Template

```markdown
### Docker failure: migrator

- **Service:** migrator
- **Status:** exited (1)
- **Log excerpt:**
  ```
  Npgsql.NpgsqlException: Connection refused
  ```
- **Likely cause:** postgres not healthy before migrator started
- **Suggested fix:** Check postgres healthcheck; verify ConnectionStrings__DefaultConnection in migrator environment
```

Common issues:

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Port already allocated | Local postgres on 5432 | Change host port in compose or stop local service |
| migrator exit 1 | Bad connection string / SQL error | Check env vars and latest `.sql` script |
| api crash loop | Missing env / bad config | Read api logs, verify ASPNETCORE_URLS |
| build failed | Dockerfile path wrong | Verify `context: ..` and dockerfile path |

## Teardown

Run **only** when user did not ask to keep stack running:

```powershell
docker compose -f "<ComposePath>" down
```

Add `-v` only if user explicitly wants to reset volumes.

## Skip Conditions

Skip Phase 3 when:

- User said "skip docker"
- No compose file found
- Docker daemon not running (report: install/start Docker Desktop)

When skipped but Phases 4–6 needed, start Api manually:

```powershell
dotnet run --project src/Orders.Api/Orders.Api.csproj
```
