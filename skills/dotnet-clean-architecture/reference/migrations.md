# Database Migrations (SQL Scripts + Migrator)

Migrations are **versioned SQL scripts** stored in Infrastructure. They are applied by a **separate console app** `MyApp.Migrator` — never by the Web API at startup.

## Principles

| Rule | Detail |
|------|--------|
| Migrations = `.sql` files | Plain SQL, numbered, idempotent where possible |
| Separate Migrator project | Single responsibility; Api does not mutate schema |
| No HostedService migrations | Never run migrations in `MyApp.Api` on startup |
| Api = DML only | Api connects with app user; Migrator may use DDL-capable user |
| Source of truth | `Infrastructure/Persistence/Sql/` — not `docker-entrypoint-initdb.d` |

## Solution Structure

```
src/
  MyApp.Infrastructure/
    Persistence/
      Sql/
        0001_create_schema_migrations.sql
        0002_create_orders.sql
        0003_create_order_items.sql
      Migrations/
        MigrationRunner.cs

  MyApp.Migrator/                  # Console app — only entry point for migrations
    Program.cs
    appsettings.json
    Dockerfile
    MyApp.Migrator.csproj

  MyApp.Api/                       # No migration code
```

## SQL Script Conventions

```
Infrastructure/Persistence/Sql/
  0001_create_schema_migrations.sql
  0002_create_orders.sql
  0003_create_order_items.sql
  0004_add_orders_index.sql
```

| Rule | Detail |
|------|--------|
| Prefix | Zero-padded number: `0001_`, `0002_` — execution order by filename |
| Naming | `{number}_{short_description}.sql` |
| One concern per file | One table/alteration per script when practical |
| PostgreSQL syntax | `TIMESTAMPTZ`, `UUID`, `NUMERIC(18,2)` |
| Idempotency | Prefer `CREATE TABLE IF NOT EXISTS` for initial scripts; alters are sequential |

Example `0002_create_orders.sql`:

```sql
CREATE TABLE IF NOT EXISTS orders (
    id          UUID PRIMARY KEY,
    customer_id TEXT            NOT NULL,
    status      TEXT            NOT NULL,
    total       NUMERIC(18, 2)  NOT NULL,
    created_at  TIMESTAMPTZ     NOT NULL
);
```

Example `0003_create_order_items.sql`:

```sql
CREATE TABLE IF NOT EXISTS order_items (
    id         UUID PRIMARY KEY,
    order_id   UUID           NOT NULL REFERENCES orders (id),
    product_id TEXT           NOT NULL,
    quantity   INTEGER        NOT NULL,
    unit_price NUMERIC(18, 2) NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_order_items_order_id ON order_items (order_id);
```

Copy SQL files to Migrator output:

```xml
<!-- MyApp.Migrator.csproj -->
<ItemGroup>
  <None Include="..\MyApp.Infrastructure\Persistence\Sql\*.sql"
        Link="Sql\%(Filename)%(Extension)"
        CopyToOutputDirectory="PreserveNewest" />
</ItemGroup>
```

## MigrationRunner (Infrastructure)

Use **DbUp** in Infrastructure to apply scripts and track applied versions:

```xml
<!-- MyApp.Infrastructure.csproj -->
<PackageReference Include="dbup-postgresql" Version="6.*" />
```

Migrator references Infrastructure and copies SQL files to output — see `MyApp.Migrator.csproj` in [project-layout.md](project-layout.md).

```csharp
// Infrastructure/Persistence/Migrations/MigrationRunner.cs
using DbUp;
using DbUp.Engine;

namespace MyApp.Infrastructure.Persistence.Migrations;

public static class MigrationRunner
{
    public static int Run(string connectionString, string scriptsPath)
    {
        EnsureDatabase.For.PostgresqlDatabase(connectionString);

        UpgradeEngine upgrader = DeployChanges.To
            .PostgresqlDatabase(connectionString)
            .WithScriptsFromFileSystem(scriptsPath)
            .JournalToPostgresqlTable("public", "schema_migrations")
            .LogToConsole()
            .Build();

        var result = upgrader.PerformUpgrade();

        if (!result.Successful)
        {
            Console.ForegroundColor = ConsoleColor.Red;
            Console.WriteLine(result.Error);
            Console.ResetColor();
            return 1;
        }

        Console.ForegroundColor = ConsoleColor.Green;
        Console.WriteLine("Migration successful.");
        Console.ResetColor();
        return 0;
    }
}
```

## Migrator Program.cs

Keep minimal — same philosophy as Api `Program.cs`:

```csharp
// MyApp.Migrator/Program.cs
using Microsoft.Extensions.Configuration;
using MyApp.Infrastructure.Persistence.Migrations;

var configuration = new ConfigurationBuilder()
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json", optional: false)
    .AddEnvironmentVariables()
    .Build();

var connectionString = configuration.GetConnectionString("DefaultConnection")
    ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");

var scriptsPath = Path.Combine(AppContext.BaseDirectory, "Sql");

return MigrationRunner.Run(connectionString, scriptsPath);
```

```json
// MyApp.Migrator/appsettings.json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=myapp;Username=myapp;Password=myapp"
  }
}
```

## docker-compose

File: **`SolutionItems/docker-compose.yml`**. Full template: [docker.md](docker.md).

Migrator runs **once** before Api starts. Do **not** mount SQL to `docker-entrypoint-initdb.d`:

```yaml
# SolutionItems/docker-compose.yml
services:
  postgres:
    image: postgres:17-alpine
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
    ports:
      - "8080:8080"
    environment:
      ConnectionStrings__DefaultConnection: "Host=postgres;Port=5432;Database=myapp;Username=myapp;Password=myapp"
    depends_on:
      migrator:
        condition: service_completed_successfully

volumes:
  postgres_data:
```

## Migrator Dockerfile

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY ["src/MyApp.Infrastructure/MyApp.Infrastructure.csproj", "MyApp.Infrastructure/"]
COPY ["src/MyApp.Migrator/MyApp.Migrator.csproj", "MyApp.Migrator/"]
COPY ["src/MyApp.Domain/MyApp.Domain.csproj", "MyApp.Domain/"]
COPY ["src/MyApp.Application/MyApp.Application.csproj", "MyApp.Application/"]

RUN dotnet restore "MyApp.Migrator/MyApp.Migrator.csproj"

COPY src/ .
WORKDIR "/src/MyApp.Migrator"
RUN dotnet publish "MyApp.Migrator.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/runtime:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "MyApp.Migrator.dll"]
```

## CI/CD

```
1. deploy postgres (or use managed PostgreSQL)
2. run MyApp.Migrator          ← apply pending SQL scripts
3. deploy MyApp.Api            ← only after migrator succeeds
```

Local manual run:

```powershell
dotnet run --project src/MyApp.Migrator
```

## Adding a New Migration

1. Create `Infrastructure/Persistence/Sql/0005_description.sql`.
2. Write forward-only SQL (ALTER, CREATE INDEX, etc.).
3. Run Migrator locally or via compose.
4. Do **not** edit already-applied scripts — add a new numbered file instead.

## Anti-patterns

```csharp
// BAD — migrations on Api startup
builder.Services.AddHostedService<MigrationHostedService>();

// BAD — Api Program.cs applies SQL
await ApplyMigrationsAsync(app.Services);

// BAD — docker-entrypoint-initdb.d as the only migration mechanism
//       (runs only on empty volume, bypasses version tracking)

// BAD — manual "run this sql" without Migrator in CI/CD

// GOOD — separate MyApp.Migrator, SQL scripts, schema_migrations journal
dotnet run --project src/MyApp.Migrator
```

## Project References

```
MyApp.Migrator  → MyApp.Infrastructure (MigrationRunner)
MyApp.Api         → no reference to Migrator, no migration code
```
