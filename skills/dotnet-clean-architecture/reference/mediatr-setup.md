---
description: MediatR handlers, pipeline behaviors, ValidationBehavior, ISender in controllers. Use when adding or changing use cases.
globs: "**/Application/**, **/*Handler.cs, **/*Command.cs, **/*Query.cs, **/*Validator.cs"
---

# MediatR Setup

MediatR 12.x for .NET 10 — handlers, pipeline behaviors, and controller dispatch via `ISender`.

## Why MediatR

| Benefit | How |
|---------|-----|
| Decoupling | Controller sends a command/query; it does not depend on concrete handler classes |
| Single entry point | Each use case is one Handler class; MediatR resolves it by request type |
| Thin controllers | Controller depends only on `ISender` — not dozens of service interfaces |
| Pipeline behaviors | Validation, logging, transactions applied cross-cutting without changing handlers |

## Packages

**Application project:**

```xml
<PackageReference Include="MediatR" Version="12.*" />
<PackageReference Include="FluentValidation" Version="11.*" />
<PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.*" />
```

## Application DependencyInjection

Root file orchestrates MediatR, pipeline behaviors, and **per-use-case modules**:

```csharp
// Application/DependencyInjection.cs
using Microsoft.Extensions.DependencyInjection;
using MyApp.Application.Common.Behaviors;
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
            .AddGetOrder();

        return services;
    }
}
```

Each use case folder has its own `DependencyInjection.cs`:

```csharp
// Application/Orders/CreateOrder/DependencyInjection.cs
public static class DependencyInjection
{
    public static IServiceCollection AddCreateOrder(this IServiceCollection services)
    {
        services.AddScoped<IValidator<CreateOrderCommand>, CreateOrderValidator>();
        return services;
    }
}
```

Full Program.cs and DI rules: [program-and-di.md](program-and-di.md)

Add more pipeline behaviors in order (outermost first):

```csharp
services.AddTransient(typeof(IPipelineBehavior<,>), typeof(LoggingBehavior<,>));
services.AddTransient(typeof(IPipelineBehavior<,>), typeof(ValidationBehavior<,>));
services.AddTransient(typeof(IPipelineBehavior<,>), typeof(TransactionBehavior<,>));
```

## Validation Pipeline Behavior

Validation runs in the pipeline — handlers stay focused on business logic:

```csharp
// Application/Common/Behaviors/ValidationBehavior.cs
using FluentValidation;
using MediatR;

namespace MyApp.Application.Common.Behaviors;

public sealed class ValidationBehavior<TRequest, TResponse>(
    IEnumerable<IValidator<TRequest>> validators)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        if (!validators.Any())
            return await next();

        var context = new ValidationContext<TRequest>(request);

        var validationResults = await Task.WhenAll(
            validators.Select(v => v.ValidateAsync(context, cancellationToken)));

        var failures = validationResults
            .SelectMany(r => r.Errors)
            .Where(f => f is not null)
            .ToList();

        if (failures.Count != 0)
            throw new ValidationException(failures);

        return await next();
    }
}
```

## Use Case Folder Structure

Each use case is a self-contained folder with models and `DependencyInjection.cs`:

```
Application/
  Orders/
    CreateOrder/
      CreateOrderCommand.cs
      OrderItemDto.cs
      CreateOrderHandler.cs
      CreateOrderValidator.cs
      DependencyInjection.cs
    GetOrder/
      GetOrderQuery.cs
      OrderDto.cs
      GetOrderHandler.cs
      DependencyInjection.cs
```

See [program-and-di.md](program-and-di.md) for full DI and Program.cs rules.

## Command Pattern

```csharp
// Application/Orders/Commands/CreateOrder/CreateOrderCommand.cs
using MediatR;
using MyApp.Domain.Common;

namespace MyApp.Application.Orders.Commands.CreateOrder;

public sealed record CreateOrderCommand(
    string CustomerId,
    List<OrderItemDto> Items) : IRequest<Result<Guid>>;

public sealed record OrderItemDto(
    string ProductId,
    int Quantity,
    decimal UnitPrice);
```

```csharp
// Application/Orders/Commands/CreateOrder/CreateOrderHandler.cs
using MediatR;
using MyApp.Application.Common.Interfaces;
using MyApp.Domain.Common;
using MyApp.Domain.Entities;

namespace MyApp.Application.Orders.Commands.CreateOrder;

internal sealed class CreateOrderHandler(
    IOrderRepository orderRepository,
    TimeProvider clock)
    : IRequestHandler<CreateOrderCommand, Result<Guid>>
{
    public async Task<Result<Guid>> Handle(
        CreateOrderCommand request,
        CancellationToken cancellationToken)
    {
        var order = Order.Create(
            request.CustomerId,
            request.Items.Select(i => new OrderItem(i.ProductId, i.Quantity, i.UnitPrice)),
            clock.GetUtcNow());

        await orderRepository.AddAsync(order, cancellationToken);

        return Result.Success(order.Id);
    }
}
```

```csharp
// Application/Orders/Commands/CreateOrder/CreateOrderValidator.cs
using FluentValidation;

namespace MyApp.Application.Orders.Commands.CreateOrder;

public sealed class CreateOrderValidator : AbstractValidator<CreateOrderCommand>
{
    public CreateOrderValidator()
    {
        RuleFor(x => x.CustomerId).NotEmpty();

        RuleFor(x => x.Items).NotEmpty();

        RuleForEach(x => x.Items).ChildRules(item =>
        {
            item.RuleFor(x => x.ProductId).NotEmpty();
            item.RuleFor(x => x.Quantity).GreaterThan(0);
            item.RuleFor(x => x.UnitPrice).GreaterThan(0);
        });
    }
}
```

## Query Pattern (Dapper in Handler)

```csharp
// Application/Orders/Queries/GetOrder/GetOrderQuery.cs
using MediatR;
using MyApp.Domain.Common;

namespace MyApp.Application.Orders.Queries.GetOrder;

public sealed record GetOrderQuery(Guid OrderId) : IRequest<Result<OrderDto>>;

public sealed record OrderDto(
    Guid Id,
    string CustomerId,
    decimal Total,
    string Status,
    DateTimeOffset CreatedAt);
```

```csharp
// Application/Orders/Queries/GetOrder/GetOrderHandler.cs
using Dapper;
using MediatR;
using MyApp.Application.Common.Interfaces;
using MyApp.Domain.Common;

namespace MyApp.Application.Orders.Queries.GetOrder;

internal sealed class GetOrderHandler(IDbConnectionFactory connectionFactory)
    : IRequestHandler<GetOrderQuery, Result<OrderDto>>
{
    public async Task<Result<OrderDto>> Handle(
        GetOrderQuery request,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.CreateConnectionAsync(cancellationToken);

        const string sql = """
            SELECT id, customer_id AS CustomerId, total, status, created_at AS CreatedAt
            FROM orders
            WHERE id = @OrderId;
            """;

        var dto = await connection.QueryFirstOrDefaultAsync<OrderDto>(
            new CommandDefinition(sql, new { request.OrderId }, cancellationToken: cancellationToken));

        return dto is not null
            ? Result.Success(dto)
            : Result.Failure<OrderDto>(Error.NotFound("ORDER_NOT_FOUND", "Order not found"));
    }
}
```

## ISender in Controllers

Controller depends **only** on `ISender`:

```csharp
public sealed class OrdersController(ISender sender) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(
        [FromBody] CreateOrderCommand command,
        CancellationToken ct)
    {
        var result = await sender.Send(command, ct);
        return result.ToCreatedResult(this, nameof(Get), new { id = result.Value });
    }
}
```

See [controllers.md](controllers.md) for full controller pattern.

## Handler Conventions

| Rule | Detail |
|------|--------|
| Visibility | Handlers are `internal sealed` |
| One handler per use case | `{Action}{Entity}Handler` — no shared god-services |
| Return type | `Result` or `Result<T>` from Domain |
| Commands | Inject repository interfaces — validation in pipeline |
| Queries | Inject `IDbConnectionFactory` or read repository |
| Never inject | `NpgsqlConnection`, concrete repositories in Api layer |
| Validators | `AbstractValidator<TRequest>` — picked up by `ValidationBehavior` |

## Transaction Pipeline (Optional)

```csharp
// Application/Common/Behaviors/TransactionBehavior.cs
public sealed class TransactionBehavior<TRequest, TResponse>(
    IDbConnectionFactory connectionFactory)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : notnull
{
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        await using var connection = await connectionFactory.CreateConnectionAsync(cancellationToken);
        await using var transaction = connection.BeginTransaction();

        try
        {
            var response = await next();
            transaction.Commit();
            return response;
        }
        catch
        {
            transaction.Rollback();
            throw;
        }
    }
}
```

## Application Package Note for Query Handlers

If query handlers use Dapper directly, add to Application.csproj:

```xml
<PackageReference Include="Dapper" Version="2.*" />
```

## Anti-patterns

```csharp
// BAD — dozens of services in controller constructor
public class OrdersController(
    ICreateOrderService create,
    IGetOrderService get,
    ICancelOrderService cancel,
    IListOrdersService list) : ControllerBase

// BAD — validation duplicated in every handler
public async Task<Result<Guid>> Handle(...)
{
    var validation = await _validator.ValidateAsync(request);
    // ...
}

// GOOD — ISender + pipeline ValidationBehavior
public class OrdersController(ISender sender) : ControllerBase
```
