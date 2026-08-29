# Classic Controllers

ASP.NET Core MVC controllers — **not** Minimal API. Controllers depend **only on `ISender`** (MediatR).

Error mapping: [error-handling.md](error-handling.md)

## Program.cs

Keep `Program.cs` minimal — see [program-and-di.md](program-and-di.md):

```csharp
// Api/Program.cs
using MyApp.Api.Extensions;

var builder = WebApplication.CreateBuilder(args);
builder.ConfigureServices();
var app = builder.Build();
app.ConfigurePipeline();
app.Run();
```

**Never** register services or middleware directly in `Program.cs`.

## Thin Controller Pattern

```csharp
// Api/Controllers/OrdersController.cs
using MediatR;
using Microsoft.AspNetCore.Mvc;
using MyApp.Api.Extensions;
using MyApp.Application.Orders.CancelOrder;
using MyApp.Application.Orders.CreateOrder;
using MyApp.Application.Orders.Queries.GetOrder;

namespace MyApp.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
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

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> Get(Guid id, CancellationToken ct)
    {
        var result = await sender.Send(new GetOrderQuery(id), ct);
        return result.ToActionResult();
    }

    [HttpPost("{id:guid}/cancel")]
    public async Task<IActionResult> Cancel(Guid id, CancellationToken ct)
    {
        var result = await sender.Send(new CancelOrderCommand(id), ct);
        return result.ToNoContentResult();
    }
}
```

No try/catch in controllers — validation and unexpected errors handled by exception handlers.

## Result Mapping Extensions

Maps `Error.Kind` → HTTP status. Full implementation: [error-handling.md](error-handling.md)

```csharp
// Api/Extensions/ResultExtensions.cs — simplified
public static IActionResult ToActionResult<T>(this Result<T> result) =>
    result.IsSuccess
        ? new OkObjectResult(result.Value)
        : result.Error!.ToProblemDetailsResult();

public static IActionResult ToNoContentResult(this Result result) =>
    result.IsSuccess
        ? new NoContentResult()
        : result.Error!.ToProblemDetailsResult();

// ErrorKind.NotFound → 404, Unprocessable → 422, Conflict → 409, etc.
```

## Controller Rules

| Rule | Detail |
|------|--------|
| Inject **`ISender` only** | Never inject handlers or repositories |
| Dispatch | `await sender.Send(commandOrQuery, ct)` |
| Map result | `result.ToActionResult()` / `ToCreatedResult` / `ToNoContentResult` |
| No try/catch | Exception handlers cover ValidationException and 500 |
| No status logic | Never `return NotFound()` based on string — use `Result` + extensions |

## Anti-patterns

```csharp
// BAD — manual status from handler message
if (result.Error == "Not found") return NotFound();

// BAD — HTTP logic in controller
return result.IsFailure ? StatusCode(422, result.Error) : Ok(result.Value);

// GOOD — Error.Kind drives status in ResultExtensions
return result.ToActionResult();
```
