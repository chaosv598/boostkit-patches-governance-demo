#!/usr/bin/env python3
"""
lint_series —— 校验 versions/<v>/patches/series 与 *.patch 目录的一致性

校验规则:
  1. series 引用的每条 entry 必须对应存在 .patch 文件
  2. patches/*.patch 中所有文件必须被 series 引用(否则孤儿)
  3. series 不允许重复 entry
  4. series 允许空行 / # 注释

用法:
  python3 .github/lint_series.py versions/*/patches/
  python3 .github/lint_series.py versions/redis-7.0.15/patches/series
"""
from __future__ import annotations

import sys
from pathlib import Path


def parse_series(path: Path) -> list[str]:
    """读 series,过滤空行和 # 注释,返回 entry 列表."""
    entries: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        entries.append(s)
    return entries


def lint_series(series_path: Path) -> list[str]:
    errs: list[str] = []
    patches_dir = series_path.parent

    if not patches_dir.is_dir():
        return [f"{series_path}: 父目录不存在 ({patches_dir})"]

    entries = parse_series(series_path)

    # 1. 重复 entry
    seen: set[str] = set()
    dups: set[str] = set()
    for e in entries:
        if e in seen:
            dups.add(e)
        seen.add(e)
    for d in sorted(dups):
        errs.append(f"{series_path}: series 重复 entry: {d}")

    # 2. entry 必须对应存在 .patch
    for e in entries:
        p = patches_dir / e
        if not p.is_file():
            errs.append(f"{series_path}: 引用了不存在的 patch: {e}")

    # 3. patches/ 目录下所有 .patch 都必须在 series 里(孤儿检查)
    on_disk = {p.name for p in patches_dir.glob("*.patch")}
    referenced = set(entries)
    orphans = on_disk - referenced
    for o in sorted(orphans):
        errs.append(f"{patches_dir}: 孤儿 patch (series 未引用): {o}")

    return errs


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("用法: lint_series.py <series-file-or-patches-dir>...", file=sys.stderr)
        return 2

    series_files: list[Path] = []
    for arg in argv[1:]:
        p = Path(arg)
        if p.is_dir():
            s = p / "series"
            if not s.is_file():
                print(f"  ⚠ {p}/series 不存在,跳过", file=sys.stderr)
                continue
            series_files.append(s)
        elif p.is_file() and p.name == "series":
            series_files.append(p)
        else:
            print(f"✗ {arg}: 不是 series 文件也不是 patches 目录", file=sys.stderr)
            return 1

    all_errs: list[str] = []
    for s in series_files:
        errs = lint_series(s)
        if errs:
            all_errs.extend(errs)
            for e in errs:
                print(f"  ✗ {e}", file=sys.stderr)
        else:
            entries = parse_series(s)
            print(f"  ✓ {s.parent}/series: {len(entries)} 条,无孤儿无重复")

    print(f"--- series lint: {len(series_files)} 个 series,{len(all_errs)} 个错误 ---")
    return 0 if not all_errs else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))