# Schema 权威定义

> 本文档是仓内三类 YAML/header 的**单一权威字段表**。所有示例、工具校验、CI 检查都以此为准。
> 文件清单:`lint.py headers` → §1,`verify.sh` → §2,`lint.py features` → §3。
> 业界出处速查表见 [§4](#4-业界出处速查)。

---

## 1. Patch 邮件式头(`*.patch` 文件首部,DEP-3)

每个 patch 文件前若干行为 header,在 `diff --git` 之前。

### 1.1 字段表

**6 必填**(DEP-3 规范):

| 字段 | 类型 | 语义 |
|---|---|---|
| `Description` | string ≥20 字符(连续块,允许多行 `\|` 续行) | patch 改了什么 + 为何改 |
| `Origin` | string | 出处 URL / vendor 名 / `local` |
| `Upstream-Status` | enum(见 1.3) | 上游合入状态(Yocto 8 状态对齐) |
| `Applies-To` | string | 该 patch 适用的上游 commit/version 范围 |
| `Maintainer` | `Name <email>` | 本仓维护人(收件方) |
| `Last-Update` | `YYYY-MM-DD` | 最后一次更新日期 |

**3 必填**(对齐 git format-patch + DCO):`From` / `Subject` / `Signed-off-by`

**条件必填**:

| 字段 | 触发条件 | 类型 | 语义 |
|---|---|---|---|
| `Upstream-PR` | `Upstream-Status ∈ {Submitted, Accepted, Backport}` | URL | 上游 PR/issue 链接 |
| `Upstream-Commit` | `Upstream-Status ∈ {Accepted, Backport}` | 40-char SHA | 上游 commit |
| `Whitelist-Reason` | `Upstream-Status ∈ {Rejected, Inappropriate, Denied, Inactive-Upstream}` | string ≥30 字符 | 不合入上游的理由 |
| `Depends-on` | 存在非相邻依赖 | patch 文件名 | 跨位序依赖(本仓用 `features.yaml.depends` 取代,一般不用) |

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

### 1.4 模板(照抄)

```text
From: chaosv598 <chaosv598@boostkit>
Subject: [PATCH] Adapt io_uring for Kunpeng ARM

Description: |
  Adapt io_uring to use Kunpeng ARM optimizations.
  Enable iouring submission polling for ARM64 cores.
Origin: https://github.com/redis/redis/pull/12345
Upstream-Status: Submitted
Upstream-PR: https://github.com/redis/redis/pull/12345
Applies-To: redis-7.0.15
Maintainer: twwang@boostkit
Last-Update: 2026-07-20
Signed-off-by: chaosv598 <chaosv598@boostkit>

diff --git a/src/io_uring.c b/src/io_uring.c
...
```

### 1.5 校验命令

```bash
python3 .github/lint.py headers versions/*/patches/
# 缺字段 → 报错 + 列出缺失字段名
# Upstream-Status 非 8 状态 → 报错 + 列出合法值
# 条件必填联动失败 → 报错(如 Submitted 缺 Upstream-PR)
```

---

## 2. `versions/<id>/upstream.yaml`(per-version)

Yocto recipe 风格 + 上游 pin + 治理归属。

### 2.1 字段表

**段 1:Recipe 元数据**(Yocto 风格,非必填,推荐填)

| 字段 | 类型 | 语义 |
|---|---|---|
| `SUMMARY` | string | 一句话描述 |
| `DESCRIPTION` | multi-line | 详细描述 |
| `HOMEPAGE` | URL | 上游项目主页 |
| `LICENSE` | SPDX 字符串 | 整体 license |
| `LIC_FILES_CHKSUM` | `file://X;md5=...` | 上游 license 文件 + md5(Yocto 用法) |
| `SECTION` | string | 分类标签(Yocto convention) |

**段 2:上游基线 pin**(必填)

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `upstream.repo` | **是** | URL | 上游 git URL |
| `upstream.version` | **是** | string | upstream tag/version |
| `upstream.commit` | **是** | 40-char SHA | immutable pin |

**段 3:治理归属 meta**(非必填,但推荐填)

| 字段 | 类型 | 语义 |
|---|---|---|
| `meta.owner` | email | 该 upstream 维护 owner(双角色之一:责任主体) |
| `meta.maintainer` | email | 当前 maintainer(双角色之二:日常接手者;可多人逗号分隔) |
| `meta.last_review` | `YYYY-MM-DD` | 上次 review 日期 |
| `meta.lifecycle` | enum | `active` / `frozen` / `deprecated` |

### 2.2 范例

```yaml
SUMMARY: "Redis in-memory data structure store with Kunpeng ARM optimizations"
DESCRIPTION: |
  Redis is an open source, in-memory data structure store used as a database,
  cache, message broker, and streaming engine. BoostKit overlay.
HOMEPAGE: "https://redis.io"
LICENSE: "BSD-3-Clause"
LIC_FILES_CHKSUM: "file://COPYING;md5=508cbf69e54be9b31b53b42e7411f8c4"
SECTION: "network/database"

upstream:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9

meta:
  owner: twwang@boostkit
  maintainer: twwang@boostkit
  last_review: 2026-07-20
  lifecycle: active
```

### 2.3 业界出处(meta 块 4 字段)

| 本仓字段 | 出处 |
|---|---|
| `meta.owner` + `meta.maintainer` | **openEuler** `community/sig/sigs/MAINTAINERS.md` 双角色模型 — `owners:` + `maintainers:` 各为独立 roster,owner = 责任主体 / sponsor,maintainer = commit rights + 日常 review |
| `meta.lifecycle` | **openEuler** 同款文件 `state: active \| frozen` — 本仓加 `deprecated` 一档以区分"停更"与"明确弃用" |
| `meta.last_review` | 本仓原创,弱对齐 **SPDX 2.3** `ReleaseDate`(7.25)/`ValidUntilDate`(7.27)语义 |

### 2.4 校验命令

```bash
bash tools/verify.sh
# 仓根禁放检查 + upstream.yaml schema(40-char SHA 校验 + 必填字段)+ 委托 apply_patch.sh
```

---

## 3. `versions/<id>/patches/features.yaml`(per-version)

OpenWrt `Config.in` + Linux kernel Kconfig 的 YAML 等价物,**单一权威**。

### 3.1 字段表

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `features.<name>` 顶层 key | **是** | kebab-case string | 稳定 identifier(被 `depends` / `ACTIVE_FEATURES` 引用) |
| `features.<name>.title` | 推荐 | string | 一句话描述(给 dashboard / 文档用) |
| `features.<name>.patches` | **是** | list[str] | 该 feature 包含的 patch 文件名(相对 `patches/features/<name>/`) |
| `features.<name>.depends` | 否 | list[str] | 依赖的其他 feature(DFS 深度优先解析 + 环依赖 hard-fail) |
| `features.<name>.default` | 否 | bool | 是否默认激活(默认组合 = 所有 `default:true` 的并集) |
| `features.<name>.upstream_status` | 否 | enum | 该 feature 主导上游状态(Yocto 8 状态枚举之一,见 §1.3;给 dashboard 用) |

### 3.2 模板

```yaml
features:
  kunpeng-hw-accel:
    title: "Kunpeng ARM 硬件加速(io_uring 适配 + DTOE DMA 网络路径)"
    patches:
      - 0001-hw-kunpeng-adapt-iouring.patch
      - 0002-perf-kunpeng-adapt-dtoe.patch
    depends: []
    default: true
    upstream_status: Inappropriate
  jemalloc-arm64:
    title: "jemalloc ARM64 pointer-tag + GC decay 策略"
    patches:
      - 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
    depends: []
    default: false
    upstream_status: Submitted
  rdb-aof-fallback:
    title: "AOF fallback when RDB corrupted"
    patches:
      - 0001-perf-rdb-fallback-aof.patch
    depends: []
    default: true
    upstream_status: Submitted
```

### 3.3 物理目录布局

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

### 3.4 组合(combo)— 客户用 `ACTIVE_FEATURES` 选

```bash
# 默认组合 = 所有 default:true 的并集(本仓 = kunpeng-hw-accel + rdb-aof-fallback)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches /tmp/build

# 客户 A:只要 rdb-aof-fallback 可靠性
ACTIVE_FEATURES="rdb-aof-fallback" bash tools/apply_patch.sh ... --features ... /tmp/build-a

# 客户 B:全开(包括默认不激活的 jemalloc-arm64)
ACTIVE_FEATURES="kunpeng-hw-accel jemalloc-arm64 rdb-aof-fallback" bash tools/apply_patch.sh ... --features ... /tmp/build-b

# 等价的 --active 参数(便于 CI 传参)
bash tools/apply_patch.sh ... --features ... --active "jemalloc-arm64 rdb-aof-fallback" /tmp/build-c
```

### 3.5 `depends` 解析

激活 feature 时自动 include 依赖项并先 apply:

```yaml
rdb-aof-fallback:
  depends: [kunpeng-hw-accel]   # 激活 C 时自动 include A,A 先 apply
```

`apply_patch.sh` 在 compose 时:
1. 校验所有 ACTIVE feature 名都在 features 里
2. 深度优先解析 depends(自动 include,dedup)
3. resolved 顺序 = depends 在前(被依赖的先 apply)
4. **环依赖 hard-fail**(例 A 依赖 B、B 依赖 A → 报错退出)

### 3.6 业界对齐

- **OpenWrt** `package/<name>/Config.in` + `Makefile` — feature 声明 + 条件 `PATCHFILES`(依赖激活后才进 build)
- **Linux kernel Kconfig** `depends on` — DFS 深度优先解析 + 环依赖 hard-fail(同款语义)
- **Yocto** `.bbappend` 条件 SRC_URI — `${@bb.utils.contains(...)}`(条件 feature 组合)

### 3.7 校验命令

```bash
python3 .github/lint.py features versions/*/patches/
# features 字段完整 → 报错 + 缺字段名
# patches 列表文件不存在 → 报错 + 路径
# depends 引用未知 feature → 报错 + 未知 feature 名
# depends 环依赖 → 报错 + 环路径
# upstream_status 非 8 状态 → 报错 + 列出合法值
# 孤儿 patch(目录有但 features.yaml 未声明) → 报错 + 路径
```

---

## 4. 业界出处速查 + 校验矩阵

### 4.1 5 家业界出处

| 方案 | 对齐到本仓何处 |
|---|---|
| **Yocto/OpenEmbedded** | recipe 字段(SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION)+ `Upstream-Status` 8 状态 |
| **DEP-3** (Debian) | patch 邮件式头 schema,6 必填字段(Description/Origin/Upstream-Status/Applies-To/Maintainer/Last-Update) |
| **Buildroot** `apply-patches.sh` | `tools/apply_patch.sh` 单点 series 应用器 |
| **OpenWrt** `package/<name>/Config.in` + `Makefile` | `features.yaml` feature 声明 + 条件 `PATCHFILES` |
| **Linux kernel Kconfig** | `depends` / `select` / `default` 语义(DFS 深度优先解析 + 环依赖检测) |

### 4.2 校验矩阵

| 校验项 | 工具 | 触发条件 | fail 表现 |
|---|---|---|---|
| patch header 6 必填 | `lint.py headers` | 任何 .patch | 缺字段 → 报错 + 列出缺失字段名 |
| patch header `Upstream-Status` 枚举 | `lint.py headers` | 任何 .patch | 非 Yocto 8 状态 → 报错 + 列出合法值 |
| patch header 条件必填联动 | `lint.py headers` | 任何 .patch | Submitted 缺 Upstream-PR → 报错 |
| `upstream.yaml.commit` 40-char SHA | `verify.sh` | CI / PR | rc=1 |
| 仓根禁放检查 | `verify.sh` | CI / PR | rc=1 |
| `features.<name>.patches` 文件存在 | `lint.py features` | 任何 feature | 报错 + 缺文件路径 |
| `features.<name>.depends` 引用存在 | `lint.py features` | 任何 feature | 报错 + 未知 feature 名 |
| `features.<name>.depends` 无环 | `lint.py features` | 任何 feature | 报错 + 环路径 |
| `features.<name>.upstream_status` 枚举 | `lint.py features` | 任何 feature | 报错 + 列出合法值 |
| 孤儿 patch(目录有但 features.yaml 未声明) | `lint.py features` | 任何 feature | 报错 + 路径 |

### 4.3 本地一键验证

```bash
bash tools/verify.sh                      # 结构 + clean apply
python3 .github/lint.py all versions/*/patches/  # patch 头 + features.yaml
```

全部 rc=0 才算通过。

---

## 5. 演进方向：v6.0 精简 Schema (PROPOSAL)

> 与 [governance.md §6](./governance.md#6-演进方向v60-buildroot-精简模型-proposal) 配套。

### 5.1 `versions/<id>/manifest.yaml`（合并 upstream.yaml + features.yaml）

**段 1：上游基线 pin**（必填）

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `upstream.repo` | **是** | URL | 上游 git URL |
| `upstream.version` | **是** | string | upstream tag/version |
| `upstream.commit` | **是** | 40-char SHA | immutable pin |

**段 2：feature config**（仅保留文件系统无法表达的 2 个字段）

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `features.<name>` 顶层 key | **是** (必须对应 `features/<name>/` 目录) | kebab-case string | 稳定 identifier |
| `features.<name>.depends` | 否 | list[str] | DFS 深度优先解析 + 环依赖 hard-fail |
| `features.<name>.default` | 否 | bool | 默认激活 (默认组合 = 所有 `default:true` 的并集) |

**砍掉的字段**（见 governance.md §6.2 决策表）：
- `upstream.yaml`: Yocto recipe 字段、`meta` 块
- `features.yaml`: `patches`（文件系统自描述）、`title`（patch 头）、`upstream_status`（派生）

### 5.2 模板

```yaml
upstream:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9

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

### 5.3 校验命令（不变）

```bash
python3 .github/lint.py features versions/*/patches/
# ↑ manifest.yaml schema (depends + default) + 目录一致性 (feature 名 = 目录名)
```