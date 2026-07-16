# Patch 生命周期 & 元数据格式

> **本文档**:字段表 + 5 状态机 + 4 个常见操作。
> **速查手册**:`docs/DEVELOPER-GUIDE.md`(PR 全流程 / 工具调用 / 不要做的事)。
> **设计原理**:`docs/GOVERNANCE.md`。
> **历史版本**:`docs/_archive/simplify-v3/patch-lifecycle.md`(3 状态叙事,已弃用)。

---

## 0. 30 秒速读

| 维度 | 取值 |
|---|---|
| 元数据 | **一版本一 yaml**(`versions/<v>/version.yaml`),patches 用数组 |
| 状态 | **5**:`pending` / `submitted` / `accepted` / `rejected` / `whitelisted` |
| 分类 | `type=ecological` / `type=project` |
| 数组顺序 | = apply 顺序(verify.sh 严格按数组顺序 git apply) |
| `dependence` | 仅作文档提示,不做拓扑校验 |

---

## 1. 元数据格式

### 1.1 版本字段(version.yaml 顶层)

```yaml
version_id: redis-7.0.15                       # 必须与目录名一致
description: Redis 7.0.15 patch overlay (BoostKit)
owner: chaosv598@boostkit
upstream_base:
  repo: https://github.com/redis/redis         # verify.sh 拉这个仓
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b71653ec9   # 40 位 SHA
```

### 1.2 patches[] 元素

```yaml
patches:
  - name: 0001-hw-kunpeng-adapt-iouring        # 必须与 patches/<name>.patch 对应
    title: Adapt io_uring for Kunpeng ARM
    owner: twwang@boostkit
    type: ecological                           # ecological(推上游) / project(本仓独享)
    status: submitted                          # 5 选 1,见 §2
    upstream_pr:                               # status∈{submitted, accepted} 时必填
      - https://github.com/redis/redis/pull/12345
    whitelist_reason: ""                       # status∈{whitelisted, rejected} 时必填
    dependence: []
```

### 1.3 字段约束

| 字段 | 必填 | 枚举/格式 | 校验时机 |
|---|---|---|---|
| `version_id` | ✅ | 字符串,与目录名一致 | sync-manifest |
| `upstream_base.repo` | ✅ | URL | verify.sh + sync-manifest |
| `upstream_base.commit` | ✅ | 40 位 SHA | verify.sh |
| `patches[].name` | ✅ | 字符串,必须去掉 `.patch` 后缀与文件匹配 | verify.sh |
| `patches[].type` | ✅ | `ecological` / `project` | sync-manifest |
| `patches[].status` | ✅ | 5 选 1 | sync-manifest |
| `patches[].upstream_pr` | status∈{submitted, accepted} 时必填 | URL 数组 ≥1 | sync-manifest |
| `patches[].whitelist_reason` | status∈{whitelisted, rejected} 时必填 | whitelisted ≥30 字符 | sync-manifest + whitelist-audit |
| `patches[].dependence` | ⬜ | 字符串数组 | 仅文档提示 |

---

## 2. 5 状态机

```
pending ──发上游PR──▶ submitted ──上游merge──▶ accepted
   │                     │
   │ type=project         │ 上游reject
   ▼                     ▼
accepted            rejected ◀── 也可改回 pending 重发
   │
   │ 永久携带(项目型 / 强硬件绑定)
   ▼
whitelisted(走 whitelist_reason ≥30 字符)
```

### 2.1 合法转换表

| 当前状态 | 合法下一状态 | 触发动作 |
|---|---|---|
| `pending` | `submitted` | 发上游 PR,把 `upstream_pr[]` 填上 |
| `pending` | `accepted` | type=project 直接在本仓落地 |
| `submitted` | `accepted` | 上游 merge,补 merged commit 备注 |
| `submitted` | `pending` | PR 被拒/长期不响应,撤回重发 |
| `submitted` | `rejected` | 上游明确 reject,`whitelist_reason` 填拒绝原因 |
| `accepted` | (终态) | 永久保留;不再变 |
| `rejected` | `pending` | 改 patch 内容后重新提交 |
| `rejected` | `whitelisted` | 决定永久携带,补 ≥30 字符 whitelist_reason |
| `whitelisted` | `pending` | 决定重新尝试上游合入(罕见) |

### 2.2 type 字段的作用

| type | 含义 | 典型 status 路径 |
|---|---|---|
| `ecological` | 修复/特性会上游合入 | pending → submitted → accepted |
| `project` | 本仓独享(平台特性、业务定制) | pending → accepted(无需 submitted) |

`type=project` 不允许 `status=rejected`(本仓 reject 项目型 patch 没语义)。

---

## 3. 4 个常见场景

### 场景 A:新增第 N 个 patch

```bash
# 1. 创建 patch 文件(命名规范见 docs/PATCHES-NAMING.md)
$EDITOR versions/redis-7.0.15/patches/0005-fix-memory-leak.patch

# 2. 在 version.yaml 的 patches[] 末尾追加一项
$EDITOR versions/redis-7.0.15/version.yaml

# 3. 本地校验
bash tools/verify.sh
python3 tools/sync-manifest.py --check
python3 tools/whitelist-audit.py --strict

# 4. commit
git add versions/redis-7.0.15/patches/0005-fix-memory-leak.patch
git add versions/redis-7.0.15/version.yaml
git commit -m "feat(7.0.15): add 0005-fix-memory-leak patch"
git push -u origin feat/add-0005-memory-leak-fix
gh pr create
```

### 场景 B:patch 状态变更(pending → submitted)

```yaml
- status: pending
+ status: submitted
+ upstream_pr:
+   - https://github.com/redis/redis/pull/12345
```

`bash tools/verify.sh && python3 tools/sync-manifest.py --check` → commit → push。

### 场景 C:加白名单 / 续白名单

```yaml
- status: accepted
+ status: whitelisted
+ whitelist_reason: |
+   Kunpeng-specific DMA-to-engine HW feature; no upstream equivalent
+   interface; reviewed by twwang@boostkit on 2026-06.
```

CI 自动派生到 `WHITELIST.yaml`。`whitelist-audit --strict` 校 reason 字数。

### 场景 D:上游发新版本(rebase)

**当前没有自动化 rebase 工具**——人工复制目录:

```bash
mkdir -p versions/redis-7.0.16/patches
cp versions/redis-7.0.15/version.yaml versions/redis-7.0.16/
cp versions/redis-7.0.15/patches/*.patch versions/redis-7.0.16/patches/
$EDITOR versions/redis-7.0.16/version.yaml
# 改:version_id / description / upstream_base.version / upstream_base.commit
```

---

## 4. 数组顺序即 apply 顺序

`patches[]` 的**顺序就是 `git apply` 的顺序**。`dependence` 字段只作文档提示,verify.sh 不做拓扑校验:

- 想让 B 依赖 A,把 B 放在 A 后面
- 永远**在末尾追加**新 patch;不要在中间插入(会改 apply 顺序 = 改实际行为)
- 如果必须调整顺序 = 等同于新增 patch,正常 PR 即可

---

## 5. 与自动派生物的关系

```
versions/<v>/version.yaml     ← 开发者手写(唯一入口)
    ↓ sync-manifest.py 派生
├── PATCHES.yaml              ← 仓根,机器读,跨版本聚合
├── WHITELIST.yaml            ← 仓根,白名单视图
└── docs/PATCHES-STATUS.md    ← 人读状态仪表盘
```

**开发者不动手改派生物**——改了也会被 CI 覆盖;sync-manifest drift 时 CI 自动 commit 修复(带 `[skip ci]`)。