#!/usr/bin/env bash
# verify —— patch overlay 仓一键验证(PR / 合并前的 gate)
#
# 检查 3 件事(其他职责移到 .github/ lint 脚本):
#
#   1. 仓根禁放检查(防误提交 upstream 源码/Dockerfile/Makefile 等)
#      业界出处:
#        - Buildroot support/scripts/check-package —— 强制 package/<name>/ 目录结构
#          https://buildroot.org/downloads/manual/manual.html#_infrastructure_for_packages
#        - OpenWrt scripts/feeds —— feed 树结构校验
#          https://github.com/openWRT/openwrt/tree/main/scripts/feeds
#        - Linux kernel scripts/checkpatch.pl —— 树结构 + patch 合规性
#          https://github.com/torvalds/linux/blob/master/scripts/checkpatch.pl
#
#   2. versions/<v>/upstream.yaml schema(Yocto recipe 字段 + 上游 pin 校验)
#      业界出处:
#        - Yocto/OpenEmbedded recipe 字段(SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION)
#          https://docs.yoctoproject.org/ref-manual/variables.html
#        - Git 40-char SHA-1 校验(Software Heritage / git 自身实践)
#          https://git-scm.com/docs/githashes
#
#   3. 干净 upstream apply:委托给 tools/apply_patch.sh
#      业界出处:(详见 apply_patch.sh 头部注释)
#        - Buildroot apply-patches.sh 单点 series 应用器
#        - OpenWrt Config.in + Makefile 特性声明 + 条件 PATCHFILES
#        - Linux kernel Kconfig depends/select/default 语义
#        - Yocto/OpenEmbedded 条件 SRC_URI
#        - DEP-3 patch 邮件式头 schema
#
# 用法: bash tools/verify.sh
# 环境变量:
#   VERIFY_STRICT=0   任何 apply 失败即 exit 1 (hard-fail)
#   VERIFY_STRICT=1   apply 失败降级 warning (默认,跟传统 verify.sh 一致)
# 退出码: 0 全过 / 1 有失败
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 非严格 = 默认 1 (apply 失败降级 warning);VERIFY_STRICT=0 改为严格
export APPLY_NON_STRICT="${VERIFY_STRICT:-1}"

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
echo "--- upstream.yaml 校验 + feature apply ---"
vcount=0

for vdir in versions/*/; do
    [ -d "$vdir" ] || continue
    vname=$(basename "$vdir")
    uyaml="$vdir/upstream.yaml"
    features_yaml="$vdir/patches/features.yaml"
    patches_dir="$vdir/patches"

    if [ ! -f "$uyaml" ]; then
        echo "  ✗ $vname: 缺 upstream.yaml"
        errs=$((errs+1))
        continue
    fi
    if [ ! -f "$features_yaml" ]; then
        echo "  ✗ $vname: 缺 patches/features.yaml"
        errs=$((errs+1))
        continue
    fi
    if [ ! -d "$patches_dir" ]; then
        echo "  ✗ $vname: 缺 patches/ 目录"
        errs=$((errs+1))
        continue
    fi

    # 读 upstream.yaml(python,保留顺序 + 校验 SHA 40-char + Yocto 字段)
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
# === upstream pin (必填 + SHA 格式校验) ===
if not isinstance(up, dict) or not up.get("repo"):
    errs.append("missing upstream.repo")
if not up.get("version"):
    errs.append("missing upstream.version")
commit = up.get("commit", "")
if not commit:
    errs.append("missing upstream.commit")
elif not re.fullmatch(r"[0-9a-f]{40}", commit or ""):
    errs.append(f"upstream.commit must be 40-char SHA, got {commit!r}")

# === Yocto recipe 字段(强推荐)— 不填只 warning,不阻塞 ===
yocto_warn = []
for f in ("SUMMARY", "LICENSE", "HOMEPAGE"):
    if not m.get(f):
        yocto_warn.append(f"{f} missing (Yocto-style recipe field)")

# === meta.owner 推荐填 ===
if meta and not meta.get("owner"):
    errs.append("meta.owner missing (recommended)")

out = {
    "repo": up.get("repo", ""),
    "version": up.get("version", ""),
    "commit": commit,
    "summary": m.get("SUMMARY", ""),
    "license": m.get("LICENSE", ""),
    "homepage": m.get("HOMEPAGE", ""),
    "errs": errs,
    "warns": yocto_warn,
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

    PYWARNS=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print('\n'.join(d.get('warns',[])))" "$read_vars")
    [ -n "$PYWARNS" ] && echo "$PYWARNS" | sed "s/^/  ⚠ $vname: /"

    REPO=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['repo'])" "$read_vars")
    SHA=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['commit'])" "$read_vars")
    VERSION=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['version'])" "$read_vars")

    # 列出默认激活的 feature(给 stdout 反馈)
    default_active=$(python3 - "$features_yaml" <<'PYEOF'
import sys, yaml
data = yaml.safe_load(open(sys.argv[1]))
feats = data.get("features", {}) or {}
print(" ".join(n for n, f in feats.items() if f.get("default", False)))
PYEOF
    )

    echo "  ✓ $vname: upstream @ $VERSION ($SHA), default features: ${default_active:-<none>}"

    # === 3. 委托 tools/apply_patch.sh(单点实现,v5.0 --features 模式)===
    WORK=$(mktemp -d)
    if bash "$ROOT/tools/apply_patch.sh" \
        "$REPO" "$SHA" \
        --features "$features_yaml" \
        "$patches_dir" "$WORK" 2>&1 | sed 's/^/    /'; then
        : # 成功
    else
        rc=$?
        # 非严格模式时 apply_patch.sh 会 exit 0 即使有 warning;rc!=0 时才是 hard 失败
        echo "  ✗ $vname: apply_patch.sh 退出 (rc=$rc)"
        errs=$((errs+1))
    fi
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
