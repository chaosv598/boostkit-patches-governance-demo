# Schema 权威定义(简版)

本仓三类 YAML/header 的**单一权威字段表**。工具脚本的校验、文档示例、CI 检查都以此为准。

- `lint_patch_headers.py` 校验 §1(per-patch header)
- `lint_series.py` 校验 §3(per-feature + per-version)
- `tools/verify.sh` 校验 §2(per-version + 目录)

---

## 1. Patch 邮件式头(`*.patch` 文件首部 DEP-3)

每个 patch 文件前若干行为 header,在 `diff --git` 之前。

### 1.1 必填字段(6 项)

| 字段 | 类型 | 语义 |
|---|---|---|
| `From` | `Name <email>` | patch 作者 |
| `Subject` | string | 一句话标题,`[PATCH]` 前缀可选 |
| `Description` | string ≥30 字符(连续块,允许多行 `\|` 续行)| patch 改了什么 + 为何改 |
| `Origin` | string | 出处 URL / vendor 名 / `local` |
| `Upstream-Status` | enum(见 1.3)| 上游合入状态(Yocto 8 状态对齐)|
| `Applies-To` | string | 该 patch 适用的上游 commit/version 范围 |
| `Maintainer` | `Name <email>` | 本仓维护人(收件方)|
| `Last-Update` | `YYYY-MM-DD` | 最后一次更新日期 |

### 1.2 条件必填字段

| 字段 | 触发条件 | 类型 | 语义 |
|---|---|---|---|
| `Upstream-PR` | `Upstream-Status ∈ {Submitted, Accepted, Backport}` | URL | 上游 PR/issue 链接 |
| `Upstream-Commit` | `Upstream-Status ∈ {Accepted, Backport}` | 40-char SHA | 上游 commit |
| `Whitelist-Reason` | `Upstream-Status ∈ {Rejected, Inappropriate, Denied, Inactive-Upstream}` | string ≥30 字符 | 不合入上游的理由 |
| `Depends-on` | 存在非相邻依赖 | patch 文件名 | 跨位序依赖(可选,本仓用 `features.yaml.depends` 取代)|

### 1.3 `Upstream-Status` 枚举(Yocto 8 状态)

```text
Pending            — 已写未提交上游
Submitted          — PR 已开未合并
Accepted           — 已 merge
Rejected           — 上游拒收
Backport           — 从上游 commit backport
Denied             — 上游明确不收
Inappropriate      — 项目独有,无上游等价
Inactive-Upstream  — 上游不活跃
```

### 1.4 范例

```text
From: chaosv598 <chaosv598@boostkit>
Subject: [PATCH] Adapt io_uring for Kunpeng ARM

Upstream-Status: Submitted
Upstream-PR: https://github.com/redis/redis/pull/12345
Description: |
  Adapt io_uring to use Kunpeng ARM optimizations.
  Enable iouring submission polling for ARM64 cores.
Applies-To: redis-7.0.15
Maintainer: twwang@boostkit
Last-Update: 2026-07-20

diff --git a/src/io_uring.c b/src/io_uring.c
...

```

### 1.5 业界出处

- **DEP-3** (Debian) — patch 邮件式头 schema
  https://dep-team.pages.debian.net/deps/dep3/
- **Yocto/OpenEmbedded** — `Upstream-Status:` 字段 8 状态语义
  https://docs.openembedded.org/arch-current/contributor-guide/recipe-style-guide.html
- **Linux kernel** — RFC822/邮件式 patch 头格式(本仓简化版,无 Signed-off-by 等)

---

## 2. `versions/<id>/upstream.yaml`(per-version)

```yaml
# 段 1: Recipe 元数据(Yocto 风格)
SUMMARY: "..."                  # 一句话描述
DESCRIPTION: |                  # 多行
  ...
HOMEPAGE: "https://..."         # 上游项目主页 URL
LICENSE: "BSD-3-Clause"         # SPDX 风格 license
LIC_FILES_CHKSUM: "file://COPYING;md5=..."   # 上游 license 文件 + md5(Yocto 用法)
SECTION: "network/database"     # 分类标签(Yocto convention)

# 段 2: 上游基线 pin(immutable)
upstream:
  repo: https://github.com/redis/redis    # 上游 git URL
  version: 7.0.15                          # upstream tag/version
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9    # 40-char SHA(immutable pin)

# 段 3: 治理归属(可选)
meta:
  owner: twwang@boostkit        # 该 upstream 维护 owner
  maintainer: twwang@boostkit   # 同 owner 或另一人
  last_review: 2026-07-20       # 上次 review 日期
  lifecycle: active             # active | frozen | deprecated
```

### 2.1 字段表

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `SUMMARY` | 否 | string | 一句话描述 |
| `DESCRIPTION` | 否 | string(多行)| 详细描述 |
| `HOMEPAGE` | 否 | URL | 上游主页 |
| `LICENSE` | 否 | SPDX 字符串 | 整体 license |
| `LIC_FILES_CHKSUM` | 否 | `file://X;md5=...` | 上游 license 文件 + md5(Yocto 用法)|
| `SECTION` | 否 | string | 分类标签(Yocto convention)|
| `upstream.repo` | **是** | URL | 上游 git URL |
| `upstream.version` | **是** | string | upstream tag/version |
| `upstream.commit` | **是** | 40-char SHA | immutable pin |
| `meta.owner` | 否 | email | 维护 owner |
| `meta.maintainer` | 否 | email | 当前 maintainer |
| `meta.last_review` | 否 | `YYYY-MM-DD` | 上次 review 日期 |
| `meta.lifecycle` | 否 | enum | `active` / `frozen` / `deprecated` |

### 2.2 业界出处

- **Yocto/OpenEmbedded recipe 字段** — SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION
  https://docs.yoctoproject.org/bitbake/recipes/
- **Git** — `upstream.commit` 用 40-char SHA-1 校验

---

## 3. `versions/<id>/patches/features.yaml`(per-version,per-feature)

OpenWrt `Config.in` + Linux kernel Kconfig 的 YAML 等价物,**单一权威**。

### 3.1 完整 schema

```yaml
# 业界参照:OpenWrt package/<name>/Config.in + Kconfig depends + Yocto 条件 SRC_URI
features:

  kunpeng-hw-accel:                         # feature 名(kebab-case)
    title: "Kunpeng ARM 硬件加速"             # 一句话描述
    patches:                                # 该 feature 包含的 patch(相对 patches/features/<name>/)
      - 0001-hw-kunpeng-adapt-iouring.patch
      - 0002-perf-kunpeng-adapt-dtoe.patch
    depends: []                             # 依赖的其他 feature(DFS 解析 + 环检测 hard-fail)
    default: true                           # 是否默认激活(默认组合 = 所有 default:true 的并集)
    upstream_status: Inappropriate          # 该 feature 主导上游状态(Yocto 8 状态枚举之一)
```

### 3.2 字段表

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `features.<name>` 顶层 key | **是**(feature 名)| kebab-case string | 稳定 identifier(被 `depends` / `ACTIVE_FEATURES` 引用)|
| `features.<name>.title` | 推荐 | string | 一句话描述(给 dashboard / 文档用)|
| `features.<name>.patches` | **是** | list[str] | 该 feature 包含的 patch 文件名(相对 `patches/features/<name>/`)|
| `features.<name>.depends` | 否 | list[str] | 依赖的其他 feature(本 feature 激活时,依赖项自动激活并先 apply)。**业界参照:Linux kernel Kconfig `depends on` + OpenWrt `Makefile` 条件 `PATCHFILES` —— 同款 DFS 深度优先解析 + 环依赖 hard-fail** |
| `features.<name>.default` | 否 | bool | 是否默认激活(默认组合 = 所有 `default:true` 的并集)|
| `features.<name>.upstream_status` | 否 | enum | 该 feature 在 patch overlay 中的主导上游状态(**Yocto 8 状态枚举之一,见 §1.3**;给 dashboard 用)。详细 per-patch 状态见每个 .patch 邮件式头 `Upstream-Status:` |

### 3.3 物理目录布局(配套)

```text
patches/
├── features.yaml                 # ★ 单一权威
├── features/                     # 一特性一目录
│   ├── kunpeng-hw-accel/
│   │   ├── 0001-hw-kunpeng-adapt-iouring.patch
│   │   └── 0002-perf-kunpeng-adapt-dtoe.patch
│   ├── jemalloc-arm64/
│   │   └── 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
│   └── rdb-aof-fallback/
│       └── 0001-perf-rdb-fallback-aof.patch
```

### 3.4 业界出处

- **OpenWrt** `package/<name>/Config.in` + `Makefile` — feature 声明 + 条件 PATCHFILES
  https://github.com/openwrt/openwrt/tree/main/package/network/services/dnsmasq/Makefile
- **Linux kernel Kconfig** `depends on` — DFS 深度优先解析 + 环依赖检测
  https://www.kernel.org/doc/Documentation/kbuild/kconfig-language.rst
- **Yocto** `.bbappend` 条件 SRC_URI — `${@bb.utils.contains(...)}`
  https://docs.yoctoproject.org/bitbake/recipes/

---

## 4. 校验矩阵

| 校验项 | 工具 | 触发条件 | fail 表现 |
|---|---|---|---|
| patch header 6 必填 | `lint_patch_headers.py` | 任何 .patch | 缺字段 → 报错 + 列出缺失字段名 |
| patch header `Upstream-Status` 枚举 | `lint_patch_headers.py` | 任何 .patch | 非 Yocto 8 状态 → 报错 + 列出合法值 |
| patch header 条件必填联动 | `lint_patch_headers.py` | 任何 .patch | Submitted 缺 Upstream-PR → 报错 |
| `upstream.yaml.commit` 40-char SHA | `verify.sh` | CI / PR | rc=1 |
| `features.<name>.patches` 文件存在 | `lint_series.py` | 任何 feature | 报错 + 缺文件路径 |
| `features.<name>.depends` 引用存在 | `lint_series.py` | 任何 feature | 报错 + 未知 feature 名 |
| `features.<name>.depends` 无环 | `lint_series.py` | 任何 feature | 报错 + 环路径 |
| `features.<name>.upstream_status` 枚举 | `lint_series.py` | 任何 feature | 报错 + 列出合法值 |
| 仓根禁放检查 | `verify.sh` | CI / PR | rc=1 |
| 孤儿 patch(目录有但 features.yaml 未声明)| `lint_series.py` | 任何 feature | 报错 + 路径 |