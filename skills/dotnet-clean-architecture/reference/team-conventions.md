---
description: Mandatory stack rules, DTO formatting, secrets, SolutionItems, agent constraints, and DO NOT DO anti-patterns. Read first on every Clean Architecture task.
alwaysApply: true
---

# Team Conventions

Apply these conventions in every .NET project unless the repository explicitly overrides them.

## Mandatory Stack

| Area | Choice | Forbidden |
|------|--------|-----------|
| Presentation | Classic ASP.NET Core **Controllers** (`ControllerBase`) | Minimal API, `IEndpointGroup`, inline `MapGet`/`MapPost` |
| Use cases | **MediatR** handlers + pipeline behaviors | Direct service injection in controllers, god-services |
| Persistence | **Dapper** + raw SQL | ORM libraries, code-first migrations |
| Database | **PostgreSQL** only | SQL Server, SQLite, MySQL (unless user explicitly overrides) |
| Containerization | Multistage **Dockerfile** + **SolutionItems/docker-compose.yml** | Compose or `.http` in solution root; single-stage Dockerfiles |

## DTO and Model Formatting

Between each property in models, DTOs, and records, leave a blank line:

```csharp
public sealed class OrderDto
{
    public Guid Id { get; init; }

    public required string CustomerId { get; init; }

    public decimal Total { get; init; }

    public string Status { get; init; } = null!;
}
```

## Configuration and Secrets

- Do **not** use User Secrets (`dotnet user-secrets`, `AddUserSecrets`, `.csproj` UserSecretsId).
- Do **not** build workflows that depend on User Secrets.
- Use `appsettings.json` / `appsettings.{Environment}.json`, environment variables, or external secret stores configured by the deployment environment.
- In Docker, pass connection strings via environment variables in `SolutionItems/docker-compose.yml`.

## SolutionItems

Auxiliary solution files — **not** projects — live in **`SolutionItems/`** at the solution root:

| File | Path |
|------|------|
| docker-compose | `SolutionItems/docker-compose.yml` |
| REST Client `.http` | `SolutionItems/*.http` |

Never place `docker-compose.yml` or `.http` files in the solution root or under `src/`. Register them in `.slnx` under `/Solution Items/`. Details: [project-layout.md](project-layout.md#solutionitems).

## Agent Build Constraints

- Do **not** run `dotnet restore` — the developer runs restore/build locally (corporate VPN required).
- Do **not** run `dotnet build` unless the user explicitly asks.
- Do **not** run `docker compose up` unless the user explicitly asks.

## Microservices Monorepo

When the workspace contains multiple service folders (each with its own solution):

1. After each modifying action, state which service(s) were changed.
2. Prefer a summary table at the end of the response:

| Service | Changes |
|---------|---------|
| Orders.Api | Added OrdersController action |
| Orders.Infrastructure | Added OrderRepository (Dapper) |

## Versioning

When `Directory.Build.props` contains `<VersionPrefix>`:

1. Bump the version **once**, at the **end** of all work — not after every small edit.
2. Before bumping, check `git status`: if `<VersionPrefix>` is already increased in pending changes, do **not** bump again.
3. Use semantic versioning: patch for fixes, minor for features, major for breaking changes.

## Language and Stack

- Primary language: **C#** on **.NET 10**.
- **MediatR** for CQRS — handlers per use case, `ISender` in controllers, pipeline behaviors for validation/logging/transactions.
- Dapper for data access; Npgsql as PostgreSQL driver.
- SQL schema changes as numbered `.sql` scripts in `Infrastructure/Persistence/Sql/`.
- Applied by **`MyApp.Migrator`** (separate console app) — never on Api startup.

See [migrations.md](migrations.md).

## Program.cs and DI

- **`Program.cs` is minimal** — only `ConfigureServices()` + `ConfigurePipeline()` + `Run()`.
- Service registration and middleware go in `Api/Extensions/` — never grow `Program.cs`.
- **Each use case** lives in its own folder with models and `DependencyInjection.cs`.
- Root `Application/DependencyInjection.cs` orchestrates MediatR and calls `Add{UseCase}()` from each folder.

See [program-and-di.md](program-and-di.md).

## Logging

- **Serilog** → JSONL (`CompactJsonFormatter`).
- Three types: `inbound` (middleware), `outbound` (`ILoggingHttpClient`), `message` (`WriteMessage`).
- W3C `traceId` from `Activity.Current` — same for all logs in one HTTP request.
- Never raw `HttpClient` for external APIs.

See [logging.md](logging.md).

## DO NOT DO (Anti-Patterns)

Hard rules — violating these breaks Clean Architecture. See code examples in [SKILL.md](../SKILL.md#anti-patterns-do-not-do).

| ❌ Never | ✅ Instead |
|----------|-----------|
| Put repository **interfaces** in Infrastructure | Define `IOrderRepository` in **Application**; implement in Infrastructure |
| **Anemic entities** with public `{ get; set; }` on state | **Rich model** — `private set`, state changes via methods returning `Result` |
| Mutate entity state in handlers (`order.Status = …`) | Call domain methods (`order.Cancel()`) — entity validates invariants |
| Reference `Microsoft.AspNetCore.*`, `System.Web`, Dapper, Npgsql in **Domain** | Pure C# in Domain — no web, no persistence APIs |
| Inject `IOrderRepository`, services, or `HttpClient` directly in **controllers** | Controller depends only on **`ISender`** |
| Run migrations on **Api startup** or via `HostedService` | Separate **`MyApp.Migrator`** console app |
| Use **Minimal API** (`MapGet`, `MapPost`, `IEndpointGroup`) | Classic **Controllers** + MediatR |
| Use **ORM** (EF Core, etc.) or code-first migrations | **Dapper** + numbered `.sql` scripts |
| Put **HTTP status codes** or `IActionResult` logic in handlers | Handlers return **`Result` + `Error`**; Api maps to HTTP |
| Validate inside every handler manually | **`ValidationBehavior`** in MediatR pipeline |
| **Mapping** entity → DTO inline in handlers (large blocks) | Extension methods or dedicated mappers in Application |
| Log outbound HTTP via **DelegatingHandler** body buffering | **`ILoggingHttpClient`** decorator |
| Put `docker-compose.yml` or `.http` in solution root | **`SolutionItems/`** + register in `.slnx` |
| Use **User Secrets** | `appsettings` + environment variables |

When in doubt, add or extend a **NetArchTest** rule: [architecture-tests.md](architecture-tests.md). Entity rules: [domain-entities.md](domain-entities.md).
