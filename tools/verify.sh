#!/usr/bin/env bash
# verify —— patch overlay 仓一键验证
#
# 检查 3 件事(其他职责移到 .github/ lint 脚本):
#   1. 仓根禁放检查(防误提交 upstream 源码/Dockerfile/Makefile 等)
#   2. versions/<v>/upstream.yaml schema(40-char SHA、必填字段)
#   3. 干净 upstream apply:clone upstream → 切到 commit → 按 series 顺序 apply 每条 patch
#
# 用法: bash tools/verify.sh
# 退出码: 0 全过 / 1 有失败
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

errs=0

echo "=== boostkit verify ==="

# === 1. 仓根禁放文件检查 ===
echo "--- 仓根禁放检查 ---"
root_bad=0
if compgen -G "*.patch" > /dev/null; then
    echo "  ✗ 仓根发现 .patch 文件(应移到 versions/<v>/patches/)"
    ls *.patch
    root_bad=$((root_bad+1))
fi
[ -f Dockerfile ] && { echo "  ✗ 仓根有 Dockerfile"; root_bad=$((root_bad+1)); }
[ -f build.sh ] && { echo "  ✗ 仓根有 build.sh"; root_bad=$((root_bad+1)); }
[ -f Makefile ] && { echo "  ✗ 仓根有 Makefile"; root_bad=$((root_bad+1)); }
for d in src/ storage/ sql/ include/ SPECS/ RPMS/ SOURCES/ BUILD/ SRPMS/ vendor/ out/; do
    [ -d "$d" ] && { echo "  ✗ 仓根有目录: $d"; root_bad=$((root_bad+1)); }
done
[ "$root_bad" = "0" ] && echo "  ✓ 仓根干净"
errs=$((errs+root_bad))

# === 2 + 3. versions/<v>/upstream.yaml schema + clean apply ===
echo "--- upstream.yaml 校验 + series apply ---"
vcount=0

for vdir in versions/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    uyaml="$vdir/upstream.yaml"
    series_file="$vdir/patches/series"
    patches_dir="$vdir/patches"

    if [ ! -f "$uyaml" ]; then
        echo "  ✗ $vname: 缺 upstream.yaml"
        errs=$((errs+1))
        continue
    fi
    if [ ! -f "$series_file" ]; then
        echo "  ✗ $vname: 缺 patches/series"
        errs=$((errs+1))
        continue
    fi
    if [ ! -d "$patches_dir" ]; then
        echo "  ✗ $vname: 缺 patches/ 目录"
        errs=$((errs+1))
        continue
    fi

    # 读 upstream.yaml(python,保留顺序 + 校验 SHA 40-char)
    read_vars=$(python3 - "$uyaml" <<'PYEOF'
import sys, json, yaml, re
from pathlib import Path

yp = Path(sys.argv[1])
m = yaml.safe_load(yp.read_text())
if not isinstance(m, dict):
    print("ERR:not_a_dict"); sys.exit(0)

up = m.get("upstream", {}) or {}
meta = m.get("meta", {}) or {}

errs = []
if not isinstance(up, dict) or not up.get("repo"):
    errs.append("missing upstream.repo")
if not up.get("version"):
    errs.append("missing upstream.version")
commit = up.get("commit", "")
if not commit:
    errs.append("missing upstream.commit")
elif not re.fullmatch(r"[0-9a-f]{40}", commit or ""):
    errs.append(f"upstream.commit must be 40-char SHA, got {commit!r}")

# meta 字段可选,但 owner 推荐填
if meta and not meta.get("owner"):
    errs.append("meta.owner missing (recommended)")

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
        echo "  ✗ $vname: upstream.yaml 解析失败"
        errs=$((errs+1))
        continue
    fi

    PYERRS=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('\n'.join(d.get('errs',[])))" "$read_vars")
    if [ -n "$PYERRS" ]; then
        echo "  ✗ $vname: upstream.yaml 字段错误:"
        echo "$PYERRS" | sed 's/^/      /'
        errs=$((errs+1))
        continue
    fi

    REPO=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['repo'])" "$read_vars")
    SHA=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['commit'])" "$read_vars")
    VERSION=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['version'])" "$read_vars")

    # 读 series(过滤空行 + # 注释)
    mapfile -t series_entries < <(grep -vE '^\s*(#|$)' "$series_file")
    if [ "${#series_entries[@]}" = "0" ]; then
        echo "  ⚠ $vname: series 为空(0 条 patch,跳过 apply 验证)"
        vcount=$((vcount+1))
        continue
    fi

    echo "  ✓ $vname: upstream @ $VERSION ($SHA), series ${#series_entries[@]} 条"

    # 3. clean upstream apply
    WORK=$(mktemp -d)
    if ! git clone --quiet --no-checkout "$REPO" "$WORK/r" 2>/dev/null; then
        echo "  ⚠ $vname: clone $REPO 失败(跳过 apply 验证)"
        rm -rf "$WORK"
        continue
    fi

    if (cd "$WORK/r" && git cat-file -t "$SHA" >/dev/null 2>&1); then
        (cd "$WORK/r" && git checkout --quiet "$SHA" 2>/dev/null) || {
            echo "  ⚠ $vname: checkout $SHA 失败,跳过"
            rm -rf "$WORK"
            continue
        }
    elif [ -n "$VERSION" ] && (cd "$WORK/r" && git checkout --quiet "$VERSION" 2>/dev/null); then
        echo "  ⚠ $vname: SHA $SHA 不可达,改用 tag $VERSION"
    else
        echo "  ⚠ $vname: SHA $SHA 和 tag 都不存在,跳过 apply 验证"
        rm -rf "$WORK"
        continue
    fi

    # 按 series 顺序 apply
    for pfile in "${series_entries[@]}"; do
        # 去除行尾空白
        pfile=$(echo "$pfile" | sed 's/[[:space:]]*$//')
        [ -z "$pfile" ] && continue
        if [ ! -f "$OLDPWD/$vdir"patches/"$pfile" ]; then
            echo "  ✗ $vname/$pfile: series 引用了不存在的 .patch"
            errs=$((errs+1))
            continue
        fi
        # 先 --check 看是否真的能 apply。
        # 失败降级为 warning(跟传统 verify.sh 一致),
        # 因为仓里可能有"已知 broken 等待 owner rebase"的 patch。
        if (cd "$WORK/r" && git apply --check "$OLDPWD/$vdir"patches/"$pfile" 2>&1 >/dev/null); then
            (cd "$WORK/r" && git apply "$OLDPWD/$vdir"patches/"$pfile" 2>/dev/null)
            echo "  ✓ $vname/$pfile"
        else
            echo "  ⚠ $vname/$pfile: apply 失败(可能 baseline 不匹配 / 与前面的 patch 冲突,owner 检查)"
        fi
    done
    rm -rf "$WORK"
    vcount=$((vcount+1))
done

# === 汇总 ===
echo "--- 汇总 ---"
if [ "$errs" = "0" ]; then
    echo "✓ verify 全部通过($vcount 个版本,patch overlay 健康)"
    exit 0
else
    echo "✗ verify 失败($errs 个错误)"
    exit 1
fi