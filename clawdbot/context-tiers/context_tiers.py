import argparse
import os
import re
import shutil
from pathlib import Path

TIERS = ["HOT", "WARM", "COLD"]
MARK_RE = re.compile(r"@byt3-tier\s+(HOT|WARM|COLD)", re.IGNORECASE)

DEFAULT_EXCLUDES = {
    ".git",
    "node_modules",
    "dist",
    "build",
    ".next",
    ".venv",
    "venv",
    "__pycache__",
}

TEXT_EXTS = {
    ".md",
    ".txt",
    ".py",
    ".js",
    ".ts",
    ".tsx",
    ".jsx",
    ".json",
    ".yaml",
    ".yml",
    ".toml",
    ".ps1",
    ".sh",
    ".bat",
    ".cmd",
}


def is_excluded(path: Path) -> bool:
    parts = set(path.parts)
    return any(p in parts for p in DEFAULT_EXCLUDES)


def detect_tier(path: Path) -> str | None:
    # only scan small-ish text files
    if path.suffix.lower() not in TEXT_EXTS:
        return None

    try:
        with path.open("r", encoding="utf-8", errors="ignore") as f:
            head = f.read(4096)
    except OSError:
        return None

    m = MARK_RE.search(head)
    if not m:
        return None
    return m.group(1).upper()


def approx_tokens(chars: int) -> int:
    # very rough: 4 chars/token
    return max(1, chars // 4)


def scan_repo(root: Path):
    results: dict[str, list[Path]] = {t: [] for t in TIERS}
    unknown: list[Path] = []

    for p in root.rglob("*"):
        if p.is_dir():
            continue
        if is_excluded(p.relative_to(root)):
            continue

        tier = detect_tier(p)
        if tier in results:
            results[tier].append(p)
        else:
            unknown.append(p)

    return results, unknown


def cmd_status(root: Path):
    results, _unknown = scan_repo(root)

    print(f"repo: {root}")
    print("\nTier totals:")
    for t in TIERS:
        files = results[t]
        total_bytes = 0
        total_chars = 0

        for f in files:
            try:
                data = f.read_bytes()
                total_bytes += len(data)
                # best-effort chars
                total_chars += len(data.decode("utf-8", errors="ignore"))
            except OSError:
                pass

        print(
            f"- {t}: {len(files)} files | ~{total_bytes/1024:.1f} KB | ~{approx_tokens(total_chars)} tokens"
        )

    print("\nTip:")
    print("- Mark your always-relevant files as HOT (active tasks, current docs, runbooks)")


def cmd_list(root: Path, tier: str):
    results, _unknown = scan_repo(root)
    tier = tier.upper()
    for p in sorted(results.get(tier, [])):
        print(str(p.relative_to(root)))


def cmd_bundle(root: Path, tier: str, out_dir: Path):
    results, _unknown = scan_repo(root)
    tier = tier.upper()
    out_dir.mkdir(parents=True, exist_ok=True)

    for src in results.get(tier, []):
        rel = src.relative_to(root)
        dst = out_dir / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)

    print(f"bundled {len(results.get(tier, []))} files to {out_dir}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "command", choices=["status", "list", "bundle"], help="what to do"
    )
    ap.add_argument("--tier", choices=TIERS, default="HOT")
    ap.add_argument("--out", default=".tmp_hot")
    args = ap.parse_args()

    root = Path.cwd()

    if args.command == "status":
        cmd_status(root)
    elif args.command == "list":
        cmd_list(root, args.tier)
    elif args.command == "bundle":
        cmd_bundle(root, args.tier, Path(args.out))


if __name__ == "__main__":
    main()
