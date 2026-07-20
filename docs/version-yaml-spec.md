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
    ├── series               # patch 应用顺序(自上而下)
    └── *.patch              # patch 文件(DEP-3 邮件式头 + diff)
```

`<upstream-id>` 命名约定:`<project>-<version>`,例如 `redis-7.0.15`。

**配套工具**(仓根 `tools/`):
- `tools/apply_patch.sh` — Buildroot 风格 series 应用器(单点实现)
- `tools/verify.sh` — 一键验证(仓根禁放 + upstream.yaml schema + 委托 apply_patch.sh)

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

### 3.3 业界对齐

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

## 6. 与业界对齐速查

| 概念 | 业界出处 | URL |
|---|---|---|
| `SUMMARY`/`LICENSE`/`LIC_FILES_CHKSUM`/`HOMEPAGE`/`SECTION` | **Yocto/OpenEmbedded recipe 字段** | https://docs.yoctoproject.org/ref-manual/variables.html |
| `Upstream-Status` 8 状态语义 | Yocto patch metadata | https://docs.yoctoproject.org/dev/contributor-guide/recipe-style-guide.html |
| `Description` / `Origin` / `Maintainer` / `Last-Update` 必填 | **DEP-3** patch header | https://dep-team.pages.debian.net/deps/dep3/ |
| `Upstream-Status` + `Whitelist-Reason` | Yocto + Debian DEP-3 | (同上) |
| `patches/series` 自上而下顺序 | Debian Quilt / ungoogled-chromium | https://salsa.debian.org/kernel-team/linux/-/tree/master/debian/patches |
| `series.conf` + SHA-256 校验和 | SUSE kernel-source | https://github.com/openSUSE/kernel-source/blob/master/scripts/apply-patches |
| `apply-patches.sh` 单点实现 | **Buildroot** + **OpenWrt** | https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh |

---

## 7. 版本演进

| 字段/工具 | 添加版本 | 替代方案 |
|---|---|---|
| `upstream.yaml` Yocto 段(SUMMARY/LICENSE/HOMEPAGE) | v3.0 | 旧 `version.yaml` 无 recipe 段 |
| patch 头 DEP-3 6 必填 | v3.0 | 旧 4 必填(From/Subject/Upstream-Status/Signed-off-by) |
| `tools/apply_patch.sh` | v3.0 | 旧 verify.sh 内联 `git apply` loop |
| `patches/series` | v2.0 | 旧 patches[] 数组顺序 |
| `Upstream-Status` 8 状态 | v2.0 | 旧 `status` 5 状态 |

v3 与 v2 兼容(增量加严),可平滑迁移。v3 不可直接回退到 v1。
