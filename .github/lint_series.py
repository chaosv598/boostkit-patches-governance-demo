#!/usr/bin/env python3
"""
lint_series —— 校验 versions/<v>/patches/series 与 *.patch 目录的一致性

校验规则:
  1. series / series.* 引用的每条 entry 必须对应存在 .patch 文件
  2. 主 series(仅文件名 == "series")要求 patches/*.patch 全部被引用(无孤儿)
     profile 文件(series.minimal / series.security / ...)允许只引用子集,不做孤儿检查
  3. series / series.* 内部不允许重复 entry
  4. series / series.* 允许空行 / # 注释

profile 概念(本仓扩展,业界出处):
  - Buildroot  package/<name>/<name>-<variant>.patch   (variant 系列)
  - OpenWrt    PATCHFILES in Makefile (按 CONFIG_* 条件)
  - 本仓      series + series.<profile>     (构建时二选一)

用法:
  python3 .github/lint_series.py versions/*/patches/
  python3 .github/lint_series.py versions/redis-7.0.15/patches/series
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PROFILE_SUFFIX_RE = re.compile(r"^series(\..+)?$")  # series 或 series.<profile>


def parse_series(path: Path) -> list[str]:
    """读 series,过滤空行和 # 注释,返回 entry 列表."""
    entries: list[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        entries.append(s)
    return entries


def is_main_series(path: Path) -> bool:
    """主 series = 文件名严格等于 'series'。series.<x> 一律视为 profile。"""
    return path.name == "series"


def profile_name(path: Path) -> str:
    """从 series.<x> 抽出 profile 名(如 'series.minimal' → 'minimal')。
    主 series 返回 'default'。"""
    if is_main_series(path):
        return "default"
    return path.name.split(".", 1)[1]


def lint_series(series_path: Path) -> list[str]:
    errs: list[str] = []
    patches_dir = series_path.parent

    if not patches_dir.is_dir():
        return [f"{series_path}: 父目录不存在 ({patches_dir})"]

    entries = parse_series(series_path)
    main = is_main_series(series_path)

    # 1. 重复 entry(所有 series 文件都查)
    seen: set[str] = set()
    dups: set[str] = set()
    for e in entries:
        if e in seen:
            dups.add(e)
        seen.add(e)
    for d in sorted(dups):
        errs.append(f"{series_path}: series 重复 entry: {d}")

    # 2. entry 必须对应存在 .patch(所有 series 文件都查)
    for e in entries:
        p = patches_dir / e
        if not p.is_file():
            errs.append(f"{series_path}: 引用了不存在的 patch: {e}")

    # 3. 孤儿检查 —— 只对主 series 强制(profile 文件本就是子集)
    if main:
        on_disk = {p.name for p in patches_dir.glob("*.patch")}
        referenced = set(entries)
        orphans = on_disk - referenced
        for o in sorted(orphans):
            errs.append(f"{patches_dir}: 孤儿 patch (series 未引用): {o}")

    return errs


def discover_series(patches_dir: Path) -> list[Path]:
    """从 patches/ 目录找所有 series / series.* 文件。
    按文件名排序,主 series 排第一。"""
    if not patches_dir.is_dir():
        return []
    found: list[Path] = []
    for p in sorted(patches_dir.iterdir()):
        if p.is_file() and PROFILE_SUFFIX_RE.match(p.name):
            found.append(p)
    # 主 series 排第一(输出稳定)
    found.sort(key=lambda x: (0 if is_main_series(x) else 1, x.name))
    return found


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("用法: lint_series.py <series-file-or-patches-dir>...", file=sys.stderr)
        return 2

    series_files: list[Path] = []
    for arg in argv[1:]:
        p = Path(arg)
        if p.is_dir():
            for s in discover_series(p):
                series_files.append(s)
        elif p.is_file() and PROFILE_SUFFIX_RE.match(p.name):
            series_files.append(p)
        else:
            print(f"✗ {arg}: 不是 series/series.* 文件也不是 patches 目录", file=sys.stderr)
            return 1

    if not series_files:
        print("✗ 未找到任何 series 文件", file=sys.stderr)
        return 1

    all_errs: list[str] = []
    for s in series_files:
        errs = lint_series(s)
        kind = "main" if is_main_series(s) else f"profile[{profile_name(s)}]"
        if errs:
            all_errs.extend(errs)
            for e in errs:
                print(f"  ✗ {e}", file=sys.stderr)
        else:
            entries = parse_series(s)
            print(f"  ✓ {s.parent}/{s.name} ({kind}): {len(entries)} 条,无孤儿无重复")

    print(f"--- series lint: {len(series_files)} 个 series 文件,"
          f"{len(all_errs)} 个错误 ---")
    return 0 if not all_errs else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))