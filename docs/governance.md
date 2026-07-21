# Patch Overlay 治理设计

## 1. 模型概述

本仓治理"在固定上游基线上叠加 N 个 patch"的问题,采用业界最广泛采用的
**version-centric + feature 声明** 模型。**v5.0 在 v4.0 (profile + inventory)
基础上,改为 OpenWrt Config.in + Kconfig 风格的 feature + combo 模型,
compose 逻辑集成到 `apply_patch.sh`(不增加新脚本)**:

```
<upstream-id>/
├── upstream.yaml              # Yocto recipe 字段 + 上游基线 + 治理归属
└── patches/
    ├── features.yaml          # ★ feature 声明 + depends + default(OpenWrt Config.in 风格,单一权威)
    ├── features/<feature>/    # 一特性一目录
    │   └── *.patch            # DEP-3 邮件式头(6 必填)+ diff
    └── inventory.json         # 派生(不入仓,见 §2.7)
```

**配套工具**(仓根):
- `tools/apply_patch.sh` — Buildroot 风格 series 应用器 + v5.0 `--features`
  模式(inline compose,集成,无新脚本)
- `tools/gen_inventory.py` — 派生 inventory.json(Buildroot/OpenWrt 风格)
- `tools/verify.sh` — 一键验证(仓根禁放 + upstream.yaml schema + 委托
  apply_patch.sh --features + 派生 inventory)

**核心原则**:

- **唯一权威** = `features.yaml`(feature 声明);patch 物理按 `features/<feature>/` 分目录
- **filename `0001-` 仅辅助阅读** — 可重命名,不影响顺序
- **patch 元数据物理上紧贴 patch** — DEP-3 邮件式头(6 必填:Description /
  Origin / Upstream-Status / Applies-To / Maintainer / Last-Update)
- **`upstream.yaml` recipe 段对齐 Yocto** — SUMMARY/LICENSE/HOMEPAGE/
  LIC_FILES_CHKSUM/SECTION,license audit / 包归属可直接复用
- **apply 单点实现** — `apply_patch.sh` Buildroot 同款 + 内部 compose
  features.yaml → tmp series,verify.sh / build-perf / 本地复跑都走它
- **feature 组合** — OpenWrt `Config.in` + Kconfig `depends` 风格;
  `apply_patch.sh --active "f1 f2"` 或环境变量 `ACTIVE_FEATURES`
- **inventory = 派生物,不入仓** — 单一真相仍是 patch 头 + features.yaml
- **不引入 DAG** — `depends` 解析为线性顺序(被依赖的先 apply)

完整字段定义见 [version-yaml-spec.md](./version-yaml-spec.md)。

---

## 2. 业界出处(集合 5 家)

本设计综合以下 5 个成熟方案的最大公约数。

### 2.1 Yocto/OpenEmbedded — `upstream.yaml` recipe 字段 + `Upstream-Status`

**出处**:
- Recipe 字段: https://docs.yoctoproject.org/ref-manual/variables.html
- Upstream-Status: https://docs.yoctoproject.org/dev/contributor-guide/recipe-style-guide.html

Yocto recipe 用顶层变量描述包元数据,patch 用 `Upstream-Status:` 描述合入状态:

```text
SUMMARY = "Redis in-memory data structure store"
HOMEPAGE = "https://redis.io"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://COPYING;md5=508cbf..."

# Per-patch (in patch header):
Upstream-Status: Submitted
Upstream-Status: Backport [upstream commit URL]
Upstream-Status: Inappropriate [oe specific]
```

**对齐点**:
- `upstream.yaml` 段 1(SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION)
  字段名 = Yocto 同款,可被 license audit / 发布单直接读取
- `Upstream-Status` **8 个枚举值直接对齐 Yocto 命名**:`Pending / Submitted
  / Accepted / Rejected / Backport / Inappropriate / Denied / Inactive-Upstream`
  (仅把 Yocto 的 `[mailing-list-or-URL]` 拆为单独的 `Upstream-PR:` 字段,更结构化)

### 2.2 DEP-3 (Debian Enhancement Proposal 3) — patch 头 schema

**出处**: https://dep-team.pages.debian.net/deps/dep3/

DEP-3 是 Debian 官方 patch header 格式规范,定义必填字段语义:

```text
From: Author <author@example.com>
Subject: Short single-line title
Description: Long multi-line description of what and why
Origin: URL or vendor/branch name (where the patch came from)
Last-Update: YYYY-MM-DD
Bug-Debian: http://bugs.debian.org/123456
Forwarded: yes/no/URL
Applied-Upstream: <commit> / <version> / <URL>
```

**对齐点**:本仓 patch 头采用 DEP-3 6 必填字段:
- `Description` / `Origin` / `Last-Update` —— DEP-3 标准
- `Upstream-Status` —— Yocto(同 §2.1)
- `Applies-To` / `Maintainer` —— DEP-3 扩展(自定义但语义清晰)

### 2.3 Buildroot `support/scripts/apply-patches.sh` — series 应用器

**出处**: https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh

Buildroot 用单点 `apply-patches.sh` 脚本消费 `series` 文件,所有 package 共享:

```bash
# Buildroot apply-patches.sh 节选
while read patch; do
    case "$patch" in ""|\#*) continue ;; esac
    patch=$(echo "$patch" | xargs)
    if ! patch -p1 -d "$target_dir" -i "$patch_dir/$patch"; then
        echo "Failed to apply $patch"; exit 1
    fi
done < "$series"
```

**对齐点**:本仓 `tools/apply_patch.sh` Buildroot 同款:
- 行格式一致(空行 / `#` 注释跳过)
- 行内 guards(`-p1` `-R`)透传
- 失败行为可配置(默认 warning,可改 hard)

**改进 vs Buildroot**:用 `git apply`(集成 git)而非 raw `patch`,自带 fetch cache。

### 2.4 OpenWrt `patches/series` + `patch-kernel.sh` — 同款

**出处**: https://github.com/openWRT/openwrt/tree/main/scripts

OpenWrt 每个 package 一个 `patches/series`,由 `scripts/patch-kernel.sh` 统一应用。

**对齐点**:本仓 `patches/series` 格式(每行 1 条 patch 路径)与 OpenWrt 完全一致。
本仓不写 `patch-kernel.sh`,而用更轻量的 `apply_patch.sh`(只 apply,不打包)。

### 2.5 Quilt / Debian `debian/patches/series` + SUSE kernel-source

**出处**:
- Quilt: https://salsa.debian.org/kernel-team/linux/-/tree/master/debian/patches
- SUSE: https://github.com/openSUSE/kernel-source/blob/master/series.conf

Debian kernel 团队维护上千个 patch,用 `series` 自上而下应用。
SUSE kernel-source 用 `series.conf` 额外带 `Git-commit:` 校验和 + guards。

**对齐点**:本仓 `patches/series` = Quilt 同款。

**未对齐点**(刻意):
- **不引入 `.pc/` 暂存** —— Quilt 的 push/pop 栈对 5–50 patch 量级过度设计
- **不引入 SHA-256 校验和** —— SUSE 的硬校验对小仓 overkill,commit 链本身是审计凭据
- **不引入 guards 机制** —— v3.0 暂不需要,未来按 SUSE `series.conf` 演进

### 2.6 Feature 声明 + 组合 — OpenWrt Config.in + Kconfig 风格

**问题**:同一 upstream 下常有"N 个特性 + 自由组合 + 特性间有依赖"需求
(例:特性 A 必选 / 特性 B 可选 / 特性 C 依赖 A),单一 `series` 文件或
`series.<profile>` 无法表达特性声明 + 依赖关系。

**业界方案**(本仓参考):
- **OpenWrt** `package/<name>/Config.in` — `bool` 选项 + `depends on` + `default y`
- **OpenWrt** `package/<name>/Makefile` — `PATCHFILES := $(if $(CONFIG_X),...)`
- **Linux kernel** `Kconfig` — `depends` / `select` 语义
- **Yocto** `recipes-*/<pkg>.bbappend` — `${@bb.utils.contains('DISTRO_FEATURES', ...)}`

**本仓选择**:`patches/features.yaml` 集中声明 feature,`apply_patch.sh` 在执行时
内联 inline python heredoc 解析依赖 + compose 成 tmp series 文件
**(用户约束:不另起新脚本)**:

```text
versions/redis-7.0.15/patches/
├── features.yaml            # ★ 单一权威(OpenWrt Config.in 的 YAML 等价)
└── features/                # 一特性一目录(物理组织)
    ├── feature-A/           # Kunpeng ARM HW 优化
    │   ├── 0001-...patch
    │   └── 0002-...patch
    ├── feature-B/           # jemalloc 性能
    │   └── 0001-...patch
    └── feature-C/           # 可靠性(AOF fallback)
        └── 0001-...patch
```

**调用**(compose 集成在 `apply_patch.sh`,无新脚本):
```bash
# 默认组合 = features.yaml 中 default:true 的并集
bash tools/apply_patch.sh \
    https://github.com/redis/redis f35f36... \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches /tmp/build

# 显式组合(环境变量或 --active)
ACTIVE_FEATURES="feature-A feature-C" bash tools/apply_patch.sh ... --features ... /tmp/build
bash tools/apply_patch.sh ... --features ... --active "feature-B feature-C" /tmp/build
```

**lint 规则**(`.github/lint_series.py`,v5.0 起改为 lint features.yaml):
- features.yaml schema 校验(title / patches / depends / default)
- depends 引用必须存在,无环依赖
- 物理 patch 必须存在 + 在 features.yaml 声明(无孤儿)
- 每个 patch 头 DEP-3 6 必填字段

**为什么 1 features.yaml = 1 upstream**(而非 per-feature):
- 单 source 真相:每个 upstream/version 只有 1 个 features.yaml
- 组合由 `ACTIVE_FEATURES` 决定,不引入 DAG,grep 可追
- 与 OpenWrt / Yocto / Kconfig 业界共识一致

### 2.7 派生物 `inventory.json` — Buildroot/OpenWrt 风格

**问题**:`upstream.yaml` 只存当前版本信息,不存 per-patch + per-feature inventory;
人工"这版本有几个 feature / 什么 patch / 什么状态 / 默认组合有哪些"查询困难。

**业界方案**(参考):
- **Buildroot** — `support/scripts/pkg-stats` 从 package 元数据派生统计
- **OpenWrt** — `scripts/metadata.pl` 扫 Makefile 提取 package 信息
- **Debian** — `dpkg-scanpackages` 从 `.dsc` 派生 `Packages` 文件

**本仓选择**:`tools/gen_inventory.py` 从 patch 头 + features.yaml 全自动派生
`versions/<v>/patches/inventory.json`,新增 features/combos 段:

```json
{
  "features": {
    "feature-A": {"title": "...", "patches": [...], "depends": [], "default": true,
                  "upstream_status_summary": {"Submitted": 1, "Inappropriate": 1}},
    "feature-B": {...},
    "feature-C": {...}
  },
  "combos": {
    "default": {
      "active": ["feature-A", "feature-C"],
      "resolved": ["feature-A", "feature-C"],
      "patch_count": 3,
      "patch_list": ["features/feature-A/0001-...", ...]
    }
  },
  "patches": [
    {"file": "0001-...", "feature": "feature-A", "in_features": ["feature-A"],
     "in_combos": ["default"], "upstream_status": "Submitted", ...}
  ],
  "stats": {
    "total_patches": 4,
    "by_upstream_status": {"Submitted": 3, "Inappropriate": 1},
    "total_features": 3,
    "default_features": ["feature-A", "feature-C"]
  }
}
```

**关键设计**:
- **不入仓**(`.gitignore` 已加)— `verify.sh` / `gen_inventory.py` 每次跑都重新生成
- **单一真相仍是 patch 头 + features.yaml** — inventory 只是查询友好的视图
- **`--check` 模式**给 CI 用:diff > 0 即 fail(忽略 generated_at 时间戳差异)
- 任何修改 patch 头 / features.yaml 后跑一次 `bash tools/verify.sh` 即可刷新

---

## 3. 工作流

### 3.1 `ci.yml`(PR / push master 时触发)

4 步顺序:

| 步骤 | 工具 | 职责 |
|---|---|---|
| 1 | `bash tools/verify.sh` | 仓根禁放 + upstream.yaml schema(Yocto 字段警告)+ 委托 `apply_patch.sh --features` + 派生 inventory 刷新 |
| 2 | `python3 .github/lint_patch_headers.py` | DEP-3 6 必填 + 额外 3 必填 + 条件必填 |
| 3 | `python3 .github/lint_series.py` | v5.0 起改为 lint `features.yaml`(schema + depends 解析 + DEP-3 必填字段) |
| 4 | `python3 tools/gen_inventory.py --check` | 派生 inventory.json 与 patch 头 + features.yaml 一致性(忽略时间戳) |

### 3.2 `build-perf.yml`(PR / push master / workflow_dispatch 触发,骨架演示)

> **本仓 CI 上的 build-perf 是骨架演示 workflow**(demonstration skeleton),
> 不实际跑编译/bench。原因:编译依赖 BoostKit 内核侧 **KRAIO SDK**
> (`networking.c` 引用 `<kraio.h>`,只有装好 BoostKit 内核 RPM 的真
> Kunpeng 机器才有该头文件),普通 `ubuntu-22.04` GHA runner 必然
> `fatal error: kraio.h: No such file or directory`。

**触发方式**:
- `pull_request` 到 `master` — 骨架演示走完,Step Summary 列出每个 step 的"实际 / 演示"
- `push` 到 `master` — 同上(合并后 smoke)
- `workflow_dispatch` — 真 Kunpeng runner 手动触发完整流程

**矩阵生成**:从 `versions/*/upstream.yaml` 动态展开(不写死 redis-7.0.15)。

**骨架里实际跑的**:
- matrix 检测(读 `versions/*/upstream.yaml`)
- 调用 `tools/apply_patch.sh --features` clean clone + compose + `git apply`
  — 与 `verify.sh` 二次确认等价(真信号)

**骨架里只 echo 不真跑的**:
- apt-get 安装 build deps + memtier 源码编译
- make patched redis
- memtier_benchmark

**真 Kunpeng runner 部署**:把每个 `[skeleton]` step 的 `run: echo ...` 替换成
`run: <实际命令>` 即可(完整命令见下"本地复跑")。整个 workflow 结构(metrics /
matrix / cache / artifact upload)已就位,直接填血肉。

**本地复跑**(给开发者,真 Kunpeng 机器上):

```bash
# 1. clean clone upstream + apply features(走 tools/apply_patch.sh --features,默认组合)
bash tools/apply_patch.sh \
  https://github.com/redis/redis \
  f35f36a265403c07b119830aa4bb3b7d71653ec9 \
  --features versions/redis-7.0.15/patches/features.yaml \
  versions/redis-7.0.15/patches \
  /tmp/build

# 2. 编译 + 性能基准
cd /tmp/build/upstream
make distclean
make -j$(nproc) USE_KRAIO=0
src/redis-server --port 6399 --daemonize yes --dbfilename dump.rdb \
                  --save '' --appendonly no --maxmemory 256mb \
                  --logfile /tmp/redis.log
src/redis-benchmark -p 6399 -c 200 -d 3 -n 10000000 -r 10000000 \
                     -t set,get --threads 20 -q
```

---

## 4. 常见操作

### 4.1 新增 patch(v5.0 features 模型)

```bash
# 1. 把 .patch 文件放到对应 feature 子目录
cp my-new.patch versions/redis-7.0.15/patches/features/feature-A/0003-my-new.patch

# 2. 编辑 DEP-3 邮件式头,必填 6 字段:
#    Description (≥20 字符)/ Origin / Upstream-Status / Applies-To / Maintainer / Last-Update
#    + 额外 3 必填:From / Subject / Signed-off-by
#    + 条件必填(按 Upstream-Status)

# 3. 在 versions/redis-7.0.15/patches/features.yaml 里
#    把新 patch 加入对应 feature 的 patches: 列表
sed -i '/feature-A:/,/^  [a-z]/ s|^      - 0002-perf-kunpeng-adapt-dtoe.patch$|      - 0002-perf-kunpeng-adapt-dtoe.patch\n      - 0003-my-new.patch|' \
    versions/redis-7.0.15/patches/features.yaml

# 4. 本地 4 工具全 rc=0(verify 内含 inventory 派生 + check)
bash tools/verify.sh
python3 .github/lint_patch_headers.py versions/*/patches/
python3 .github/lint_series.py versions/*/patches/
python3 tools/gen_inventory.py --check versions/*/

# 5. 开 PR,触发 ci.yml + build-perf.yml
```

### 4.2 改 patch 状态(如 Submitted → Accepted)

直接编辑 patch 头:
```diff
- Upstream-Status: Submitted
- Upstream-PR: https://github.com/redis/redis/pull/12345
+ Upstream-Status: Accepted
+ Upstream-PR: https://github.com/redis/redis/pull/12345
+ Upstream-Commit: deadbeef1234567890abcdef1234567890abcdef
```

### 4.3 改上游版本(如 7.0.15 → 7.0.16)

```bash
# 1. 改 versions/redis-7.0.15/upstream.yaml:
sed -i 's/version: 7.0.15/version: 7.0.16/; s|commit: f35f36a.*|commit: <new-sha>|' \
    versions/redis-7.0.15/upstream.yaml

# 2. 重新跑 apply_patch.sh 看 patch 是否仍能 apply
bash tools/apply_patch.sh \
  https://github.com/redis/redis \
  <new-sha> \
  versions/redis-7.0.15/patches/series \
  versions/redis-7.0.15/patches \
  /tmp/build

# 3. 不能 apply 的 patch 进入 "rebase needed" 流程(参考 4.4)
```

### 4.4 废弃 patch

```bash
# 在 series 删除该 patch 路径(保留 .patch 文件以便历史追溯)
sed -i '/0002-perf-kunpeng-adapt-dtoe.patch/d' \
    versions/redis-7.0.15/patches/series

# 或在 patch 头改 Upstream-Status: Inappropriate + Whitelist-Reason
# 让 apply_patch.sh 仍然 apply 但标记废弃
```

### 4.5 新增 feature(v5.0)

```bash
# 1. 创建 feature 子目录(若还没有)
mkdir -p versions/redis-7.0.15/patches/features/feature-D

# 2. 把 patch 放到子目录
cp my-new.patch versions/redis-7.0.15/patches/features/feature-D/0001-my-new.patch

# 3. 在 features.yaml 声明新 feature
cat >> versions/redis-7.0.15/patches/features.yaml <<'EOF'
  feature-D:
    title: "新特性(示例)"
    patches:
      - 0001-my-new.patch
    depends: [feature-A]               # 可选,若需要 feature-A 先 apply
    default: false                     # 默认不激活,客户显式 ACTIVE_FEATURES 选
    upstream_status_summary:
      Submitted: 1
EOF

# 4. 跑 4 工具验证
bash tools/verify.sh
python3 .github/lint_series.py versions/redis-7.0.15/patches/

# 5. 用新 feature 跑 apply_patch.sh(默认组合不变,显式 ACTIVE 启用)
ACTIVE_FEATURES="feature-A feature-C feature-D" bash tools/apply_patch.sh \
  https://github.com/redis/redis \
  f35f36a265403c07b119830aa4bb3b7d71653ec9 \
  --features versions/redis-7.0.15/patches/features.yaml \
  versions/redis-7.0.15/patches \
  /tmp/build-d

# 6. inventory.json 自动派生,显示新 feature 与 patch 矩阵
python3 -c "import json; d=json.load(open('versions/redis-7.0.15/patches/inventory.json')); \
    print('features:', list(d['features'].keys())); \
    print('default patches:', d['combos']['default']['patch_count'])"
```

> **设计要点**:
> - patch 物理按 feature 分目录(grep 一目了然)
> - feature 集中声明在 features.yaml(单一权威)
> - depends 表达特性间依赖(自动 include + 解析)
> - apply_patch.sh 内联 compose,无新脚本

---

## 5. FAQ

### Q1: 为什么不用 Quilt?

Quilt 适合 Debian kernel 那种 1000+ patch 的场景,`.pc/` 暂存 + push/pop 栈
能力很强。本仓 5–50 patch 量级,`apply_patch.sh` + `git apply` 足够,引入 Quilt
会带不必要的复杂度。

### Q2: 为什么不用 SUSE `series.conf` SHA-256?

SUSE 面向 Build Service / RPM 自动化,patch 可能在多个镜像 / 时间点分发,硬校验
是必要的。本仓是 GitHub 单一 source of truth,commit hash 本身是 audit trail,
不需要额外 SHA 校验和。如果将来要做 reproducibility build,可演进到 SUSE 模式。

### Q3: upstream.yaml 的 Yocto 字段不填会报错吗?

不会,只 warning(`verify.sh` 提示 `⚠ SUMMARY missing`)。强推荐填 — license
audit / 包归属需要。但不阻塞 CI。

### Q4: DEP-3 6 必填字段是硬要求吗?

是。`lint_patch_headers.py` rc=1 = block merge。Description 太短(<20 字符)
或 Last-Update 格式错也会 fail。

### Q5: apply_patch.sh 的 fetch cache 怎么复用?

cache 放在 `<work_dir>/upstream/`,二次跑不会重新 clone。如果想完全清空,删
`/tmp/<vid>/upstream/` 目录即可。

### Q6: 真 Kunpeng runner 上的 build-perf 怎么启用?

把 `build-perf.yml` 里每个 `[skeleton]` step 的 `run: | echo ...` 替换成
`run: <实际命令>`(apt-get / make / memtier),workflow 其它结构不动。
然后在 repo Settings → Runners 上加 self-hosted runner label,workflow 用
`runs-on: [self-hosted, kunpeng]` 替换 ubuntu-latest。

### Q7: feature 组合 vs per-feature 多 repo,选哪个?

**用 feature 组合**(本仓 v5.0 选择)。理由:
- 单 source 真相:每个 upstream/version 只有 1 个 `features.yaml`
- 组合由 `ACTIVE_FEATURES` 决定,grep 可追
- 与 OpenWrt / Yocto / Kconfig 业界共识一致
- 不引入 DAG,`depends` 解析为线性顺序

**什么时候反过来用 per-feature 多 repo**:
- 特性数量极大(>50,例如 Linux kernel subsystem),需要独立发布
- 特性之间完全没有依赖关系,可任意装/卸

本仓 5–20 feature 量级,单 `features.yaml` 足够。

### Q8: inventory.json 为什么不入仓?

- 派生 = 自动生成,人工手编就一定 drift,反而成 bug 源
- 单一真相仍是 patch 头 + features.yaml(inventory 是它们的视图)
- 每次 `bash tools/verify.sh` 自动重生成(在 CI 和本地都跑)
- `gen_inventory.py --check` 给 CI 用,差异 > 0 即 fail

### Q9: 为什么把 compose 集成到 apply_patch.sh,不另起脚本?

用户约束 "不要增加新脚本"。`apply_patch.sh` 内联 inline python heredoc 实现
compose,功能等价于独立 `compose_series.py`,但:
- 单点实现:verify.sh / build-perf.yml / 本地复跑全走它
- 不增加新文件,新人不用先理解"compose 工具在哪"
- 临时 series 文件路径只在 apply_patch.sh 内部可见,trace 简单

如果将来 compose 逻辑变复杂(例:支持 Quilt topic / SUSE guards),
那时再拆出独立 `compose_series.py` 也不晚(YAGNI)。

如果将来要做 web dashboard,可以让 dashboard 后端定期 git pull + 跑
`gen_inventory.py` + 缓存到 Redis,而不是读 git 里的 json 文件。
