#!/bin/bash
# apply_patch.sh — Buildroot/OpenWrt 风格的 patch series 应用器
#
# 参考:
#   - Buildroot: support/scripts/apply-patches.sh
#     https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh
#   - OpenWrt:   scripts/patch-kernel.sh + 每个 package 下的 patches/series
#     https://github.com/openWRT/openwrt/tree/main/scripts
#   - SUSE:      scripts/apply-patches (kernel-source)
#
# 用法:
#   apply_patch.sh <upstream_repo> <upstream_commit> <series_file> <patch_dir> <work_dir> [patch_args...]
#
# 参数:
#   upstream_repo    upstream git URL (例: https://github.com/redis/redis)
#   upstream_commit  40-char SHA,要 checkout 的基线
#   series_file      patches/series 文件路径
#   patch_dir        patch 文件所在目录
#   work_dir         工作目录(会在里面创建 upstream/ 子目录,带 cache)
#   patch_args       透传给 git apply 的额外参数 (例: --whitespace=fix)
#
# 行为:
#   - 若 work_dir/upstream/.git 不存在 → git clone
#   - 若目标 commit 不在本地 → git fetch --depth 1 origin <commit>
#   - git checkout <commit>
#   - 按 series 文件顺序逐条 git apply (从 patch_dir/<filename>)
#     - 空行 / # 开头行跳过
#     - 行内可写 -p1 / -R 等 guard(取行首 token,过滤空白后传给 git apply)
#   - 任一条失败 → exit 1
#
# 输出:
#   写到 stdout:每条 patch "  ✓ <filename>" / 失败 "  ✗ <filename>: reason"

set -euo pipefail

if [ $# -lt 5 ]; then
    echo "Usage: $0 <upstream_repo> <upstream_commit> <series_file> <patch_dir> <work_dir> [patch_args...]" >&2
    exit 2
fi

REPO="$1"
COMMIT="$2"
SERIES="$3"
PATCH_DIR="$4"
WORK="$5"
shift 5
EXTRA_ARGS=("$@")

# 转绝对路径(脚本 cd 进 upstream 后相对路径会失效)
SERIES="$(cd "$(dirname "$SERIES")" && pwd)/$(basename "$SERIES")"
PATCH_DIR="$(cd "$PATCH_DIR" && pwd)"

# 40-char SHA 校验
if ! [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "✗ upstream_commit 不是 40-char SHA: $COMMIT" >&2
    exit 2
fi

[ -f "$SERIES" ]  || { echo "✗ series 文件不存在: $SERIES"  >&2; exit 2; }
[ -d "$PATCH_DIR" ] || { echo "✗ patch_dir 不存在: $PATCH_DIR" >&2; exit 2; }

mkdir -p "$WORK"
cd "$WORK"

# === 1. clone + checkout ===
if [ ! -d "upstream/.git" ]; then
    echo "→ clone $REPO"
    git clone --quiet "$REPO" upstream
fi

cd upstream
if ! git cat-file -t "$COMMIT" >/dev/null 2>&1; then
    echo "→ fetch $COMMIT"
    git fetch --quiet --depth 1 origin "$COMMIT" || \
        { git fetch --quiet --unshallow origin; git fetch --quiet --tags origin; }
fi
git checkout -q "$COMMIT"
HEAD_SHORT="$(git rev-parse --short HEAD)"
echo "→ upstream @ $HEAD_SHORT"
cd ..

# === 2. 按 series 应用 ===
ok=0
warn=0
total=0

while IFS= read -r raw || [ -n "$raw" ]; do
    # 去行内注释 + trim
    line="${raw%%#*}"
    line="$(echo "$line" | xargs 2>/dev/null || echo "$line")"
    [ -z "$line" ] && continue

    # 拆 patch 文件名 vs 行内 guards(以 - 开头的 token 提到 EXTRA)
    args=("${EXTRA_ARGS[@]}")
    file=""
    for tok in $line; do
        case "$tok" in
            -*) args+=("$tok") ;;
            *)   [ -z "$file" ] && file="$tok" ;;
        esac
    done
    [ -z "$file" ] && continue

    total=$((total+1))
    patch_path="$PATCH_DIR/$file"
    if [ ! -f "$patch_path" ]; then
        echo "  ✗ $file: 文件不存在 ($patch_path)"
        exit 1
    fi

    if git -C upstream apply "${args[@]}" "$patch_path" 2>/tmp/apply.err; then
        echo "  ✓ $file"
        ok=$((ok+1))
    else
        echo "  ✗ $file: apply 失败"
        sed 's/^/      /' /tmp/apply.err
        warn=$((warn+1))
        # 默认 hard-fail;设 APPLY_NON_STRICT=1 才降级 warning
        if [ "${APPLY_NON_STRICT:-0}" != "1" ]; then
            exit 1
        fi
    fi
done < "$SERIES"

echo "→ apply summary: ✓ $ok / ✗ $warn / total $total"
exit 0
