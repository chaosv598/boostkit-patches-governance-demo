# Schema 权威定义 (v6.0)

> 本文档是仓内 YAML / header 的**单一权威字段表**。所有示例、工具校验、CI 检查都以此为准。

## 目录结构

```
versions/redis-7.0.15/
├── manifest.yaml              # ★ 上游 pin + 可选 depends
├── kunpeng-hw-accel/          # feature 目录（含 .patch 的目录即 feature）
│   ├── 0001-hw-kunpeng-adapt-iouring.patch
│   └── 0002-perf-kunpeng-adapt-dtoe.patch
├── jemalloc-arm64/
│   └── 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
└── rdb-aof-fallback/
    └── 0001-perf-rdb-fallback-aof.patch
```

---

## 1. Patch 邮件式头（`*.patch` 文件首部, DEP-3）

每个 patch 文件前若干行为 header，在 `diff --git` 之前。

### 1.1 字段表

**6 必填**（DEP-3 规范）：

| 字段 | 类型 | 语义 |
|---|---|---|
| `Description` | string ≥20 字符 | patch 改了什么 + 为何改 |
| `Origin` | string | 出处 URL / vendor 名 / `local` |
| `Upstream-Status` | enum（见 1.3） | 上游合入状态（Yocto 8 状态对齐） |
| `Applies-To` | string | 该 patch 适用的上游 commit/version 范围 |
| `Maintainer` | `Name <email>` | 本仓维护人 |
| `Last-Update` | `YYYY-MM-DD` | 最后一次更新日期 |

**3 必填**（对齐 git format-patch + DCO）：`From` / `Subject` / `Signed-off-by`

**条件必填**：

| 字段 | 触发条件 | 类型 | 语义 |
|------|----------|------|------|
| `Upstream-PR` | `Upstream-Status ∈ {Submitted, Accepted, Backport}` | URL | 上游 PR/issue 链接 |
| `Upstream-Commit` | `Upstream-Status ∈ {Accepted, Backport}` | 40-char SHA | 上游 commit |
| `Whitelist-Reason` | `Upstream-Status ∈ {Rejected, Inappropriate, Denied, Inactive-Upstream}` | string ≥30 字符 | 不合入上游的理由 |

### 1.2 `Upstream-Status` 枚举（Yocto 8 状态）

```text
Pending / Submitted / Accepted / Rejected / Backport
Inappropriate / Denied / Inactive-Upstream
```

### 1.3 模板

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

### 1.4 校验命令

```bash
python3 .github/lint.py headers versions/*/
```

---

## 2. `versions/<id>/manifest.yaml`

Buildroot 风格：上游 pin + 可选 depends。

### 2.1 字段表

| 字段 | 必填 | 类型 | 语义 |
|------|------|------|------|
| `repo` | **是** | URL | 上游 git URL |
| `version` | **是** | string | upstream tag/version |
| `commit` | **是** | 40-char SHA | immutable pin |
| `depends` | 否 | dict | feature 间依赖（见 2.3） |

### 2.2 模板

```yaml
repo: https://github.com/redis/redis
version: 7.0.15
commit: f35f36a265403c07b119830aa4bb3b7d71653ec9
```

### 2.3 `depends` 字段

可选。仅在 feature 间有真正的依赖关系时才声明：

```yaml
depends:
  C: [B, A]          # C 依赖 B 和 A，且 B 先于 A apply
  D: [C]             # D 依赖 C（传递：B→A→C→D）
```

- 列表顺序 = 依赖项之间的 apply 顺序
- 被依赖项始终在依赖者之前
- 不声明 = 无依赖，所有 feature 按目录名字典序 apply
- `ACTIVE_FEATURES="C"` 时自动拉入 B 和 A

### 2.4 校验命令

```bash
bash tools/verify.sh                       # 结构 + clean apply
python3 .github/lint.py manifest versions/*/ # schema + depends + DEP-3
```

---

## 3. 业界出处速查

| 方案 | 对齐到本仓何处 |
|------|----------------|
| **Buildroot** `apply-patches.sh` | 目录即 feature，文件名序即 apply 顺序 |
| **Linux kernel Kconfig** | `depends` DFS 深度优先解析 + 环检测 |
| **DEP-3** (Debian) | patch 邮件式头 schema，6 必填字段 |

## 4. 校验矩阵

| 校验项 | 工具 | fail 表现 |
|--------|------|-----------|
| patch header 6 必填 | `lint.py headers` | 报错 + 缺失字段名 |
| `Upstream-Status` 枚举 | `lint.py headers` | 报错 + 合法值列表 |
| 条件必填联动 | `lint.py headers` | 报错 |
| manifest 必填字段 | `lint.py manifest` | 报错 |
| `depends` 引用存在 | `lint.py manifest` | 报错 + 未知 feature 名 |
| `depends` 无环 | `lint.py manifest` | 报错 + 环路径 |
| 孤儿 .patch（版本根） | `lint.py manifest` | 报错 + 路径 |
| 仓根禁放 | `verify.sh` | rc=1 |
| clean apply | `verify.sh` | rc=1 |

## 5. 版本历史

| 版本 | 关键变更 |
|------|----------|
| v5.2 | `upstream.yaml` (Yocto recipe + meta) + `features.yaml` (patches/title/default/upstream_status/depends) |
| **v6.0** | 合并为 `manifest.yaml`（repo/version/commit + 可选 depends）；去掉 `patches/features/` 嵌套；砍 Yocto/meta/title/default/upstream_status/patches 列表 |
