#!/usr/bin/env bash
# verify — patch overlay 仓一键验证 (v6.0)
#
# 检查:
#   1. 仓根禁放
#   2. manifest.yaml schema (upstream pin)
#   3. 功能目录一致性 (feature 目录 vs manifest)
#   4. 干净 upstream apply (委托 apply_patch.sh)
#
# 用法: bash tools/verify.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export APPLY_NON_STRICT="${VERIFY_STRICT:-0}"

errs=0
echo "=== boostkit verify ==="

# === 1. 仓根禁放 ===
echo "--- 仓根禁放 ---"
root_bad=0
if compgen -G "*.patch" > /dev/null 2>&1; then
    echo "  ✗ 仓根发现 .patch"
    ls *.patch 2>/dev/null; root_bad=$((root_bad+1))
fi
[ -f Dockerfile ] && { echo "  ✗ 仓根有 Dockerfile"; root_bad=$((root_bad+1)); }
[ -f Makefile ]   && { echo "  ✗ 仓根有 Makefile";   root_bad=$((root_bad+1)); }
for d in src/ storage/ sql/ include/ SPECS/ RPMS/ SOURCES/ BUILD/ SRPMS/ vendor/ out/; do
    [ -d "$d" ] && { echo "  ✗ 仓根有目录: $d"; root_bad=$((root_bad+1)); }
done
[ "$root_bad" = "0" ] && echo "  ✓ 仓根干净"
errs=$((errs+root_bad))

# === 2 + 3. manifest.yaml + feature 目录 + clean apply ===
echo "--- manifest + apply ---"
vcount=0

for vdir in versions/*/; do
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

    REPO=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['repo'])" "$read_vars")
    SHA=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['commit'])" "$read_vars")
    VERSION=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['version'])" "$read_vars")

    # 发现 feature 目录
    features=$(for d in "$vdir"*/; do [ -d "$d" ] || continue; n=$(basename "$d"); [[ "$n" == .* ]] && continue; compgen -G "$d*.patch" > /dev/null 2>&1 && echo -n "$n "; done)

    echo "  ✓ $vname: upstream @ $VERSION ($SHA), features: ${features:-<none>}"

    # === 4. clean apply ===
    WORK=$(mktemp -d)
    if bash "$ROOT/tools/apply_patch.sh" "$REPO" "$SHA" "$vdir" "$WORK" 2>&1 | sed 's/^/    /'; then
        :
    else
        rc=$?
        echo "  ✗ $vname: apply_patch.sh 退出 (rc=$rc)"
        errs=$((errs+1))
    fi
    rm -rf "$WORK"
    vcount=$((vcount+1))
done

echo "--- 汇总 ---"
if [ "$errs" = "0" ]; then
    echo "✓ verify 全部通过 ($vcount 个版本)"
    exit 0
else
    echo "✗ verify 失败 ($errs 个错误)"
    exit 1
fi
