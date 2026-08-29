---
description: Rich domain entities — invariants, encapsulation, state machines, factory methods. Use when creating or changing Domain entities and business rules.
globs: "**/Domain/**, **/Entities/**, **/Enums/**"
---

# Domain Entities (Rich Model)

Entities in **Domain** are **rich models** — not anemic DTOs with public `{ get; set; }` that anyone can mutate into an invalid state.

## Rich Model vs Anemic DTO

| Anemic (forbidden) | Rich model (required) |
|--------------------|----------------------|
| Public setters on state (`Status`, `Total`, …) | `private set` or no setter — state changes only through methods |
| Handler sets `order.Status = Cancelled` | Handler calls `order.Cancel()` — entity validates the transition |
| Validation scattered in Application | **Invariants live in the entity** |
| State + data, no behavior | **State + behavior** — encapsulation hides how state changes |

```csharp
// BAD — anemic entity, inconsistent state is possible
public class Order
{
    public Guid Id { get; set; }
    public OrderStatus Status { get; set; }  // anyone can set Completed on empty order
    public decimal Total { get; set; }
}

// handler anti-pattern
order.Status = OrderStatus.Cancelled;  // no invariant check
```

```csharp
// GOOD — rich entity, invalid transitions rejected
public sealed class Order : Entity
{
    public OrderStatus Status { get; private set; }

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

## Entity as a Small State Machine

Treat each aggregate as a **finite state machine**:

- **States** — enum values (`OrderStatus.Pending`, `Cancelled`, `Completed`).
- **Transitions** — explicit methods (`Cancel()`, `Complete()`, `Ship()`).
- **Valid transition** — method succeeds, state changes, related behavior may run (recalculate total, raise domain event, etc.).
- **Invalid transition** — method returns `Result.Failure(Error(...))` — state **unchanged**.

```
        Create()
Pending --------Cancel()--------> Cancelled
   |
   +--------Complete()--------> Completed
```

Rules:

1. No “jump” between arbitrary states from outside — only through named methods.
2. Each method documents which transitions it allows.
3. Side effects of a valid transition stay **inside** the entity (or domain service called from entity).

Handlers **orchestrate** (load → call entity method → persist). They **do not** assign entity state directly.

## Encapsulation

Rich model = **state hidden behind behavior**.

| Mechanism | Purpose |
|-----------|---------|
| `private set` on properties | External code reads state, cannot mutate |
| `private` / `internal` constructors | Cannot `new Order()` bypassing invariants |
| `public static Create(...)` | New aggregate — all invariants checked at birth |
| `public static Restore(...)` | Rehydration from DB — Infrastructure only; not for business logic |
| Private collections + `IReadOnlyCollection` | Cannot add/remove items without entity method |
| `Result` from mutating methods | Expected rule violations without exceptions |

```csharp
public sealed class Order : Entity
{
    private readonly List<OrderItem> _items = [];

    private Order() { CustomerId = string.Empty; }

    public string CustomerId { get; private set; }

    public IReadOnlyCollection<OrderItem> Items => _items.AsReadOnly();

    public static Order Create(string customerId, IEnumerable<OrderItem> items, DateTimeOffset now)
    {
        // invariants at creation: non-empty customer, at least one item, total >= 0
        var itemList = items.ToList();
        if (string.IsNullOrWhiteSpace(customerId))
            throw new DomainException("CustomerId is required."); // or Result if preferred for Create

        return new Order
        {
            Id = Guid.NewGuid(),
            CustomerId = customerId,
            Status = OrderStatus.Pending,
            Total = itemList.Sum(i => i.UnitPrice * i.Quantity),
            CreatedAt = now
        };
    }

    public static Order Restore(/* persistence shape */) { /* no business rules — trust DB */ }
}
```

**Create** vs **Restore**:

- **`Create`** — business constructor; enforces all invariants for new aggregates.
- **`Restore`** — maps persistence → entity; used by Infrastructure repository after read. Does not re-run creation rules.

## Invariants

**Invariant** — condition that must always be true for the aggregate.

Examples:

- Order total equals sum of line items.
- Cancelled order cannot become Completed.
- Order must have at least one item when Pending.

Where invariants live:

| Layer | Responsibility |
|-------|----------------|
| **Entity methods** | Business invariants, state transitions |
| **FluentValidation** (Application) | Input shape — required fields, formats, ranges on DTOs/commands |
| **Handler** | Orchestration only — not `if (order.Status == …)` business rules |

Move repeated cross-entity rules to **domain services** in Domain — still pure C#, no Infrastructure.

## Entity Base Class

```csharp
// Domain/Common/Entity.cs
namespace MyApp.Domain.Common;

public abstract class Entity
{
    public Guid Id { get; protected init; }
}
```

All aggregates inherit `Entity`. Identity (`Id`) set only in `Create` / `Restore`.

## Handler Pattern with Rich Entity

```csharp
internal sealed class CancelOrderHandler(IOrderRepository orderRepository)
    : IRequestHandler<CancelOrderCommand, Result>
{
    public async Task<Result> Handle(CancelOrderCommand request, CancellationToken ct)
    {
        var order = await orderRepository.GetByIdAsync(request.OrderId, ct);
        if (order is null)
            return Result.Failure(Error.NotFound("ORDER_NOT_FOUND", "Order not found"));

        var cancelResult = order.Cancel();   // entity decides — not the handler
        if (cancelResult.IsFailure)
            return cancelResult;

        await orderRepository.UpdateAsync(order, ct);
        return Result.Success();
    }
}
```

Repository **persists** entity state after valid transitions — never applies business rules.

## Anti-Patterns

```csharp
// BAD — handler mutates entity state
order.Status = OrderStatus.Cancelled;
await orderRepository.UpdateAsync(order, ct);

// BAD — public setter on domain entity
public OrderStatus Status { get; set; }

// BAD — validation of business rules only in handler
if (order.Status != OrderStatus.Pending)
    return Result.Failure(...);  // belongs in order.Cancel()

// BAD — Domain entity looks like EF/database model
public class Order { public List<OrderItem> Items { get; set; } = []; }

// GOOD
var result = order.Cancel();
if (result.IsFailure) return result;
await orderRepository.UpdateAsync(order, ct);
```

## Checklist for New Entity

```
- [ ] No public setters on state properties
- [ ] Private parameterless ctor (or protected for inheritance)
- [ ] static Create(...) for new instances with invariants
- [ ] static Restore(...) for repository rehydration
- [ ] State changes only via methods returning Result
- [ ] Collections exposed as IReadOnlyCollection; mutations via entity methods
- [ ] Handlers call entity methods — never assign Status/Total/etc.
```

## Related

- [error-handling.md](error-handling.md) — `Result`, `Error`, `ErrorKind` in domain methods
- [result-pattern.md](result-pattern.md) — when to use Result vs exceptions
- [dapper-persistence.md](dapper-persistence.md) — `Restore` in repository mapping
- [team-conventions.md](team-conventions.md#do-not-do-anti-patterns) — DO NOT DO table
