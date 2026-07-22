#!/bin/bash
# apply_patch.sh — Buildroot 风格的 patch 应用器 (v6.0)
#
# 业界参照:
#   Buildroot: support/scripts/apply-patches.sh
#     https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh
#     按目录文件名字典序 apply，不维护系列文件，目录即配置。
#
# 用法:
#   apply_patch.sh <repo> <sha> <version_dir> <work_dir>
#
#   环境变量:
#     ACTIVE_FEATURES="f1 f2"  只 apply 指定 feature 子集 (空格分隔)
#     不设 = apply 版本目录下所有含 .patch 的子目录 (字典序)
#
# 行为:
#   1. git clone + checkout upstream
#   2. 扫描 version_dir 发现 feature 目录 (含 *.patch 的子目录)
#   3. 按 ACTIVE_FEATURES 过滤 (不设 = 全量)
#   4. 按 feature 目录名字典序遍历，每个 feature 内按 *.patch 文件名字典序 apply

set -euo pipefail

if [ $# -lt 4 ]; then
    cat >&2 <<'USAGE'
Usage:
  apply_patch.sh <repo> <sha> <version_dir> <work_dir>

Examples:
  # 全部 feature
  apply_patch.sh https://github.com/redis/redis \
      f35f36a265403c07b119830aa4bb3b7d71653ec9 \
      versions/redis-7.0.15 /tmp/build

  # 只选 rdb-aof-fallback
  ACTIVE_FEATURES="rdb-aof-fallback" apply_patch.sh \
      https://github.com/redis/redis f35f36a265403c07b119830aa4bb3b7d71653ec9 \
      versions/redis-7.0.15 /tmp/build-a
USAGE
    exit 2
fi

REPO="$1"
COMMIT="$2"
VERSION_DIR="$3"
WORK="$4"
shift 4

if ! [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "✗ upstream_commit 不是 40-char SHA: $COMMIT" >&2
    exit 2
fi

VERSION_DIR="$(cd "$VERSION_DIR" && pwd)"
[ -d "$VERSION_DIR" ] || { echo "✗ version_dir 不存在: $VERSION_DIR" >&2; exit 2; }

# === 发现 feature 目录 (Buildroot 风格: 目录即配置) ===
echo "→ scan features in $VERSION_DIR"
ALL_FEATURES=()
for d in "$VERSION_DIR"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    # 跳过隐藏目录和非目录
    [[ "$name" == .* ]] && continue
    # feature = 目录下有 .patch 文件
    if compgen -G "$d*.patch" > /dev/null 2>&1; then
        ALL_FEATURES+=("$name")
    fi
done

if [ ${#ALL_FEATURES[@]} -eq 0 ]; then
    echo "✗ 版本目录下没有 feature (无 *.patch)" >&2
    exit 2
fi

# === 确定激活的 feature ===
ACTIVE="${ACTIVE_FEATURES:-}"
if [ -n "$ACTIVE" ]; then
    FEATURES=()
    for f in $ACTIVE; do
        found=false
        for af in "${ALL_FEATURES[@]}"; do
            if [ "$f" = "$af" ]; then found=true; break; fi
        done
        if $found; then
            FEATURES+=("$f")
        else
            echo "✗ 未知 feature: $f (可用: ${ALL_FEATURES[*]})" >&2
            exit 2
        fi
    done
    echo "  ACTIVE_FEATURES=${FEATURES[*]} (用户指定)"
else
    FEATURES=("${ALL_FEATURES[@]}")
    echo "  features=${FEATURES[*]} (全部)"
fi

# === 构建 patch apply 顺序 ===
TMP_SERIES="$(mktemp)"
trap 'rm -f "$TMP_SERIES"' EXIT

total=0
{
    echo "# Buildroot-style: composed by apply_patch.sh"
    echo "# features: ${FEATURES[*]}"
    echo ""
    for feat in "${FEATURES[@]}"; do
        for pf in $(ls "$VERSION_DIR/$feat"/*.patch 2>/dev/null | sort); do
            rel="${pf#$VERSION_DIR/}"
            echo "$rel"
            total=$((total+1))
        done
    done
} > "$TMP_SERIES"

echo "  → ${#FEATURES[@]} features, $total patches"

# === clone + checkout ===
mkdir -p "$WORK"
cd "$WORK"

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
echo "→ upstream @ $(git rev-parse --short HEAD)"
cd ..

# === apply ===
ok=0
warn=0
n=0

while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%#*}"
    line="$(echo "$line" | xargs 2>/dev/null || echo "$line")"
    [ -z "$line" ] && continue

    n=$((n+1))
    patch_path="$VERSION_DIR/$line"
    if [ ! -f "$patch_path" ]; then
        echo "  ✗ $line: 文件不存在"
        exit 1
    fi

    if git -C upstream apply "$patch_path" 2>/tmp/apply.err; then
        echo "  ✓ $line"
        ok=$((ok+1))
    else
        echo "  ✗ $line: apply 失败"
        sed 's/^/      /' /tmp/apply.err
        warn=$((warn+1))
        if [ "${APPLY_NON_STRICT:-0}" != "1" ]; then
            exit 1
        fi
    fi
done < "$TMP_SERIES"

echo "→ apply summary: ✓ $ok / ✗ $warn / total $n"
exit 0
