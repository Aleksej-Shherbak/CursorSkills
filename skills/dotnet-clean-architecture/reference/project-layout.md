# Project Layout

Standard 4-project Clean Architecture layout for .NET 10 with Controllers, Dapper, and PostgreSQL.

## Solution Structure

```
MyApp/
├── MyApp.slnx
├── .dockerignore
├── Directory.Build.props          # optional
├── SolutionItems/                 # physical folder on disk — auxiliary files
│   ├── docker-compose.yml
│   └── MyApp.Api.http
└── src/
    MyApp.Domain/
      Entities/
        Order.cs
        OrderItem.cs
      Enums/
        OrderStatus.cs
      Exceptions/
        DomainException.cs
      Common/
        Entity.cs
        Error.cs
        ErrorKind.cs
        Result.cs

    MyApp.Application/
      Common/
        Behaviors/
          ValidationBehavior.cs
        Interfaces/
          IDbConnectionFactory.cs
          IOrderRepository.cs
      DependencyInjection.cs
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
        CancelOrder/
          CancelOrderCommand.cs
          CancelOrderHandler.cs
          CancelOrderValidator.cs
          DependencyInjection.cs

    MyApp.Infrastructure/
      Logging/
        InboundLoggingMiddleware.cs
        SerilogStructuredLogWriter.cs
        TraceIdProvider.cs
      Http/
        ILoggingHttpClient.cs
        LoggingHttpClient.cs
      Persistence/
        Sql/
          0001_create_schema_migrations.sql
          0002_create_orders.sql
          0003_create_order_items.sql
        Migrations/
          MigrationRunner.cs
        NpgsqlConnectionFactory.cs
        Repositories/
          OrderRepository.cs
      DependencyInjection.cs

    MyApp.Migrator/
      Program.cs
      appsettings.json
      Dockerfile

    MyApp.Api/
      Logging/
        SerilogConfiguration.cs
      Controllers/
        OrdersController.cs
      Exceptions/
        ValidationExceptionHandler.cs
        GlobalExceptionHandler.cs
      Extensions/
        WebApplicationBuilderExtensions.cs
        WebApplicationExtensions.cs
        ResultExtensions.cs
      Dockerfile
      Program.cs
      appsettings.json

tests/
  MyApp.Application.Tests/
  MyApp.Domain.Tests/
```

## SolutionItems

Two related concepts — do not confuse them:

| Concept | What it is |
|---------|------------|
| **`SolutionItems/`** (folder on disk) | Physical directory at solution root where `docker-compose.yml`, `*.http`, etc. live |
| **`/Solution Items/`** (in `.slnx`) | Virtual folder in Solution Explorer — links to files via `<File Path="..."/>` |

Auxiliary files that are **not** projects live in **`SolutionItems/`** on disk. Register them in **`MyApp.slnx`** so they appear in the IDE under **Solution Items**:

```xml
<Solution>
  <Folder Name="/Solution Items/">
    <File Path="SolutionItems/docker-compose.yml" />
    <File Path="SolutionItems/MyApp.Api.http" />
    <File Path=".dockerignore" />
    <File Path="Directory.Build.props" />
  </Folder>

  <Folder Name="/src/">
    <Project Path="src/MyApp.Domain/MyApp.Domain.csproj" />
    <Project Path="src/MyApp.Application/MyApp.Application.csproj" />
    <Project Path="src/MyApp.Infrastructure/MyApp.Infrastructure.csproj" />
    <Project Path="src/MyApp.Migrator/MyApp.Migrator.csproj" />
    <Project Path="src/MyApp.Api/MyApp.Api.csproj" />
  </Folder>

  <Folder Name="/tests/">
    <Project Path="tests/MyApp.Domain.Tests/MyApp.Domain.Tests.csproj" />
    <Project Path="tests/MyApp.Application.Tests/MyApp.Application.Tests.csproj" />
  </Folder>
</Solution>
```

Use **`.slnx`** (default in .NET 10: `dotnet new sln`). The old `.sln` format is not used.

`dotnet sln` manages **projects** only — solution items are added by editing `.slnx` manually or via IDE (Add → Existing Item to Solution Items folder).

| File | Location on disk | Notes |
|------|------------------|-------|
| `docker-compose.yml` | `SolutionItems/` | Never in solution root |
| `*.http` (REST Client) | `SolutionItems/` | API smoke tests, manual requests |
| `.dockerignore` | solution root | Required at build context root for Docker |
| `Dockerfile` | `src/MyApp.Api/`, `src/MyApp.Migrator/` | Per-project, inside `src/` |

Do **not** put `docker-compose.yml` or `.http` files in the solution root or inside `src/`.

Run compose from solution root:

```bash
docker compose -f SolutionItems/docker-compose.yml up --build
```

Example `.http` file (`SolutionItems/MyApp.Api.http`):

```http
@MyApp.Api_HostAddress = http://localhost:8080

### Get order
GET {{MyApp.Api_HostAddress}}/api/orders/{{orderId}}
Accept: application/json
```

## Project References (Dependency Direction)

```
Domain          → (none)
Application     → Domain
Infrastructure  → Application, Domain
Migrator        → Infrastructure (and transitively Application, Domain)
Api             → Application, Infrastructure, Domain
```

The compiler enforces boundaries via `<ProjectReference>` — no manual layer checks needed if references are correct.

## Domain.csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
```

No NuGet packages. No project references.

## Application.csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\MyApp.Domain\MyApp.Domain.csproj" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="FluentValidation" Version="11.*" />
    <PackageReference Include="FluentValidation.DependencyInjectionExtensions" Version="11.*" />
    <PackageReference Include="MediatR" Version="12.*" />
  </ItemGroup>
</Project>
```

Application has **no** Dapper or Npgsql packages. MediatR is allowed.

## Infrastructure.csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\MyApp.Application\MyApp.Application.csproj" />
    <ProjectReference Include="..\MyApp.Domain\MyApp.Domain.csproj" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="Dapper" Version="2.*" />
    <PackageReference Include="Npgsql" Version="9.*" />
    <PackageReference Include="dbup-postgresql" Version="6.*" />
    <PackageReference Include="Microsoft.AspNetCore.Http.Abstractions" Version="2.*" />
    <PackageReference Include="Microsoft.Extensions.Configuration.Abstractions" Version="10.*" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="10.*" />
    <PackageReference Include="Microsoft.Extensions.Http" Version="10.*" />
    <PackageReference Include="Serilog" Version="4.*" />
  </ItemGroup>
</Project>
```

Persistence: **Dapper**, **Npgsql**, **DbUp**. Logging: middleware + `ILoggingHttpClient` + Serilog writer. Serilog host/sinks configured in Api.

## Api.csproj

```xml
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\MyApp.Application\MyApp.Application.csproj" />
    <ProjectReference Include="..\MyApp.Infrastructure\MyApp.Infrastructure.csproj" />
    <ProjectReference Include="..\MyApp.Domain\MyApp.Domain.csproj" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="Serilog.AspNetCore" Version="9.*" />
    <PackageReference Include="Serilog.Formatting.Compact" Version="3.*" />
  </ItemGroup>
</Project>
```

## Migrator.csproj

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>

  <ItemGroup>
    <ProjectReference Include="..\MyApp.Infrastructure\MyApp.Infrastructure.csproj" />
  </ItemGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="10.*" />
    <PackageReference Include="Microsoft.Extensions.Configuration.EnvironmentVariables" Version="10.*" />
  </ItemGroup>

  <ItemGroup>
    <None Include="..\MyApp.Infrastructure\Persistence\Sql\*.sql"
          Link="Sql\%(Filename)%(Extension)"
          CopyToOutputDirectory="PreserveNewest" />
  </ItemGroup>
</Project>
```

Api has **no** migration code. Migrator is the only app that applies SQL scripts.

## Use Case Folder Convention

Each use case is one folder with models and local DI:

```
Application/
  Orders/
    CreateOrder/       # Command + DTOs + Handler + Validator + DependencyInjection.cs
    GetOrder/
    CancelOrder/
  Products/
    CreateProduct/
    ListProducts/
```

Rules: models belong to the use case folder; `DependencyInjection.cs` registers that use case; root `Application/DependencyInjection.cs` calls all `Add{UseCase}()` methods.

## Clean Program.cs

`Program.cs` contains only bootstrap — configuration in `Api/Extensions/`:

```csharp
var builder = WebApplication.CreateBuilder(args);
builder.ConfigureServices();
var app = builder.Build();
app.ConfigurePipeline();
app.Run();
```

Details: [program-and-di.md](program-and-di.md)

## Directory.Build.props (Optional)

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <VersionPrefix>1.0.0</VersionPrefix>
  </PropertyGroup>
</Project>
```

See [team-conventions.md](team-conventions.md) for version bump rules.

## Related References

- [migrations.md](migrations.md) — SQL scripts, Migrator, DbUp
- [error-handling.md](error-handling.md) — Error, ErrorKind, exception handlers
- [logging.md](logging.md) — Serilog JSONL, inbound/outbound/message, W3C traceId
- [program-and-di.md](program-and-di.md) — clean Program.cs, per-use-case DI
- [mediatr-setup.md](mediatr-setup.md) — handlers, pipeline behaviors, ISender
- [dapper-persistence.md](dapper-persistence.md) — repositories, SQL scripts
- [controllers.md](controllers.md) — ApiController pattern
- [docker.md](docker.md) — Dockerfile and docker-compose
