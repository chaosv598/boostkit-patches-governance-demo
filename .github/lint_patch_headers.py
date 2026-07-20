#!/usr/bin/env python3
"""
lint_patch_headers —— 校验每个 .patch 文件的 RFC822 邮件式头 schema

字段对齐 Yocto Upstream-Status + SUSE Git-commit + DEP-3 header。

校验规则(完整规范见 docs/version-yaml-spec.md §4):
  必填:From / Subject / Upstream-Status / Signed-off-by
  条件必填(按 Upstream-Status 状态):
    Submitted/Accepted/Backport → Upstream-PR
    Accepted/Backport → Upstream-Commit
    Rejected/Inappropriate/Denied/Inactive-Upstream → Whitelist-Reason (≥30 字符)

用法:
  python3 .github/lint_patch_headers.py versions/*/patches/*.patch
  python3 .github/lint_patch_headers.py versions/redis-7.0.15/patches/

退出码:
  0 全过 / 1 有失败
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

# 必填字段集合
REQUIRED = ("From", "Subject", "Upstream-Status", "Signed-off-by")

# Upstream-Status 枚举(对齐 Yocto)
VALID_STATUSES = {
    "Pending", "Submitted", "Accepted", "Rejected",
    "Backport", "Inappropriate", "Denied", "Inactive-Upstream",
}

# 条件必填映射
STATUS_REQUIRES_PR = {"Submitted", "Accepted", "Backport"}
STATUS_REQUIRES_COMMIT = {"Accepted", "Backport"}
STATUS_REQUIRES_WHITELIST_REASON = {
    "Rejected", "Inappropriate", "Denied", "Inactive-Upstream",
}
MIN_WHITELIST_REASON_LEN = 30

# patch 头解析:从文件开头读,直到第一个 diff 行(`--- a/...` 或 `diff --git`)
# 注意:必须用 MULTILINE,否则 ^ 只匹配文件开头
HEADER_END_RE = re.compile(r"^(diff --git |--- |\+\+\+ )", re.MULTILINE)


def parse_header(text: str) -> tuple[dict[str, str], str]:
    """从 patch 文件头解析键值对。
    返回 (header_dict, body_without_header).

    解析规则:
      - 邮件式头(From: / Date: / Subject: 等)按 'Key: Value' 解析
      - 支持 RFC822 风格延续行(下一行以空格/tab 开头)
      - 支持 YAML literal block 延续(`Key: |` 后接缩进行)
      - 第一个 diff / --- / +++ 行视为 body 开始
    """
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
            # 尝试 Key: Value 解析
            km = re.match(r"^([A-Za-z][A-Za-z0-9-]*):\s*(.*)$", line)
            if km:
                key = km.group(1)
                val = km.group(2).rstrip()
                if val == "|":
                    # YAML literal block: 收集后续缩进行
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
                # RFC822 延续行(上一行的延续)
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
                # 不可识别的行(可能是 commit message body 在 Subject 后),
                # 跳过(假设 body 不强制解析)
                i += 1
                continue
        else:
            body_lines.append(line)
            i += 1

    return headers, "\n".join(body_lines)


def lint_patch(patch_path: Path) -> list[str]:
    """检查单个 patch 文件,返回错误列表(空 = 全过)."""
    errs: list[str] = []
    text = patch_path.read_text(encoding="utf-8", errors="replace")

    # 必须包含 diff 段(否则不是 patch 文件)
    if not HEADER_END_RE.search(text):
        return [f"{patch_path}: 不是 patch 文件(缺少 diff/---/+++ 段)"]

    headers, _ = parse_header(text)

    # 必填字段检查
    for f in REQUIRED:
        if f not in headers or not headers[f].strip():
            errs.append(f"{patch_path}: 缺必填头 {f}:")

    # Upstream-Status 枚举检查
    status = headers.get("Upstream-Status", "").strip()
    if status and status not in VALID_STATUSES:
        errs.append(
            f"{patch_path}: Upstream-Status={status!r} 非法;"
            f"允许: {', '.join(sorted(VALID_STATUSES))}"
        )

    # 条件必填检查
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
        elif not re.fullmatch(r"[0-9a-f]{40}", commit):
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


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("用法: lint_patch_headers.py <patch-or-dir>...", file=sys.stderr)
        return 2

    paths: list[Path] = []
    for arg in argv[1:]:
        p = Path(arg)
        if p.is_dir():
            paths.extend(sorted(p.rglob("*.patch")))
        elif p.is_file():
            paths.append(p)
        else:
            print(f"✗ {arg}: 不存在", file=sys.stderr)
            return 1

    if not paths:
        print("(无 .patch 文件)")
        return 0

    all_errs: list[str] = []
    for p in paths:
        errs = lint_patch(p)
        if errs:
            all_errs.extend(errs)
            for e in errs:
                print(f"  ✗ {e}", file=sys.stderr)
        else:
            print(f"  ✓ {p}")

    print(f"--- patch header lint: {len(paths)} 个文件,{len(all_errs)} 个错误 ---")
    return 0 if not all_errs else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))