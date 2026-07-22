#!/usr/bin/env python3
"""
lint —— BoostKit Patch 仓统一 lint 工具

对齐:
  - DEP-3 (Debian Enhancement Proposal 3, patches 头格式规范)
    https://dep-team.pages.debian.net/deps/dep3/
  - Yocto/OpenEmbedded Upstream-Status 8 状态语义
    https://docs.yoctoproject.org/dev/dev-manual/common-tasks.html#patches
  - git format-patch 邮件式头(From/Date/Subject/Signed-off-by)
  - OpenWrt package/<name>/Config.in (bool + depends + default schema)
  - Linux kernel Kconfig (depends / select 语义)

用法:
  python3 .github/lint.py headers <patch-or-dir>...   # patch 头校验(DEP-3 6 必填 + 条件必填)
  python3 .github/lint.py features <patches-dir>...   # features.yaml 校验(schema + depends + DEP-3)
  python3 .github/lint.py all <patches-dir>...        # 一键全量(headers + features)

退出码:
  0 全过 / 1 有失败
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import yaml


DEP3_REQUIRED = ("Description", "Origin", "Upstream-Status", "Applies-To", "Maintainer", "Last-Update")

VALID_STATUSES = frozenset({
    "Pending", "Submitted", "Accepted", "Rejected",
    "Backport", "Inappropriate", "Denied", "Inactive-Upstream",
})

STATUS_REQUIRES_PR = {"Submitted", "Accepted", "Backport"}
STATUS_REQUIRES_COMMIT = {"Accepted", "Backport"}
STATUS_REQUIRES_WHITELIST_REASON = {
    "Rejected", "Inappropriate", "Denied", "Inactive-Upstream",
}
MIN_WHITELIST_REASON_LEN = 30
MIN_DESCRIPTION_LEN = 20

HEADER_END_RE = re.compile(r"^(diff --git |--- |\+\+\+ )", re.MULTILINE)
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def parse_header(text: str) -> tuple[dict[str, str], str]:
    headers: dict[str, str] = {}
    body_lines: list[str] = []
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
                body_lines.append(line)
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
                if headers[last_key]:
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
            body_lines.append(line)
            i += 1

    return headers, "\n".join(body_lines)


def parse_header_minimal(text: str) -> dict[str, str]:
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
                headers[key] = "<multiline>" if val == "|" else val
            elif line.startswith((" ", "\t")) and headers:
                pass
    return headers


# === subcommand: headers ===

def lint_patch(patch_path: Path) -> list[str]:
    errs: list[str] = []
    text = patch_path.read_text(encoding="utf-8", errors="replace")

    if not HEADER_END_RE.search(text):
        return [f"{patch_path}: 不是 patch 文件(缺少 diff/---/+++ 段)"]

    headers, _ = parse_header(text)

    for f in DEP3_REQUIRED:
        if f not in headers or not headers[f].strip():
            errs.append(f"{patch_path}: 缺必填字段 {f}:")

    for f in ("From", "Subject", "Signed-off-by"):
        if f not in headers or not headers[f].strip():
            errs.append(f"{patch_path}: 缺必填字段 {f}:")

    desc = headers.get("Description", "").strip()
    if desc and len(desc) < MIN_DESCRIPTION_LEN:
        errs.append(
            f"{patch_path}: Description 太短 ({len(desc)} < {MIN_DESCRIPTION_LEN} 字符)"
        )

    lu = headers.get("Last-Update", "").strip()
    if lu and not re.match(r"^\d{4}-\d{2}-\d{2}$", lu):
        errs.append(
            f"{patch_path}: Last-Update={lu!r} 不是 YYYY-MM-DD 格式"
        )

    status = headers.get("Upstream-Status", "").strip()
    if status and status not in VALID_STATUSES:
        errs.append(
            f"{patch_path}: Upstream-Status={status!r} 非法;"
            f"允许: {', '.join(sorted(VALID_STATUSES))}"
        )

    if status in STATUS_REQUIRES_PR:
        if not headers.get("Upstream-PR", "").strip():
            errs.append(
                f"{patch_path}: Upstream-Status={status} → 必填 Upstream-PR:"
            )
    if status in STATUS_REQUIRES_COMMIT:
        commit = headers.get("Upstream-Commit", "").strip()
        if not commit:
            errs.append(
                f"{patch_path}: Upstream-Status={status} → 必填 Upstream-Commit:"
            )
        elif not SHA_RE.fullmatch(commit):
            errs.append(
                f"{patch_path}: Upstream-Commit={commit!r} 不是 40-char SHA"
            )
    if status in STATUS_REQUIRES_WHITELIST_REASON:
        reason = headers.get("Whitelist-Reason", "").strip()
        if len(reason) < MIN_WHITELIST_REASON_LEN:
            errs.append(
                f"{patch_path}: Upstream-Status={status} → Whitelist-Reason 必填且 ≥{MIN_WHITELIST_REASON_LEN} 字符"
                f"(当前 {len(reason)} 字符)"
            )

    return errs


def cmd_headers(paths: list[Path]) -> int:
    all_errs: list[str] = []
    for p in paths:
        errs = lint_patch(p)
        if errs:
            all_errs.extend(errs)
            for e in errs:
                print(f"  ✗ {e}", file=sys.stderr)
        else:
            print(f"  ✓ {p}")

    print(f"\n--- patch header lint: {len(paths)} 个文件, {len(all_errs)} 个错误 ---")
    return 0 if not all_errs else 1


# === subcommand: features ===

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

    declared_patches: set[tuple[str, str]] = set()
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

        up_status = info.get("upstream_status")
        if up_status is not None:
            if up_status not in VALID_STATUSES:
                errs.append(
                    f"{features_yaml}: feature {fname!r}.upstream_status={up_status!r} "
                    f"不是 Yocto 8 状态之一(合法值: {sorted(VALID_STATUSES)})"
                )

    for fname, info in features.items():
        if not isinstance(info, dict):
            continue
        for dep in (info.get("depends", []) or []):
            if dep not in features:
                errs.append(f"{features_yaml}: feature {fname!r}.depends={dep!r} 未知")

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

    feat_root = patches_dir / "features"
    if feat_root.is_dir():
        for fdir in sorted(feat_root.iterdir()):
            if not fdir.is_dir():
                continue
            feat_name = fdir.name
            for p in sorted(fdir.glob("*.patch")):
                if (feat_name, p.name) not in declared_patches:
                    errs.append(f"{features_yaml}: 孤儿 patch (features.yaml 未声明): {feat_name}/{p.name}")

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
            hdr = parse_header_minimal(text)
            missing = [k for k in DEP3_REQUIRED if not hdr.get(k)]
            if missing:
                errs.append(f"{full}: 缺 DEP-3 必填字段: {', '.join(missing)}")

    return errs


def cmd_features(targets: list[Path]) -> int:
    all_errs: list[str] = []
    for fy in targets:
        errs = lint_features(fy)
        if errs:
            all_errs.extend(errs)
            for e in errs:
                print(f"  ✗ {e}", file=sys.stderr)
        else:
            print(f"  ✓ {fy}: features.yaml schema OK, DEP-3 必填字段全")

    print(f"\n--- features.yaml lint: {len(targets)} 个, {len(all_errs)} 个错误 ---")
    return 0 if not all_errs else 1


# === subcommand: all ===

def cmd_all(features_targets: list[Path], original_args: list[str]) -> int:
    ret = 0
    if cmd_features(features_targets) != 0:
        ret = 1

    patch_dirs: list[Path] = []
    for arg in original_args:
        p = Path(arg)
        if p.is_dir():
            patch_dirs.append(p)

    if patch_dirs:
        patch_paths: list[Path] = []
        for d in patch_dirs:
            patch_paths.extend(sorted(d.rglob("*.patch")))
        if patch_paths and cmd_headers(patch_paths) != 0:
            ret = 1

    return ret


# === arg helpers ===

def collect_patch_paths(args: list[str]) -> list[Path]:
    paths: list[Path] = []
    for arg in args:
        p = Path(arg)
        if p.is_dir():
            paths.extend(sorted(p.rglob("*.patch")))
        elif p.is_file():
            paths.append(p)
        else:
            print(f"✗ {arg}: 不存在", file=sys.stderr)
            sys.exit(1)
    return paths


def collect_features_targets(args: list[str]) -> list[Path]:
    targets: list[Path] = []
    for arg in args:
        p = Path(arg)
        if p.is_dir():
            fy = p / "features.yaml"
            if not fy.is_file():
                print(f"  ⚠ {p}/features.yaml 不存在, 跳过", file=sys.stderr)
                continue
            targets.append(fy)
        elif p.is_file() and p.name == "features.yaml":
            targets.append(p)
        else:
            print(f"✗ {arg}: 不是 features.yaml 文件也不是 patches 目录", file=sys.stderr)
            sys.exit(1)
    if not targets:
        print("✗ 未找到任何 features.yaml", file=sys.stderr)
        sys.exit(1)
    return targets


USAGE = """\
用法:
  python3 .github/lint.py headers <patch-or-dir>...
  python3 .github/lint.py features <patches-dir-or-features.yaml>...
  python3 .github/lint.py all <patches-dir>...

示例:
  python3 .github/lint.py headers versions/*/patches/
  python3 .github/lint.py features versions/*/patches/
  python3 .github/lint.py all versions/*/patches/"""


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(USAGE, file=sys.stderr)
        return 2

    subcmd = argv[1]
    rest = argv[2:]

    if subcmd == "headers":
        paths = collect_patch_paths(rest)
        if not paths:
            print("(无 .patch 文件)")
            return 0
        return cmd_headers(paths)
    elif subcmd == "features":
        targets = collect_features_targets(rest)
        return cmd_features(targets)
    elif subcmd == "all":
        targets = collect_features_targets(rest)
        return cmd_all(targets, rest)
    else:
        print(f"✗ 未知子命令: {subcmd}\n\n{USAGE}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
