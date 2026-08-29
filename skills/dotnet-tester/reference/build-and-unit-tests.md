---
description: dotnet restore, build, and test commands with error parsing and fix suggestions. Use when build or unit tests fail.
globs: "**/*.csproj, **/*.slnx, **/*.sln, **/tests/**"
---

# Build and Unit Tests

## Phase 1 — Build

```powershell
dotnet restore "<SolutionPath>"
dotnet build "<SolutionPath>" --no-restore
```

Capture full stdout/stderr. On non-zero exit, **stop pipeline** and produce fix report.

### Build Error Report

| File | Line | Error | Suggested fix |
|------|------|-------|---------------|
| Orders.Application/CreateOrderHandler.cs | 12 | CS0246: IOrderRepository not found | Add `using MyApp.Application.Common.Interfaces;` or ProjectReference |
| Orders.Api/Orders.Api.csproj | — | NU1101: Package X not found | Add PackageReference or check NuGet source / VPN |

Common patterns:

| Error code | Likely cause | Fix |
|------------|--------------|-----|
| CS0246 | Missing using or reference | Add using / ProjectReference |
| CS0535 | Interface not implemented | Implement missing members |
| NU1101 / NU1202 | Package/version mismatch | Align PackageReference versions |
| MSB4018 | Build target failure | Read inner exception in log |

## Phase 2 — Unit Tests

```powershell
dotnet test "<SolutionPath>" --no-build --verbosity normal
```

If build was skipped, omit `--no-build` and let test trigger build:

```powershell
dotnet test "<SolutionPath>" --verbosity normal
```

### Test Failure Report

For each failed test:

```markdown
### Failed: Orders.Unit.Tests.CreateOrderHandlerTests.Handle_valid_command_returns_success

- **Assertion:** Expected Result.IsSuccess to be true, but was false
- **Likely cause:** Handler returns Failure when repository mock not configured
- **Suggested fix:** Verify mock setup in test or fix handler logic
- **File:** tests/Orders.Unit.Tests/CreateOrderHandlerTests.cs:45
```

### Architecture Test Failures

When `*Architecture.Tests*` fails, report violating types from NetArchTest output:

```
Failing types: MyApp.Domain.Entities.Order → references MyApp.Infrastructure
Suggested fix: Move IOrderRepository to Application layer
```

## Partial Run — Unit Tests Only

When user says "only unit tests":

1. Run Phase 0 discovery
2. Build if not recently built (or run `dotnet test` without `--no-build`)
3. Skip Phases 3–6 unless requested

## Exit Criteria

| Phase | Pass | Fail |
|-------|------|------|
| Build | exit code 0 | exit code ≠ 0 → blocking |
| Unit tests | all passed | any failed → blocking (unless user said continue) |
