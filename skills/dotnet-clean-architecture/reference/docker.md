# Docker and docker-compose

Every project includes multistage Dockerfiles for **Api** and **Migrator**, plus `SolutionItems/docker-compose.yml` with PostgreSQL.

Auxiliary compose and `.http` files: [project-layout.md](project-layout.md#solutionitems).
## Multistage Dockerfile (Api)

Place in `src/MyApp.Api/`:

```dockerfile
# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ["src/MyApp.Domain/MyApp.Domain.csproj", "MyApp.Domain/"]
COPY ["src/MyApp.Application/MyApp.Application.csproj", "MyApp.Application/"]
COPY ["src/MyApp.Infrastructure/MyApp.Infrastructure.csproj", "MyApp.Infrastructure/"]
COPY ["src/MyApp.Api/MyApp.Api.csproj", "MyApp.Api/"]

RUN dotnet restore "MyApp.Api/MyApp.Api.csproj"

COPY src/ .
WORKDIR "/src/MyApp.Api"
RUN dotnet publish "MyApp.Api.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app

RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

COPY --from=build /app/publish .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "MyApp.Api.dll"]
```

Migrator Dockerfile: see [migrations.md](migrations.md).

## docker-compose.yml

Place in **`SolutionItems/docker-compose.yml`** — not in the solution root.

Build `context` is the solution root (`..` relative to the compose file). Migrator runs once before Api. SQL scripts are **not** mounted to `docker-entrypoint-initdb.d`:

```yaml
# SolutionItems/docker-compose.yml
services:
  postgres:
    image: postgres:17-alpine
    container_name: myapp-postgres
    environment:
      POSTGRES_USER: myapp
      POSTGRES_PASSWORD: myapp
      POSTGRES_DB: myapp
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myapp -d myapp"]
      interval: 5s
      timeout: 5s
      retries: 5

  migrator:
    build:
      context: ..
      dockerfile: src/MyApp.Migrator/Dockerfile
    container_name: myapp-migrator
    environment:
      ConnectionStrings__DefaultConnection: "Host=postgres;Port=5432;Database=myapp;Username=myapp;Password=myapp"
    depends_on:
      postgres:
        condition: service_healthy
    restart: "no"

  api:
    build:
      context: ..
      dockerfile: src/MyApp.Api/Dockerfile
    container_name: myapp-api
    ports:
      - "8080:8080"
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ConnectionStrings__DefaultConnection: "Host=postgres;Port=5432;Database=myapp;Username=myapp;Password=myapp"
    depends_on:
      migrator:
        condition: service_completed_successfully

volumes:
  postgres_data:
```

Run from solution root:

```bash
docker compose -f SolutionItems/docker-compose.yml up --build
```
## appsettings for Docker

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=myapp;Username=myapp;Password=myapp"
  }
}
```

Local run uses `localhost`; `SolutionItems/docker-compose.yml` overrides via `ConnectionStrings__DefaultConnection` env var.

## .dockerignore

```
**/.git
**/.vs
**/bin
**/obj
**/.cursor
**/node_modules
```

## Bootstrap Checklist

```
MyApp/
├── MyApp.slnx
├── .dockerignore
├── SolutionItems/
│   ├── docker-compose.yml
│   └── MyApp.Api.http
└── src/
    MyApp.Migrator/
      Dockerfile
      Program.cs
    MyApp.Api/
      Dockerfile
```
## Rules

| Rule | Detail |
|------|--------|
| Compose location | `SolutionItems/docker-compose.yml` — not solution root |
| `.http` files | `SolutionItems/*.http` — REST Client / manual API tests |
| Multistage required | Separate `build` (sdk) and `final` (runtime/aspnet) stages || Migrator before Api | `api.depends_on.migrator: service_completed_successfully` |
| PostgreSQL only | Compose must include `postgres` service |
| Migrations via Migrator | Do not use `docker-entrypoint-initdb.d` for schema versioning |
| No User Secrets | Connection strings via env vars in compose |
| Port | Expose API on 8080 internally |
