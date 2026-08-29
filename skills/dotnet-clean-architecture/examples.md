# Examples

End-to-end scenarios for applying the dotnet-clean-architecture skill.

## Example 1: Bootstrap a New API

**User prompt:** "Create a new Orders API with Clean Architecture for .NET 10."

**Agent steps:**

1. Create solution with 4 projects: `Orders.Domain`, `Orders.Application`, `Orders.Infrastructure`, `Orders.Api`.
2. Add Domain: `Entity`, `Result`, `Order` (rich model — `private set`, `Create`, behavior methods), `OrderItem`, `OrderStatus`.
3. Add Application use case folders (`CreateOrder/` with models, Handler, Validator, `DependencyInjection.cs`).
4. Wire use cases in root `Application/DependencyInjection.cs` via `AddCreateOrder()`, etc.
5. Add Infrastructure: Dapper repositories, SQL scripts in `Persistence/Sql/`.
6. Add Migrator: `MyApp.Migrator` console app, DbUp runner, Dockerfile.
7. Add Api: minimal `Program.cs`, extensions, `OrdersController(ISender)`.
8. Add `SolutionItems/docker-compose.yml`: `postgres` → `migrator` → `api`.
9. Add `SolutionItems/MyApp.Api.http` for manual API requests.
10. Add `MyApp.Architecture.Tests` with NetArchTest.Rules layer dependency tests.
11. No User Secrets. No `dotnet restore`.

**Expected structure:**

```
Orders/
├── Orders.slnx
├── .dockerignore
├── SolutionItems/
│   ├── docker-compose.yml
│   └── Orders.Api.http
├── src/
│   Orders.Infrastructure/
│     Persistence/Sql/0002_create_orders.sql
│   Orders.Migrator/
│     Program.cs
│     Dockerfile
│   Orders.Application/
│     Orders/CreateOrder/
│       CreateOrderCommand.cs
│       OrderItemDto.cs
│       CreateOrderHandler.cs
│       CreateOrderValidator.cs
│       DependencyInjection.cs
│   Orders.Api/
│     Program.cs
│     Extensions/WebApplicationBuilderExtensions.cs
│     Controllers/OrdersController.cs
└── tests/
    Orders.Architecture.Tests/
```

## Example 2: Refactor Fat Controller to MediatR Handlers

**Before (anti-pattern):**

```csharp
[ApiController]
[Route("api/orders")]
public class OrdersController(IDbConnection conn) : ControllerBase
{
    [HttpPost]
    public async Task<IActionResult> Create(CreateOrderRequest req)
    {
        var order = new Order { CustomerId = req.CustomerId };
        order.Total = req.Items.Sum(i => i.Price * i.Qty);
        await conn.ExecuteAsync("INSERT INTO orders ...", order);
        return Created($"/api/orders/{order.Id}", order.Id);
    }
}
```

**After (target):**

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
}
```

Handler in Application:

```csharp
internal sealed class CreateOrderHandler(IOrderRepository repo, TimeProvider clock)
    : IRequestHandler<CreateOrderCommand, Result<Guid>> { ... }
```

## Example 3: Add Cancel Order Feature

**User prompt:** "Add cancel order endpoint — only pending orders can be cancelled."

**Agent steps:**

1. **Domain** — `Cancel()` on `Order` returning `Result`.
2. **Application** — `Orders/Commands/CancelOrder/`:
   - `CancelOrderCommand(Guid OrderId) : IRequest<Result>`
   - `CancelOrderHandler` — load via repository, call `order.Cancel()`, update
   - `CancelOrderValidator`
3. **Api** — add action to existing controller:

```csharp
[HttpPost("{id:guid}/cancel")]
public async Task<IActionResult> Cancel(Guid id, CancellationToken ct)
{
    var result = await sender.Send(new CancelOrderCommand(id), ct);
    return result.ToNoContentResult();
}
```

No new controller dependencies — still only `ISender`.

## Example 4: Add Transaction Pipeline Behavior

**User prompt:** "Wrap all commands in a database transaction."

**Agent steps:**

1. Create `TransactionBehavior<TRequest, TResponse>` in `Application/Common/Behaviors/`.
2. Register before or after `ValidationBehavior` in `DependencyInjection.cs`.
3. Handlers remain unchanged — transaction is cross-cutting via pipeline.

## Example 5: Add SQL Migration

**User prompt:** "Add index on orders.customer_id."

**Agent steps:**

1. Create `Infrastructure/Persistence/Sql/0004_add_orders_customer_id_index.sql`.
2. Do not edit already-applied scripts — add a new numbered file.
3. Run `dotnet run --project src/MyApp.Migrator` or `docker compose run migrator`.
4. Api code unchanged.

## Example 6: Docker Local Development

See [docker.md](reference/docker.md) and [migrations.md](reference/migrations.md) — `postgres` → `migrator` → `api`.

## Example 7: Return Specific HTTP Status from Handler

**User prompt:** "Cancel order should return 422 if order is not pending."

**Agent steps:**

1. Domain `Cancel()` returns `Result.Failure(Error.Unprocessable("ORDER_NOT_PENDING", "..."))`.
2. Handler propagates Result — no HTTP logic.
3. Controller: `return result.ToNoContentResult();`
4. `ResultExtensions` maps `ErrorKind.Unprocessable` → 422 automatically.

Do **not** add status code logic to handler or controller.

## Example 8: Refactor Anemic Entity to Rich Model

**User prompt:** "Order entity has public setters — refactor to rich domain model."

**Before (anti-pattern):**

```csharp
public class Order : Entity
{
    public string CustomerId { get; set; } = null!;
    public OrderStatus Status { get; set; }
    public decimal Total { get; set; }
}

// CancelOrderHandler — business rule in wrong layer
order.Status = OrderStatus.Cancelled;
```

**After (target):**

1. **Domain** — `private set`, `Create`/`Restore`, `Cancel()` returns `Result`.
2. **Handler** — load → `order.Cancel()` → persist; never assign `Status`.
3. **Repository** — map rows via `Order.Restore(...)`, persist after valid transitions.

Full guide: [domain-entities.md](reference/domain-entities.md)
