#!/bin/bash
# apply_patch.sh — Buildroot 风格的 patch series 应用器
#                   + OpenWrt Config.in / Linux kernel Kconfig / Yocto 条件 SRC_URI
#                   风格的 feature+combo compose (v5.0)
#
# 参考(业界 5 家,详见 docs/governance.md §2):
#   - Buildroot: support/scripts/apply-patches.sh
#     https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh
#     单点 series 应用器架构(line 读 + skip 空行/注释 + 行内 guards -pN/-R 透传
#     + git apply 调用),本仓直接复用架构
#   - OpenWrt:   package/<name>/{Config.in,Makefile}
#     https://github.com/openWRT/openwrt/tree/main/package
#     Config.in:bool 选项 + depends + default —— 对应本仓 features.yaml
#     Makefile:  条件 PATCHFILES                —— 对应本仓 --active
#   - Linux kernel Kconfig: depends / select / default 语义
#     https://www.kernel.org/doc/Documentation/kbuild/kconfig-language.rst
#     深度优先 depends 解析 + 环依赖检测 —— 本仓 inline python heredoc 实现
#     本仓 features.<name>.depends 字段直接对齐 Kconfig `depends on`(同款 DFS + 环检测)
#   - Yocto/OpenEmbedded: recipes-*/<pkg>.bbappend 条件 SRC_URI
#     ${@bb.utils.contains('DISTRO_FEATURES', 'x', 'y', '', d)} —— 对应 ACTIVE_FEATURES
#   - DEP-3:     patch 邮件式头 schema
#     https://dep-team.pages.debian.net/deps/dep3/
#     每个 .patch 文件头 6 必填字段(由 .github/lint.py headers 校验,
#     不在 apply_patch.sh 内部)
#
# 注:本仓 v5.0 起已删除 patches/series 文件 + series.<profile>,统一改用 features.yaml。
#     v5.1 起已删除 tools/gen_inventory.py(用户反馈:gitignored 派生体系价值有限)。
#     Quilt / Debian `debian/patches/series` / SUSE `series.conf` 仅作历史背景参考,
#     不在 v5.0+ 实际引用范围内(详见 docs/governance.md §2)。
#
# 用法 (两种模式):
#
#   1) 传统 series 文件模式(单 series):
#       apply_patch.sh <repo> <sha> <series_file> <patch_dir> <work_dir> [patch_args...]
#
#   2) Feature+combo 模式 (v5.0+,OpenWrt Config.in 风格):
#       apply_patch.sh <repo> <sha> --features <features.yaml> [--active "f1 f2 ..."] \
#                      <patch_dir> <work_dir> [patch_args...]
#       ACTIVE_FEATURES="f1 f2"   默认 = features.yaml 中 default:true 的并集
#
# 参数:
#   upstream_repo    upstream git URL
#   upstream_commit  40-char SHA
#   series_file      patches/series 文件路径(传统模式)
#   features_yaml    features.yaml 文件路径(feature 模式)
#   --active "f1 f2" 显式指定激活的 feature 列表(空格分隔);默认 = features.yaml 中 default:true
#   patch_dir        patch 文件所在目录(传统模式:series 里直接写文件名;feature 模式:patch_dir + features/<f>/<p>)
#   work_dir         工作目录
#   patch_args       透传给 git apply
#
# 行为:
#   1. 若 work_dir/upstream/.git 不存在 → git clone
#   2. 若目标 commit 不在本地 → git fetch --depth 1 origin <commit>
#   3. git checkout <commit>
#   4. 按 series 顺序逐条 git apply
#      - 空行 / # 开头行跳过
#      - 行内可写 -p1 / -R 等 guard(取行首 token,过滤空白后传给 git apply)
#   5. 任一条失败 → exit 1(APPLY_NON_STRICT=1 时降级 warning)
#
# Feature 模式额外步骤(在 1-2 之前):
#   A. 解析 features.yaml(python inline)+ ACTIVE_FEATURES → 解析依赖 + 检测环
#   B. 生成 tmp series 文件,内容 = 各 feature 的 patches 拼接(depends 在前)
#   C. 后续步骤同传统模式

set -euo pipefail

# === 参数解析 ===
if [ $# -lt 3 ]; then
    cat >&2 <<'USAGE'
Usage:
  apply_patch.sh <repo> <sha> <series_file> <patch_dir> <work_dir> [args...]
  apply_patch.sh <repo> <sha> --features <features.yaml> [--active "f1 f2"] <patch_dir> <work_dir> [args...]

Examples:
  # 传统 series 文件
  apply_patch.sh https://github.com/redis/redis f35f36... \
      versions/redis-7.0.15/patches/series \
      versions/redis-7.0.15/patches /tmp/build

  # Feature 模式(默认 = features.yaml 中 default:true)
  apply_patch.sh https://github.com/redis/redis f35f36... \
      --features versions/redis-7.0.15/patches/features.yaml \
      versions/redis-7.0.15/patches /tmp/build

  # Feature 模式(显式 active,环境变量或 --active)
  ACTIVE_FEATURES="kunpeng-hw-accel jemalloc-arm64" apply_patch.sh \
      https://github.com/redis/redis f35f36... \
      --features versions/redis-7.0.15/patches/features.yaml \
      versions/redis-7.0.15/patches /tmp/build
USAGE
    exit 2
fi

REPO="$1"
COMMIT="$2"
shift 2

# 默认值
SERIES=""
FEATURES_YAML=""
ACTIVE="${ACTIVE_FEATURES:-}"
PATCH_DIR=""
WORK=""

# 解析剩余参数(传统模式 or feature 模式)
while [ $# -gt 0 ]; do
    case "$1" in
        --features)
            [ $# -ge 2 ] || { echo "✗ --features 需要参数" >&2; exit 2; }
            FEATURES_YAML="$2"
            shift 2
            ;;
        --active)
            [ $# -ge 2 ] || { echo "✗ --active 需要参数" >&2; exit 2; }
            ACTIVE="$2"
            shift 2
            ;;
        -*)
            echo "✗ 未知选项: $1" >&2
            exit 2
            ;;
        *)
            # 第一个非选项 = series 或 patch_dir(feature 模式没有 series)
            # 第二个非选项 = patch_dir
            # 第三个非选项 = work_dir
            if [ -z "$SERIES" ] && [ -z "$FEATURES_YAML" ]; then
                SERIES="$1"
            elif [ -z "$PATCH_DIR" ]; then
                PATCH_DIR="$1"
            elif [ -z "$WORK" ]; then
                WORK="$1"
            else
                echo "✗ 多余位置参数: $1" >&2
                exit 2
            fi
            shift
            ;;
    esac
done

# 模式判定
if [ -n "$FEATURES_YAML" ]; then
    MODE="features"
elif [ -n "$SERIES" ]; then
    MODE="series"
else
    echo "✗ 必须指定 series_file 或 --features" >&2
    exit 2
fi

[ -n "$PATCH_DIR" ] || { echo "✗ 缺 patch_dir" >&2; exit 2; }
[ -n "$WORK" ] || { echo "✗ 缺 work_dir" >&2; exit 2; }

# 透传给 git apply 的额外参数
EXTRA_ARGS=("$@")

# 转绝对路径
[ -n "$SERIES" ] && SERIES="$(cd "$(dirname "$SERIES")" && pwd)/$(basename "$SERIES")"
[ -n "$FEATURES_YAML" ] && FEATURES_YAML="$(cd "$(dirname "$FEATURES_YAML")" && pwd)/$(basename "$FEATURES_YAML")"
PATCH_DIR="$(cd "$PATCH_DIR" && pwd)"

# 40-char SHA 校验
if ! [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
    echo "✗ upstream_commit 不是 40-char SHA: $COMMIT" >&2
    exit 2
fi

# === Feature 模式:compose tmp series 文件 ===
TMP_SERIES=""
if [ "$MODE" = "features" ]; then
    [ -f "$FEATURES_YAML" ] || { echo "✗ features.yaml 不存在: $FEATURES_YAML" >&2; exit 2; }
    [ -d "$PATCH_DIR" ] || { echo "✗ patch_dir 不存在: $PATCH_DIR" >&2; exit 2; }

    TMP_SERIES="$(mktemp)"
    trap 'rm -f "$TMP_SERIES"' EXIT

    echo "→ compose features: $FEATURES_YAML"
    echo "  ACTIVE_FEATURES=${ACTIVE:-<features.yaml defaults>}"

    # inline python 解析 features.yaml + 解析依赖 + 写 tmp series 文件
    python3 - "$FEATURES_YAML" "$ACTIVE" "$TMP_SERIES" <<'PYEOF'
import sys
from pathlib import Path
import yaml

yp = Path(sys.argv[1])
active_str = sys.argv[2]
out = Path(sys.argv[3])

try:
    data = yaml.safe_load(yp.read_text(encoding="utf-8"))
except yaml.YAMLError as e:
    sys.exit(f"features.yaml YAML 解析失败: {e}")

if not isinstance(data, dict):
    sys.exit(f"features.yaml: 顶层不是 dict")

features = data.get("features", {})
if not isinstance(features, dict) or not features:
    sys.exit(f"features.yaml: 没有 features 段(或为空)")

# 默认 active = features.yaml 里 default:true 的并集
if not active_str.strip():
    active = [n for n, f in features.items() if f.get("default", False)]
else:
    active = active_str.split()

if not active:
    sys.exit(f"features.yaml: 没有激活的 feature(显式 ACTIVE_FEATURES={active_str!r} 且无 default:true)")

# 解析依赖(深度优先,depends 在前)
seen = set()
resolved = []
def resolve(name, stack=()):
    if name in seen:
        return
    if name in stack:
        cycle = " -> ".join(stack + (name,))
        sys.exit(f"环依赖: {cycle}")
    if name not in features:
        sys.exit(f"未知 feature: {name!r}(在 ACTIVE 或 depends 里)")
    f = features[name]
    if not isinstance(f.get("patches"), list) or not f["patches"]:
        sys.exit(f"feature {name!r}: patches 段缺失或为空")
    if not isinstance(f["patches"], list):
        sys.exit(f"feature {name!r}: patches 不是 list")
    for dep in f.get("depends", []) or []:
        resolve(dep, stack + (name,))
    seen.add(name)
    resolved.append(name)

for a in active:
    resolve(a)

# 校验每个 patch 文件存在(features.yaml 在 patches/ 下,patch 在 patches/features/<f>/<p>)
yp_dir = yp.parent
total_patches = 0
for feat in resolved:
    feat_dir = yp_dir / "features" / feat
    if not feat_dir.is_dir():
        sys.exit(f"feature {feat!r}: 目录不存在 {feat_dir}")
    for p in features[feat]["patches"]:
        ppath = feat_dir / p
        if not ppath.is_file():
            sys.exit(f"feature {feat!r}: patch 不存在 {ppath}")
        total_patches += 1

# 写 tmp series 文件(每行:"features/<feat>/<patch>")
lines = [
    f"# Composed by apply_patch.sh --features from {yp.name}",
    f"# ACTIVE_FEATURES={active_str or '<features.yaml defaults>'}",
    f"# RESOLVED_FEATURES={' '.join(resolved)}",
    "",
]
for feat in resolved:
    for p in features[feat]["patches"]:
        lines.append(f"features/{feat}/{p}")
out.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"  ✓ composed {len(resolved)} features → {total_patches} patches → {out}")
PYEOF

    SERIES="$TMP_SERIES"
fi

[ -f "$SERIES" ]   || { echo "✗ series 文件不存在: $SERIES" >&2; exit 2; }
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