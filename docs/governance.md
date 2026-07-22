# Patch Overlay 治理设计

## 1. 模型概述

本仓治理"在固定上游基线上叠加 N 个 patch"的问题,采用业界最广泛采用的
**version-centric + feature 声明** 模型。**v5.0 升级到 OpenWrt Config.in +
Kconfig 风格的 feature + combo 模型,compose 逻辑集成到 `apply_patch.sh`
(不增加新脚本)**:

```
<upstream-id>/
├── upstream.yaml              # Yocto recipe 字段 + 上游基线 + 治理归属
└── patches/
    ├── features.yaml          # ★ feature 声明 + depends + default(OpenWrt Config.in 风格,单一权威)
    └── features/<feature>/    # 一特性一目录
        └── *.patch            # DEP-3 邮件式头(6 必填)+ diff
```

**配套工具**(仓根):
- `tools/apply_patch.sh` — Buildroot 风格 series 应用器 + v5.0 `--features`
  模式(inline compose,集成,无新脚本)
- `tools/verify.sh` — 一键验证(仓根禁放 + upstream.yaml schema + 委托 apply_patch.sh --features)

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
- **不引入 DAG** — `depends` 解析为线性顺序(被依赖的先 apply)
- **无派生 json**(v5.1 起) — 单一真相就是 features.yaml + patch 头,不维护 inventory.json

完整字段定义见 [schemas.md](./schemas.md)(单一权威)。

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

### 2.4 OpenWrt `package/<name>/Config.in` + `Makefile` — feature 声明 + 条件 PATCHFILES

**出处**: https://github.com/openWRT/openwrt/tree/main/package

OpenWrt 每个 package 在自己的 `Config.in` 里用 Kconfig 语法声明 `bool` 选项 +
`depends on` + `default y`,然后在 `Makefile` 里根据 CONFIG_X 条件选择 PATCHFILES。

```text
# OpenWrt package/foo/Config.in
config PACKAGE_FOO_FEATURE_A
    bool "Feature A: Kunpeng HW acceleration"
    default y
    depends on PACKAGE_FOO

# OpenWrt package/foo/Makefile
ifeq ($(CONFIG_PACKAGE_FOO_FEATURE_A),y)
    PATCHFILES += 0001-kunpeng-hw-accel.patch 0002-kunpeng-hw-accel.patch
endif
```

**对齐点**(本仓 v5.0 主线):
- `patches/features.yaml` = `Config.in` 的 YAML 等价物(`bool` + `depends` + `default` 字段 1:1 对应)
- `--active "f1 f2"` / `ACTIVE_FEATURES` env = `Makefile` 的 `CONFIG_X` 条件选择语义
- patch 物理按 `features/<feature>/` 分目录 = OpenWrt per-package patch dir

### 2.5 Linux kernel `Kconfig` — depends / select / default 语义

**出处**: https://www.kernel.org/doc/Documentation/kbuild/kconfig-language.rst

Linux kernel 用 Kconfig 表达"配置项之间依赖",核心语义:
- `depends on X` — 只有 X 选时才显示/生效
- `select Y` — 选 X 时自动选 Y(反向强制)
- `default y` — 默认开
- **深度优先解析 + 环依赖检测** — Kconfig 解析器的标准算法

**对齐点**(本仓 v5.0 depends 解析):
- `apply_patch.sh` inline python heredoc 实现 `depends` 深度优先解析
- 环依赖 → `sys.exit("环依赖: A -> B -> A")`
- 自动 include 依赖 + dedup = Linux kernel 的 `select` 反向语义
- `default: true/false` = `default y/n`

**双业界出处覆盖**(互为补充,共同背书本仓 `depends` 设计):
- **Linux kernel Kconfig** `depends on` — 解析算法(DFS + 环检测)
  https://www.kernel.org/doc/Documentation/kbuild/kconfig-language.rst
- **OpenWrt** `package/<name>/Makefile` 条件 `PATCHFILES` — 依赖激活后
  哪些 patch 进 build 的实际产出机制
  https://github.com/openwrt/openwrt/tree/main/package/network/services/dnsmasq/Makefile
  (参考:`PKG_BUILD_DEPENDS` 触发 PATCHFILES 列表)

### 2.6 Feature 声明 + 组合 — OpenWrt Config.in + Kconfig 风格

**问题**:同一 upstream 下常有"N 个特性 + 自由组合 + 特性间有依赖"需求
(例:特性 A 必选 / 特性 B 可选 / 特性 C 依赖 A),单一 `series` 文件或
`series.<profile>` 无法表达特性声明 + 依赖关系。

**业界方案**(本仓参考):
- **OpenWrt** `Config.in` + `Makefile` (见 §2.4) — 文件格式 + 条件 PATCHFILES
- **Linux kernel** `Kconfig` (见 §2.5) — depends 解析算法
- **Yocto** `recipes-*/<pkg>.bbappend` — `${@bb.utils.contains('DISTRO_FEATURES', ...)}` 条件 SRC_URI

**本仓选择**:`patches/features.yaml` 集中声明 feature,`apply_patch.sh` 在执行时
内联 inline python heredoc 解析依赖 + compose 成 tmp series 文件
**(用户约束:不另起新脚本)**:

```text
versions/redis-7.0.15/patches/
├── features.yaml            # ★ 单一权威(OpenWrt Config.in 的 YAML 等价)
└── features/                # 一特性一目录(物理组织)
    ├── kunpeng-hw-accel/           # Kunpeng ARM HW 优化
    │   ├── 0001-...patch
    │   └── 0002-...patch
    ├── jemalloc-arm64/           # jemalloc 性能
    │   └── 0001-...patch
    └── rdb-aof-fallback/           # 可靠性(AOF fallback)
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
ACTIVE_FEATURES="kunpeng-hw-accel rdb-aof-fallback" bash tools/apply_patch.sh ... --features ... /tmp/build
bash tools/apply_patch.sh ... --features ... --active "jemalloc-arm64 rdb-aof-fallback" /tmp/build
```

**lint 规则**(`.github/lint.py features`,v5.2 起合并 lint 脚本):
- features.yaml schema 校验(title / patches / depends / default)
- depends 引用必须存在,无环依赖
- 物理 patch 必须存在 + 在 features.yaml 声明(无孤儿)
- 每个 patch 头 DEP-3 6 必填字段

**为什么 1 features.yaml = 1 upstream**(而非 per-feature):
- 单 source 真相:每个 upstream/version 只有 1 个 features.yaml
- 组合由 `ACTIVE_FEATURES` 决定,不引入 DAG,grep 可追
- 与 OpenWrt / Yocto / Kconfig 业界共识一致

### 2.7 `tools/` 工具脚本 → 业界出处对照表

把 §2.1–§2.5 的 5 家业界出处**具体映射**到本仓工具脚本。工具头部注释也同样包含此表。

| 工具 | 业界出处 | 本仓实现 |
|---|---|---|
| `tools/apply_patch.sh` | **Buildroot** `apply-patches.sh` + **OpenWrt** `Config.in` / `Makefile` + **Linux Kconfig** `depends` | 单点 series 应用器 + inline python compose，`--active` 选 feature，depends DFS 解析 + 环检测 |
| `tools/verify.sh` | **Buildroot** `check-package` + **OpenWrt** `scripts/feeds` + **Yocto** recipe | 仓根禁放 + upstream.yaml schema + 委托 `apply_patch.sh --features` clean apply |
| `.github/lint.py headers` | **DEP-3** + **Yocto** `Upstream-Status` | 6 必填 + 条件必填联动 |
| `.github/lint.py features` | **OpenWrt Config.in** + **Linux Kconfig** | schema + depends + 环检测 + 孤儿 patch + DEP-3 必填字段 |

**总结一句话**:本仓每个工具步骤都能追到至少 1 个业界出处,没有"自己造轮子"的环节。

---

## 3. 工作流

### 3.1 `ci.yml`(PR / push master 时触发)

3 步顺序(v5.1 起,v5.0 是 4 步,v5.2 合并 lint 脚本):

| 步骤 | 工具 | 职责 |
|---|---|---|
| 1 | `bash tools/verify.sh` | 仓根禁放 + upstream.yaml schema(Yocto 字段警告)+ 委托 `apply_patch.sh --features` clean apply |
| 2 | `python3 .github/lint.py features` | features.yaml(schema + depends 解析 + DEP-3 必填字段) |
| 3 | `python3 .github/lint.py headers` | DEP-3 6 必填 + 额外 3 必填 + 条件必填 |

> **v5.1 移除原 step 4**(`gen_inventory.py --check`):原因 inventory.json 是
> gitignored 派生物 + verify.sh 已写过一遍,CI 上 --check 是同义反复(自己跟自己
> 比永远相等)。需要查看 features / patches / combos 时直接看 `features.yaml`
> + `features/<f>/*.patch` 即可。

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
cp my-new.patch versions/redis-7.0.15/patches/features/kunpeng-hw-accel/0003-my-new.patch

# 2. 编辑 DEP-3 邮件式头,必填 6 字段:
#    Description (≥20 字符)/ Origin / Upstream-Status / Applies-To / Maintainer / Last-Update
#    + 额外 3 必填:From / Subject / Signed-off-by
#    + 条件必填(按 Upstream-Status)

# 3. 在 versions/redis-7.0.15/patches/features.yaml 里
#    把新 patch 加入对应 feature 的 patches: 列表
sed -i '/kunpeng-hw-accel:/,/^  [a-z]/ s|^      - 0002-perf-kunpeng-adapt-dtoe.patch$|      - 0002-perf-kunpeng-adapt-dtoe.patch\n      - 0003-my-new.patch|' \
    versions/redis-7.0.15/patches/features.yaml

# 4. 本地 3 工具全 rc=0
bash tools/verify.sh
python3 .github/lint.py headers versions/*/patches/
python3 .github/lint.py features versions/*/patches/

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

# 2. 重新跑 apply_patch.sh --features 看 patch 是否仍能 apply
bash tools/apply_patch.sh \
  https://github.com/redis/redis \
  <new-sha> \
  --features versions/redis-7.0.15/patches/features.yaml \
  versions/redis-7.0.15/patches \
  /tmp/build

# 3. 不能 apply 的 patch 进入 "rebase needed" 流程(参考 4.4)
```

### 4.4 废弃 patch

```bash
# 在 features.yaml 删除该 patch 路径(保留 .patch 文件以便历史追溯)
sed -i '/0002-perf-kunpeng-adapt-dtoe.patch/d' \
    versions/redis-7.0.15/patches/features.yaml

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
    depends: [kunpeng-hw-accel]               # 可选,若需要 kunpeng-hw-accel 先 apply
    default: false                     # 默认不激活,客户显式 ACTIVE_FEATURES 选
    upstream_status_summary:
      Submitted: 1
EOF

# 4. 跑 3 工具验证
bash tools/verify.sh
python3 .github/lint.py features versions/redis-7.0.15/patches/

# 5. 用新 feature 跑 apply_patch.sh(默认组合不变,显式 ACTIVE 启用)
ACTIVE_FEATURES="kunpeng-hw-accel rdb-aof-fallback feature-D" bash tools/apply_patch.sh \
  https://github.com/redis/redis \
  f35f36a265403c07b119830aa4bb3b7d71653ec9 \
  --features versions/redis-7.0.15/patches/features.yaml \
  versions/redis-7.0.15/patches \
  /tmp/build-d
```

> **设计要点**:
> - patch 物理按 feature 分目录(grep 一目了然)
> - feature 集中声明在 features.yaml(单一权威)
> - depends 表达特性间依赖(自动 include + 解析)
> - apply_patch.sh 内联 compose,无新脚本

---

## 5. FAQ

### Q1: 为什么不用 Quilt `debian/patches/series`?

Quilt 适合 Debian kernel 那种 1000+ patch 的场景,`.pc/` 暂存 + push/pop 栈
能力很强。但本仓 v5.0 起已经移除了 `patches/series` 系列文件(改用 OpenWrt
Config.in + Kconfig 风格的 `features.yaml` 表达特性),Quilt 的 `series` 文件
模型与本仓模型不兼容,且 5–50 patch 量级不需要 push/pop 栈。

### Q2: 为什么不用 SUSE `series.conf` SHA-256 校验?

本仓 v5.0 起已经移除了 `series.conf` 类显式系列文件,改用 `features.yaml` +
git commit hash 表达 patch provenance,commit 链本身就是 audit trail。如果将来
要做 reproducibility build,可演进到 SUSE 模式(但需要先恢复显式系列文件)。

### Q3: upstream.yaml 的 Yocto 字段不填会报错吗?

不会,只 warning(`verify.sh` 提示 `⚠ SUMMARY missing`)。强推荐填 — license
audit / 包归属需要。但不阻塞 CI。

### Q4: DEP-3 6 必填字段是硬要求吗?

是。`lint.py headers` rc=1 = block merge。Description 太短(<20 字符)
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


### Q9: 为什么把 compose 集成到 apply_patch.sh,不另起脚本?

用户约束 "不要增加新脚本"。`apply_patch.sh` 内联 inline python heredoc 实现
compose,功能等价于独立 `compose_series.py`,但:
- 单点实现:verify.sh / build-perf.yml / 本地复跑全走它
- 不增加新文件,新人不用先理解"compose 工具在哪"
- 临时 series 文件路径只在 apply_patch.sh 内部可见,trace 简单

如果将来 compose 逻辑变复杂(例:支持 guards / per-feature 自动测试),
那时再拆出独立 `compose_series.py` 也不晚(YAGNI)。

---

## 6. 演进方向：v6.0 Buildroot 精简模型 (PROPOSAL)

> 本节为设计提案，供评审。当前代码仍为 v5.2 模型，实施后再更新 §1 和 schemas.md。

### 6.1 动机

v5.2 模型存在三处信息重复：

| 重复点 | 来源 A | 来源 B | 说明 |
|--------|--------|--------|------|
| patch 列表 | `features.yaml.patches:` | `ls features/<name>/` | 文件系统已自描述，YAML 是冗余维护 |
| feature 描述 | `features.yaml.title` | `.patch` 头 `Description:` | patch 头已有精确描述 |
| 上游状态 | `features.yaml.upstream_status` | `.patch` 头 `Upstream-Status:` | 逐 patch 状态是真相，feature 级聚合可派生 |
| Yocto recipe 字段 | `upstream.yaml` (SUMMARY/LICENSE/...) | — | 这是构建/发布系统的职责，不是 patch 仓的职责 |

**Buildroot 的教益**：Buildroot 不维护任何 patch 列表文件。patch 按 `NNNN-description.patch` 命名，`apply-patches.sh` 按目录文件名序遍历 apply。需要条件包含时，在 `Config.in` + `.mk` 里用 Kconfig 语法表达——**文件系统 + Kconfig，零冗余 YAML**。

### 6.2 设计方案

**两个 YAML 合并为一个 `manifest.yaml`**，仅保留文件系统无法表达的字段：

```
versions/redis-7.0.15/
├── manifest.yaml              # ★ 唯一配置文件（上游 pin + feature config）
└── patches/
    └── features/
        ├── kunpeng-hw-accel/
        │   ├── 0001-hw-kunpeng-adapt-iouring.patch
        │   └── 0002-perf-kunpeng-adapt-dtoe.patch
        ├── jemalloc-arm64/
        │   └── 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
        └── rdb-aof-fallback/
            └── 0001-perf-rdb-fallback-aof.patch
```

**manifest.yaml 模板**：

```yaml
# 上游基线 (Buildroot 风格: immutable pin, 无 Yocto recipe 字段)
upstream:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9

# Feature config (Buildroot Config.in Kconfig 语义 +
#               OpenWrt 条件 PATCHFILES: 只声明文件系统无法表达的信息)
features:
  kunpeng-hw-accel:
    depends: []
    default: true
  jemalloc-arm64:
    depends: []
    default: false
  rdb-aof-fallback:
    depends: []
    default: true
```

**字段决策表**：

| 字段 | v5.2 | v6.0 | 理由 |
|------|:---:|:---:|------|
| `upstream.repo/version/commit` | upstream.yaml | manifest.yaml | 唯一硬需 |
| Yocto recipe (SUMMARY/LICENSE/...) | upstream.yaml | **砍掉** | 构建/发布系统职责 |
| `meta` (owner/maintainer/lifecycle) | upstream.yaml | **砍掉** | git blame + CODEOWNERS 更可靠 |
| `features.<name>.patches` | features.yaml | **砍掉** | 文件系统 `ls features/<name>/` 即得 |
| `features.<name>.title` | features.yaml | **砍掉** | patch 头 `Description:` 已有 |
| `features.<name>.upstream_status` | features.yaml | **砍掉** | 从 patch 头 `Upstream-Status:` 实时计算 |
| `features.<name>.depends` | features.yaml | manifest.yaml | **唯一来源，保留** |
| `features.<name>.default` | features.yaml | manifest.yaml | **唯一来源，保留** |

### 6.3 apply_patch.sh 变更

v5.2 的 compose 逻辑从 `features.yaml.patches` 列表读取 patch 顺序 → 改为遍历 `features/<feature>/` 目录，按 `*.patch` 文件名字典序 apply：

```text
# v5.2: 读 YAML 列表
features:
  kunpeng-hw-accel:
    patches:
      - 0001-hw-kunpeng-adapt-iouring.patch
      - 0002-perf-kunpeng-adapt-dtoe.patch

# v6.0: 读目录排序
features/kunpeng-hw-accel/
├── 0001-hw-kunpeng-adapt-iouring.patch    ← apply 第 1 个
└── 0002-perf-kunpeng-adapt-dtoe.patch     ← apply 第 2 个
```

depends 解析和 `default: true` 默认组合逻辑不变。

### 6.4 复杂度对比

| 维度 | v5.2 | v6.0 | 降幅 |
|------|:--:|:--:|:--:|
| 版本级文件数 | 2 (upstream.yaml + features.yaml) | 1 (manifest.yaml) | -50% |
| YAML 字段总数 | ~16 | 5 | -69% |
| 新增 patch 操作 | 3 步 (cp + 写 patch 头 + 改 YAML) | 2 步 (cp + 写 patch 头) | -33% |
| lint 校验面 | patch 头 + features.yaml + upstream.yaml | patch 头 + manifest.yaml | -33% |

### 6.5 与业界对齐（精简为 3 家）

| 方案 | 对齐点 |
|------|--------|
| **Buildroot** `apply-patches.sh` | patch 顺序由文件名字典序决定，不维护列表文件（**主对齐**） |
| **OpenWrt** `Config.in` + `Makefile` | `depends` + `default` = Kconfig 语义 + 条件 PATCHFILES（仅此二字段保留） |
| **DEP-3** (Debian) | patch 头 schema，6 必填字段（不变） |

> Yocto recipe 字段和 Linux kernel Kconfig `select` 语义在 v6.0 中移除——前者归位到构建系统，后者由 `depends` 的自动 include 行为等效覆盖。

### 6.6 何时需要恢复 `patches:` 列表或 `series` 文件？

- 单个 feature 内 patch 数量 >20 且需要非字典序排序 → `manifest.yaml` 加可选的 `order:` 列表
- 跨 feature 的 patch 交叠顺序需要精细控制 → 恢复 `series` 文件

本仓场景（<50 patch，每个 feature <10 patch，文件名字典序足够表达顺序）维持 YAGNI。

