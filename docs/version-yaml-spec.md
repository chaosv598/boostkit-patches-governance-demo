# version-yaml 字段规范

> 权威定义 `versions/<upstream-id>/` 下文件的字段语义和约束。
> 本规范**集合 Yocto / DEP-3 / Buildroot-OpenWrt 三家之长**:
> - **`upstream.yaml` 字段名 = Yocto/OpenEmbedded recipe 同款**
>   ([SUMMARY / LICENSE / LIC_FILES_CHKSUM / HOMEPAGE / SECTION](https://docs.yoctoproject.org/ref-manual/variables.html))
> - **patch 头 schema = DEP-3 同款** 6 必填字段
>   ([DEP-3](https://dep-team.pages.debian.net/deps/dep3/))
> - **series 顺序 + apply 脚本 = Buildroot/OpenWrt 同款**
>   ([Buildroot apply-patches.sh](https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh))
>
> 详细设计原理见 [governance.md](./governance.md)。

## 1. 目录结构

每个 `versions/<upstream-id>/` 子目录固定包含 3 类文件:

```
versions/<upstream-id>/
├── upstream.yaml            # recipe 元数据 (Yocto) + 上游 pin + 治理归属
└── patches/
    ├── series               # patch 应用顺序(自上而下,默认 profile)
    ├── series.<profile>     # profile 系列文件(可选,见 §3.3)
    └── *.patch              # patch 文件(DEP-3 邮件式头 + diff)
```

派生(不入仓):
- `inventory.json` — `tools/gen_inventory.py` 从 patch 头 + series 派生(见 §6)

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

## 3. `patches/series`

**唯一权威**的 patch 应用顺序清单。Buildroot/OpenWrt 同款。

### 3.1 格式

```text
# 行格式:<patch 路径>(相对 patches/)
# 允许:空行、注释(#)、尾随空白
# 禁止:相对路径、绝对路径、Glob、变量展开

0001-hw-kunpeng-adapt-iouring.patch
0002-perf-kunpeng-adapt-dtoe.patch
0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch
0004-perf-rdb-fallback-aof.patch
```

### 3.2 规则

- **每行 1 条**:一条 patch 路径,自上而下应用
- **顺序权威**:filename `0001-` 仅辅助阅读/检索,可任意重命名,不影响顺序
- **必填条件**:`series` 中的每条路径必须对应 `patches/<path>.patch` 实际存在
- **孤儿检查**:`patches/*.patch` 中没被 `series` 引用的视为孤儿,CI 报错
- **去重检查**:`series` 中重复路径视为错误
- **注释**:以 `#` 开头的行视为注释,跳过
- **空行**:跳过

### 3.3 Profile 系列文件(`series.<profile>`)— 本仓扩展

为支持"同一 upstream + 多个 patch 集合"场景(例:full / minimal / security / ci),
主 `series` 文件之外允许创建 `series.<profile>` 作为**profile 系列文件**:

```text
versions/redis-7.0.15/patches/
├── series              # 默认 profile (name="default")
├── series.minimal      # profile "minimal":跳过 Kunpeng HW / jemalloc 子模块
└── series.security     # profile "security":只保留 AOF fallback
```

**调用方式**:`tools/apply_patch.sh` 接受任意 series 文件路径,所以 profile 直接复用:

```bash
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15/patches/series.security \
    versions/redis-7.0.15/patches \
    /tmp/build-security
```

**lint 规则**(与主 series 略有差别):
- 所有 series 文件都查 "无重复 entry" + "entry 引用必须存在"
- **只有主 series 强制孤儿检查**(profile 本就是子集,允许不含某些 patch)
- profile 文件允许为空(0 条)或只含 1 条

**业界对照**:
- **Buildroot** — `package/<name>/<name>-<variant>.patch` (variant 系列)
- **OpenWrt** — `PATCHFILES` 配合 `CONFIG_*` 条件(参见 OpenWrt Makefile)
- **本仓扩展** — `series` + `series.<profile>` 二选一(参见 §3.4)

### 3.4 系列文件 vs per-feature 多系列(本仓选择)

| 方案 | 适用场景 | 代表项目 |
|---|---|---|
| **1 个 series = 1 个 upstream/version**(本仓选择) | 1 个上游版本的所有 patch 全部入仓,profile 文件做子集 | ungoogled-chromium / Buildroot / OpenWrt |
| 1 个 series = 1 个 feature 模块 | 不同 feature 装/卸独立 | Linux kernel(若干子目录)|
| 1 个 series = 1 个 profile | 同一上游多 profile | Quilt 风格的 Debian 包 |

**为什么选方案 1**:
- 单 source 真相:每个 upstream/version 只有 1 个主 series,patches/ 下所有 patch 都必须挂在它上面
- profile 子集通过 `series.<profile>` 表达,避免 per-feature 引入 DAG
- 与 Buildroot / OpenWrt / ungoogled-chromium 业界共识一致

### 3.5 业界对齐

- **Buildroot** — `package/<name>/patches/series` 同款格式
- **OpenWrt** — `package/<name>/patches/series` 同款格式
- **Quilt/Debian** — `debian/patches/series` 同款"自上而下顺序清单"
- **SUSE** — `series.conf` 同款显式清单(本项目不引入 guards + SHA-256 校验和)

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
| `patches/series` 自上而下顺序 | Debian Quilt / ungoogled-chromium | https://salsa.debian.org/kernel-team/linux/-/tree/master/debian/patches |
| `series.conf` + SHA-256 校验和 | SUSE kernel-source | https://github.com/openSUSE/kernel-source/blob/master/scripts/apply-patches |
| `apply-patches.sh` 单点实现 | **Buildroot** + **OpenWrt** | https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh |
| `series.<profile>` 子集系列文件 | Buildroot variant + OpenWrt `PATCHFILES` | (本仓扩展) |
| `inventory.json` 派生物(单跑 + check) | Buildroot `pkg-stats` + OpenWrt `metadata.pl` | (本仓) |

---

## 8. 版本演进

| 字段/工具 | 添加版本 | 替代方案 |
|---|---|---|
| `tools/gen_inventory.py` + `inventory.json` 派生 | **v4.0** | (新增) |
| `series.<profile>` profile 系列文件 | **v4.0** | (新增,本仓扩展) |
| `upstream.yaml` Yocto 段(SUMMARY/LICENSE/HOMEPAGE) | v3.0 | 旧 `version.yaml` 无 recipe 段 |
| patch 头 DEP-3 6 必填 | v3.0 | 旧 4 必填(From/Subject/Upstream-Status/Signed-off-by) |
| `tools/apply_patch.sh` | v3.0 | 旧 verify.sh 内联 `git apply` loop |
| `patches/series` | v2.0 | 旧 patches[] 数组顺序 |
| `Upstream-Status` 8 状态 | v2.0 | 旧 `status` 5 状态 |

v4 与 v3 兼容(增量加严),可平滑迁移。v3 不可直接回退到 v1。
