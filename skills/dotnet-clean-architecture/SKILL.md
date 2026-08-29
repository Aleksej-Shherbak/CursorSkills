---
name: dotnet-clean-architecture
description: >
  Enforces Clean Architecture for .NET 10: 4-project layout (Domain, Application,
  Infrastructure, Api), dependency inversion, MediatR handlers with pipeline
  behaviors, rich domain entities with invariants and encapsulation, Dapper + PostgreSQL persistence, classic
  ASP.NET Core controllers, multistage Dockerfile and docker-compose. Use when
  scaffolding, refactoring, or reviewing .NET backends, layered architecture,
  CQRS, MediatR, Dapper, PostgreSQL, Docker, or Clean Architecture.
disable-model-invocation: true
---

# Clean Architecture for .NET

Apply this skill when building, refactoring, or reviewing .NET 10 backends with Clean Architecture.

**Always read** [team-conventions.md](reference/team-conventions.md) for mandatory stack rules and project-specific conventions.

## Agent Mode — Reference Routing

Reference files include **frontmatter** (`description`, `globs`) — pull the matching doc when editing files in that area:

| When working on… | Read |
|------------------|------|
| Any task | [team-conventions.md](reference/team-conventions.md) |
| Scaffolding / csproj / `.slnx` | [project-layout.md](reference/project-layout.md) |
| Handlers, validators, MediatR | [mediatr-setup.md](reference/mediatr-setup.md) |
| Domain entities, invariants, rich model | [domain-entities.md](reference/domain-entities.md) |
| Repositories, SQL, Dapper | [dapper-persistence.md](reference/dapper-persistence.md) |
| Controllers, endpoints | [controllers.md](reference/controllers.md) |
| Errors, Result mapping | [error-handling.md](reference/error-handling.md) |
| Logging, HttpClient | [logging.md](reference/logging.md) |
| Program.cs, DI | [program-and-di.md](reference/program-and-di.md) |
| Migrations, Migrator | [migrations.md](reference/migrations.md) |
| Docker, compose | [docker.md](reference/docker.md) |
| Architecture tests | [architecture-tests.md](reference/architecture-tests.md) |

Full anti-pattern list: [team-conventions.md — DO NOT DO](reference/team-conventions.md#do-not-do-anti-patterns).

## Mandatory Stack

| Area | Use | Never use |
|------|-----|-----------|
| API | Classic **Controllers** (`ControllerBase`) + **`ISender`** | Minimal API, `MapGet`/`MapPost`, `IEndpointGroup` |
| Use cases | **MediatR** handlers (`IRequest` / `IRequestHandler`) + pipeline behaviors | Direct service injection in controllers, god-services |
| Data access | **Dapper** + parameterized SQL | ORM libraries, code-first migrations |
| Database | **PostgreSQL** | Other databases (unless user explicitly overrides) |
| DevOps | Multistage **Dockerfile** + **docker-compose** + **Migrator** | Migrations in Api startup, `docker-entrypoint-initdb.d` for schema |
| Logging | **Serilog** JSONL — `inbound`, `outbound`, `message` + W3C traceId | Unstructured logs, raw `HttpClient`, `DelegatingHandler` for bodies |

## Core Principles

1. **Dependency inversion is the foundation** — All dependencies point inward. Domain has zero project references. Application references only Domain. Infrastructure references Application and Domain. Api references all but depends on abstractions.
2. **Domain owns the rules** — Entities are **rich models**: state + behavior, invariants enforced inside the entity, state changes only through methods (small state machines). Never anemic `{ get; set; }` DTOs. Pure C# only — no Dapper, no HTTP, no database APIs.
3. **Use cases are the unit of work** — Each use case is a MediatR handler in Application. MediatR resolves the handler by request type. Cross-cutting concerns (validation, logging, transactions) go into pipeline behaviors.
4. **Infrastructure is a plugin** — Dapper repositories, Npgsql, external APIs — all live in Infrastructure and implement interfaces from Application.
5. **The API layer is thin** — Controllers depend only on `ISender`. `Program.cs` stays minimal; configuration lives in extension methods.

## Clean Program.cs

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.ConfigureServices();
var app = builder.Build();
app.ConfigurePipeline();
app.Run();
```

Never register services or middleware directly in `Program.cs`. Details: [program-and-di.md](reference/program-and-di.md)

## Use Case Folders

Each use case = one folder with models + `DependencyInjection.cs`:

```
Application/Orders/CreateOrder/
  CreateOrderCommand.cs
  OrderItemDto.cs
  CreateOrderHandler.cs
  CreateOrderValidator.cs
  DependencyInjection.cs
```

Root `Application/DependencyInjection.cs` calls `AddCreateOrder()`, `AddGetOrder()`, etc.

## Project Layout

```
MyApp/
├── MyApp.slnx
├── .dockerignore
├── SolutionItems/
│   ├── docker-compose.yml
│   └── MyApp.Api.http
└── src/
    MyApp.Domain/
    MyApp.Application/
    MyApp.Infrastructure/
    MyApp.Migrator/          # SQL migrations runner
    MyApp.Api/             # minimal Program.cs, Extensions/, Controllers/
```

Full structure: [project-layout.md](reference/project-layout.md)

## MediatR Use Cases

```csharp
// Command
public sealed record CreateOrderCommand(
    string CustomerId,
    List<OrderItemDto> Items) : IRequest<Result<Guid>>;

// Handler — validation runs in ValidationBehavior pipeline
internal sealed class CreateOrderHandler(
    IOrderRepository orderRepository,
    TimeProvider clock)
    : IRequestHandler<CreateOrderCommand, Result<Guid>>
{
    public async Task<Result<Guid>> Handle(CreateOrderCommand request, CancellationToken ct)
    {
        var order = Order.Create(/* ... */);
        await orderRepository.AddAsync(order, ct);
        return Result.Success(order.Id);
    }
}
```

Registration (in use case folder + root orchestrator):

```csharp
// Application/Orders/CreateOrder/DependencyInjection.cs
services.AddScoped<IValidator<CreateOrderCommand>, CreateOrderValidator>();

// Application/DependencyInjection.cs
services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(assembly));
services.AddTransient(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));
services.AddCreateOrder().AddGetOrder();
```

Full MediatR patterns, pipeline behaviors: [mediatr-setup.md](reference/mediatr-setup.md)

## Dapper + Repository Abstraction

All relational database access goes through **Dapper** in Infrastructure. PostgreSQL via **Npgsql**.

| Layer | Responsibility |
|-------|----------------|
| Application | `IOrderRepository`, `IDbConnectionFactory` interfaces |
| Infrastructure | Dapper implementations, parameterized SQL |
| Migrator | Applies versioned `.sql` scripts (DbUp) — separate console app |
| Domain | No database code |

```csharp
public interface IOrderRepository
{
    Task<Order?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task AddAsync(Order order, CancellationToken ct = default);
    Task UpdateAsync(Order order, CancellationToken ct = default);
}
```

Full patterns (connection factory, repositories, SQL scripts): [dapper-persistence.md](reference/dapper-persistence.md)

## Migrations (SQL Scripts + Migrator)

Schema changes are **numbered SQL files** in `Infrastructure/Persistence/Sql/`. Applied by **`MyApp.Migrator`** — never by Api.

```
Infrastructure/Persistence/Sql/
  0001_create_schema_migrations.sql
  0002_create_orders.sql
  0003_create_order_items.sql

MyApp.Migrator/          # console app, runs before Api in docker-compose
  Program.cs
  Dockerfile
```

```powershell
dotnet run --project src/MyApp.Migrator
```

Never use `HostedService` or Api startup to run migrations.

Full guide: [migrations.md](reference/migrations.md)

## Domain Entity — Rich Model

Entities are **rich models**, not anemic DTOs. State and behavior live together; invalid transitions are rejected inside the entity. Think of each aggregate as a **small state machine** — only valid transitions via explicit methods.

Full guide: [domain-entities.md](reference/domain-entities.md)

```csharp
public sealed class Order : Entity
{
    private readonly List<OrderItem> _items = [];

    public OrderStatus Status { get; private set; }

    public IReadOnlyCollection<OrderItem> Items => _items.AsReadOnly();

    public static Order Create(string customerId, IEnumerable<OrderItem> items, DateTimeOffset now)
    {
        // invariants at birth — non-empty customer, items, valid total
    }

    public Result Cancel()
    {
        if (Status is not OrderStatus.Pending)
            return Result.Failure(Error.Unprocessable(
                "ORDER_NOT_PENDING",
                "Only pending orders can be cancelled"));

        Status = OrderStatus.Cancelled;
        return Result.Success();
    }
}
```

**Never** `order.Status = …` in handlers. **Always** `order.Cancel()` (or equivalent domain method).

## Error Handling

Handlers return `Result.Failure(Error(...))` — **never** HTTP status codes. Api maps `ErrorKind` → status:

| ErrorKind | HTTP |
|-----------|------|
| `NotFound` | 404 |
| `Unprocessable` | 422 |
| `Conflict` | 409 |
| `Forbidden` | 403 |

```csharp
return Result.Failure(Error.NotFound("ORDER_NOT_FOUND", "Order not found"));
return result.ToActionResult(); // Api reads Error.Kind
```

FluentValidation → `ValidationException` → 400 via exception handler. Unexpected → 500.

Full guide: [error-handling.md](reference/error-handling.md)

## Logging

Three log types — all **JSONL** via **Serilog**, shared **W3C traceId** per request:

| Type | Source | `message` |
|------|--------|-----------|
| `inbound` | `InboundLoggingMiddleware` | empty `""` |
| `outbound` | `ILoggingHttpClient` decorator | empty `""` |
| `message` | `IStructuredLogWriter.WriteMessage()` in handlers | non-empty |

Never use raw `HttpClient` for external calls — always `ILoggingHttpClient`.

Full guide: [logging.md](reference/logging.md)

## Thin Controllers (ISender only)

```csharp
[ApiController]
[Route("api/[controller]")]
public sealed class OrdersController(ISender sender) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreateOrderCommand command, CancellationToken ct)
    {
        var result = await sender.Send(command, ct);
        return result.ToCreatedResult(this, nameof(Get), new { id = result.Value });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct)
    {
        var result = await sender.Send(new GetOrderQuery(id), ct);
        return result.ToActionResult();
    }
}
```

Controller rules: [controllers.md](reference/controllers.md)

## Docker

Every new project: multistage `Dockerfile` in `src/`, `SolutionItems/docker-compose.yml`, `SolutionItems/*.http` for API requests.

Templates: [docker.md](reference/docker.md)

## Architecture Tests

Bootstrap **`MyApp.Architecture.Tests`** with **NetArchTest.Rules** — enforce layer dependencies so violations fail CI (and agent can self-correct when user runs tests).

Minimum rules: Domain → no Application/Infrastructure/AspNetCore; Application → no Infrastructure; repository interfaces in Application only.

Full suite: [architecture-tests.md](reference/architecture-tests.md)

## Anti-Patterns (DO NOT DO)

See full table: [team-conventions.md](reference/team-conventions.md#do-not-do-anti-patterns).

### Anemic entity with public setters

```csharp
// BAD — anyone can corrupt state
public class Order
{
    public OrderStatus Status { get; set; }
}

// handler bypasses domain rules
order.Status = OrderStatus.Cancelled;

// GOOD — rich model, transition via method
public OrderStatus Status { get; private set; }
var result = order.Cancel();
```

See [domain-entities.md](reference/domain-entities.md).

### Repository interface in Infrastructure

```csharp
// BAD — interface in Infrastructure
namespace MyApp.Infrastructure.Persistence;
public interface IOrderRepository { ... }

// GOOD — interface in Application, implementation in Infrastructure
namespace MyApp.Application.Common.Interfaces;
public interface IOrderRepository { ... }
```

### AspNetCore or Dapper in Domain

```csharp
// BAD
using Microsoft.AspNetCore.Http;
using Dapper;

namespace MyApp.Domain.Entities;

// GOOD — pure C# only in Domain
namespace MyApp.Domain.Entities;
```

### Mapping bloated inside handler

```csharp
// BAD — 30 lines of DTO mapping in Handle()
public async Task<Result<OrderDto>> Handle(GetOrderQuery request, CancellationToken ct)
{
    var order = await repo.GetByIdAsync(request.Id, ct);
    return new OrderDto { Id = order.Id, /* ... */ };
}

// GOOD — extension or static mapper in Application
return order.ToDto();
```

### Direct Service Injection in Controller

```csharp
// BAD — controller depends on many services
public class OrdersController(
    ICreateOrderService create, IGetOrderService get, ICancelOrderService cancel) : ControllerBase

// GOOD — single ISender, MediatR dispatches to handler
public class OrdersController(ISender sender) : ControllerBase
{
    await sender.Send(command, ct);
}
```

### Validation in Handler Instead of Pipeline

```csharp
// BAD — duplicated validation in every handler
var validation = await _validator.ValidateAsync(request, ct);

// GOOD — ValidationBehavior in MediatR pipeline
```

### Minimal API and Fat Controller

See [team-conventions.md](reference/team-conventions.md).

## Decision Guide

| Scenario | Recommendation |
|----------|---------------|
| Use case implementation | MediatR Command/Query + Handler + Validator |
| Domain entity | Rich model — `private set`, methods return `Result`, no public state mutation |
| Cross-cutting concerns | `IPipelineBehavior<,>` (validation, logging, transactions) |
| Command persistence | `IOrderRepository` with Dapper in Infrastructure |
| Read-only query | Handler with `IDbConnectionFactory` + Dapper |
| Use case organization | One folder per use case: models + Handler + Validator + `DependencyInjection.cs` |
| Program.cs | Minimal bootstrap only; `ConfigureServices()` / `ConfigurePipeline()` extensions |
| Controller dependencies | `ISender` only |
| Schema changes | New numbered `.sql` file + run `MyApp.Migrator` |
| Migrations execution | Separate `MyApp.Migrator` — not Api startup |
| Business / not found errors | `Result.Failure(Error.NotFound(...))` etc. → `ResultExtensions` |
| Specific HTTP status from handler | Set `ErrorKind` on `Error` — never status code in handler |
| Inbound HTTP logging | `InboundLoggingMiddleware` — one JSONL entry per request |
| Outbound HTTP logging | `ILoggingHttpClient` decorator — not DelegatingHandler |
| Diagnostic/business log | `IStructuredLogWriter.WriteMessage()` — type `message` |
| Input validation errors | FluentValidation → `ValidationExceptionHandler` → 400 |
| Unexpected errors | `GlobalExceptionHandler` → 500 |

## Workflow Checklist

```
- [ ] Domain: Error, ErrorKind, Result types
- [ ] Domain: rich entities — private setters, Create/Restore, behavior methods returning Result
- [ ] Domain: no public mutation of entity state from handlers
- [ ] Application: use case folder (models + Handler + Validator + DependencyInjection.cs)
- [ ] Application: register use case in root DependencyInjection.cs (Add{UseCase}())
- [ ] Application: ValidationBehavior in MediatR pipeline
- [ ] Infrastructure: Dapper repositories
- [ ] Infrastructure: SQL migration scripts in Persistence/Sql/
- [ ] Migrator: MyApp.Migrator console app + Dockerfile
- [ ] SolutionItems: docker-compose.yml + *.http (not in solution root)
- [ ] docker-compose: postgres → migrator → api
- [ ] Api: ResultExtensions + exception handlers
- [ ] Api: Serilog JSONL + InboundLoggingMiddleware in ConfigurePipeline
- [ ] Infrastructure: IStructuredLogWriter + ILoggingHttpClient decorator
- [ ] Api: Program.cs minimal; services in ConfigureServices, pipeline in ConfigurePipeline
- [ ] Docker: multistage Dockerfile + docker-compose with PostgreSQL
- [ ] No User Secrets; no dotnet restore
- [ ] Architecture tests: MyApp.Architecture.Tests + NetArchTest layer rules
- [ ] Bump VersionPrefix once at end if Directory.Build.props exists
```

End-to-end scenarios: [examples.md](examples.md)

## Additional Resources

- [migrations.md](reference/migrations.md) — SQL scripts, Migrator, DbUp
- [program-and-di.md](reference/program-and-di.md) — clean Program.cs, per-use-case DI
- [mediatr-setup.md](reference/mediatr-setup.md) — handlers, pipeline behaviors, ISender
- [project-layout.md](reference/project-layout.md) — solution structure and csproj
- [domain-entities.md](reference/domain-entities.md) — rich model, invariants, state machines
- [dapper-persistence.md](reference/dapper-persistence.md) — Dapper, repositories, SQL
- [controllers.md](reference/controllers.md) — ApiController + ISender
- [docker.md](reference/docker.md) — Dockerfile, docker-compose
- [error-handling.md](reference/error-handling.md) — Error, ErrorKind, exception handlers, HTTP mapping
- [logging.md](reference/logging.md) — Serilog JSONL, inbound/outbound/message, W3C traceId
- [result-pattern.md](reference/result-pattern.md) — Result quick reference
- [architecture-tests.md](reference/architecture-tests.md) — NetArchTest.Rules layer dependency tests
- [team-conventions.md](reference/team-conventions.md) — mandatory stack, DTO spacing, DO NOT DO anti-patterns

---

Inspired by [dotnet-claude-kit](https://github.com/codewithmukesh/dotnet-claude-kit), adapted for Cursor Agent with MediatR, Dapper, PostgreSQL, Controllers, and Docker.
