#!/usr/bin/env python3
"""
lint_patch_headers —— 校验每个 .patch 文件的 DEP-3 邮件式头 schema

对齐:
  - DEP-3 (Debian Enhancement Proposal 3, patches 头格式规范)
    https://dep-team.pages.debian.net/deps/dep3/
  - Yocto OpenEmbedded Upstream-Status 8 状态语义
    https://docs.yoctoproject.org/dev/dev-manual/common-tasks.html#patches
  - SUSE kernel-source Git-commit 元数据校验思路

校验规则(完整规范见 docs/version-yaml-spec.md §4):
  必填 6 字段 (用户要求):
    Description     - 目的/Description (DEP-3 标准字段)
    Origin          - 来源 (DEP-3 扩展;记 PR/URL/内部)
    Upstream-Status - 上游状态 (Yocto 8 状态枚举)
    Applies-To      - 适用上游版本 (自定义;例: "redis 7.0.15")
    Maintainer      - 维护人 (DEP-3 扩展;BoosKit owner,不一定等于 From)
    Last-Update     - 最后更新时间 (DEP-3 标准字段)

  额外必填 (对齐 git format-patch):
    From            - 作者
    Subject         - 标题
    Signed-off-by   - DCO 签名

  条件必填 (按 Upstream-Status 状态):
    Submitted/Accepted/Backport → Upstream-PR
    Accepted/Backport           → Upstream-Commit (40-char SHA)
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

# === 必填字段 ===
# 用户明确要求的 6 字段(DEP-3 + 自定义)
USER_REQUIRED_6 = (
    "Description",      # 目的
    "Origin",           # 来源
    "Upstream-Status",  # 上游状态
    "Applies-To",       # 适用版本
    "Maintainer",       # 维护人
    "Last-Update",      # 最后更新时间
)

# 额外必填(对齐 git format-patch + DCO)
EXTRA_REQUIRED = ("From", "Subject", "Signed-off-by")

ALL_REQUIRED = USER_REQUIRED_6 + EXTRA_REQUIRED

# === Upstream-Status 枚举(对齐 Yocto 8 状态) ===
VALID_STATUSES = {
    "Pending", "Submitted", "Accepted", "Rejected",
    "Backport", "Inappropriate", "Denied", "Inactive-Upstream",
}

# === 条件必填映射 ===
STATUS_REQUIRES_PR = {"Submitted", "Accepted", "Backport"}
STATUS_REQUIRES_COMMIT = {"Accepted", "Backport"}
STATUS_REQUIRES_WHITELIST_REASON = {
    "Rejected", "Inappropriate", "Denied", "Inactive-Upstream",
}
MIN_WHITELIST_REASON_LEN = 30
MIN_DESCRIPTION_LEN = 20  # Description 不能太短,避免空泛

# patch 头解析:从文件开头读,直到第一个 diff 行(`--- a/...` 或 `diff --git`)
# 注意:必须用 MULTILINE,否则 ^ 只匹配文件开头
HEADER_END_RE = re.compile(r"^(diff --git |--- |\+\+\+ )", re.MULTILINE)
SHA_RE = re.compile(r"^[0-9a-f]{40}$")


def parse_header(text: str) -> tuple[dict[str, str], str]:
    """从 patch 文件头解析键值对。返回 (header_dict, body_without_header).

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


def lint_patch(patch_path: Path) -> list[str]:
    """检查单个 patch 文件,返回错误列表(空 = 全过)."""
    errs: list[str] = []
    text = patch_path.read_text(encoding="utf-8", errors="replace")

    if not HEADER_END_RE.search(text):
        return [f"{patch_path}: 不是 patch 文件(缺少 diff/---/+++ 段)"]

    headers, _ = parse_header(text)

    # === 必填 6 字段(用户要求) ===
    for f in USER_REQUIRED_6:
        if f not in headers or not headers[f].strip():
            errs.append(f"{patch_path}: 缺必填字段 {f}:")

    # === 额外必填 ===
    for f in EXTRA_REQUIRED:
        if f not in headers or not headers[f].strip():
            errs.append(f"{patch_path}: 缺必填字段 {f}:")

    # === Description 长度(防空泛) ===
    desc = headers.get("Description", "").strip()
    if desc and len(desc) < MIN_DESCRIPTION_LEN:
        errs.append(
            f"{patch_path}: Description 太短 ({len(desc)} < {MIN_DESCRIPTION_LEN} 字符)"
        )

    # === Last-Update 日期格式(YYYY-MM-DD) ===
    lu = headers.get("Last-Update", "").strip()
    if lu and not re.match(r"^\d{4}-\d{2}-\d{2}$", lu):
        errs.append(
            f"{patch_path}: Last-Update={lu!r} 不是 YYYY-MM-DD 格式"
        )

    # === Upstream-Status 枚举 + 条件必填 ===
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
