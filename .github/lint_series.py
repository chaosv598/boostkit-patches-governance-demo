#!/usr/bin/env python3
"""
lint_series —— v5.0 起改为 lint features.yaml

v5.0 起 series 文件不再存在(patches/series 是 apply_patch.sh 从 features.yaml
派生出来的 tmp 文件),所以本工具改为校验 patches/features.yaml。

校验规则:
  1. features.yaml 顶层有 features 段(非空 dict)
  2. 每个 feature 字段完整:title / patches(list, 非空)
  3. depends 引用必须存在(无悬挂)
  4. 无环依赖
  5. patches 列表里每个 patch 文件必须实际存在
  6. patches/features/<feature>/ 目录下的 .patch 必须在 features.yaml 声明(否则孤儿)
  7. 每个 feature 的 patches 列表里,每个 patch 头必须有 DEP-3 6 必填字段
     (委托 lint_patch_headers.py 的解析,只挑关键字段验证)

业界参照:
  - OpenWrt package/<name>/Config.in  (bool + depends + default schema)
  - Kconfig                              (depends / select 语义)
  - Yocto DISTRO_FEATURES                (特性组合)
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml

DEP3_REQUIRED = ("Description", "Origin", "Upstream-Status", "Applies-To", "Maintainer", "Last-Update")

# Yocto/OpenEmbedded Upstream-Status 8 状态枚举
# 参照:https://docs.openembedded.org/arch-current/contributor-guide/recipe-style-guide.html
# 对应 docs/version-yaml-spec.md §4.5
YOCTO_UPSTREAM_STATES = frozenset({
    "Pending",
    "Submitted",
    "Accepted",
    "Rejected",
    "Backport",
    "Denied",
    "Inappropriate",
    "Inactive-Upstream",
})

HEADER_END_RE = re.compile(r"^(diff --git |--- |\+\+\+ )", re.MULTILINE)


def parse_patch_header_minimal(text: str) -> dict[str, str]:
    """极简版 patch 头解析:只拿 DEP-3 6 必填字段。"""
    headers: dict[str, str] = {}
    lines = text.splitlines()
    in_header = True
    for line in lines:
        if in_header:
            if HEADER_END_RE.match(line):
                break
            m = re.match(r"^([A-Za-z][A-Za-z0-9-]*):\s*(.*)$", line)
            if m:
                key = m.group(1)
                val = m.group(2).rstrip()
                if val == "|":
                    headers[key] = "<multiline>"
                else:
                    headers[key] = val
            elif line.startswith((" ", "\t")) and headers:
                pass  # continuation, ignore
    return headers


def lint_features(features_yaml: Path) -> list[str]:
    errs: list[str] = []
    patches_dir = features_yaml.parent

    if not features_yaml.is_file():
        return [f"{features_yaml}: 不存在"]

    try:
        data = yaml.safe_load(features_yaml.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        return [f"{features_yaml}: YAML 解析失败: {e}"]

    if not isinstance(data, dict):
        return [f"{features_yaml}: 顶层不是 dict"]

    features = data.get("features", {})
    if not isinstance(features, dict) or not features:
        return [f"{features_yaml}: 没有 features 段(或为空)"]

    # 1. 每个 feature 字段完整
    declared_patches: set[tuple[str, str]] = set()  # (feature, patch)
    for fname, info in features.items():
        if not isinstance(info, dict):
            errs.append(f"{features_yaml}: feature {fname!r} 不是 dict")
            continue
        if not info.get("title"):
            errs.append(f"{features_yaml}: feature {fname!r}: title 缺失")
        patches = info.get("patches")
        if not isinstance(patches, list) or not patches:
            errs.append(f"{features_yaml}: feature {fname!r}: patches 缺失或为空")
            continue
        for p in patches:
            declared_patches.add((fname, p))
            full = patches_dir / "features" / fname / p
            if not full.is_file():
                errs.append(f"{features_yaml}: feature {fname!r}: patch 不存在 {full}")

        deps = info.get("depends", []) or []
        if not isinstance(deps, list):
            errs.append(f"{features_yaml}: feature {fname!r}: depends 不是 list")
            deps = []

        # 1.a upstream_status schema:单值,必须是 Yocto 8 状态枚举之一
        # 业界参照:Yocto recipe Upstream-Status(单值)+ 该 feature 下 patch 头 Upstream-Status: 聚合
        up_status = info.get("upstream_status")
        if up_status is not None:
            if up_status not in YOCTO_UPSTREAM_STATES:
                errs.append(
                    f"{features_yaml}: feature {fname!r}.upstream_status={up_status!r} "
                    f"不是 Yocto 8 状态之一(合法值: {sorted(YOCTO_UPSTREAM_STATES)})"
                )

    # 2. depends 引用必须存在
    for fname, info in features.items():
        if not isinstance(info, dict):
            continue
        for dep in (info.get("depends", []) or []):
            if dep not in features:
                errs.append(f"{features_yaml}: feature {fname!r}.depends={dep!r} 未知")

    # 3. 环依赖检测
    def has_cycle(start: str) -> bool:
        seen: set[str] = set()
        stack = [start]
        while stack:
            n = stack.pop()
            if n in seen:
                continue
            seen.add(n)
            info = features.get(n)
            if not isinstance(info, dict):
                continue
            for d in (info.get("depends", []) or []):
                if d == start:
                    return True
                if d not in seen:
                    stack.append(d)
        return False

    for fname in features:
        if has_cycle(fname):
            errs.append(f"{features_yaml}: feature {fname!r}: 检测到环依赖")

    # 4. 孤儿检查:patches/features/<feature>/*.patch 必须在 features.yaml 声明
    feat_root = patches_dir / "features"
    if feat_root.is_dir():
        for fdir in sorted(feat_root.iterdir()):
            if not fdir.is_dir():
                continue
            feat_name = fdir.name
            for p in sorted(fdir.glob("*.patch")):
                if (feat_name, p.name) not in declared_patches:
                    errs.append(f"{features_yaml}: 孤儿 patch (features.yaml 未声明): {feat_name}/{p.name}")

    # 5. DEP-3 6 必填字段
    for fname, info in features.items():
        if not isinstance(info, dict):
            continue
        for p in (info.get("patches", []) or []):
            full = patches_dir / "features" / fname / p
            if not full.is_file():
                continue
            try:
                text = full.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            hdr = parse_patch_header_minimal(text)
            missing = [k for k in DEP3_REQUIRED if not hdr.get(k)]
            if missing:
                errs.append(f"{full}: 缺 DEP-3 必填字段: {', '.join(missing)}")

    return errs


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("用法: lint_series.py <features.yaml-or-patches-dir>...", file=sys.stderr)
        return 2

    targets: list[Path] = []
    for arg in argv[1:]:
        p = Path(arg)
        if p.is_dir():
            # patches/ 目录 → 找 features.yaml
            fy = p / "features.yaml"
            if not fy.is_file():
                print(f"  ⚠ {p}/features.yaml 不存在,跳过", file=sys.stderr)
                continue
            targets.append(fy)
        elif p.is_file() and p.name == "features.yaml":
            targets.append(p)
        else:
            print(f"✗ {arg}: 不是 features.yaml 文件也不是 patches 目录", file=sys.stderr)
            return 1

    if not targets:
        print("✗ 未找到任何 features.yaml", file=sys.stderr)
        return 1

    all_errs: list[str] = []
    for fy in targets:
        errs = lint_features(fy)
        if errs:
            all_errs.extend(errs)
            for e in errs:
                print(f"  ✗ {e}", file=sys.stderr)
        else:
            print(f"  ✓ {fy}: features.yaml schema OK,DEP-3 必填字段全")

    print(f"--- features.yaml lint: {len(targets)} 个,"
          f"{len(all_errs)} 个错误 ---")
    return 0 if not all_errs else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))