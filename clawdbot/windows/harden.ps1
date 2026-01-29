<#
byt3-tools :: Clawdbot quick hardening script (Windows)

What it does:
- Finds common Clawdbot/Moltbot config locations
- Checks whether auth is enabled (best-effort, based on config keys)
- Checks file permissions on config (Everyone/Users write is bad)
- Checks what the gateway port is listening on (local vs 0.0.0.0)

It does NOT change anything unless you pass -FixAcl.

Usage:
  powershell -ExecutionPolicy Bypass -File .\clawdbot\windows\harden.ps1
  powershell -ExecutionPolicy Bypass -File .\clawdbot\windows\harden.ps1 -FixAcl

Notes:
- Config shapes vary across versions. This script tries a few common keys.
- @byt3-tier HOT
#>

[CmdletBinding()]
param(
  [switch]$FixAcl,
  [switch]$Json
)

function Write-Info($msg){ Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Bad($msg){ Write-Host "[x] $msg" -ForegroundColor Red }
function Write-Good($msg){ Write-Host "[ok] $msg" -ForegroundColor Green }

$report = [ordered]@{
  ts = (Get-Date).ToString('o')
  machine = $env:COMPUTERNAME
  user = $env:USERNAME
  findings = @()
  configCandidates = @()
  configLoaded = $null
  listen = @()
}

function Add-Finding($severity, $title, $details){
  $report.findings += [ordered]@{ severity=$severity; title=$title; details=$details }
}

function Try-LoadJson($path){
  try {
    $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    return $raw | ConvertFrom-Json -ErrorAction Stop
  } catch {
    return $null
  }
}

# --- locate config ---
$candidates = @()
if ($env:CLAWDBOT_CONFIG) { $candidates += $env:CLAWDBOT_CONFIG }

# Common guesses
$candidates += @(
  (Join-Path $env:USERPROFILE ".clawdbot\clawdbot.json"),
  (Join-Path $env:USERPROFILE ".clawdbot\config.json"),
  (Join-Path $env:APPDATA "clawdbot\clawdbot.json"),
  (Join-Path $env:APPDATA "clawdbot\config.json"),
  (Join-Path $env:APPDATA "moltbot\moltbot.json"),
  (Join-Path $env:APPDATA "moltbot\config.json")
)

$candidates = $candidates | Where-Object { $_ -and ($_ -ne "") } | Select-Object -Unique

foreach ($p in $candidates) {
  if (Test-Path -LiteralPath $p) {
    $report.configCandidates += $p
  }
}

if ($report.configCandidates.Count -eq 0) {
  Write-Warn "No config file found in common locations. If you have it somewhere else, set CLAWDBOT_CONFIG to the path."
  Add-Finding "warn" "config_not_found" "No config file found in common locations."
} else {
  Write-Info "Found config candidates:" 
  $report.configCandidates | ForEach-Object { Write-Host "  - $_" }
}

$configPath = $null
foreach ($p in $report.configCandidates) {
  $cfg = Try-LoadJson $p
  if ($cfg -ne $null) { $configPath = $p; $report.configLoaded = $p; break }
}

$config = $null
if ($configPath) {
  $config = Try-LoadJson $configPath
  if ($config -eq $null) {
    Write-Warn "Found config file but couldn't parse JSON: $configPath"
    Add-Finding "warn" "config_parse_failed" $configPath
  } else {
    Write-Good "Loaded config: $configPath"
  }
}

# --- auth checks (best effort) ---
function Get-ConfigValue($obj, $path){
  # path like "gateway.auth.token" or "gateway.authToken"
  $cur = $obj
  foreach ($k in $path.Split('.')) {
    if ($cur -eq $null) { return $null }
    if ($cur.PSObject.Properties.Name -contains $k) { $cur = $cur.$k } else { return $null }
  }
  return $cur
}

$authToken = $null
$bind = $null
$port = $env:CLAWDBOT_GATEWAY_PORT
if (-not $port) { $port = 18789 }

if ($config) {
  $authToken = (Get-ConfigValue $config "gateway.authToken")
  if (-not $authToken) { $authToken = (Get-ConfigValue $config "gateway.auth.token") }
  if (-not $authToken) { $authToken = (Get-ConfigValue $config "gateway.auth_token") }
  if (-not $authToken) { $authToken = (Get-ConfigValue $config "authToken") }

  $bind = (Get-ConfigValue $config "gateway.bind")
  if (-not $bind) { $bind = (Get-ConfigValue $config "gateway.host") }
  if (-not $bind) { $bind = (Get-ConfigValue $config "gateway.listen") }

  $cfgPort = (Get-ConfigValue $config "gateway.port")
  if ($cfgPort) { $port = $cfgPort }
}

if ($authToken -and ($authToken.ToString().Length -ge 16)) {
  Write-Good "Auth token looks set (length $($authToken.ToString().Length))."
} else {
  Write-Bad "Auth token not detected in config. If this gateway is reachable from the internet, that's bad."
  Add-Finding "critical" "auth_token_missing" "No auth token detected in config."
}

# --- ACL checks ---
function Test-WeakAcl($path){
  try {
    $acl = Get-Acl -LiteralPath $path
    $bad = @()
    foreach ($ace in $acl.Access) {
      $id = $ace.IdentityReference.Value
      $rights = $ace.FileSystemRights.ToString()
      $type = $ace.AccessControlType.ToString()
      if ($type -ne "Allow") { continue }

      $isBroad = ($id -match "^Everyone$") -or ($id -match "\\Users$") -or ($id -match "\\Authenticated Users$")
      $isWrite = ($rights -match "Write") -or ($rights -match "Modify") -or ($rights -match "FullControl")
      if ($isBroad -and $isWrite) { $bad += "$id:$rights" }
    }
    return $bad
  } catch {
    return @()
  }
}

if ($configPath) {
  $badAcl = Test-WeakAcl $configPath
  if ($badAcl.Count -gt 0) {
    Write-Bad "Config ACL looks too open:" 
    $badAcl | ForEach-Object { Write-Host "  - $_" }
    Add-Finding "high" "config_acl_weak" ($badAcl -join "; ")

    if ($FixAcl) {
      Write-Info "FixAcl enabled. Tightening permissions on: $configPath"
      # Keep it simple: remove inheritance + grant only current user full control
      icacls "$configPath" /inheritance:r | Out-Null
      icacls "$configPath" /grant:r "$($env:USERNAME):(F)" | Out-Null
      Write-Good "ACL tightened for current user."
      Add-Finding "info" "config_acl_fixed" $configPath
    } else {
      Write-Warn "Run with -FixAcl to tighten config file permissions (recommended)."
    }
  } else {
    Write-Good "Config ACL looks ok (no broad write access detected)."
  }
}

# --- listening checks ---
try {
  $conns = Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction Stop
  foreach ($c in $conns) {
    $report.listen += [ordered]@{ localAddress=$c.LocalAddress; localPort=$c.LocalPort; owningProcess=$c.OwningProcess }
  }

  $public = $conns | Where-Object { $_.LocalAddress -eq "0.0.0.0" -or $_.LocalAddress -eq "::" }
  if ($public) {
    Write-Warn "Gateway port $port is listening on 0.0.0.0/:: (public bind)."
    Add-Finding "high" "gateway_public_bind" "Port $port listening on 0.0.0.0 or ::"
  } else {
    Write-Good "Gateway port $port appears not to be listening on 0.0.0.0/:: (good)."
  }
} catch {
  Write-Warn "Could not check listening sockets for port $port (Get-NetTCPConnection failed)."
  Add-Finding "warn" "listen_check_failed" "Get-NetTCPConnection failed"
}

# --- output ---
if ($Json) {
  $report | ConvertTo-Json -Depth 6
  exit 0
}

Write-Host "\nSummary:" -ForegroundColor White
foreach ($f in $report.findings) {
  $sev = $f.severity
  $line = "- [$sev] $($f.title): $($f.details)"
  if ($sev -in @("critical","high")) { Write-Host $line -ForegroundColor Yellow }
  else { Write-Host $line }
}

Write-Host "\nNext steps:" -ForegroundColor White
Write-Host "- Make sure auth is enabled (token set)"
Write-Host "- If this is public-facing, bind to localhost or put it behind a reverse proxy + auth"
Write-Host "- Tighten config permissions (run with -FixAcl)"
