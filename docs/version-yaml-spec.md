# version-yaml 字段规范

> 权威定义 `versions/<upstream-id>/` 下文件的字段语义和约束。
> 本规范**集合 Yocto / DEP-3 / Buildroot-OpenWrt / Kconfig 五家之长**:
> - **`upstream.yaml` 字段名 = Yocto/OpenEmbedded recipe 同款**
>   ([SUMMARY / LICENSE / LIC_FILES_CHKSUM / HOMEPAGE / SECTION](https://docs.yoctoproject.org/ref-manual/variables.html))
> - **patch 头 schema = DEP-3 同款** 6 必填字段
>   ([DEP-3](https://dep-team.pages.debian.net/deps/dep3/))
> - **patch apply 脚本 = Buildroot/OpenWrt 同款**
>   ([Buildroot apply-patches.sh](https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh))
> - **feature 声明 + depends + default = OpenWrt Config.in + Kconfig 同款**
>   ([OpenWrt package Config.in](https://github.com/openWRT/openwrt/tree/main/package))
> - **feature 组合 + 条件 PATCHFILES = Yocto 条件 SRC_URI 同款**
>   ([Yocto bbappend SRC_URI](https://docs.yoctoproject.org/bitbake/recipes/))
>
> 详细设计原理见 [governance.md](./governance.md)。

## 1. 目录结构

每个 `versions/<upstream-id>/` 子目录固定包含:

```
versions/<upstream-id>/
├── upstream.yaml            # recipe 元数据 (Yocto) + 上游 pin + 治理归属
└── patches/
    ├── features.yaml        # ★ feature 声明(OpenWrt Config.in 风格;单一权威)
    ├── features/<feature>/  # 一特性一目录
    │   └── *.patch          # 该特性下的 patch(DEP-3 邮件式头 + diff)
    └── inventory.json       # 派生(不入仓,见 §6)
```

`<upstream-id>` 命名约定:`<project>-<version>`,例如 `redis-7.0.15`。

**配套工具**(仓根 `tools/`):
- `tools/apply_patch.sh` — Buildroot 风格 series 应用器(单点实现,接受任意 series 文件)
- `tools/gen_inventory.py` — 派生 `inventory.json`(Buildroot/OpenWrt 风格)
- `tools/verify.sh` — 一键验证(仓根禁放 + upstream.yaml schema + 委托 apply_patch.sh + inventory 派生刷新)

---

## 2. `upstream.yaml`

Yocto recipe 风格元数据 + 上游基线 pin + BoostKit 治理归属。三段式,职责清晰。

### 2.1 完整 schema

```yaml
# === 段 1: Recipe 元数据 (Yocto 风格) ===
SUMMARY: "Redis in-memory data structure store with Kunpeng ARM optimizations"
DESCRIPTION: |
  Redis is an open source (BSD licensed), in-memory data structure store
  used as a database, cache, message broker, and streaming engine. This
  BoostKit overlay layers ARM/Kunpeng-specific optimizations on top of
  upstream Redis 7.0.15.
HOMEPAGE: "https://redis.io"
LICENSE: "BSD-3-Clause"
LIC_FILES_CHKSUM: "file://COPYING;md5=508cbf69e54be9b31b53b42e7411f8c4"
SECTION: "network/database"

# === 段 2: 上游基线 (pin) — 不可变 ===
upstream:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9     # 必填,40-char SHA

# === 段 3: 治理元数据 (BoostKit 内部) ===
meta:
  owner: twwang@boostkit                  # 责任 owner,邮件通知目标
  maintainer: twwang@boostkit             # 主维护人(可多人,逗号分隔)
  description: Redis 7.0.15 patch overlay (BoostKit)
  last_review: 2026-07-20                 # 上次复盘日期
  lifecycle: active                       # active | frozen | deprecated
```

### 2.2 字段表

#### Recipe 元数据段(Yocto 字段)

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `SUMMARY` | **推荐** | string | 一行短描述 |
| `DESCRIPTION` | 否 | multi-line | 详细描述 |
| `HOMEPAGE` | **推荐** | URL | upstream 项目主页 |
| `LICENSE` | **推荐** | SPDX 标识符 | 上游 license(本仓默认 BSD-3-Clause) |
| `LIC_FILES_CHKSUM` | 否 | `file://X;md5=...` | 上游 license 文件 + md5(Yocto 用于 license audit) |
| `SECTION` | 否 | string | 分类标签(Yocto convention) |

> **不填只 warning,不阻塞**(让现有仓无痛迁移)。强推荐填 — 是 license audit / 包归属 / 发布单的输入。

#### 上游基线段(`upstream.*`)

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `upstream.repo` | **是** | URL | upstream Git 仓库 |
| `upstream.version` | **是** | string | upstream tag/branch(人类可读) |
| `upstream.commit` | **是** | 40-char SHA | `version` 对应的 immutable commit(SHA 格式严格校验) |

#### 治理元数据段(`meta.*`)

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `meta.owner` | 推荐 | email | 责任 owner |
| `meta.maintainer` | 推荐 | email | 主维护人(可多人逗号分隔) |
| `meta.description` | 否 | string | 一句话说明 |
| `meta.last_review` | 否 | YYYY-MM-DD | 上次复盘日期 |
| `meta.lifecycle` | 否 | `active`/`frozen`/`deprecated` | 生命周期状态 |
| `meta.planned_eol` | 否 | YYYY-MM-DD | 计划停服日期(可选,如 6.0.20 已 EOL) |

### 2.3 不放什么

**禁止**把以下内容放进 `upstream.yaml`:
- ~~patches[] 数组~~ — 顺序由 `patches/series` 表达
- ~~per-patch status / upstream_pr / whitelist_reason~~ — 全部进 patch 邮件式头(见 §4)

---

## 3. `patches/features.yaml`(OpenWrt Config.in 风格 — v5.0 单一权威)

**v5.0 起,本仓不再用 `patches/series` 文件**。所有 patch 应用顺序与组合由
`features.yaml` 声明,`tools/apply_patch.sh` 在执行时 inline compose 成 tmp series
文件,然后按 series 应用(与 v4.0 兼容的"series 文件"路径依然支持)。

### 3.1 完整 schema

```yaml
# OpenWrt Config.in + Kconfig depends 的 YAML 等价
# 业界参照:OpenWrt package/<name>/Config.in + Yocto 条件 SRC_URI
features:

  feature-A:
    title: "Kunpeng ARM 硬件加速(io_uring 适配 + DTOE DMA 网络路径)"
    patches:
      - 0001-hw-kunpeng-adapt-iouring.patch
      - 0002-perf-kunpeng-adapt-dtoe.patch
    depends: []               # 无依赖
    default: true             # 默认激活
    upstream_status_summary:
      Submitted: 1
      Inappropriate: 1

  feature-B:
    title: "jemalloc ARM64 pointer-tag + GC decay 策略优化"
    patches:
      - 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
    depends: []
    default: false            # 默认不激活
    upstream_status_summary:
      Submitted: 1

  feature-C:
    title: "RDB 损坏时降级到 AOF,避免硬停服"
    patches:
      - 0001-perf-rdb-fallback-aof.patch
    depends: []               # 若 depends: [feature-A] 则激活 C 时自动 include A
    default: true
    upstream_status_summary:
      Submitted: 1
```

### 3.2 字段表

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `features.<name>.title` | 推荐 | string | 一句话描述(给 dashboard / 文档用) |
| `features.<name>.patches` | **是** | list[str] | 该 feature 包含的 patch 文件名(相对 `patches/features/<name>/`) |
| `features.<name>.depends` | 否 | list[str] | 依赖的其他 feature(本 feature 激活时,依赖项自动激活并先 apply) |
| `features.<name>.default` | 否 | bool | 是否默认激活(默认组合 = 所有 `default:true` 的并集) |
| `features.<name>.upstream_status_summary` | 否 | dict[str,int] | 该 feature 下 patch 状态分布(给 dashboard 用;详细见 patch 头) |

### 3.3 物理目录布局

```text
patches/
├── features.yaml                 # ★ 单一权威
├── features/                     # 一特性一目录
│   ├── feature-A/
│   │   ├── 0001-hw-kunpeng-adapt-iouring.patch
│   │   └── 0002-perf-kunpeng-adapt-dtoe.patch
│   ├── feature-B/
│   │   └── 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
│   └── feature-C/
│       └── 0001-perf-rdb-fallback-aof.patch
└── inventory.json                # 派生(不入仓)
```

每个 feature 下 patch 文件名 `0001-` 仅辅助阅读/检索,顺序由 `patches.yaml`
里 `patches:` 列表决定。

### 3.4 组合(combo)— 客户用 `ACTIVE_FEATURES` 选

**默认组合** = features.yaml 里 `default:true` 的并集。
**显式组合** = 环境变量 `ACTIVE_FEATURES="<空格分隔的 feature 名>"` 或 `--active` 参数。

```bash
# 默认组合(feature-A + feature-C)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches /tmp/build

# 客户 A:只要 feature-C
ACTIVE_FEATURES="feature-C" bash tools/apply_patch.sh ... --features ... /tmp/build-a

# 客户 B:全开
ACTIVE_FEATURES="feature-A feature-B feature-C" bash tools/apply_patch.sh ... /tmp/build-b

# --active 参数等价于 ACTIVE_FEATURES 环境变量
bash tools/apply_patch.sh ... --features ... --active "feature-B feature-C" /tmp/build-c
```

### 3.5 依赖解析(`depends`)

`apply_patch.sh` 在 compose 时:
1. 校验所有 ACTIVE feature 名都在 features 里
2. 深度优先解析 depends(自动 include,dedup,环依赖检测)
3. resolved 顺序 = depends 在前(被依赖的先 apply)
4. 校验每个 patch 物理存在

```text
# 例:feature-C 依赖 feature-A
ACTIVE_FEATURES="feature-C"
  → resolved: [feature-A, feature-C]   # A 自动 include 并排前面
  → patches: [features/feature-A/0001..., features/feature-C/0001...]

# 例:环依赖
feature-A.depends: [feature-B]
feature-B.depends: [feature-A]
  → compose 失败:环依赖: A -> B -> A
```

### 3.6 业界对齐

- **OpenWrt Config.in** — `bool` 选项 + `depends on` + `default y` ([OpenWrt package](https://github.com/openWRT/openwrt/tree/main/package))
- **Linux kernel Kconfig** — `depends on` / `select` 语义([Kconfig language](https://www.kernel.org/doc/Documentation/kbuild/kconfig-language.rst))
- **Yocto 条件 SRC_URI** — `${@bb.utils.contains('DISTRO_FEATURES', ...)}`
- **Buildroot defconfig** — `BR2_PACKAGE_*=y` per package

### 3.7 为什么 1 features.yaml = 1 upstream(而非 per-feature 多 yaml)

| 方案 | 适用场景 | 代表项目 |
|---|---|---|
| **1 features.yaml = 1 upstream/version**(本仓选择) | 1 个上游版本的所有 feature 全部声明,组合由 ACTIVE_FEATURES 决定 | OpenWrt / Yocto / Kconfig / Kbuild |
| 1 series = 1 feature 模块 | 不同 feature 装/卸独立 | Linux kernel(若干子目录)|
| 1 repo = N feature yaml | 微服务/multi-tenant | Nx / Turborepo |

**为什么选方案 1**:
- 单 source 真相:每个 upstream/version 只有 1 个 features.yaml
- 组合由 ACTIVE_FEATURES 决定,不引入 DAG,grep 可追
- 与 OpenWrt / Yocto 业界共识一致

### 3.8 Legacy 兼容:旧 `patches/series` 文件依然支持

为平滑迁移,`apply_patch.sh` 仍接受传统 series 文件路径:

```bash
# 仍可工作(legacy):传 series 文件而非 --features
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a... \
    versions/redis-7.0.15/patches/series \
    versions/redis-7.0.15/patches /tmp/build
```

新仓推荐用 `--features` 模式;老仓可继续 series 模式直到迁移完成。

---

## 4. patch 邮件式头(DEP-3)

每个 `*.patch` 文件的第 1-15 行是 **DEP-3 / git-format-patch 风格的邮件式头**,
承载 patch 的 provenance / 上游状态 / commit 引用 / sign-off。

### 4.1 完整模板

```text
From: Author Name <author@example.com>
Date: Mon, 13 Jul 2026 14:30:00 +0800
Subject: [PATCH] Short single-line title
Description: |
  Multi-line detailed description of what the patch changes and why.
  Should be ≥20 chars to satisfy lint (avoid placeholder "TODO").
Origin: https://github.com/redis/redis/pull/12345
Upstream-Status: Submitted
Upstream-PR: https://github.com/redis/redis/pull/12345
Upstream-Commit: deadbeef1234567890abcdef1234567890abcdef
Whitelist-Reason: |
  Multi-line explanation when status indicates we won't send upstream.
  ≥30 chars to satisfy lint.
Applies-To: redis 7.0.15
Maintainer: twwang <twwang@boostkit>
Last-Update: 2026-07-20
Signed-off-by: Author Name <author@example.com>
Depends-on: 0002-perf-kunpeng-adapt-dtoe.patch

Long commit message body explaining the patch...

---

diff --git a/file.c b/file.c
...
```

### 4.2 字段表 — **DEP-3 6 必填字段**(用户要求)

| # | 字段 | 必填 | 格式 | 语义 |
|---|---|---|---|---|
| 1 | `Description` | **是** | ≥20 字符 | 目的/Description(DEP-3 标准字段)|
| 2 | `Origin` | **是** | URL 或文本 | 来源:PR URL / 内部分支 / vendor tag |
| 3 | `Upstream-Status` | **是** | 枚举(见 4.3) | 上游合入状态(Yocto 8 状态对齐) |
| 4 | `Applies-To` | **是** | `<project> <version>` | 适用上游版本(例:`redis 7.0.15`) |
| 5 | `Maintainer` | **是** | `Name <email>` | 维护人(可能不等于 From) |
| 6 | `Last-Update` | **是** | `YYYY-MM-DD` | 最后更新时间(DEP-3 标准字段) |

### 4.3 字段表 — **额外必填**(对齐 git format-patch + DCO)

| # | 字段 | 必填 | 格式 | 语义 |
|---|---|---|---|---|
| 7 | `From` | **是** | `Name <email>` | 作者 |
| 8 | `Subject` | **是** | `[PATCH] <title>` | 标题 |
| 9 | `Signed-off-by` | **是** | `Name <email>` | DCO sign-off |

### 4.4 字段表 — 条件必填

| 字段 | 触发条件 | 格式 | 语义 |
|---|---|---|---|
| `Upstream-PR` | `Upstream-Status ∈ {Submitted, Accepted, Backport}` | URL | 上游 PR/issue |
| `Upstream-Commit` | `Upstream-Status ∈ {Accepted, Backport}` | 40-char SHA | 上游 commit |
| `Whitelist-Reason` | `Upstream-Status ∈ {Rejected, Inappropriate, Denied, Inactive-Upstream}` | ≥30 字符 | 不合入上游的理由 |
| `Depends-on` | 存在非相邻依赖 | patch 文件名 | 跨位序依赖(可选) |

### 4.5 `Upstream-Status` 状态机(对齐 Yocto 8 状态)

| 值 | 语义 | 对应旧 `version.yaml` status |
|---|---|---|
| `Pending` | 已写但未提交上游 | `pending` |
| `Submitted` | PR 已开,未合并 | `submitted` |
| `Accepted` | 已 merge | `accepted` |
| `Rejected` | 上游拒收 | `rejected` |
| `Backport` | 从上游 commit backport | (新增) |
| `Inappropriate` | 项目独有,无上游等价物 | `whitelisted` |
| `Denied` | 上游明确不收 | `whitelisted`(子类) |
| `Inactive-Upstream` | 上游不活跃 | `whitelisted`(子类) |

### 4.6 条件必填矩阵

| `Upstream-Status` | `Upstream-PR` | `Upstream-Commit` | `Whitelist-Reason` |
|---|---|---|---|
| `Pending` | — | — | — |
| `Submitted` | 必填 | — | — |
| `Accepted` | 必填 | 必填 | — |
| `Rejected` | — | — | 必填(≥30) |
| `Backport` | 必填 | 必填 | — |
| `Inappropriate` | — | — | 必填(≥30) |
| `Denied` | — | — | 必填(≥30) |
| `Inactive-Upstream` | — | — | 必填(≥30) |

---

## 5. `tools/apply_patch.sh`(Buildroot 风格)

`patches/series` 的执行器 — Buildroot `support/scripts/apply-patches.sh` 同款设计。

### 5.1 用法

```bash
bash tools/apply_patch.sh \
    <upstream_repo> <upstream_commit> \
    <series_file> <patch_dir> <work_dir> \
    [extra git-apply args...]

# 例:
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15/patches/series \
    versions/redis-7.0.15/patches \
    /tmp/build
```

### 5.2 行为

1. 若 `work_dir/upstream/.git` 不存在 → `git clone`
2. 若目标 commit 不在本地 → `git fetch --depth 1 origin <commit>`
3. `git checkout <commit>`
4. 按 `series` 文件顺序逐条 `git apply`(行内可写 `-p1` / `-R` 等 guards 透传)
5. 默认 `APPLY_NON_STRICT=1` → 失败降级 warning;设为 `0` 硬中断(exit 1)

### 5.3 与业界对比

| 特性 | Buildroot apply-patches.sh | openEuler apply-patches.sh | 本仓 apply_patch.sh |
|---|---|---|---|
| 行格式 | `patch` 命令 | `patch` 命令 | `git apply` |
| Guards | 无 | `-p1` `-R` 行内 | `-p1` `-R` 行内 |
| 失败默认行为 | hard-fail | hard-fail | **warning(可改 hard)** |
| 工作目录 | 临时 | 临时 | 临时(可复用 cache) |
| fetch cache | 无 | 无 | **有**(`/tmp/<vid>/upstream`) |

---

## 6. `tools/gen_inventory.py`(Buildroot/OpenWrt 风格派生)

为解决"系列里每一 patch 是什么状态 / 属于哪个 profile"这类查询需求,本仓引入
**派生物 `versions/<v>/patches/inventory.json`**,由 `tools/gen_inventory.py`
从 patch 邮件式头 + series 文件**全自动派生**。

### 6.1 设计原则

- **派生 = 非源**:inventory.json **不入仓**(`.gitignore` 已在 v4.0 加),
  单一真相仍是 patch 头 + series 文件
- **用途**:dashboard / 报告 / 一键查"这个版本有哪些 patch,什么状态,属于哪些 profile"
- **业界出处**:
  - Buildroot `support/scripts/pkg-stats`(从 package 元数据派生统计)
  - OpenWrt `scripts/metadata.pl`(扫 Makefile 提取 package 信息)
  - Debian `dpkg-scanpackages`(从 `.dsc` 派生 `Packages` 文件)

### 6.2 用法

```bash
# 写 inventory.json(每次 verify.sh 自动调)
python3 tools/gen_inventory.py versions/*/

# CI:仅检查是否新鲜,与业务字段一致(忽略 generated_at 时间戳差异)
python3 tools/gen_inventory.py --check versions/*/
```

### 6.3 输出 schema(精简版)

```json
{
  "version_id": "redis-7.0.15",
  "upstream": {"repo": "...", "version": "...", "commit": "..."},
  "generated_at": "2026-07-20T...",
  "generator": "tools/gen_inventory.py",
  "patches": [
    {
      "file": "0001-hw-kunpeng-adapt-iouring.patch",
      "upstream_status": "Submitted",
      "maintainer": "twwang <twwang@boostkit>",
      "last_update": "2026-07-20",
      "applies_to": "redis 7.0.15",
      "subject": "...",
      "description_first_line": "...",
      "in_series_default": true,
      "in_profiles": ["default", "minimal"]
    }
  ],
  "profiles": {
    "default":  {"file": "patches/series",          "patch_count": 4},
    "minimal":  {"file": "patches/series.minimal",  "patch_count": 2},
    "security": {"file": "patches/series.security", "patch_count": 1}
  },
  "stats": {
    "total_patches": 4,
    "by_upstream_status": {"Submitted": 3, "Inappropriate": 1},
    "orphans": [],
    "missing_from_series": []
  }
}
```

### 6.4 字段语义

| 字段 | 来源 | 用途 |
|---|---|---|
| `patches[].file` | `patches/*.patch` glob | patch 文件名(glob 排序) |
| `patches[].upstream_status` | patch 头 `Upstream-Status:` | 状态聚合 |
| `patches[].in_series_default` | 主 series 是否引用 | 孤儿检查 |
| `patches[].in_profiles` | 所有 series / series.* 引用 | profile 矩阵 |
| `profiles.<name>.patch_count` | series / series.* 行数 | profile 概要 |
| `stats.by_upstream_status` | 聚合 | dashboard 卡片 |
| `stats.orphans` | 在 `patches/` 但不在主 `series` | 主 series 完整性 |

---

## 7. 与业界对齐速查

| 概念 | 业界出处 | URL |
|---|---|---|
| `SUMMARY`/`LICENSE`/`LIC_FILES_CHKSUM`/`HOMEPAGE`/`SECTION` | **Yocto/OpenEmbedded recipe 字段** | https://docs.yoctoproject.org/ref-manual/variables.html |
| `Upstream-Status` 8 状态语义 | Yocto patch metadata | https://docs.yoctoproject.org/dev/contributor-guide/recipe-style-guide.html |
| `Description` / `Origin` / `Maintainer` / `Last-Update` 必填 | **DEP-3** patch header | https://dep-team.pages.debian.net/deps/dep3/ |
| `Upstream-Status` + `Whitelist-Reason` | Yocto + Debian DEP-3 | (同上) |
| `features.yaml` `bool` 选项 + `depends` + `default` | **OpenWrt Config.in** | https://github.com/openWRT/openwrt/tree/main/package |
| `depends` 深度优先解析 + 环依赖检测 | **Linux kernel Kconfig** | https://www.kernel.org/doc/Documentation/kbuild/kconfig-language.rst |
| 条件 SRC_URI(`${@bb.utils.contains(...)}`) | **Yocto** `.bbappend` | https://docs.yoctoproject.org/bitbake-style-guide/ |
| `apply_patch.sh` 单点实现 + `git apply` | **Buildroot** `apply-patches.sh` | https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh |
| `inventory.json` 派生物(单跑 + check) | Buildroot `pkg-stats` + OpenWrt `metadata.pl` | (本仓扩展) |

> **历史参考**(v5.0 不再使用,仅作背景):Quilt `debian/patches/series` /
> SUSE `series.conf` SHA-256 校验 / v4.0 `series.<profile>` profile 文件。
> v5.0 起统一改用 `features.yaml` + git commit hash 表达 patch provenance。

---

## 8. 版本演进

| 字段/工具 | 添加版本 | 替代方案 |
|---|---|---|
| `patches/features.yaml` feature+combo 模型(OpenWrt Config.in + Kconfig) | **v5.0** | 替代 v4.0 `series.<profile>`(v5.0 已删除 series 文件) |
| `apply_patch.sh --features` inline compose(无新脚本) | **v5.0** | 替代 v4.0 series 文件模式(仍兼容 legacy series 文件) |
| `inventory.json` `features`/`combos` 段 | **v5.0** | v4.0 inventory 仅含 patches 段 |
| `lint_series.py` lint features.yaml | **v5.0** | v4.0 lint series 一致性(已删) |
| `tools/gen_inventory.py` + `inventory.json` 派生 | v4.0 | (新增) |
| `series.<profile>` profile 系列文件 | v4.0 | **v5.0 已删除**(由 `features.yaml` 替代) |
| `patches/series` 显式系列文件 | v2.0 | **v5.0 已删除**(由 `features.yaml` + compose 替代;仍兼容 legacy 调用) |
| `upstream.yaml` Yocto 段(SUMMARY/LICENSE/HOMEPAGE) | v3.0 | 旧 `version.yaml` 无 recipe 段 |
| patch 头 DEP-3 6 必填 | v3.0 | 旧 4 必填(From/Subject/Upstream-Status/Signed-off-by) |
| `tools/apply_patch.sh` | v3.0 | 旧 verify.sh 内联 `git apply` loop |
| `Upstream-Status` 8 状态 | v2.0 | 旧 `status` 5 状态 |

v5 与 v4 不兼容(`series.<profile>` / `patches/series` 文件被删除),需迁移到
`features.yaml`。v5 的 `apply_patch.sh` 仍支持 legacy series 文件参数(平滑过渡),
但新仓推荐 `--features` 模式。
