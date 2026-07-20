#!/usr/bin/env python3
"""
gen_inventory.py —— 从 patch 头 + series 文件派生 inventory.json

参照:
  - Buildroot support/scripts/pkg-stats:
    https://github.com/buildroot/buildroot/blob/master/support/scripts/pkg-stats
    (从 package 元数据派生统计)
  - OpenWrt scripts/metadata.pl:
    https://github.com/openWRT/openwrt/blob/main/scripts/metadata.pl
    (扫描 Makefile 提取 package 信息)
  - Debian dpkg-scanpackages:
    (从 .dsc 派生 Packages 文件)

设计原则:
  - inventory.json 是 *派生产物*,不入仓(.gitignore)
  - 单一真相仍是 patch 头(DEP-3)+ series 文件
  - 用途: dashboard / 报告 / 一键查"这个版本有哪些 patch,什么状态"

输出 schema (versions/<v>/patches/inventory.json):
{
  "version_id": "redis-7.0.15",
  "upstream": {"repo": "...", "version": "...", "commit": "..."},
  "generated_at": "2026-07-20T12:00:00Z",
  "generator": "tools/gen_inventory.py",
  "patches": [
    {
      "file": "0001-foo.patch",
      "upstream_status": "Submitted",
      "maintainer": "twwang",
      "last_update": "2026-07-20",
      "applies_to": "redis 7.0.15",
      "subject": "...",
      "description_first_line": "...",
      "in_series_default": true,
      "in_profiles": ["minimal", "security"]
    },
    ...
  ],
  "profiles": {
    "default": {"file": "series", "patch_count": 4},
    "minimal": {"file": "series.minimal", "patch_count": 3}
  },
  "stats": {
    "total_patches": 5,
    "by_upstream_status": {"Submitted": 3, "Inappropriate": 1, ...},
    "orphans": [],
    "missing_from_series": []
  }
}

用法:
  python3 tools/gen_inventory.py versions/redis-7.0.15/
  python3 tools/gen_inventory.py versions/*/                # all versions
  python3 tools/gen_inventory.py --check versions/redis-7.0.15/  # CI 用,差异>0 退出 1
"""
from __future__ import annotations

import argparse
import datetime
import glob
import json
import os
import re
import sys
from pathlib import Path

import yaml


HEADER_END_RE = re.compile(r"^(diff --git |--- |\+\+\+ )", re.MULTILINE)


def parse_patch_header(text: str) -> dict[str, str]:
    """从 patch 文本解析 DEP-3 邮件式头(复用 lint_patch_headers 的逻辑,简化版)。"""
    headers: dict[str, str] = {}
    in_header = True
    last_key: str | None = None

    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if in_header:
            m = HEADER_END_RE.match(line)
            if m:
                in_header = False
                i += 1
                continue
            km = re.match(r"^([A-Za-z][A-Za-z0-9-]*):\s*(.*)$", line)
            if km:
                key = km.group(1)
                val = km.group(2).rstrip()
                if val == "|":
                    block: list[str] = []
                    i += 1
                    while i < len(lines):
                        cont = lines[i]
                        if cont.startswith("    ") or cont.startswith("\t"):
                            block.append(cont[4:] if cont.startswith("    ") else cont[1:])
                            i += 1
                        elif cont.strip() == "":
                            block.append("")
                            i += 1
                        else:
                            break
                    headers[key] = "\n".join(block).strip()
                    last_key = key
                    continue
                else:
                    headers[key] = val
                    last_key = key
                    i += 1
                    continue
            elif line.startswith((" ", "\t")) and last_key is not None:
                cont = line.lstrip(" \t")
                if headers.get(last_key):
                    headers[last_key] = headers[last_key] + " " + cont
                else:
                    headers[last_key] = cont
                i += 1
                continue
            elif line.strip() == "":
                i += 1
                continue
            else:
                i += 1
                continue
        else:
            break  # 到 diff 段就停

    return headers


def read_series(series_path: Path) -> list[str]:
    """读 series 文件,返回 entry 列表(已 trim + 跳过空行/# 注释)。"""
    if not series_path.exists():
        return []
    entries: list[str] = []
    for raw in series_path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        entries.append(line)
    return entries


def discover_profiles(patches_dir: Path) -> dict[str, Path]:
    """发现 patches/ 下所有 series + series.* profile 文件。

    - series         → profile "default"
    - series.minimal → profile "minimal"
    - series.ci      → profile "ci"
    业界参照:Buildroot/OpenWrt 没有 profile 概念,这是本仓扩展。
    """
    profiles: dict[str, Path] = {}
    main = patches_dir / "series"
    if main.exists():
        profiles["default"] = main

    # series.* = profile variants
    for p in sorted(patches_dir.glob("series.*")):
        if p.is_file():
            profile_name = p.name.split(".", 1)[1]
            profiles[profile_name] = p
    return profiles


def generate_inventory(version_dir: Path) -> dict:
    """为单个 versions/<v>/ 目录生成 inventory。"""
    vname = version_dir.name
    uyaml = version_dir / "upstream.yaml"
    patches_dir = version_dir / "patches"

    if not uyaml.exists():
        raise FileNotFoundError(f"{vname}: 缺 upstream.yaml")
    if not patches_dir.is_dir():
        raise FileNotFoundError(f"{vname}: 缺 patches/")

    # 读 upstream.yaml(Yocto recipe 段 + upstream pin)
    u = yaml.safe_load(uyaml.read_text(encoding="utf-8"))
    upstream_block = u.get("upstream", {}) or {}
    upstream = {
        "repo": upstream_block.get("repo", ""),
        "version": upstream_block.get("version", ""),
        "commit": upstream_block.get("commit", ""),
        "license": u.get("LICENSE", ""),
        "summary": u.get("SUMMARY", ""),
    }

    # 找所有 patch 文件
    patch_files = sorted(patches_dir.glob("*.patch"))

    # 找所有 profile
    profiles = discover_profiles(patches_dir)
    default_series_entries = read_series(profiles.get("default", patches_dir / "series"))

    # 反向索引:profile name → entry set
    profile_entries: dict[str, set[str]] = {
        name: set(read_series(path)) for name, path in profiles.items()
    }

    patches_info = []
    stats_by_status: dict[str, int] = {}

    for pfile in patch_files:
        text = pfile.read_text(encoding="utf-8", errors="replace")
        hdr = parse_patch_header(text)
        status = hdr.get("Upstream-Status", "")
        stats_by_status[status] = stats_by_status.get(status, 0) + 1

        desc_first = hdr.get("Description", "").splitlines()[0] if hdr.get("Description") else ""

        # 这个 patch 在哪些 profile 里
        in_profiles = sorted(
            name for name, entries in profile_entries.items()
            if pfile.name in entries
        )

        patches_info.append({
            "file": pfile.name,
            "upstream_status": status,
            "maintainer": hdr.get("Maintainer", ""),
            "last_update": hdr.get("Last-Update", ""),
            "applies_to": hdr.get("Applies-To", ""),
            "subject": hdr.get("Subject", ""),
            "description_first_line": desc_first,
            "in_series_default": pfile.name in profile_entries.get("default", set()),
            "in_profiles": in_profiles,
        })

    # stats: orphan + missing
    series_set = profile_entries.get("default", set())
    patch_names = {p["file"] for p in patches_info}
    orphans = sorted(patch_names - series_set)              # 在 patches/ 但不在 series
    missing_from_series = sorted(series_set - patch_names) # 在 series 但 patches/ 没文件

    return {
        "version_id": vname,
        "upstream": upstream,
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "generator": "tools/gen_inventory.py",
        "patches": patches_info,
        "profiles": {
            name: {"file": str(path.relative_to(version_dir)),
                   "patch_count": len(read_series(path))}
            for name, path in profiles.items()
        },
        "stats": {
            "total_patches": len(patches_info),
            "by_upstream_status": stats_by_status,
            "orphans": orphans,
            "missing_from_series": missing_from_series,
        },
    }


def write_inventory(version_dir: Path, inv: dict, check: bool = False) -> int:
    """写 inventory.json 到 patches/。check 模式下,只在有差异时 exit 1。

    check 模式忽略 generated_at(每次跑都不同);只比对业务字段(profile/patches/stats)。
    """
    out_path = version_dir / "patches" / "inventory.json"
    new_text = json.dumps(inv, indent=2, ensure_ascii=False, sort_keys=False) + "\n"

    if check:
        if not out_path.exists():
            print(f"  ✗ {out_path}: 不存在(请先生成)")
            return 1
        existing = out_path.read_text(encoding="utf-8")
        # 生成 new 的快照,把 generated_at 置为 sentinel 再比对(避免每次跑时间戳不同)
        new_for_cmp = json.loads(new_text)
        new_for_cmp["generated_at"] = "TIMESTAMP"
        new_text_cmp = json.dumps(new_for_cmp, indent=2, ensure_ascii=False, sort_keys=False) + "\n"
        existing_for_cmp = existing.replace(_existing_timestamp(existing), "TIMESTAMP", 1)
        if existing_for_cmp != new_text_cmp:
            # 显示具体 diff 行号(摘前 5 行差异)
            print(f"  ✗ {out_path}: 差异(请重新生成)")
            return 1
        print(f"  ✓ {out_path}: up-to-date")
        return 0
    else:
        out_path.write_text(new_text, encoding="utf-8")
        print(f"  ✓ wrote {out_path} ({inv['stats']['total_patches']} patches, "
              f"{len(inv['profiles'])} profiles)")
        return 0


def _existing_timestamp(text: str) -> str:
    """从已存在的 inventory.json 里抠出 'generated_at' 的值字符串。
    找形如 '  "generated_at": "2026-07-20T12:28:59+00:00"' 的行,返回那个时间戳串。"""
    m = re.search(r'"generated_at":\s*"([^"]+)"', text)
    return m.group(1) if m else ""


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Generate inventory.json from patch headers + series files."
    )
    parser.add_argument("paths", nargs="+",
                        help="versions/<v>/ 目录(可多个,支持 glob)")
    parser.add_argument("--check", action="store_true",
                        help="CI 模式:inventory.json 不存在或与 patch 头不一致即 exit 1")
    args = parser.parse_args(argv[1:])

    rc = 0
    for path_str in args.paths:
        # 展开 glob
        if any(c in path_str for c in "*?["):
            matches = sorted(glob.glob(path_str))
        else:
            matches = [path_str]

        for m in matches:
            vdir = Path(m)
            if not vdir.is_dir():
                print(f"  ✗ {m}: 不是目录", file=sys.stderr)
                rc = 1
                continue
            try:
                inv = generate_inventory(vdir)
            except (FileNotFoundError, yaml.YAMLError) as e:
                print(f"  ✗ {m}: {e}", file=sys.stderr)
                rc = 1
                continue
            if write_inventory(vdir, inv, check=args.check) != 0:
                rc = 1

    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
