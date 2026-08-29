---
description: Verify curl availability and correct usage on Windows and Unix. Mandatory preflight before Phase 5 and 6.
alwaysApply: true
---

# curl Prerequisites

**Blocking check** before Phase 5 (curl smoke) and Phase 6 (scenario execution).

## Why This Matters

On Windows PowerShell, `curl` is often an **alias** for `Invoke-WebRequest` — different syntax, different behavior. This skill requires **real curl**.

## Preflight — Windows

```powershell
# Step 1: detect alias
$curlCmd = Get-Command curl -ErrorAction SilentlyContinue
if ($curlCmd -and $curlCmd.CommandType -eq 'Alias') {
    # FAIL — alias detected
}

# Step 2: verify curl.exe exists
curl.exe --version
```

| Result | Action |
|--------|--------|
| `curl.exe --version` succeeds | PASS — use `curl.exe` for all requests |
| Only alias exists | FAIL — report: "Install curl or use curl.exe from Windows 10+ build" |
| Not found | FAIL — blocking; skip Phases 5–6 |

**Always write `curl.exe`** in scenario files and commands on Windows — never bare `curl`.

## Preflight — macOS / Linux

```bash
command -v curl
curl --version
```

Use `curl` (not `.exe`) on Unix.

## Required curl Flags

| Flag | Purpose |
|------|---------|
| `-s` | Silent — clean output for parsing |
| `-w "\nHTTP_CODE:%{http_code}"` | Append status code on separate line |
| `-X METHOD` | HTTP method (GET, POST, PUT, DELETE) |
| `-H "Header: value"` | Request headers |
| `-d '{...}'` | JSON body |
| `-o file` / `-D -` | Save body or dump headers when needed |

## Example — GET with status code

Windows:

```powershell
curl.exe -s -w "`nHTTP_CODE:%{http_code}" http://localhost:8080/api/orders
```

Unix:

```bash
curl -s -w "\nHTTP_CODE:%{http_code}" http://localhost:8080/api/orders
```

## Example — POST JSON

Windows:

```powershell
curl.exe -s -w "`nHTTP_CODE:%{http_code}" -X POST http://localhost:8080/api/orders `
  -H "Content-Type: application/json" `
  -d '{"customerId":"test-001","items":[{"productId":"p1","quantity":1,"unitPrice":10.00}]}'
```

## Parsing Response

Split output on `HTTP_CODE:` line:

```
{"id":"3fa85f64-..."}
HTTP_CODE:201
```

- Body = everything before last `HTTP_CODE:` line
- Status = number after `HTTP_CODE:`

Compare status to scenario `expectedStatus` in frontmatter.

## Failure Report

If curl preflight fails:

```markdown
### Blocking: curl not available

- **Detected:** PowerShell alias `curl` → Invoke-WebRequest
- **Required:** curl.exe (Windows 10 1803+ includes it)
- **Action:** Use full path `curl.exe` or install curl; Phases 5–6 skipped
```
