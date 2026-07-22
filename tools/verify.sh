#!/usr/bin/env bash
# verify — patch overlay 仓一键验证 (v6.0)
#
# 检查 3 件事:
#   1. 仓根禁放检查
#   2. manifest.yaml schema (upstream pin + features config)
#   3. 干净 upstream apply (委托 apply_patch.sh --manifest)
#
# 用法: bash tools/verify.sh
# 环境变量:
#   VERIFY_STRICT=1   apply 失败 hard-fail
#   VERIFY_STRICT=0   apply 失败降级 warning (默认)
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export APPLY_NON_STRICT="${VERIFY_STRICT:-0}"

errs=0
echo "=== boostkit verify ==="

# === 1. 仓根禁放检查 ===
echo "--- 仓根禁放检查 ---"
root_bad=0
if compgen -G "*.patch" > /dev/null 2>&1; then
    echo "  ✗ 仓根发现 .patch 文件"
    ls *.patch 2>/dev/null
    root_bad=$((root_bad+1))
fi
[ -f Dockerfile ] && { echo "  ✗ 仓根有 Dockerfile"; root_bad=$((root_bad+1)); }
[ -f Makefile ]   && { echo "  ✗ 仓根有 Makefile"; root_bad=$((root_bad+1)); }
for d in src/ storage/ sql/ include/ SPECS/ RPMS/ SOURCES/ BUILD/ SRPMS/ vendor/ out/; do
    [ -d "$d" ] && { echo "  ✗ 仓根有目录: $d"; root_bad=$((root_bad+1)); }
done
[ "$root_bad" = "0" ] && echo "  ✓ 仓根干净"
errs=$((errs+root_bad))

# === 2 + 3. manifest.yaml schema + clean apply ===
echo "--- manifest.yaml 校验 + apply ---"
vcount=0

for vdir in versions/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    manifest="$vdir/manifest.yaml"

    if [ ! -f "$manifest" ]; then
        echo "  ✗ $vname: 缺 manifest.yaml"
        errs=$((errs+1))
        continue
    fi

    # 读 manifest.yaml，校验 upstream pin
    read_vars=$(python3 - "$manifest" <<'PYEOF'
import sys, yaml, re, json
from pathlib import Path

m = yaml.safe_load(Path(sys.argv[1]).read_text())
if not isinstance(m, dict):
    print("ERR:not_a_dict"); sys.exit(0)

up = m.get("upstream", {}) or {}
errs = []
if not up.get("repo"):
    errs.append("missing upstream.repo")
if not up.get("version"):
    errs.append("missing upstream.version")
commit = up.get("commit", "")
if not commit:
    errs.append("missing upstream.commit")
elif not re.fullmatch(r"[0-9a-f]{40}", commit or ""):
    errs.append(f"upstream.commit must be 40-char SHA, got {commit!r}")

features = m.get("features", {}) or {}
if not isinstance(features, dict) or not features:
    errs.append("missing or empty features section")

out = {
    "repo": up.get("repo", ""),
    "version": up.get("version", ""),
    "commit": commit,
    "errs": errs,
}
print(json.dumps(out))
PYEOF
    )

    if [ "$(echo "$read_vars" | head -c 3)" = "ERR" ]; then
        echo "  ✗ $vname: manifest.yaml 解析失败"
        errs=$((errs+1))
        continue
    fi

    PYERRS=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('\n'.join(d.get('errs',[])))" "$read_vars")
    if [ -n "$PYERRS" ]; then
        echo "  ✗ $vname: manifest.yaml 字段错误:"
        echo "$PYERRS" | sed 's/^/      /'
        errs=$((errs+1))
        continue
    fi

    REPO=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['repo'])" "$read_vars")
    SHA=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['commit'])" "$read_vars")
    VERSION=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['version'])" "$read_vars")

    default_active=$(python3 - "$manifest" <<'PYEOF'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
feats = data.get("features", {}) or {}
print(" ".join(n for n, f in feats.items() if f.get("default", False)))
PYEOF
    )

    echo "  ✓ $vname: upstream @ $VERSION ($SHA), default features: ${default_active:-<none>}"

    # === 3. clean apply (委托 apply_patch.sh --manifest) ===
    WORK=$(mktemp -d)
    if bash "$ROOT/tools/apply_patch.sh" \
        "$REPO" "$SHA" \
        --manifest "$manifest" \
        "$vdir" "$WORK" 2>&1 | sed 's/^/    /'; then
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
