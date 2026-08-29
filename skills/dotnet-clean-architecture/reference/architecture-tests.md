---
description: NetArchTest.Rules dependency tests — enforce layer boundaries. Use when adding test projects or verifying Clean Architecture compliance.
globs: "**/tests/**/*, **/*Architecture*Tests*/**/*, **/*Tests*.csproj"
---

# Architecture Tests (NetArchTest.Rules)

Automated guardrails for Clean Architecture. When layer boundaries break, tests fail with failing type names — agent can self-correct.

## Package

```xml
<!-- tests/MyApp.Architecture.Tests/MyApp.Architecture.Tests.csproj -->
<PackageReference Include="NetArchTest.Rules" Version="1.*" />
<PackageReference Include="xunit" Version="2.*" />
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
<PackageReference Include="xunit.runner.visualstudio" Version="2.*" />
```

Reference all production assemblies under test:

```xml
<ItemGroup>
  <ProjectReference Include="..\..\src\MyApp.Domain\MyApp.Domain.csproj" />
  <ProjectReference Include="..\..\src\MyApp.Application\MyApp.Application.csproj" />
  <ProjectReference Include="..\..\src\MyApp.Infrastructure\MyApp.Infrastructure.csproj" />
  <ProjectReference Include="..\..\src\MyApp.Api\MyApp.Api.csproj" />
</ItemGroup>
```

Register in `.slnx`:

```xml
<Folder Name="/tests/">
  <Project Path="tests/MyApp.Architecture.Tests/MyApp.Architecture.Tests.csproj" />
</Folder>
```

## Standard Test Suite

Replace `MyApp` with your solution prefix. Run when user asks to verify architecture or after layer changes.

```csharp
using NetArchTest.Rules;
using Xunit;

namespace MyApp.Architecture.Tests;

public sealed class LayerDependencyTests
{
    private const string DomainNamespace = "MyApp.Domain";
    private const string ApplicationNamespace = "MyApp.Application";
    private const string InfrastructureNamespace = "MyApp.Infrastructure";
    private const string ApiNamespace = "MyApp.Api";

    [Fact]
    public void Domain_should_not_reference_Application_Infrastructure_or_Api()
    {
        var result = Types.InAssembly(typeof(Domain.Common.Result).Assembly)
            .ShouldNot()
            .HaveDependencyOnAny(
                ApplicationNamespace,
                InfrastructureNamespace,
                ApiNamespace)
            .GetResult();

        Assert.True(result.IsSuccessful, FormatFailures(result));
    }

    [Fact]
    public void Domain_should_not_reference_AspNetCore_or_Dapper()
    {
        var result = Types.InAssembly(typeof(Domain.Common.Result).Assembly)
            .ShouldNot()
            .HaveDependencyOnAny(
                "Microsoft.AspNetCore",
                "System.Web",
                "Dapper",
                "Npgsql")
            .GetResult();

        Assert.True(result.IsSuccessful, FormatFailures(result));
    }

    [Fact]
    public void Application_should_not_reference_Infrastructure_or_Api()
    {
        var result = Types.InAssembly(typeof(Application.DependencyInjection).Assembly)
            .ShouldNot()
            .HaveDependencyOnAny(InfrastructureNamespace, ApiNamespace)
            .GetResult();

        Assert.True(result.IsSuccessful, FormatFailures(result));
    }

    [Fact]
    public void Infrastructure_should_not_reference_Api()
    {
        var result = Types.InAssembly(typeof(Infrastructure.DependencyInjection).Assembly)
            .ShouldNot()
            .HaveDependencyOn(ApiNamespace)
            .GetResult();

        Assert.True(result.IsSuccessful, FormatFailures(result));
    }

    [Fact]
    public void Handlers_should_reside_in_Application()
    {
        var result = Types.InAssembly(typeof(Application.DependencyInjection).Assembly)
            .That()
            .HaveNameEndingWith("Handler")
            .Should()
            .ResideInNamespace(ApplicationNamespace)
            .GetResult();

        Assert.True(result.IsSuccessful, FormatFailures(result));
    }

    [Fact]
    public void Controllers_should_reside_in_Api()
    {
        var result = Types.InAssembly(typeof(Program).Assembly)
            .That()
            .HaveNameEndingWith("Controller")
            .Should()
            .ResideInNamespace($"{ApiNamespace}.Controllers")
            .GetResult();

        Assert.True(result.IsSuccessful, FormatFailures(result));
    }

    [Fact]
    public void Repository_interfaces_should_reside_in_Application_only()
    {
        var result = Types.InCurrentDomain()
            .That()
            .HaveNameEndingWith("Repository")
            .And()
            .AreInterfaces()
            .Should()
            .ResideInNamespace(ApplicationNamespace)
            .GetResult();

        Assert.True(result.IsSuccessful, FormatFailures(result));
    }

    [Fact]
    public void Aggregate_roots_should_inherit_Entity_and_reside_in_Entities_namespace()
    {
        var result = Types.InAssembly(typeof(Domain.Common.Entity).Assembly)
            .That()
            .Inherit(typeof(Domain.Common.Entity))
            .Should()
            .ResideInNamespace($"{DomainNamespace}.Entities")
            .GetResult();

        Assert.True(result.IsSuccessful, FormatFailures(result));
    }

    private static string FormatFailures(TestResult result) =>
        result.IsSuccessful
            ? string.Empty
            : string.Join(", ", result.FailingTypeNames ?? []);
}
```

Adjust anchor types (`typeof(Domain.Common.Result)`, `typeof(Application.DependencyInjection)`, `typeof(Program)`) to types that exist in your solution.

## When Agent Should Add or Run Tests

| Trigger | Action |
|---------|--------|
| New solution bootstrap | Create `MyApp.Architecture.Tests` with suite above |
| Moved interface to wrong layer | Fix code; run architecture tests if user asks |
| User reports layer violation | Add targeted NetArchTest rule for that case |

Agent does **not** run `dotnet test` unless the user explicitly asks (same as `dotnet build`).

## Extending Rules

```csharp
[Fact]
public void Domain_entities_should_not_implement_IRequest()
{
    var result = Types.InAssembly(typeof(Domain.Common.Entity).Assembly)
        .That()
        .Inherit(typeof(Domain.Common.Entity))
        .ShouldNot()
        .ImplementInterface(typeof(MediatR.IRequest))
        .GetResult();

    Assert.True(result.IsSuccessful, FormatFailures(result));
}
```

## Related

- Layer rules and anti-patterns: [team-conventions.md](team-conventions.md#do-not-do-anti-patterns)
- Rich entities: [domain-entities.md](domain-entities.md)
- Project layout: [project-layout.md](project-layout.md)
