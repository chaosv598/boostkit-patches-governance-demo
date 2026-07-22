#!/bin/bash
# apply_patch.sh — Buildroot 风格的 patch 应用器 (v6.0)
#
# 业界参照:
#   - Buildroot: support/scripts/apply-patches.sh
#     https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh
#     单点应用器，按目录文件名字典序遍历 patch，不维护 series 文件
#   - DEP-3: patch 邮件式头 schema
#     https://dep-team.pages.debian.net/deps/dep3/
#     6 必填字段（由 lint.py headers 校验，不在本脚本内部）
#
# 用法:
#   apply_patch.sh <repo> <sha> --manifest <manifest.yaml> [--active "f1 f2"] <version_dir> <work_dir>
#
#   ACTIVE_FEATURES="f1 f2"   env 覆盖（优先级低于 --active）
#   默认 = manifest.yaml 中 default:true 的并集
#
# 参数:
#   upstream_repo   上游 git URL
#   upstream_commit  40-char SHA
#   --manifest       manifest.yaml 路径（含 upstream pin + feature config）
#   --active "f1 f2" 显式激活的 feature 列表（空格分隔）
#   version_dir      版本目录（feature 子目录所在）
#   work_dir         工作目录
#
# 行为:
#   1. 解析 manifest.yaml → upstream info + features
#   2. 确定激活的 feature 列表 + DFS 解析 depends
#   3. 遍历 feature 目录，按 *.patch 文件名字典序构建 apply 顺序
#   4. git clone + checkout upstream
#   5. git apply 每个 patch
#   6. 任一条失败 → exit 1 (APPLY_NON_STRICT=1 时降级 warning)

set -euo pipefail

# === 参数解析 ===
if [ $# -lt 3 ]; then
    cat >&2 <<'USAGE'
Usage:
  apply_patch.sh <repo> <sha> --manifest <manifest.yaml> [--active "f1 f2"] <version_dir> <work_dir>

Examples:
  # 默认组合 (default:true 的并集)
  apply_patch.sh https://github.com/redis/redis f35f36a265403c07b119830aa4bb3b7d71653ec9 \
      --manifest versions/redis-7.0.15/manifest.yaml \
      versions/redis-7.0.15 /tmp/build

  # 客户 A: 只要 rdb-aof-fallback
  ACTIVE_FEATURES="rdb-aof-fallback" apply_patch.sh ... /tmp/build-a

  # 等价 --active
  apply_patch.sh ... --active "rdb-aof-fallback" ... /tmp/build-c

Selecting feature subsets:
  - uses --active "f1 f2 ..." or ACTIVE_FEATURES env var
  - depends are auto-resolved (activating C that depends on A → A applied first)
USAGE
    exit 2
fi

REPO="$1"
COMMIT="$2"
shift 2

MANIFEST=""
ACTIVE="${ACTIVE_FEATURES:-}"
VERSION_DIR=""
WORK=""

while [ $# -gt 0 ]; do
    case "$1" in
        --manifest)
            [ $# -ge 2 ] || { echo "✗ --manifest 需要参数" >&2; exit 2; }
            MANIFEST="$2"
            shift 2
            ;;
        --active)
            [ $# -ge 2 ] || { echo "✗ --active 需要参数" >&2; exit 2; }
            ACTIVE="$2"
            shift 2
            ;;
        -*)
            echo "✗ 未知选项: $1" >&2; exit 2
            ;;
        *)
            if [ -z "$VERSION_DIR" ]; then
                VERSION_DIR="$1"
            elif [ -z "$WORK" ]; then
                WORK="$1"
            else
                echo "✗ 多余位置参数: $1" >&2; exit 2
            fi
            shift
            ;;
    esac
done

[ -n "$MANIFEST" ] || { echo "✗ 必须指定 --manifest" >&2; exit 2; }
[ -n "$VERSION_DIR" ] || { echo "✗ 缺 version_dir" >&2; exit 2; }
[ -n "$WORK" ] || { echo "✗ 缺 work_dir" >&2; exit 2; }

MANIFEST="$(cd "$(dirname "$MANIFEST")" && pwd)/$(basename "$MANIFEST")"
VERSION_DIR="$(cd "$VERSION_DIR" && pwd)"

[ -f "$MANIFEST" ] || { echo "✗ manifest.yaml 不存在: $MANIFEST" >&2; exit 2; }
[ -d "$VERSION_DIR" ] || { echo "✗ version_dir 不存在: $VERSION_DIR" >&2; exit 2; }

if ! [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "✗ upstream_commit 不是 40-char SHA: $COMMIT" >&2
    exit 2
fi

# === 解析 manifest.yaml + 确定 patch 顺序 ===
echo "→ manifest: $MANIFEST"
echo "  ACTIVE_FEATURES=${ACTIVE:-<manifest defaults>}"

TMP_SERIES="$(mktemp)"
trap 'rm -f "$TMP_SERIES"' EXIT

python3 - "$MANIFEST" "$ACTIVE" "$VERSION_DIR" "$TMP_SERIES" <<'PYEOF'
import sys, yaml
from pathlib import Path

m_path = Path(sys.argv[1])
active_str = sys.argv[2]
version_dir = Path(sys.argv[3])
out = Path(sys.argv[4])

try:
    data = yaml.safe_load(m_path.read_text(encoding="utf-8"))
except yaml.YAMLError as e:
    sys.exit(f"manifest.yaml YAML 解析失败: {e}")

if not isinstance(data, dict):
    sys.exit("manifest.yaml: 顶层不是 dict")

upstream = data.get("upstream", {})
if not upstream.get("repo") or not upstream.get("version") or not upstream.get("commit"):
    sys.exit("manifest.yaml: 缺 upstream.repo/version/commit")

features = data.get("features", {})
if not isinstance(features, dict) or not features:
    sys.exit("manifest.yaml: 没有 features 段（或为空）")

# 默认 active = default:true 的并集
if not active_str.strip():
    active = [n for n, f in features.items() if f.get("default", False)]
else:
    active = active_str.split()

if not active:
    sys.exit(f"manifest.yaml: 没有激活的 feature (ACTIVE_FEATURES={active_str!r} 且无 default:true)")

# DFS 解析 depends（depends 在前）
seen = set()
resolved = []
def resolve(name, stack=()):
    if name in seen:
        return
    if name in stack:
        cycle = " -> ".join(stack + (name,))
        sys.exit(f"环依赖: {cycle}")
    if name not in features:
        sys.exit(f"未知 feature: {name!r} (在 ACTIVE 或 depends 里)")
    f = features[name]
    for dep in (f.get("depends", []) or []):
        resolve(dep, stack + (name,))
    seen.add(name)
    resolved.append(name)

for a in active:
    resolve(a)

# 构建 patch 列表：遍历 feature 目录，按 *.patch 文件名字典序
total_patches = 0
lines = [
    f"# Buildroot-style: composed by apply_patch.sh from {m_path.name}",
    f"# ACTIVE_FEATURES={active_str or '<manifest defaults>'}",
    f"# RESOLVED_FEATURES={' '.join(resolved)}",
    "",
]
for feat in resolved:
    feat_dir = version_dir / feat
    if not feat_dir.is_dir():
        sys.exit(f"feature {feat!r}: 目录不存在 {feat_dir}")
    patch_files = sorted(feat_dir.glob("*.patch"))
    if not patch_files:
        sys.exit(f"feature {feat!r}: 目录下没有 .patch 文件 {feat_dir}")
    for pf in patch_files:
        lines.append(f"{feat}/{pf.name}")
        total_patches += 1

out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"  ✓ composed {len(resolved)} features → {total_patches} patches → {out}")
PYEOF

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
HEAD_SHORT="$(git rev-parse --short HEAD)"
echo "→ upstream @ $HEAD_SHORT"
cd ..

# === 按顺序 apply ===
ok=0
warn=0
total=0

while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%#*}"
    line="$(echo "$line" | xargs 2>/dev/null || echo "$line")"
    [ -z "$line" ] && continue

    total=$((total+1))
    patch_path="$VERSION_DIR/$line"
    if [ ! -f "$patch_path" ]; then
        echo "  ✗ $line: 文件不存在 ($patch_path)"
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

echo "→ apply summary: ✓ $ok / ✗ $warn / total $total"
exit 0
