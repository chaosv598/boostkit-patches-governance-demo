#!/bin/bash
# apply_patch.sh — Buildroot 风格的 patch 应用器 (v6.0)
#
# 业界参照:
#   Buildroot: support/scripts/apply-patches.sh
#     按目录文件名字典序 apply，不维护系列文件，目录即配置。
#   Linux Kconfig: depends 深度优先解析
#     https://www.kernel.org/doc/Documentation/kbuild/kconfig-language.rst
#
# 用法:
#   apply_patch.sh <repo> <sha> <version_dir> <work_dir>
#
#   环境变量:
#     ACTIVE_FEATURES="f1 f2"  只 apply 指定 feature 子集 (空格分隔)
#     不设 = apply 版本目录下所有含 .patch 的子目录
#
# 排序规则:
#   1. 如果 manifest.yaml 有 depends → DFS 深度优先解析
#      depends: { C: [B, A] } → B 先于 A，都在 C 之前
#   2. 如果 manifest.yaml 无 depends → feature 目录名字典序
#   3. 每个 feature 内: *.patch 文件名字典序

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
      versions/redis-7.0.15 /tmp/build
USAGE
    exit 2
fi

REPO="$1"
COMMIT="$2"
VERSION_DIR="$3"
WORK="$4"
shift 4

if ! [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "✗ upstream_commit 不是 40-char SHA: $COMMIT" >&2; exit 2
fi

VERSION_DIR="$(cd "$VERSION_DIR" && pwd)"
[ -d "$VERSION_DIR" ] || { echo "✗ version_dir 不存在: $VERSION_DIR" >&2; exit 2; }

# === 发现 feature 目录 ===
ALL_FEATURES=()
for d in "$VERSION_DIR"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    [[ "$name" == .* ]] && continue
    compgen -G "$d*.patch" > /dev/null 2>&1 && ALL_FEATURES+=("$name")
done

if [ ${#ALL_FEATURES[@]} -eq 0 ]; then
    echo "✗ 版本目录下没有 feature (无 *.patch)" >&2; exit 2
fi

# === 确定激活 feature + 排序 ===
ACTIVE="${ACTIVE_FEATURES:-}"
MANIFEST="$VERSION_DIR/manifest.yaml"

# 解析 depends（可选，只在 manifest 有 depends 段时才用 DFS）
HAS_DEPENDS=false
python3 -c "
import yaml, sys
m = yaml.safe_load(open('$MANIFEST'))
d = m.get('depends')
sys.exit(0 if isinstance(d, dict) and d else 1)
" 2>/dev/null && HAS_DEPENDS=true || true

if $HAS_DEPENDS; then
    echo "→ depends: 深度优先解析"
    TMP_SERIES="$(mktemp)"
    trap 'rm -f "$TMP_SERIES"' EXIT

    python3 - "$MANIFEST" "$ACTIVE" "$VERSION_DIR" "$TMP_SERIES" <<'PYEOF'
import sys, yaml
from pathlib import Path

manifest = Path(sys.argv[1])
active_str = sys.argv[2]
version_dir = Path(sys.argv[3])
out = Path(sys.argv[4])

data = yaml.safe_load(manifest.read_text(encoding="utf-8"))
depends = data.get("depends", {}) or {}

# 确定激活的 feature
if active_str.strip():
    active = active_str.split()
else:
    active = [d.name for d in sorted(version_dir.iterdir())
              if d.is_dir() and not d.name.startswith(".") and list(d.glob("*.patch"))]

# DFS 解析: depends 列表顺序 = 依赖项之间的 apply 顺序
seen = set()
resolved = []
def resolve(name, stack=()):
    if name in seen:
        return
    if name in stack:
        cycle = " -> ".join(stack + (name,))
        sys.exit(f"环依赖: {cycle}")
    for dep in depends.get(name, []):
        resolve(dep, stack + (name,))
    seen.add(name)
    resolved.append(name)

for a in active:
    if a not in depends:
        # 不在 depends 里的 feature, 按字典序在后面处理
        pass
    resolve(a)

# 不在 depends 里也没被拉入的 feature, 按字典序追加
for d in sorted(version_dir.iterdir()):
    if d.is_dir() and not d.name.startswith(".") and list(d.glob("*.patch")):
        if d.name not in seen:
            resolved.append(d.name)
            seen.add(d.name)

# 构建 patch 列表
total = 0
lines = [f"# Buildroot-style series from {manifest.name}", ""]
for feat in resolved:
    feat_dir = version_dir / feat
    for pf in sorted(feat_dir.glob("*.patch")):
        lines.append(f"{feat}/{pf.name}")
        total += 1

out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"  features: {resolved} ({total} patches)")
PYEOF
    if [ $? -ne 0 ]; then
        echo "✗ depends 解析失败" >&2; exit 1
    fi
else
    # 无 depends → 字典序
    echo "→ features: 字典序"
    TMP_SERIES="$(mktemp)"
    trap 'rm -f "$TMP_SERIES"' EXIT

    if [ -n "$ACTIVE" ]; then
        FEATURES=()
        for f in $ACTIVE; do
            found=false
            for af in "${ALL_FEATURES[@]}"; do
                [ "$f" = "$af" ] && found=true && break
            done
            $found && FEATURES+=("$f") || { echo "✗ 未知 feature: $f (可用: ${ALL_FEATURES[*]})" >&2; exit 2; }
        done
    else
        FEATURES=("${ALL_FEATURES[@]}")
    fi
    echo "  features: ${FEATURES[*]}"

    total=0
    { echo "# Buildroot-style: composed by apply_patch.sh"; echo ""; } > "$TMP_SERIES"
    for feat in "${FEATURES[@]}"; do
        for pf in $(ls "$VERSION_DIR/$feat"/*.patch 2>/dev/null | sort); do
            echo "${pf#$VERSION_DIR/}" >> "$TMP_SERIES"
            total=$((total+1))
        done
    done
    echo "  → $total patches"
fi

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
ok=0; warn=0; n=0
while IFS= read -r raw || [ -n "$raw" ]; do
    line="${raw%%#*}"; line="$(echo "$line" | xargs 2>/dev/null || echo "$line")"
    [ -z "$line" ] && continue
    n=$((n+1))
    patch_path="$VERSION_DIR/$line"
    [ -f "$patch_path" ] || { echo "  ✗ $line: 不存在"; exit 1; }

    if git -C upstream apply "$patch_path" 2>/tmp/apply.err; then
        echo "  ✓ $line"; ok=$((ok+1))
    else
        echo "  ✗ $line: apply 失败"; sed 's/^/      /' /tmp/apply.err; warn=$((warn+1))
        [ "${APPLY_NON_STRICT:-0}" != "1" ] && exit 1
    fi
done < "$TMP_SERIES"

echo "→ apply summary: ✓ $ok / ✗ $warn / total $n"
exit 0
