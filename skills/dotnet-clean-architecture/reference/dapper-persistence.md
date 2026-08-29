---
description: Dapper repositories, connection factory, parameterized SQL, PostgreSQL. Use when creating or changing persistence layer.
globs: "**/Infrastructure/Persistence/**, **/Infrastructure/**/Repositories/**, **/Application/**/Interfaces/**"
---

# Dapper Persistence (PostgreSQL)

Data access via **Dapper** and **PostgreSQL** only.

## Packages

**Application** — no Dapper/Npgsql packages (only interfaces).

**Infrastructure:**

```xml
<PackageReference Include="Dapper" Version="2.*" />
<PackageReference Include="Npgsql" Version="9.*" />
```

## Connection Factory Abstraction

Define in Application; implement in Infrastructure:

```csharp
// Application/Common/Interfaces/IDbConnectionFactory.cs
using System.Data;

namespace MyApp.Application.Common.Interfaces;

public interface IDbConnectionFactory
{
    Task<IDbConnection> CreateConnectionAsync(CancellationToken ct = default);
}
```

```csharp
// Infrastructure/Persistence/NpgsqlConnectionFactory.cs
using System.Data;
using Microsoft.Extensions.Configuration;
using MyApp.Application.Common.Interfaces;
using Npgsql;

namespace MyApp.Infrastructure.Persistence;

internal sealed class NpgsqlConnectionFactory(IConfiguration config) : IDbConnectionFactory
{
    private readonly string _connectionString = config.GetConnectionString("DefaultConnection")
        ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");

    public async Task<IDbConnection> CreateConnectionAsync(CancellationToken ct = default)
    {
        var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }
}
```

## Repository Interface (Application)

One interface per aggregate or bounded context — not a generic repository for every entity:

```csharp
// Application/Common/Interfaces/IOrderRepository.cs
using MyApp.Domain.Entities;

namespace MyApp.Application.Common.Interfaces;

public interface IOrderRepository
{
    Task<Order?> GetByIdAsync(Guid id, CancellationToken ct = default);

    Task AddAsync(Order order, CancellationToken ct = default);

    Task UpdateAsync(Order order, CancellationToken ct = default);
}
```

## Repository Implementation (Infrastructure)

```csharp
// Infrastructure/Persistence/Repositories/OrderRepository.cs
using Dapper;
using MyApp.Application.Common.Interfaces;
using MyApp.Domain.Entities;
using MyApp.Domain.Enums;

namespace MyApp.Infrastructure.Persistence.Repositories;

internal sealed class OrderRepository(IDbConnectionFactory connectionFactory) : IOrderRepository
{
    public async Task<Order?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        await using var connection = await connectionFactory.CreateConnectionAsync(ct);

        const string sql = """
            SELECT o.id, o.customer_id, o.status, o.total, o.created_at
            FROM orders o
            WHERE o.id = @Id;

            SELECT oi.id, oi.order_id, oi.product_id, oi.quantity, oi.unit_price
            FROM order_items oi
            WHERE oi.order_id = @Id;
            """;

        await using var multi = await connection.QueryMultipleAsync(new CommandDefinition(sql, new { Id = id }, cancellationToken: ct));

        var row = await multi.ReadFirstOrDefaultAsync<OrderRow>();
        if (row is null)
            return null;

        var itemRows = (await multi.ReadAsync<OrderItemRow>()).ToList();
        return MapToOrder(row, itemRows);
    }

    public async Task AddAsync(Order order, CancellationToken ct = default)
    {
        await using var connection = await connectionFactory.CreateConnectionAsync(ct);
        await using var transaction = connection.BeginTransaction();

        try
        {
            const string orderSql = """
                INSERT INTO orders (id, customer_id, status, total, created_at)
                VALUES (@Id, @CustomerId, @Status, @Total, @CreatedAt);
                """;

            await connection.ExecuteAsync(new CommandDefinition(orderSql, new
            {
                order.Id,
                order.CustomerId,
                Status = order.Status.ToString(),
                order.Total,
                order.CreatedAt
            }, transaction, cancellationToken: ct));

            const string itemSql = """
                INSERT INTO order_items (id, order_id, product_id, quantity, unit_price)
                VALUES (@Id, @OrderId, @ProductId, @Quantity, @UnitPrice);
                """;

            foreach (var item in order.Items)
            {
                await connection.ExecuteAsync(new CommandDefinition(itemSql, new
                {
                    item.Id,
                    OrderId = order.Id,
                    item.ProductId,
                    item.Quantity,
                    item.UnitPrice
                }, transaction, cancellationToken: ct));
            }

            transaction.Commit();
        }
        catch
        {
            transaction.Rollback();
            throw;
        }
    }

    public async Task UpdateAsync(Order order, CancellationToken ct = default)
    {
        await using var connection = await connectionFactory.CreateConnectionAsync(ct);

        const string sql = """
            UPDATE orders
            SET status = @Status, total = @Total
            WHERE id = @Id;
            """;

        await connection.ExecuteAsync(new CommandDefinition(sql, new
        {
            order.Id,
            Status = order.Status.ToString(),
            order.Total
        }, cancellationToken: ct));
    }

    private static Order MapToOrder(OrderRow row, List<OrderItemRow> items) =>
        Order.Restore(row.Id, row.CustomerId, Enum.Parse<OrderStatus>(row.Status), row.Total, row.CreatedAt, items);

    private sealed record OrderRow(Guid Id, string CustomerId, string Status, decimal Total, DateTimeOffset CreatedAt);

    private sealed record OrderItemRow(Guid Id, Guid OrderId, string ProductId, int Quantity, decimal UnitPrice);
}
```

Domain entity needs a `Restore` factory for rehydration from DB (separate from `Create`):

```csharp
public static Order Restore(
    Guid id, string customerId, OrderStatus status, decimal total,
    DateTimeOffset createdAt, IEnumerable<OrderItemRow> items)
{
    var order = new Order { Id = id, CustomerId = customerId, Status = status, Total = total, CreatedAt = createdAt };
    foreach (var item in items)
        order._items.Add(new OrderItem(item.ProductId, item.Quantity, item.UnitPrice));
    return order;
}
```

## Query Handlers with Dapper

Query handlers implement `IRequestHandler` and may use `IDbConnectionFactory`:

```csharp
internal sealed class GetOrderHandler(IDbConnectionFactory connectionFactory)
    : IRequestHandler<GetOrderQuery, Result<OrderDto>>
{
    public async Task<Result<OrderDto>> Handle(GetOrderQuery request, CancellationToken ct)
    {
        await using var connection = await connectionFactory.CreateConnectionAsync(ct);
        // parameterized SQL via Dapper ...
    }
}
```

| Use case | Data access |
|----------|-------------|
| Command with domain behavior | `IOrderRepository` via command handler |
| Simple read / projection | Query handler with Dapper |
| Complex reusable query | Dedicated read repository interface |

## Schema Migrations

Migrations are **SQL scripts** in `Infrastructure/Persistence/Sql/`. Applied by **`MyApp.Migrator`** — a separate console app.

Api never runs migrations. Full guide: [migrations.md](migrations.md)

## DI Registration

```csharp
// Infrastructure/DependencyInjection.cs
public static IServiceCollection AddInfrastructure(
    this IServiceCollection services,
    IConfiguration config)
{
    services.AddSingleton<IDbConnectionFactory, NpgsqlConnectionFactory>();
    services.AddScoped<IOrderRepository, OrderRepository>();

    return services;
}
```

## Anti-patterns

```csharp
// BAD — concrete NpgsqlConnection injected in Application handler
public class CreateOrderHandler(NpgsqlConnection conn) { }

// BAD — SQL in Api or Domain layer

// GOOD — Dapper SQL in Infrastructure repositories; query handlers use IDbConnectionFactory
```
