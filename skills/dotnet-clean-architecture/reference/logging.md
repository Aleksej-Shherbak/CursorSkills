---
description: Serilog JSONL logging — inbound, outbound, message types, W3C traceId. Use when adding middleware, HTTP client, or structured logs.
globs: "**/Logging/**, **/*Middleware*.cs, **/*HttpClient*.cs, **/Serilog*.cs"
---

# Logging (Serilog, JSONL, W3C Trace)

Structured logging with **Serilog** → **JSONL** (one JSON object per line). Three log types: **inbound**, **outbound**, **message**. All logs within one HTTP request share the same **W3C traceId**.

## Log Types

| Type | When | `message` field | Required fields |
|------|------|-----------------|-----------------|
| `inbound` | HTTP request hits our Api | empty string `""` | traceId, url, status, requestBody, responseBody, durationMs |
| `outbound` | Our service calls external HTTP API | empty string `""` | traceId, url, status, requestBody, responseBody, durationMs |
| `message` | Application/infrastructure event | **non-empty** | traceId, message |

All fields are written in **one log entry** per inbound/outbound call — not split across multiple lines.

## JSONL Output Shape

```json
{"@t":"2026-08-29T08:48:00.123Z","type":"inbound","traceId":"4bf92f3577b34da6a3ce929d0e0e4736","message":"","url":"/api/orders","method":"POST","status":201,"requestBody":"{\"customerId\":\"c1\"}","responseBody":"\"guid\"","durationMs":42}
{"@t":"2026-08-29T08:48:00.456Z","type":"outbound","traceId":"4bf92f3577b34da6a3ce929d0e0e4736","message":"","url":"https://payments.example/charge","method":"POST","status":200,"requestBody":"{...}","responseBody":"{...}","durationMs":120}
{"@t":"2026-08-29T08:48:00.789Z","type":"message","traceId":"4bf92f3577b34da6a3ce929d0e0e4736","message":"Order created successfully","url":null,"status":null,"requestBody":null,"responseBody":null,"durationMs":null}
```

Nulls may be omitted for `message`-type logs — use Serilog destructuring or explicit nulls consistently per project.

## W3C Trace Context

Every inbound request gets a W3C-compatible trace. All logs (inbound, outbound, message) within that request use the same `traceId`.

```csharp
// Api/Extensions/WebApplicationBuilderExtensions.cs — in ConfigureServices
builder.Services.AddHttpContextAccessor();

// Enable W3C Activity IDs (do once at startup)
Activity.DefaultIdFormat = ActivityIdFormat.W3C;
Activity.ForceDefaultIdFormat = true;
```

TraceId source in code:

```csharp
// Prefer Activity.Current (W3C traceparent)
public static string GetTraceId() =>
    Activity.Current?.TraceId.ToString()
    ?? Activity.Current?.RootId
    ?? "unknown";
```

Outbound calls **propagate** trace context to downstream systems:

```csharp
var traceParent = Activity.Current?.Id; // W3C traceparent format
if (traceParent is not null)
    request.Headers.TryAddWithoutValidation("traceparent", traceParent);
```

## Serilog Setup

Serilog in **Api** (composition root). JSONL to console; add file/async sink in production if needed.

```xml
<!-- MyApp.Api.csproj -->
<PackageReference Include="Serilog.AspNetCore" Version="9.*" />
<PackageReference Include="Serilog.Formatting.Compact" Version="3.*" />
```

```csharp
// Api/Logging/SerilogConfiguration.cs
using Serilog;
using Serilog.Formatting.Compact;

namespace MyApp.Api.Logging;

public static class SerilogConfiguration
{
    public static void ConfigureBootstrapLogger() =>
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Information()
            .Enrich.FromLogContext()
            .WriteTo.Console(new CompactJsonFormatter())
            .CreateBootstrapLogger();

    public static void ConfigureHost(WebApplicationBuilder builder) =>
        builder.Host.UseSerilog((context, services, configuration) => configuration
            .ReadFrom.Configuration(context.Configuration)
            .ReadFrom.Services(services)
            .Enrich.FromLogContext()
            .Enrich.WithProperty("application", "MyApp.Api")
            .WriteTo.Console(new CompactJsonFormatter()));
}
```

```csharp
// Api/Program.cs
using MyApp.Api.Logging;
using Serilog;

SerilogConfiguration.ConfigureBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);
    SerilogConfiguration.ConfigureHost(builder);
    // ...
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}
```

```json
// appsettings.json (optional overrides)
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft.AspNetCore": "Warning"
      }
    }
  }
}
```

## Log Model and Writer

Define a single writer in **Infrastructure** (or Api if preferred — Infrastructure keeps Serilog details):

```csharp
// Infrastructure/Logging/LogType.cs
namespace MyApp.Infrastructure.Logging;

public static class LogType
{
    public const string Inbound = "inbound";
    public const string Outbound = "outbound";
    public const string Message = "message";
}
```

```csharp
// Infrastructure/Logging/IStructuredLogWriter.cs
namespace MyApp.Infrastructure.Logging;

public interface IStructuredLogWriter
{
    void WriteInbound(InboundLogEntry entry);

    void WriteOutbound(OutboundLogEntry entry);

    void WriteMessage(string message, string? traceId = null);
}

public sealed record InboundLogEntry(
    string TraceId,
    string Url,
    string Method,
    int Status,
    string RequestBody,
    string ResponseBody,
    long DurationMs);

public sealed record OutboundLogEntry(
    string TraceId,
    string Url,
    string Method,
    int Status,
    string RequestBody,
    string ResponseBody,
    long DurationMs);
```

```csharp
// Infrastructure/Logging/SerilogStructuredLogWriter.cs
using Serilog;

namespace MyApp.Infrastructure.Logging;

internal sealed class SerilogStructuredLogWriter : IStructuredLogWriter
{
    public void WriteInbound(InboundLogEntry entry) =>
        Log.Information(
            "{Type} {TraceId} {Url} {Method} {Status} {RequestBody} {ResponseBody} {DurationMs} {Message}",
            LogType.Inbound,
            entry.TraceId,
            entry.Url,
            entry.Method,
            entry.Status,
            entry.RequestBody,
            entry.ResponseBody,
            entry.DurationMs,
            string.Empty);

    public void WriteOutbound(OutboundLogEntry entry) =>
        Log.Information(
            "{Type} {TraceId} {Url} {Method} {Status} {RequestBody} {ResponseBody} {DurationMs} {Message}",
            LogType.Outbound,
            entry.TraceId,
            entry.Url,
            entry.Method,
            entry.Status,
            entry.RequestBody,
            entry.ResponseBody,
            entry.DurationMs,
            string.Empty);

    public void WriteMessage(string message, string? traceId = null) =>
        Log.Information(
            "{Type} {TraceId} {Message}",
            LogType.Message,
            traceId ?? TraceIdProvider.Current,
            message);
}
```

```csharp
// Infrastructure/Logging/TraceIdProvider.cs
using System.Diagnostics;

namespace MyApp.Infrastructure.Logging;

public static class TraceIdProvider
{
    public static string Current =>
        Activity.Current?.TraceId.ToString() ?? "unknown";
}
```

Register in Infrastructure DI:

```csharp
services.AddSingleton<IStructuredLogWriter, SerilogStructuredLogWriter>();
```

Application handlers inject `IStructuredLogWriter` for **message** logs only — not inbound/outbound (those are automatic).

## 1. Inbound Logging (Middleware)

Use **middleware** — not filters, not manual logging in controllers. One log entry per request with all fields.

```csharp
// Infrastructure/Logging/InboundLoggingMiddleware.cs
using System.Diagnostics;
using System.Text;
using Microsoft.AspNetCore.Http;

namespace MyApp.Infrastructure.Logging;

public sealed class InboundLoggingMiddleware(
    RequestDelegate next,
    IStructuredLogWriter logWriter)
{
    private const int MaxBodySize = 64 * 1024;

    public async Task InvokeAsync(HttpContext context)
    {
        var sw = Stopwatch.StartNew();
        var traceId = Activity.Current?.TraceId.ToString() ?? "unknown";

        var requestBody = await ReadRequestBodyAsync(context.Request);

        var originalBody = context.Response.Body;
        await using var responseBuffer = new MemoryStream();
        context.Response.Body = responseBuffer;

        try
        {
            await next(context);
        }
        finally
        {
            sw.Stop();
            var responseBody = await ReadResponseBodyAsync(responseBuffer);

            responseBuffer.Position = 0;
            await responseBuffer.CopyToAsync(originalBody);
            context.Response.Body = originalBody;

            logWriter.WriteInbound(new InboundLogEntry(
                TraceId: traceId,
                Url: $"{context.Request.Path}{context.Request.QueryString}",
                Method: context.Request.Method,
                Status: context.Response.StatusCode,
                RequestBody: requestBody,
                ResponseBody: responseBody,
                DurationMs: sw.ElapsedMilliseconds));
        }
    }

    private static async Task<string> ReadRequestBodyAsync(HttpRequest request)
    {
        request.EnableBuffering();
        request.Body.Position = 0;
        using var reader = new StreamReader(request.Body, Encoding.UTF8, leaveOpen: true);
        var body = await reader.ReadToEndAsync();
        request.Body.Position = 0;
        return Truncate(body);
    }

    private static async Task<string> ReadResponseBodyAsync(MemoryStream stream)
    {
        stream.Position = 0;
        using var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);
        return Truncate(await reader.ReadToEndAsync());
    }

    private static string Truncate(string value) =>
        value.Length <= MaxBodySize ? value : value[..MaxBodySize] + "...[truncated]";
}
```

Register in `ConfigurePipeline` **after** `UseExceptionHandler`, **before** `MapControllers`:

```csharp
app.UseMiddleware<InboundLoggingMiddleware>();
```

Skip paths if needed (health checks):

```csharp
if (context.Request.Path.StartsWithSegments("/health"))
{
    await next(context);
    return;
}
```

## 2. Outbound Logging (HttpClient Decorator)

Do **not** use `DelegatingHandler` to parse bodies — use an explicit **decorator** that reads body once per call.

```csharp
// Infrastructure/Http/ILoggingHttpClient.cs
namespace MyApp.Infrastructure.Http;

public interface ILoggingHttpClient
{
    Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken = default);
}
```

```csharp
// Infrastructure/Http/LoggingHttpClient.cs
using System.Diagnostics;
using MyApp.Infrastructure.Logging;

namespace MyApp.Infrastructure.Http;

internal sealed class LoggingHttpClient(
    HttpClient httpClient,
    IStructuredLogWriter logWriter) : ILoggingHttpClient
{
    public async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken = default)
    {
        var sw = Stopwatch.StartNew();
        var traceId = Activity.Current?.TraceId.ToString() ?? "unknown";

        PropagateTraceContext(request);

        var requestBody = request.Content is not null
            ? await request.Content.ReadAsStringAsync(cancellationToken)
            : string.Empty;

        var response = await httpClient.SendAsync(request, cancellationToken);

        sw.Stop();

        var responseBody = response.Content is not null
            ? await response.Content.ReadAsStringAsync(cancellationToken)
            : string.Empty;

        logWriter.WriteOutbound(new OutboundLogEntry(
            TraceId: traceId,
            Url: request.RequestUri?.ToString() ?? string.Empty,
            Method: request.Method.Method,
            Status: (int)response.StatusCode,
            RequestBody: requestBody,
            ResponseBody: responseBody,
            DurationMs: sw.ElapsedMilliseconds));

        return response;
    }

    private static void PropagateTraceContext(HttpRequestMessage request)
    {
        var traceParent = Activity.Current?.Id;
        if (traceParent is not null)
            request.Headers.TryAddWithoutValidation("traceparent", traceParent);
    }
}
```

Register typed client:

```csharp
// Infrastructure/DependencyInjection.cs
services.AddHttpClient<ILoggingHttpClient, LoggingHttpClient>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(30);
});
```

Or named client per external system:

```csharp
services.AddHttpClient("PaymentGateway", client =>
{
    client.BaseAddress = new Uri(config["PaymentGateway:BaseUrl"]!);
})
.AddTypedClient<ILoggingHttpClient>((httpClient, sp) =>
    new LoggingHttpClient(httpClient, sp.GetRequiredService<IStructuredLogWriter>()));
```

**Rule:** Application/Infrastructure code never calls raw `HttpClient` for external APIs — always `ILoggingHttpClient`.

## 3. Message Logging

For business/diagnostic messages in handlers, services, repositories:

```csharp
// Application/Orders/Commands/CreateOrder/CreateOrderHandler.cs
internal sealed class CreateOrderHandler(
    IOrderRepository orderRepository,
    IStructuredLogWriter logWriter,
    TimeProvider clock)
    : IRequestHandler<CreateOrderCommand, Result<Guid>>
{
    public async Task<Result<Guid>> Handle(CreateOrderCommand request, CancellationToken ct)
    {
        // ...
        logWriter.WriteMessage($"Order {order.Id} created for customer {request.CustomerId}");
        return Result.Success(order.Id);
    }
}
```

`message` type always has **non-empty** `message` field. traceId is picked up from `Activity.Current` automatically.

Do **not** use `_logger.LogInformation("Order created")` for structured logs — use `IStructuredLogWriter.WriteMessage` to keep JSONL shape consistent.

Optional: wrap Serilog `ILogger` only for startup/bootstrap; runtime app logs go through `IStructuredLogWriter`.

## Interface Placement

| Component | Layer |
|-----------|-------|
| `IStructuredLogWriter`, log entry records | Infrastructure (implementation) or Application (interface) |
| `InboundLoggingMiddleware` | Infrastructure |
| `ILoggingHttpClient` / `LoggingHttpClient` | Infrastructure |
| Serilog host configuration | Api |
| `WriteMessage` from handlers | Application (via interface) |

Preferred: put `IStructuredLogWriter` in **Application/Common/Interfaces/**; implement in Infrastructure.

## Project Layout

```
Infrastructure/
  Logging/
    LogType.cs
    TraceIdProvider.cs
    SerilogStructuredLogWriter.cs
    InboundLoggingMiddleware.cs
  Http/
    ILoggingHttpClient.cs
    LoggingHttpClient.cs

Application/
  Common/
    Interfaces/
      IStructuredLogWriter.cs   # optional — move interface here

Api/
  Logging/
    SerilogConfiguration.cs
  Program.cs
```

## Pipeline Order

```csharp
public static WebApplication ConfigurePipeline(this WebApplication app)
{
    app.UseExceptionHandler();
    app.UseMiddleware<InboundLoggingMiddleware>();  // after exception handler
    app.UseHttpsRedirection();
    app.MapControllers();
    return app;
}
```

## Rules Summary

| Rule | Detail |
|------|--------|
| Format | JSONL via Serilog `CompactJsonFormatter` |
| Types | `inbound`, `outbound`, `message` — always in `type` field |
| inbound/outbound `message` | Always empty string `""` |
| message type | `message` field must be non-empty |
| traceId | W3C `Activity.Current.TraceId` — same for all logs in one request |
| Outbound HTTP | Only through `ILoggingHttpClient` decorator |
| Inbound HTTP | `InboundLoggingMiddleware` — one log per request |
| No DelegatingHandler | For outbound body logging — use decorator |
| Body truncation | Cap at 64KB (configurable) to protect logs |
| Sensitive data | Redact in middleware/decorator if needed (passwords, tokens) |

## Anti-patterns

```csharp
// BAD — raw HttpClient without outbound logging
await httpClient.PostAsync(url, content);

// BAD — DelegatingHandler that re-reads body streams
public class LoggingHandler : DelegatingHandler { ... }

// BAD — multiple log lines for one HTTP call
_logger.LogInformation("Request started");
_logger.LogInformation("Request finished");

// BAD — message-type with empty message
logWriter.WriteMessage("");

// BAD — different trace ids within same request
// (happens if you generate Guid instead of Activity.Current)

// GOOD
await loggingHttpClient.SendAsync(request, ct);
logWriter.WriteInbound(entry);  // middleware only
logWriter.WriteMessage("Order created");
```

## Sensitive Data (Optional Extension)

Add redaction before logging:

```csharp
private static string Redact(string body) =>
    Regex.Replace(body, """"password"\s*:\s*"[^"]*"""", """"password":"***"""");
```

Apply in middleware and decorator before `WriteInbound` / `WriteOutbound`.
