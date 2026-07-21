#!/usr/bin/env python3
"""
gen_inventory.py —— 从 patch 头 + features.yaml 派生 inventory.json

参照:
  - Buildroot support/scripts/pkg-stats:
    https://github.com/buildroot/buildroot/blob/master/support/scripts/pkg-stats
    (从 package 元数据派生统计)
  - OpenWrt scripts/metadata.pl:
    https://github.com/openWRT/openwrt/blob/main/scripts/metadata.pl
    (扫描 Makefile 提取 package 信息)
  - OpenWrt package/<name>/Config.in:
    https://github.com/openWRT/openwrt/tree/main/package
    (bool 选项 + depends + default  →  本仓 features.yaml)
  - Yocto recipes-*/<pkg>.bbappend:
    (条件 SRC_URI / DISTRO_FEATURES)
  - Debian dpkg-scanpackages:
    (从 .dsc 派生 Packages 文件)

设计原则:
  - inventory.json 是 *派生产物*,不入仓(.gitignore)
  - 单一真相仍是 patch 头(DEP-3)+ features.yaml(OpenWrt Config.in 风格)
  - 用途: dashboard / 报告 / 一键查"这个版本有哪些 feature + patch + 什么状态"

输出 schema (versions/<v>/patches/inventory.json):
{
  "version_id": "redis-7.0.15",
  "upstream": {"repo": "...", "version": "...", "commit": "..."},
  "generated_at": "2026-07-20T12:00:00Z",
  "generator": "tools/gen_inventory.py",
  "features": {
    "feature-A": {
      "title": "...",
      "patches": ["0001-...patch"],
      "depends": [],
      "default": true,
      "upstream_status_summary": {"Submitted": 1, ...}
    }
  },
  "combos": {
    "default": {
      "active": ["feature-A", "feature-C"],
      "resolved": ["feature-A", "feature-C"],
      "patch_count": 3,
      "patch_list": ["features/feature-A/0001-...patch", ...]
    }
  },
  "patches": [
    {
      "file": "0001-...patch",
      "path": "features/feature-A/0001-...patch",
      "feature": "feature-A",
      "in_features": ["feature-A"],
      "in_combos": ["default"],
      "upstream_status": "Submitted",
      "maintainer": "...",
      "last_update": "2026-07-20",
      "applies_to": "redis 7.0.15",
      "subject": "...",
      "description_first_line": "..."
    }
  ],
  "stats": {
    "total_patches": 4,
    "by_upstream_status": {"Submitted": 3, "Inappropriate": 1},
    "total_features": 3,
    "default_features": ["feature-A", "feature-C"]
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


def resolve_features(active: list[str], all_features: dict) -> list[str]:
    """解析依赖,返回 resolved feature 列表(深度优先,depends 在前)。
    与 apply_patch.sh 的 inline python 等价(独立验证)。"""
    seen: set[str] = set()
    resolved: list[str] = []

    def _resolve(name: str, stack: tuple = ()) -> None:
        if name in seen:
            return
        if name in stack:
            cycle = " -> ".join(stack + (name,))
            raise ValueError(f"环依赖: {cycle}")
        if name not in all_features:
            raise ValueError(f"未知 feature: {name!r}")
        f = all_features[name]
        if not isinstance(f.get("patches"), list) or not f["patches"]:
            raise ValueError(f"feature {name!r}: patches 段缺失或为空")
        for dep in f.get("depends", []) or []:
            _resolve(dep, stack + (name,))
        seen.add(name)
        resolved.append(name)

    for a in active:
        _resolve(a)
    return resolved


def find_patches(patches_dir: Path) -> list[Path]:
    """发现 patches/features/<feature>/*.patch。
    物理 layout:v5.0 起,patches 必须按 features/<feature>/ 组织。"""
    return sorted(patches_dir.glob("features/*/*.patch"))


def generate_inventory(version_dir: Path) -> dict:
    """为单个 versions/<v>/ 目录生成 inventory。"""
    vname = version_dir.name
    uyaml = version_dir / "upstream.yaml"
    patches_dir = version_dir / "patches"
    features_yaml = patches_dir / "features.yaml"

    if not uyaml.exists():
        raise FileNotFoundError(f"{vname}: 缺 upstream.yaml")
    if not patches_dir.is_dir():
        raise FileNotFoundError(f"{vname}: 缺 patches/")
    if not features_yaml.exists():
        raise FileNotFoundError(f"{vname}: 缺 patches/features.yaml(v5.0 起必须)")

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

    # 读 features.yaml(OpenWrt Config.in 风格)
    fdata = yaml.safe_load(features_yaml.read_text(encoding="utf-8"))
    features_block = fdata.get("features", {}) if isinstance(fdata, dict) else {}
    if not features_block:
        raise ValueError(f"{vname}: features.yaml 没有 features 段")

    # 默认 active
    default_active = [n for n, f in features_block.items() if f.get("default", False)]
    try:
        resolved_default = resolve_features(default_active, features_block)
    except ValueError as e:
        raise ValueError(f"{vname}: features.yaml 默认组合解析失败: {e}") from None

    # 反向索引:patch file → feature
    patch_to_feature: dict[str, str] = {}
    patch_paths = find_patches(patches_dir)
    for p in patch_paths:
        # p = patches/features/<feature>/<patch>
        rel = p.relative_to(patches_dir).as_posix()  # features/<feature>/<patch>
        parts = rel.split("/")
        if len(parts) == 3 and parts[0] == "features":
            patch_to_feature[p.name] = parts[1]

    # 校验:features.yaml 里声明的 patches 必须真实存在
    declared_patches: set[str] = set()
    feat_patches: dict[str, list[str]] = {}
    for feat_name, info in features_block.items():
        plist = info.get("patches", []) or []
        feat_patches[feat_name] = plist
        for p in plist:
            declared_patches.add(p)
            full = patches_dir / "features" / feat_name / p
            if not full.is_file():
                raise FileNotFoundError(f"{vname}: feature {feat_name!r} 声明的 patch {p} 不存在 ({full})")

    # 校验:patches/features/<feature>/*.patch 必须在 features.yaml 声明
    orphans: list[str] = []
    for p in patch_paths:
        if p.name not in declared_patches:
            orphans.append(str(p.relative_to(version_dir)))

    # 每个 patch 头解析
    patches_info = []
    stats_by_status: dict[str, int] = {}
    feat_status_summary: dict[str, dict[str, int]] = {
        n: {} for n in features_block
    }

    # 按 feature 顺序遍历 resolved_default,然后是其余 feature
    for feat_name in list(features_block.keys()):
        for p_file in feat_patches[feat_name]:
            full = patches_dir / "features" / feat_name / p_file
            text = full.read_text(encoding="utf-8", errors="replace")
            hdr = parse_patch_header(text)
            status = hdr.get("Upstream-Status", "")
            stats_by_status[status] = stats_by_status.get(status, 0) + 1
            feat_status_summary[feat_name][status] = feat_status_summary[feat_name].get(status, 0) + 1

            desc_first = hdr.get("Description", "").splitlines()[0] if hdr.get("Description") else ""

            # 这个 patch 在哪些 feature 里(1 个)
            in_features = [feat_name]
            # 在哪些 combo 里(目前只有 "default")
            in_combos = ["default"] if feat_name in resolved_default else []

            patches_info.append({
                "file": p_file,
                "path": f"features/{feat_name}/{p_file}",
                "feature": feat_name,
                "in_features": in_features,
                "in_combos": in_combos,
                "upstream_status": status,
                "maintainer": hdr.get("Maintainer", ""),
                "last_update": hdr.get("Last-Update", ""),
                "applies_to": hdr.get("Applies-To", ""),
                "subject": hdr.get("Subject", ""),
                "description_first_line": desc_first,
            })

    # features block(给 dashboard)
    features_info: dict[str, dict] = {}
    for feat_name, info in features_block.items():
        features_info[feat_name] = {
            "title": info.get("title", ""),
            "patches": info.get("patches", []),
            "depends": info.get("depends", []),
            "default": info.get("default", False),
            "upstream_status_summary": feat_status_summary[feat_name],
        }

    # default combo
    default_combo_patch_list: list[str] = []
    for feat in resolved_default:
        for p in feat_patches[feat]:
            default_combo_patch_list.append(f"features/{feat}/{p}")

    return {
        "version_id": vname,
        "upstream": upstream,
        "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "generator": "tools/gen_inventory.py",
        "features": features_info,
        "combos": {
            "default": {
                "active": default_active,
                "resolved": resolved_default,
                "patch_count": len(default_combo_patch_list),
                "patch_list": default_combo_patch_list,
            }
        },
        "patches": patches_info,
        "stats": {
            "total_patches": len(patches_info),
            "by_upstream_status": stats_by_status,
            "total_features": len(features_block),
            "default_features": default_active,
            "orphans": orphans,
            "missing_from_features_yaml": sorted(declared_patches - {p["file"] for p in patches_info}),
        },
    }


def write_inventory(version_dir: Path, inv: dict, check: bool = False) -> int:
    """写 inventory.json 到 patches/。check 模式下,只在有差异时 exit 1。

    check 模式忽略 generated_at(每次跑都不同);只比对业务字段。
    """
    out_path = version_dir / "patches" / "inventory.json"
    new_text = json.dumps(inv, indent=2, ensure_ascii=False, sort_keys=False) + "\n"

    if check:
        if not out_path.exists():
            print(f"  ✗ {out_path}: 不存在(请先生成)")
            return 1
        existing = out_path.read_text(encoding="utf-8")
        new_for_cmp = json.loads(new_text)
        new_for_cmp["generated_at"] = "TIMESTAMP"
        new_text_cmp = json.dumps(new_for_cmp, indent=2, ensure_ascii=False, sort_keys=False) + "\n"
        existing_for_cmp = existing.replace(_existing_timestamp(existing), "TIMESTAMP", 1)
        if existing_for_cmp != new_text_cmp:
            print(f"  ✗ {out_path}: 差异(请重新生成)")
            return 1
        print(f"  ✓ {out_path}: up-to-date")
        return 0
    else:
        out_path.write_text(new_text, encoding="utf-8")
        print(f"  ✓ wrote {out_path} ({inv['stats']['total_patches']} patches, "
              f"{inv['stats']['total_features']} features)")
        return 0


def _existing_timestamp(text: str) -> str:
    """从已存在的 inventory.json 里抠出 'generated_at' 的值字符串。"""
    m = re.search(r'"generated_at":\s*"([^"]+)"', text)
    return m.group(1) if m else ""


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        description="Generate inventory.json from patch headers + features.yaml."
    )
    parser.add_argument("paths", nargs="+",
                        help="versions/<v>/ 目录(可多个,支持 glob)")
    parser.add_argument("--check", action="store_true",
                        help="CI 模式:inventory.json 不存在或与 patch 头 + features.yaml 不一致即 exit 1")
    args = parser.parse_args(argv[1:])

    rc = 0
    for path_str in args.paths:
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
            except (FileNotFoundError, ValueError, yaml.YAMLError) as e:
                print(f"  ✗ {m}: {e}", file=sys.stderr)
                rc = 1
                continue
            if write_inventory(vdir, inv, check=args.check) != 0:
                rc = 1

    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))