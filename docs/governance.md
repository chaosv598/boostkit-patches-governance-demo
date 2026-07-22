# Patch Overlay 治理设计 (v6.0)

## 1. 模型概述

本仓治理"在固定上游基线上叠加 N 个 patch"的问题。v6.0 对齐 **Buildroot `package/<name>/`** 结构：
文件系统即配置，manifest 仅声明无法从目录结构推导的信息。

```
versions/redis-7.0.15/
├── manifest.yaml              # ★ 上游 pin + 可选 depends
├── kunpeng-hw-accel/          # feature 目录（含 .patch 的目录即 feature）
├── jemalloc-arm64/
└── rdb-aof-fallback/
```

**配套工具**：
- `tools/apply_patch.sh` — Buildroot 风格应用器。扫版本目录发现 feature（有 `.patch` 的子目录），字典序 apply。有 `depends` 声明时 DFS 解析排序
- `tools/verify.sh` — 一键验证（仓根禁放 + manifest schema + clean clone + apply）
- `.github/lint.py` — patch 头校验（`headers`）+ manifest + DEP-3 一致性（`manifest`）

**核心原则**：
- **文件系统即配置** — feature 目录 = feature 声明，`ls` 即 patch 列表，文件名序即 apply 顺序
- **patch 元数据紧贴 patch** — DEP-3 6 必填（Description/Origin/Upstream-Status/Applies-To/Maintainer/Last-Update）
- **apply 单点实现** — `apply_patch.sh`，verify / build-perf / 本地复跑全走它
- **depends 可选** — 无需依赖时 manifesto 不写，feature 字典序 apply
- **无 Yocto recipe 字段** — 构建/发布系统职责，不在 patch 仓
- **无派生文件** — 单一真相就是目录结构 + patch 头 + manifest

## 2. 业界出处

本仓设计对齐以下 3 家：

### 2.1 Buildroot `apply-patches.sh` — 目录即配置

- 出处：https://github.com/buildroot/buildroot/blob/master/support/scripts/apply-patches.sh
- Buildroot 按 `package/<name>/` 下 patch 文件名字典序 apply，不维护系列文件
- **本仓对齐点**：feature 目录即 feature，`ls *.patch` 字典序就是 apply 顺序

### 2.2 Linux kernel Kconfig — depends 深度优先解析

- 出处：https://www.kernel.org/doc/Documentation/kbuild/kconfig-language.rst
- 实现：`scripts/kconfig/symbol.c` — `dep_stack` 栈回溯检测 + 深度优先解析 `depends on` 链
- **本仓对齐点**：manifest `depends:` 采用同款 DFS + 环检测算法，列表顺序 = 依赖项之间的 apply 顺序

### 2.3 DEP-3 (Debian) — patch 头 schema

- 出处：https://dep-team.pages.debian.net/deps/dep3/
- **本仓对齐点**：patch 头 6 必填 + 条件必填，`lint.py headers` 强制校验

### 2.4 工具→出处对照表

| 工具 | 业界出处 | 本仓实现 |
|------|----------|----------|
| `apply_patch.sh` | **Buildroot** `apply-patches.sh` + **Kconfig** `depends` | 目录扫 feature + 文件名序 apply + 可选 DFS depends |
| `verify.sh` | **Buildroot** `check-package` | 仓根禁放 + manifest schema + clean apply |
| `lint.py headers` | **DEP-3** + **Yocto** `Upstream-Status` | 6 必填 + 条件必填联动 |
| `lint.py manifest` | **Buildroot** 目录结构 | manifest schema + depends 引用 + 环检测 + 孤儿 + DEP-3 |

## 3. 工作流

### 3.1 `ci.yml`（3 步）

| 步骤 | 命令 | 职责 |
|------|------|------|
| 1 | `bash tools/verify.sh` | 仓根禁放 + manifest schema + clean apply |
| 2 | `python3 .github/lint.py manifest versions/*/` | manifest schema + depends + DEP-3 必填 |
| 3 | `python3 .github/lint.py headers versions/*/` | patch 头 schema |

### 3.2 本地复跑

```bash
bash tools/verify.sh
python3 .github/lint.py manifest versions/*/
python3 .github/lint.py headers versions/*/
```

## 4. 常见操作

### 4.1 新增 patch

```bash
# 1. 放到对应 feature 目录
cp my-new.patch versions/redis-7.0.15/kunpeng-hw-accel/0003-my-new.patch

# 2. 写 DEP-3 头（6 必填 + From/Subject/Signed-off-by）

# 3. 本地验证
bash tools/verify.sh
python3 .github/lint.py manifest versions/*/
python3 .github/lint.py headers versions/*/
```

### 4.2 改上游版本

```bash
# 改 manifest.yaml:
sed -i 's/version: 7.0.15/version: 7.0.16/; s|commit: f35f36a.*|commit: <new-sha>|' \
    versions/redis-7.0.15/manifest.yaml

# 重新 apply 验证
bash tools/apply_patch.sh \
  https://github.com/redis/redis <new-sha> \
  versions/redis-7.0.15 /tmp/build
```

### 4.3 新增 feature

```bash
mkdir versions/redis-7.0.15/feature-E
cp my.patch versions/redis-7.0.15/feature-E/0001-my.patch

# 如果 feature-E 依赖其他 feature，在 manifest.yaml 加:
# depends:
#   feature-E: [kunpeng-hw-accel]
```

### 4.4 废弃 patch

```bash
# 删除 .patch 文件，或改 patch 头:
# Upstream-Status: Inappropriate
# Whitelist-Reason: 上游架构变更，本 patch 不再需要
```

## 5. FAQ

### Q1: apply 顺序怎么定的？

无 `depends` → feature 目录名字典序，每个 feature 内 patch 文件名字典序。
有 `depends` → DFS 解析，依赖项在前、依赖者在后，列表内顺序决定依赖项之间的顺序。

### Q2: 为什么不用 Quilt `series` 文件？

Quilt 适合 1000+ patch 的 Debian kernel 场景。本仓 <50 patch，目录即系列，不需要 push/pop 栈。

### Q3: 为什么砍掉 Yocto recipe 字段？

SUMMARY/LICENSE/HOMEPAGE 等属于构建/发布系统职责，不属于 patch 仓。license audit 可走构建系统的 RPM spec 或 Yocto recipe。

### Q4: DEP-3 6 必填是硬要求吗？

是。`lint.py headers` rc=1 = block merge。Description <20 字符或 Last-Update 格式错也会 fail。

### Q5: apply_patch.sh cache 怎么复用？

cache 在 `<work_dir>/upstream/`，二次跑不重新 clone。

### Q6: feature 组合 vs per-feature 多 repo，选哪个？

用 feature 组合（单 repo 多目录）。per-feature 多 repo 仅在 >50 feature 且需要独立发布时适用。

### Q7: 为什么 compose 不另起脚本？

单点实现：verify / build-perf / 本地复跑全走 `apply_patch.sh`。将来逻辑变复杂时再拆不晚（YAGNI）。

---

## 6. 版本历史

| 版本 | 关键变更 |
|------|----------|
| v4.0 | `series.<profile>` 多系列文件 |
| v5.0 | `features.yaml` + `ACTIVE_FEATURES` + depends DFS |
| v5.1 | 删 `gen_inventory.py` + `inventory.json` |
| v5.2 | `lint_patch_headers.py` + `lint_series.py` 合并为 `lint.py` |
| **v6.0** | 两个 YAML 合并为 `manifest.yaml`；去掉 `patches/features/` 嵌套；砍掉 Yocto recipe 字段 / meta / title / upstream_status / default / 大多数 depends；目录即配置 |
