# Program.cs and Dependency Injection

`Program.cs` stays **minimal** — only bootstrap. All service registration and middleware configuration live in extension methods.

Each **use case** lives in its own folder with models and a local `DependencyInjection.cs`.

## Clean Program.cs

`Program.cs` must contain **only** wiring calls — no `AddControllers`, no middleware, no business configuration:

```csharp
// Api/Program.cs
using MyApp.Api.Extensions;
using MyApp.Api.Logging;
using Serilog;

SerilogConfiguration.ConfigureBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);
    SerilogConfiguration.ConfigureHost(builder);
    builder.ConfigureServices();
    var app = builder.Build();
    app.ConfigurePipeline();
    app.Run();
}
finally
{
    Log.CloseAndFlush();
}
```

Serilog details: [logging.md](logging.md).

**Never** add new lines to `Program.cs` when adding features — extend use case folders or extension methods instead.

## Api Extension Methods

```csharp
// Api/Extensions/WebApplicationBuilderExtensions.cs
namespace MyApp.Api.Extensions;

public static class WebApplicationBuilderExtensions
{
    public static WebApplicationBuilder ConfigureServices(this WebApplicationBuilder builder)
    {
        builder.Services.AddControllers();
        builder.Services.AddApplication();
        builder.Services.AddInfrastructure(builder.Configuration);
        builder.Services.AddSingleton(TimeProvider.System);

        builder.Services.AddHttpContextAccessor();

        Activity.DefaultIdFormat = ActivityIdFormat.W3C;
        Activity.ForceDefaultIdFormat = true;

        builder.Services.AddExceptionHandler<ValidationExceptionHandler>();
        builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
        builder.Services.AddProblemDetails();

        return builder;
    }
}
```

```csharp
// Api/Extensions/WebApplicationExtensions.cs
namespace MyApp.Api.Extensions;

public static class WebApplicationExtensions
{
    public static WebApplication ConfigurePipeline(this WebApplication app)
    {
        app.UseExceptionHandler();
        app.UseMiddleware<InboundLoggingMiddleware>();
        app.UseHttpsRedirection();
        app.MapControllers();

        return app;
    }
}
```

Logging middleware and Serilog setup: [logging.md](logging.md). Exception handlers: [error-handling.md](error-handling.md).

| File | Responsibility |
|------|----------------|
| `Program.cs` | Create builder → ConfigureServices → Build → ConfigurePipeline → Run |
| `WebApplicationBuilderExtensions` | All `IServiceCollection` registration |
| `WebApplicationExtensions` | Middleware pipeline (`Use*`, `Map*`) |

Add new middleware only in `ConfigurePipeline` — not in `Program.cs`. Order: `UseExceptionHandler` → `InboundLoggingMiddleware` → `UseHttpsRedirection` → `MapControllers`.

## Use Case Folder Structure

Each use case is a **self-contained folder** with its own models and DI:

```
Application/
  Common/
    Behaviors/
      ValidationBehavior.cs
    Interfaces/
      IDbConnectionFactory.cs
      IOrderRepository.cs
  DependencyInjection.cs          # root: MediatR + pipeline + calls use cases

  Orders/
    CreateOrder/
      CreateOrderCommand.cs       # request model
      OrderItemDto.cs               # models for this use case
      CreateOrderHandler.cs
      CreateOrderValidator.cs
      DependencyInjection.cs        # registers this use case in DI

    GetOrder/
      GetOrderQuery.cs
      OrderDto.cs
      GetOrderHandler.cs
      DependencyInjection.cs

    CancelOrder/
      CancelOrderCommand.cs
      CancelOrderHandler.cs
      CancelOrderValidator.cs
      DependencyInjection.cs
```

**Rules:**

| Rule | Detail |
|------|--------|
| One folder = one use case | `CreateOrder/`, not shared `Commands/` bucket |
| Models stay in the folder | Command, Query, DTOs used only by this handler |
| `DependencyInjection.cs` per folder | Registers validators and use-case-specific services |
| Root `DependencyInjection.cs` | MediatR, pipeline behaviors, delegates to use cases |
| No shared DTO dumping ground | If DTO is reused across use cases, move to Domain or a shared Application contract deliberately |

## Per-Use-Case DependencyInjection

```csharp
// Application/Orders/CreateOrder/DependencyInjection.cs
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace MyApp.Application.Orders.CreateOrder;

public static class DependencyInjection
{
    public static IServiceCollection AddCreateOrder(this IServiceCollection services)
    {
        services.AddScoped<IValidator<CreateOrderCommand>, CreateOrderValidator>();

        return services;
    }
}
```

```csharp
// Application/Orders/GetOrder/DependencyInjection.cs
namespace MyApp.Application.Orders.GetOrder;

public static class DependencyInjection
{
    public static IServiceCollection AddGetOrder(this IServiceCollection services)
    {
        // Register use-case-specific services if needed
        return services;
    }
}
```

## Root Application DependencyInjection

Orchestrates MediatR, pipeline, and all use case modules:

```csharp
// Application/DependencyInjection.cs
using Microsoft.Extensions.DependencyInjection;
using MyApp.Application.Common.Behaviors;
using MyApp.Application.Orders.CancelOrder;
using MyApp.Application.Orders.CreateOrder;
using MyApp.Application.Orders.GetOrder;
using System.Reflection;

namespace MyApp.Application;

public static class DependencyInjection
{
    public static IServiceCollection AddApplication(this IServiceCollection services)
    {
        var assembly = Assembly.GetExecutingAssembly();

        services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(assembly));

        services.AddTransient(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));

        services
            .AddCreateOrder()
            .AddGetOrder()
            .AddCancelOrder();

        return services;
    }
}
```

When adding a new use case:

1. Create folder with Command/Query, Handler, models, Validator (if command).
2. Add `DependencyInjection.cs` with `Add{UseCase}()` extension.
3. Call `Add{UseCase}()` from root `Application/DependencyInjection.cs`.
4. Do **not** touch `Program.cs`.

## Infrastructure DI (same principle)

```csharp
// Infrastructure/DependencyInjection.cs — called from ConfigureServices, not Program.cs
public static IServiceCollection AddInfrastructure(
    this IServiceCollection services,
    IConfiguration configuration)
{
    services.AddSingleton<IDbConnectionFactory, NpgsqlConnectionFactory>();
    services.AddScoped<IOrderRepository, OrderRepository>();

    return services;
}
```

For large Infrastructure, split by concern (`AddPersistence()`, `AddExternalServices()`) in separate files under `Infrastructure/`.

## Anti-patterns

```csharp
// BAD — growing Program.cs
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
builder.Services.AddSwaggerGen();
builder.Services.AddCors(...);
builder.Services.AddApplication();
builder.Services.AddInfrastructure(builder.Configuration);
builder.Services.AddScoped<IValidator<CreateOrderCommand>, CreateOrderValidator>();
// ... 50 more lines

// BAD — validators registered in root DI instead of use case folder
// Application/DependencyInjection.cs
services.AddScoped<IValidator<CreateOrderCommand>, CreateOrderValidator>();

// BAD — flat handlers without use case folder
Application/CreateOrderHandler.cs
Application/CreateOrderCommand.cs

// GOOD — minimal Program.cs + use case module
builder.ConfigureServices();
app.ConfigurePipeline();
```
