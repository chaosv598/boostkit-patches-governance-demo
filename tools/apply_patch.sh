#!/bin/bash
# apply_patch.sh — Buildroot 风格的 patch 应用器 (v6.0)
#
# 业界参照:
#   Buildroot: support/scripts/apply-patches.sh
#   Linux Kconfig: depends 深度优先解析
#
# 用法:
#   apply_patch.sh [--features "f1 f2"] <version_dir> <work_dir>
#
#   --features "f1 f2"  只 apply 指定 feature 子集
#   不传 = apply 全部
#   ACTIVE_FEATURES 环境变量也可用（CI 场景）
#
# repo/version/commit 从 version_dir/manifest.yaml 读取。

set -euo pipefail

if [ $# -lt 2 ]; then
    cat >&2 <<'USAGE'
Usage: apply_patch.sh [--features "f1 f2"] <version_dir> <work_dir>

Examples:
  apply_patch.sh src/Redis-7.0.15 /tmp/build
  apply_patch.sh --features "rdb-aof-fallback" src/Redis-7.0.15 /tmp/build
USAGE
    exit 2
fi

FEATURES_ARG="${ACTIVE_FEATURES:-}"

# parse --features flag
while [ $# -gt 0 ]; do
    case "$1" in
        --features)
            [ $# -ge 2 ] || { echo "✗ --features 需要参数" >&2; exit 2; }
            FEATURES_ARG="$2"
            shift 2
            ;;
        -*)
            echo "✗ 未知选项: $1" >&2; exit 2
            ;;
        *)
            break
            ;;
    esac
done

VERSION_DIR="$1"
WORK="$2"
shift 2

VERSION_DIR="$(cd "$VERSION_DIR" && pwd)"
[ -d "$VERSION_DIR" ] || { echo "✗ version_dir 不存在: $VERSION_DIR" >&2; exit 2; }
MANIFEST="$VERSION_DIR/manifest.yaml"
[ -f "$MANIFEST" ] || { echo "✗ manifest.yaml 不存在: $MANIFEST" >&2; exit 2; }

# === 从 manifest 读取 upstream info ===
MANIFEST_DATA=$(python3 - "$MANIFEST" <<'PYEOF'
import sys, yaml, json, re
m = yaml.safe_load(open(sys.argv[1]))
errs = []
for f in ("repo","version","commit"):
    if not m.get(f): errs.append(f"missing {f}")
c = m.get("commit","")
if c and not re.fullmatch(r"[0-9a-f]{40}", c or ""):
    errs.append(f"commit must be 40-char SHA, got {c!r}")
if errs:
    sys.exit(", ".join(errs))
print(json.dumps({
    "repo": m["repo"], "version": m["version"], "commit": m["commit"],
    "depends": m.get("depends"),
}))
PYEOF
) || { echo "✗ manifest 解析失败: $?" >&2; exit 2; }

REPO=$(echo "$MANIFEST_DATA" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['repo'])")
COMMIT=$(echo "$MANIFEST_DATA" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['commit'])")
VERSION=$(echo "$MANIFEST_DATA" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['version'])")

echo "→ $VERSION_DIR ($VERSION @ $COMMIT)"

# === 发现 feature 目录 ===
ALL_FEATURES=()
for d in "$VERSION_DIR"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    [[ "$name" == .* ]] && continue
    compgen -G "$d*.patch" > /dev/null 2>&1 && ALL_FEATURES+=("$name")
done

if [ ${#ALL_FEATURES[@]} -eq 0 ]; then
    echo "✗ 没有 feature (无 *.patch)" >&2; exit 2
fi

ACTIVE="$FEATURES_ARG"
HAS_DEPENDS=$(echo "$MANIFEST_DATA" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if isinstance(d.get('depends'),dict) and d['depends'] else 1)" 2>/dev/null && echo true || echo false)

TMP_SERIES="$(mktemp)"
trap 'rm -f "$TMP_SERIES"' EXIT

if $HAS_DEPENDS; then
    echo "→ depends: DFS 解析"
    python3 - "$MANIFEST" "$ACTIVE" "$VERSION_DIR" "$TMP_SERIES" <<'PYEOF'
import sys, yaml
from pathlib import Path

manifest = Path(sys.argv[1]); active_str = sys.argv[2]
version_dir = Path(sys.argv[3]); out = Path(sys.argv[4])
data = yaml.safe_load(manifest.read_text(encoding="utf-8"))
depends = data.get("depends", {}) or {}

if active_str.strip():
    active = active_str.split()
else:
    active = [d.name for d in sorted(version_dir.iterdir())
              if d.is_dir() and not d.name.startswith(".") and list(d.glob("*.patch"))]

seen = set(); resolved = []
def resolve(name, stack=()):
    if name in seen: return
    if name in stack: sys.exit(f"环依赖: {' -> '.join(stack + (name,))}")
    for dep in depends.get(name, []): resolve(dep, stack + (name,))
    seen.add(name); resolved.append(name)

for a in active:
    if a in depends: resolve(a)
for d in sorted(version_dir.iterdir()):
    if d.is_dir() and not d.name.startswith(".") and list(d.glob("*.patch")):
        if d.name not in seen: resolved.append(d.name); seen.add(d.name)

# conflicts check
feats = data.get("features") or {}
if isinstance(feats, dict):
    for f in resolved:
        for c in (feats.get(f, {}).get("conflicts") or []):
            if c in resolved:
                sys.exit(f"冲突: {f} 和 {c} 不能同时激活，请用 --features 选择其一")

total = 0; lines = [f"# Buildroot series from {manifest.name}", ""]
for feat in resolved:
    for pf in sorted((version_dir / feat).glob("*.patch")):
        lines.append(f"{feat}/{pf.name}"); total += 1
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"  features: {resolved} ({total} patches)")
PYEOF
    [ $? -ne 0 ] && { echo "✗ depends 解析失败" >&2; exit 1; }
else
    echo "→ features: 字典序"
    if [ -n "$ACTIVE" ]; then
        FEATURES=()
        for f in $ACTIVE; do
            found=false
            for af in "${ALL_FEATURES[@]}"; do [ "$f" = "$af" ] && found=true && break; done
            $found && FEATURES+=("$f") || { echo "✗ 未知 feature: $f" >&2; exit 2; }
        done
    else
        FEATURES=("${ALL_FEATURES[@]}")
    fi
    echo "  features: ${FEATURES[*]}"

    # === conflicts 检查 ===
    CONFLICTS_YAML=$(python3 - "$MANIFEST" <<'PYEOF'
import sys, yaml, json
m = yaml.safe_load(open(sys.argv[1]))
feats = m.get("features")
if not isinstance(feats, dict) or not feats:
    print("{}"); sys.exit(0)
conflicts = {k: v.get("conflicts", []) or [] for k, v in feats.items() if v.get("conflicts")}
print(json.dumps(conflicts))
PYEOF
    )
    if [ "$CONFLICTS_YAML" != "{}" ]; then
        CONFLICT_CHECK=$(python3 - "$CONFLICTS_YAML" "${FEATURES[*]}" <<'PYEOF'
import sys, json
conflicts = json.loads(sys.argv[1])
selected = sys.argv[2].split()
for f in selected:
    for c in conflicts.get(f, []):
        if c in selected:
            print(f"冲突: {f} 和 {c} 不能同时激活，请用 --features 选择其一"); sys.exit(1)
PYEOF
        ) || { echo "  ✗ $CONFLICT_CHECK" >&2; exit 1; }
    fi

    total=0; { echo "# Buildroot series"; echo ""; } > "$TMP_SERIES"
    for feat in "${FEATURES[@]}"; do
        for pf in $(ls "$VERSION_DIR/$feat"/*.patch 2>/dev/null | sort); do
            echo "${pf#$VERSION_DIR/}" >> "$TMP_SERIES"; total=$((total+1))
        done
    done
    echo "  → $total patches"
fi

# === clone + checkout ===
mkdir -p "$WORK"; cd "$WORK"
if [ ! -d "upstream/.git" ]; then
    echo "→ clone $REPO"; git clone --quiet "$REPO" upstream
fi
cd upstream
if ! git cat-file -t "$COMMIT" >/dev/null 2>&1; then
    echo "→ fetch $COMMIT"; git fetch --quiet --depth 1 origin "$COMMIT" || { git fetch --quiet --unshallow origin; git fetch --quiet --tags origin; }
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
echo "→ apply: ✓ $ok / ✗ $warn / total $n"

# === install (skip if SKIP_INSTALL=1) ===
if [ "${SKIP_INSTALL:-0}" = "1" ]; then
    echo ""
    echo "--- install: 跳过 (SKIP_INSTALL=1)"
else
INSTALL_DATA=$(python3 - "$MANIFEST" "$VERSION_DIR" <<'PYEOF'
import sys, yaml, json
from pathlib import Path
m = yaml.safe_load(Path(sys.argv[1]).read_text())
inst = m.get("install")
if not isinstance(inst, dict) or not inst:
    print("{}"); sys.exit(0)
version_dir = Path(sys.argv[2]); out = {}
deps = inst.get("deps", []) or []
missing = [d for d in deps if not (version_dir / d).exists()]
if missing: out["deps_missing"] = missing
config = inst.get("configure", "").strip()
build_cmd = inst.get("build", "").strip()
if config: out["configure"] = config
if build_cmd: out["build"] = build_cmd
print(json.dumps(out))
PYEOF
)
if [ "$INSTALL_DATA" != "{}" ]; then
    echo ""; echo "--- install ---"
    MISSING=$(echo "$INSTALL_DATA" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print('\n'.join(d.get('deps_missing',[])))")
    [ -n "$MISSING" ] && { echo "  ⚠ 缺少 build 依赖:"; echo "$MISSING" | sed 's/^/      /'; }
    CONFIG=$(echo "$INSTALL_DATA" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('configure',''))")
    BUILD=$(echo "$INSTALL_DATA" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('build',''))")
    [ -n "$CONFIG" ] && { echo "  → $CONFIG"; (cd upstream && eval "$CONFIG") || echo "  ⚠ configure 失败"; }
    [ -n "$BUILD" ] && { echo "  → $BUILD"; (cd upstream && eval "$BUILD") || echo "  ⚠ build 失败（可能需 Kunpeng 硬件）"; }
fi
fi
exit 0
