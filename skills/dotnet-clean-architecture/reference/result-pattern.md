---
description: Result, Error, ErrorKind quick reference. Use when returning failures from handlers or domain logic.
globs: "**/Result.cs, **/Error*.cs, **/ErrorKind.cs"
---

# Result Pattern

Structured `Result` with `Error` + `ErrorKind` in Domain. Api maps `ErrorKind` to HTTP status.

Full error handling guide: [error-handling.md](error-handling.md)

## Domain Types

See [error-handling.md](error-handling.md) for complete `Error`, `ErrorKind`, and `Result` implementations.

Quick reference:

```csharp
// Success
return Result.Success();
return Result.Success(orderId);

// Failure with semantic kind
return Result.Failure(Error.NotFound("ORDER_NOT_FOUND", "Order not found"));
return Result.Failure(Error.Unprocessable("ORDER_NOT_PENDING", "Only pending orders can be cancelled"));
return Result.Failure<OrderDto>(Error.NotFound("ORDER_NOT_FOUND", "Order not found"));
```

## Usage in Domain

```csharp
public Result Cancel()
{
    if (Status is not OrderStatus.Pending)
        return Result.Failure(Error.Unprocessable(
            "ORDER_NOT_PENDING",
            "Only pending orders can be cancelled"));

    Status = OrderStatus.Cancelled;
    return Result.Success();
}
```

## Usage in Handlers

```csharp
public async Task<Result<Guid>> Handle(CreateOrderCommand request, CancellationToken ct)
{
    var order = Order.Create(/* ... */);
    await orderRepository.AddAsync(order, ct);
    return Result.Success(order.Id);
}

public async Task<Result<OrderDto>> Handle(GetOrderQuery request, CancellationToken ct)
{
    // ...
    return dto is not null
        ? Result.Success(dto)
        : Result.Failure<OrderDto>(Error.NotFound("ORDER_NOT_FOUND", "Order not found"));
}
```

## HTTP Mapping in Controllers

All failures go through `ResultExtensions` — maps `Error.Kind` to status code:

```csharp
var result = await sender.Send(command, ct);
return result.ToCreatedResult(this, nameof(Get), new { id = result.Value });

var result = await sender.Send(new GetOrderQuery(id), ct);
return result.ToActionResult(); // 200 or 404/422/409 based on Error.Kind

var result = await sender.Send(new CancelOrderCommand(id), ct);
return result.ToNoContentResult(); // 204 or error status from Error.Kind
```

## When to Use Result vs Exceptions

| Scenario | Approach |
|----------|----------|
| Invalid input (format, required fields) | FluentValidation → `ValidationException` → 400 |
| Expected business rule violation | `Result.Failure(Error.Unprocessable(...))` |
| Entity not found | `Result.Failure(Error.NotFound(...))` |
| Duplicate / conflict | `Result.Failure(Error.Conflict(...))` |
| Access denied | `Result.Failure(Error.Forbidden(...))` |
| Unexpected infrastructure failure | Let exception propagate → 500 |
| Programming errors | Exception — not Result |

## Do Not Use

- `Result.Failure(string message)` — always use `Error` with `Kind` and `Code`
- HTTP status codes in Domain or Application layers
- `throw` for expected business outcomes
