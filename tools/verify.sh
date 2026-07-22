#!/usr/bin/env bash
# verify — patch overlay 仓一键验证 (v6.0)
#
# 执行:
#   1. lint (manifest + DEP-3 + patch headers)
#   2. clean apply (委托 apply_patch.sh)
#
# 用法: bash tools/verify.sh
set -e
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export APPLY_NON_STRICT="${VERIFY_STRICT:-0}"
errs=0
echo "=== boostkit verify ==="

# === 0. lint gate ===
echo "--- lint ---"
python3 "$ROOT/tools/lint.py" all src/*/ || { echo "✗ lint 未通过"; exit 1; }

# === manifest + apply ===
echo ""
echo "--- manifest + apply ---"
vcount=0

for vdir in src/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    manifest="$vdir/manifest.yaml"

    if [ ! -f "$manifest" ]; then
        echo "  ✗ $vname: 缺 manifest.yaml"
        errs=$((errs+1)); continue
    fi

    read_vars=$(python3 - "$manifest" <<'PYEOF'
import sys, yaml, re, json
from pathlib import Path

m = yaml.safe_load(Path(sys.argv[1]).read_text())
if not isinstance(m, dict):
    print("ERR:not_a_dict"); sys.exit(0)

errs = []
for f in ("repo", "version", "commit"):
    if not m.get(f):
        errs.append(f"missing {f}")
commit = m.get("commit", "")
if commit and not re.fullmatch(r"[0-9a-f]{40}", commit or ""):
    errs.append(f"commit must be 40-char SHA, got {commit!r}")

print(json.dumps({
    "repo": m.get("repo", ""),
    "version": m.get("version", ""),
    "commit": commit,
    "errs": errs,
}))
PYEOF
    )

    if [ "$(echo "$read_vars" | head -c 3)" = "ERR" ]; then
        echo "  ✗ $vname: manifest.yaml 解析失败"
        errs=$((errs+1)); continue
    fi

    PYERRS=$(python3 -c "import json,sys; print('\n'.join(json.loads(sys.argv[1]).get('errs',[])))" "$read_vars")
    if [ -n "$PYERRS" ]; then
        echo "  ✗ $vname: manifest 字段错误:"
        echo "$PYERRS" | sed 's/^/      /'
        errs=$((errs+1)); continue
    fi

    VERSION=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['version'])" "$read_vars")
    REPO=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['repo'])" "$read_vars")

    echo "  ✓ $vname: $REPO @ $VERSION"
    vcount=$((vcount+1))

    # 读取 conflicts 以便逐个 feature apply
    CONFLICTS=$(python3 - "$manifest" <<'PYEOF'
import sys, yaml, json
m = yaml.safe_load(open(sys.argv[1]))
feats = m.get("features") or {}
c = []
for f, v in feats.items():
    for cf in (v.get("conflicts") or []):
        c.append([f, cf])
print(json.dumps(c))
PYEOF
    )

    WORK=$(mktemp -d)
    HAS_CONFLICTS=$(echo "$CONFLICTS" | python3 -c "import json,sys; sys.exit(0 if json.loads(sys.stdin.read()) else 1)" 2>/dev/null && echo true || echo false)

    if $HAS_CONFLICTS; then
        # 有冲突：逐个 feature 单独 apply
        for feat_dir in "$vdir"*/; do
            feat=$(basename "$feat_dir")
            [[ "$feat" == .* ]] && continue
            compgen -G "$feat_dir*.patch" > /dev/null 2>&1 || continue
            echo "    → 单独 apply: $feat"
            SKIP_INSTALL=1 bash "$ROOT/tools/apply_patch.sh" \
                --features "$feat" "$vdir" "$WORK" 2>&1 | sed 's/^/      /' || {
                echo "    ✗ $feat apply 失败"
                errs=$((errs+1))
            }
            rm -rf "$WORK/upstream"
        done
    else
        # 无冲突：全量 apply
        SKIP_INSTALL=1 bash "$ROOT/tools/apply_patch.sh" "$vdir" "$WORK" 2>&1 | sed 's/^/    /' || {
            rc=$?
            echo "  ✗ $vname: apply_patch.sh 退出 (rc=$rc)"
            errs=$((errs+1))
        }
    fi
    rm -rf "$WORK"
done

echo "--- 汇总 ---"
if [ "$errs" = "0" ]; then
    echo "✓ verify 全部通过 ($vcount 个版本)"
    exit 0
else
    echo "✗ verify 失败 ($errs 个错误)"
    exit 1
fi
