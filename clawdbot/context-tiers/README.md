# Context Tiers (HOT / WARM / COLD)

This is a tiny helper for keeping agent context small and relevant.

## Tier markers

Put one of these near the top of a file:

- `@byt3-tier HOT`
- `@byt3-tier WARM`
- `@byt3-tier COLD`

Examples:

```md
<!-- @byt3-tier HOT -->
```

```py
# @byt3-tier WARM
```

## Commands

From repo root:

```bash
python .\clawdbot\context-tiers\context_tiers.py status
python .\clawdbot\context-tiers\context_tiers.py list --tier HOT
python .\clawdbot\context-tiers\context_tiers.py bundle --tier HOT --out .\.tmp_hot
```

## Notes

- Token estimate is rough: `chars/4`.
- We ignore common junk (`node_modules`, `.git`, build outputs).
