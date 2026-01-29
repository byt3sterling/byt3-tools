# Clawdbot / Moltbot helpers

Stuff I keep re-using when I’m setting up Clawdbot/Moltbot for real work.

## Quick hardening (Windows)

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\clawdbot\windows\harden.ps1
```

If the script says your config ACL is too open:

```powershell
powershell -ExecutionPolicy Bypass -File .\clawdbot\windows\harden.ps1 -FixAcl
```

### What it checks

- Finds common config locations
- Best-effort check for an auth token in config
- Warns if the gateway is listening on `0.0.0.0` / `::`
- Warns if your config file permissions are too open

It’s intentionally boring. Boring is safe.
