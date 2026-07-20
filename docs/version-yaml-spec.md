# version-yaml 字段规范

> 权威定义 `versions/<upstream-id>/` 下文件的字段语义和约束。
> 本规范对齐业界成熟方案,**字段名 = Yocto/OpenEmbedded 同款**,
> 顺序机制 = SUSE/Debian/Quilt 同款。
> 详细设计原理见 [governance.md](./governance.md)。

## 1. 目录结构

每个 `versions/<upstream-id>/` 子目录固定包含 3 类文件:

```
versions/<upstream-id>/
├── upstream.yaml            # 上游基线(必填)
└── patches/
    ├── series               # patch 应用顺序(必填)
    └── *.patch              # patch 文件(含 RFC822 邮件式头)
```

`<upstream-id>` 命名约定:`<project>-<version>`,例如 `redis-7.0.15`。

## 2. `upstream.yaml`

唯一权威的上游基线 + 治理归属信息。

### 2.1 完整 schema

```yaml
upstream:
  repo: https://github.com/redis/redis      # 必填,Git URL
  version: 7.0.15                           # 必填,upstream tag/branch 名
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9   # 必填,40-char SHA,immutable pin

meta:                                        # 可选,治理归属
  owner: twwang@boostkit                     # 该 upstream 的维护 owner
  description: Redis 7.0.15 patch overlay (BoostKit)
```

### 2.2 字段表

| 字段 | 必填 | 类型 | 语义 |
|---|---|---|---|
| `upstream.repo` | 是 | URL | upstream Git 仓库 |
| `upstream.version` | 是 | string | upstream tag/branch(人类可读) |
| `upstream.commit` | 是 | 40-char SHA | `version` 对应的 immutable commit |
| `meta.owner` | 否 | email | 维护 owner;无则走 OSS 治理默认 |
| `meta.description` | 否 | string | 一句话说明 |

### 2.3 不放什么

**禁止**把以下内容放进 `upstream.yaml`(都已迁出):

- ~~patches[] 数组~~ — 顺序由 `patches/series` 表达
- ~~type / status / upstream_pr / whitelist_reason / dependence~~ — 全部进 patch 邮件式头

## 3. `patches/series`

唯一权威的 patch 应用顺序清单。

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

对齐:
- **Quilt/Debian `debian/patches/series`** — 同款"自上而下顺序清单"
- **SUSE `series.conf`** — 显式清单(本项目不引入 guards 机制)
- **ungoogled-chromium `patches/series`** — `chromium_version.txt` ↔ `upstream.yaml` 一一对应

## 4. patch 邮件式头

每个 `*.patch` 文件的第 1-15 行是 **RFC822 / git-format-patch 风格的邮件式头**,
承载 patch 的 provenance / upstream status / commit 引用 / sign-off。
本节对齐 Yocto `Upstream-Status` 字段 + SUSE `Git-commit` 字段 + DEP-3 header。

### 4.1 完整模板

```text
From: Author Name <author@example.com>
Date: Mon, 13 Jul 2026 14:30:00 +0800
Subject: [PATCH] Short single-line title

Upstream-Status: Submitted
Upstream-PR: https://github.com/redis/redis/pull/12345
Upstream-Commit: deadbeef1234567890abcdef1234567890abcdef
Whitelist-Reason: "Kunpeng-specific HW feature with no upstream equivalent"
Signed-off-by: Author Name <author@example.com>
Depends-on: 0002-perf-kunpeng-adapt-dtoe.patch

Long description (commit message body) explaining:
- What the patch changes
- Why the change is needed
- Compatibility notes / constraints

---

diff --git a/file.c b/file.c
...
```

### 4.2 字段表

| 字段 | 必填 | 格式 | 语义 |
|---|---|---|---|
| `From` | 是 | `Name <email>` | 作者,匹配 git author |
| `Date` | 是 | RFC 2822 | 提交日期 |
| `Subject` | 是 | `[PATCH] <title>` | 标题 |
| `Upstream-Status` | 是 | 枚举(见 4.3) | 上游合入状态 |
| `Upstream-PR` | 条件必填 | URL | 上游 PR/issue;`Status ∈ {Submitted,Accepted,Backport}` 时必填 |
| `Upstream-Commit` | 条件必填 | 40-char SHA | 上游 commit;`Status=Backport` 时必填 |
| `Whitelist-Reason` | 条件必填 | ≥30 字符 | 不合入上游的理由;`Status ∈ {Inappropriate,Denied,Inactive-Upstream}` 时必填 |
| `Signed-off-by` | 是 | `Name <email>` | DCO sign-off |
| `Depends-on` | 否 | patch 文件名 | 仅当存在非相邻依赖时填写 |

### 4.3 `Upstream-Status` 状态机

对齐 Yocto/OpenEmbedded 命名:

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

### 4.4 条件必填矩阵

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

## 5. 与业界对齐

| 字段/概念 | 业界出处 | URL |
|---|---|---|
| `Upstream-Status` 枚举 + 语义 | Yocto/OpenEmbedded patch metadata | https://docs.yoctoproject.org/dev/contributor-guide/recipe-style-guide.html |
| `Upstream-Commit` + `series.conf` 排序校验 | SUSE kernel-source | https://github.com/openSUSE/kernel-source/blob/master/series.conf |
| `patches/series` 自上而下顺序 | Debian Quilt | https://salsa.debian.org/kernel-team/linux/-/tree/master/debian/patches |
| RFC822/DEP-3 邮件式头 | Debian DEP-3 | https://dep-team.pages.debian.net/deps/dep3/ |
| 版本 pin ↔ patches 分离 | ungoogled-chromium | https://github.com/Eloston/ungoogled-chromium/blob/master/patches/series |

## 6. 版本演进

| 字段 | 添加版本 | 替代方案 |
|---|---|---|
| `upstream.yaml` | v2.0 | 旧 `version.yaml` 含 patches[] 的合并 schema |
| `patches/series` | v2.0 | 旧 patches[] 数组顺序 |
| `Upstream-Status` | v2.0 | 旧 `status` 字段(枚举不兼容,需重命名) |

v2 不可直接回退到 v1,因为状态语义从 5 状态变为 8 状态。
但顺序机制和上游基线表达兼容。