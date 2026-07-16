# Developer Guide —— 5 分钟上手

> **目的**:让第一次接触本仓的开发者,5 分钟内能改一处、跑通本地校验、开 PR、CI 绿、合并。
> **核心目标**:开发者只编辑 `versions/<v>/version.yaml` + `versions/<v>/patches/<name>.patch`,其他文件都自动派生。
> **阅读路径**:完全新人 → 读下面「§A 新人 5 分钟快路径」走一遍;有经验 → 直接跳「§0 30 秒速读」+ 遇到问题回头查细节。

---

## §A. 新人 5 分钟快路径

> **适用对象**:第一次接触本仓的开发者(假设你会 git + GitHub + bash 基础)。
> **目标**:5 分钟铺垫 + 5 分钟实操,完成你的第一个 PR。

### §A.1 5 分钟铺垫:5 件事先记牢

1. **唯一手写入口**:`versions/<v>/version.yaml` + `versions/<v>/patches/<name>.patch`
2. **派生物不动手**:`PATCHES.yaml` / `WHITELIST.yaml` / `docs/PATCHES-STATUS.md` 全由 CI 写
3. **本地必跑 3 工具**:`verify.sh` + `sync-manifest.py --check` + `whitelist-audit.py --strict`
4. **CI 5 阶段全绿才允许 merge**;build-perf 改动 patch 才触发
5. **5 状态机**:`pending` / `submitted` / `accepted` / `rejected` / `whitelisted`

### §A.2 准备环境(2 分钟)

```bash
git clone https://github.com/chaosv598/boostkit-patches-governance-demo.git
cd boostkit-patches-governance-demo
pip install pyyaml
bash tools/verify.sh                  # 应看到全部 ✓
python3 tools/sync-manifest.py --check   # 应看到 sync-manifest 一致
```

两个工具都退出码 0 即可继续。如果 `verify.sh` 报 `apply 失败(单 patch)` 是正常的 warning(网络/版本漂移),不阻塞。

### §A.3 5 分钟实操:改一个 patch 的状态

**目标**:把 `redis-7.0.15/0003-perf-jemalloc-arm64-pointer-tag-and-gc` 从 `submitted` 改成 `accepted`(假装上游已 merge)。

```bash
git checkout master && git pull
git checkout -b docs/onboarding-demo
```

打开 `versions/redis-7.0.15/version.yaml`,找到 0003 那一条:

```diff
   - name: 0003-perf-jemalloc-arm64-pointer-tag-and-gc
     title: Adapt jemalloc 5.2.1 ARM64 pointer-tag and GC strategy optimize
     owner: yinbin@boostkit
     type: ecological
-    status: submitted
+    status: accepted
     upstream_pr:
       - https://github.com/redis/jemalloc/pull/9876
```

```bash
# 本地校验
bash tools/verify.sh                       # 字段 + 一致性 + apply
python3 tools/sync-manifest.py --check     # drift 检测

# commit + push + PR
git add versions/redis-7.0.15/version.yaml
git commit -m "docs(0003): mark as accepted (onboarding demo)"
git push -u origin docs/onboarding-demo
gh pr create --title "docs(0003): mark as accepted (onboarding demo)" \
  --body-file .github/PULL_REQUEST_TEMPLATE.md
```

PR 页面右下角 GitHub Actions 应跑 ci.yml 5 阶段,全部 ✅;merge 后 PATCHES.yaml / WHITELIST.yaml 会自动更新(sync-manifest 在 post-merge 也会跑)。🎉 完成。

### §A.4 完成清单(新人 check)

- [ ] 克隆仓 + 跑 `verify.sh` + `sync-manifest.py --check` 看到绿
- [ ] 改一个 patch 的 status,本地 3 工具全过
- [ ] commit + push + 开 PR + 等 CI 5 阶段全绿
- [ ] squash merge
- [ ] 跑 sync-manifest --check 在 master 上看到 PATCHES.yaml / WHITELIST.yaml 已自动更新

---

## 0. 30 秒速读

| 维度 | 数值 |
|---|---|
| 开发者契约 | `versions/<v>/version.yaml`(一版本一 yaml) |
| Patch 文件 | `versions/<v>/patches/<name>.patch` |
| 自动派生文件 | `PATCHES.yaml` / `WHITELIST.yaml` / `docs/PATCHES-STATUS.md`(**禁止手改**) |
| 本地工具 | 3 个必跑:`verify.sh` / `sync-manifest.py` / `whitelist-audit.py`(+ `build-perf.sh` 可选) |
| CI 工作流 | `ci.yml`(5 阶段门禁)+ `build-perf.yml`(真实编译+压测) |
| Patch 状态 | 5 个:`pending` / `submitted` / `accepted` / `rejected` / `whitelisted` |
| Patch 分类 | `type=ecological`(推上游合入)/ `type=project`(本仓独享) |

**铁律**:**唯一手写入口 = `version.yaml` + `patches/*.patch`**。其它生成物由 `sync-manifest.py` 在 CI 自动维护,drift 时 CI 会自动 commit 修复。

---

## 1. 元数据格式

### 1.1 版本字段(version.yaml 顶层)

```yaml
version_id: redis-7.0.15                       # 必须与目录名一致
description: Redis 7.0.15 patch overlay (BoostKit)
owner: chaosv598@boostkit
upstream_base:
  repo: https://github.com/redis/redis         # verify.sh 会拉这个仓
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b71653ec9   # 40 位 SHA(必填精确)
```

### 1.2 patches[] 元素

```yaml
patches:
  - name: 0001-hw-kunpeng-adapt-iouring        # 文件名去掉 .patch 后缀,必须与 patches/<name>.patch 对应
    title: Adapt io_uring for Kunpeng ARM      # 一句话作用
    owner: twwang@boostkit                     # 该 patch 负责人
    type: ecological                           # ecological(推上游) / project(本仓独享)
    status: submitted                          # 5 选 1,见下表
    upstream_pr:                               # type=ecological 且 status∈{submitted,accepted} 时必填
      - https://github.com/redis/redis/pull/12345
    whitelist_reason: ""                       # status=whitelisted 时必填(≥30 字符);status=rejected 时填拒绝原因
    dependence: []                             # 提示性,verify.sh 按数组顺序 apply
```

### 1.3 5 状态机

```
pending ──发上游PR──▶ submitted ──上游merge──▶ accepted
   │                     │
   │ type=project         │ 上游reject
   ▼                     ▼
accepted            rejected
   │                     │
   │ 永久携带             │ 也可改回 pending 重发
   ▼
whitelisted(走 exception 块,不进 patches.status)
```

| status | 含义 | 必填字段 |
|---|---|---|
| `pending` | patch 已加入但未发 PR | — |
| `submitted` | 已发上游 PR,等审核 | `upstream_pr[]` ≥1 |
| `accepted` | 上游已 merge(ecological)/ 本仓已落地(project) | `upstream_pr[]` ≥1 |
| `rejected` | 上游明确拒绝合入 | `whitelist_reason`(填拒绝原因) |
| `whitelisted` | 永久携带,不再追求上游合入 | `whitelist_reason` ≥30 字符 |

**字段命名注意**:`version.yaml` 里叫 `type`(不是 `category`);`upstream_pr` 是**数组**;PR URL 列表不用 `pr` 字段。

---

## 2. 3 个本地工具

```bash
bash tools/verify.sh                 # 字段 + 一致性 + upstream apply dry-run
python3 tools/sync-manifest.py --check   # drift 检测(也跑在 CI)
python3 tools/sync-manifest.py --write   # 写回 PATCHES.yaml / WHITELIST.yaml / docs/PATCHES-STATUS.md
python3 tools/whitelist-audit.py --strict # 白名单审计
bash tools/build-perf.sh all <v>    # 可选:本地真编 + 跑 memtier_benchmark
```

**退出码**:`0` = 通过;非 0 = hard fail。`verify.sh` 对单 patch apply 失败降级为 warning(网络/版本漂移正常),其它工具硬错即拒收。

---

## 3. PR 全流程(5 步走)

### Step 1:分支

```bash
git checkout master && git pull
git checkout -b feat/<short-desc>     # 命名:feat-/fix-/docs-/chore-/refactor-
```

### Step 2:改文件(只碰两个)

**新增 patch:**
```bash
$EDITOR versions/redis-7.0.15/patches/0005-fix-memory-leak.patch
# 在 versions/redis-7.0.15/version.yaml 的 patches[] 末尾追加条目
```

**改状态(pending → submitted):**
```yaml
- status: pending
+ status: submitted
+ upstream_pr:
+   - https://github.com/redis/redis/pull/12345
```

**加白名单(accepted → whitelisted):**
```yaml
- status: accepted
+ status: whitelisted
+ whitelist_reason: |
+   Kunpeng-specific DMA-to-engine HW feature; no upstream equivalent
+   interface; reviewed by twwang@boostkit on 2026-06.
```

### Step 3:本地校验(3 个工具必跑)

```bash
bash tools/verify.sh                       # 字段 + 一致性 + apply
python3 tools/sync-manifest.py --check     # drift(改完 yaml 必跑)
python3 tools/whitelist-audit.py --strict  # 白名单
```

期望输出:全部 `✓`,无 hard error。

### Step 4:commit + push

```bash
git add versions/<v>/version.yaml versions/<v>/patches/<name>.patch
git commit -m "feat(7.0.15): add 0005-fix-memory-leak patch"
git push -u origin feat/...
```

**不要 commit `PATCHES.yaml` / `WHITELIST.yaml` / `docs/PATCHES-STATUS.md`**——CI 会自动写并 auto-commit(`[skip ci]` 标记)。

### Step 5:开 PR + 等 CI

```bash
gh pr create --title "feat(7.0.15): add ..." --body-file .github/PULL_REQUEST_TEMPLATE.md
```

CI(`ci.yml`)会跑 5 阶段,期望全部绿:

```
✓ Sync manifest check       drift=false (或 CI 自动 commit 修复)
✓ Verify (schema + apply)   verify.sh 全过
✓ Whitelist audit            reason 字数合格
```

如 PR 改动了 `versions/<v>/patches/**`,还会自动触发 `build-perf.yml`,真实编译 + 跑 memtier_benchmark。

---

## 4. 5 个常见场景

### 场景 A:新增第 N 个 patch

见 §3 Step 2/3。文件名规范:`NNNN-{hw|perf|sec|compat|feature}-{kebab-topic}.patch`,NNNN version 内唯一,4 位补零。

### 场景 B:patch 状态变更

直接编辑 yaml,改 `status` 字段(必要时加 `upstream_pr` / `whitelist_reason`)。git commit message 即时间线。

### 场景 C:加白名单 / 续白名单

改 `status: whitelisted` + `whitelist_reason ≥30 字符`,CI 自动派生到 `WHITELIST.yaml`。

### 场景 D:上游发新版本(rebase)

当前**没有自动化 rebase 工具**——人工复制目录:

```bash
mkdir -p versions/redis-7.0.16/patches
cp versions/redis-7.0.15/version.yaml versions/redis-7.0.16/
cp versions/redis-7.0.15/patches/*.patch versions/redis-7.0.16/patches/
$EDITOR versions/redis-7.0.16/version.yaml
# 改:version_id / description / upstream_base.version / upstream_base.commit
```

### 场景 E:同步漂移(PATCHES.yaml 与 yaml 不一致)

`sync-manifest.py --check` 会报 drift。两修法:

- **手动**:`python3 tools/sync-manifest.py --write && git add ... && git commit -m 'manifest: auto-sync [skip ci]'`
- **CI 自动**:`ci.yml` 检测到 drift 会自动 commit + push(`permissions: contents: write` 已开)

---

## 5. 不要做的事(避免 PR 被拒)

1. ❌ **不要直接 push master** —— 必须开 PR
2. ❌ **不要手改 `PATCHES.yaml` / `WHITELIST.yaml` / `docs/PATCHES-STATUS.md`** —— CI 会覆盖,徒增 commit
3. ❌ **不要在 `patches[]` 中间插入** —— 永远在末尾追加(数组顺序 = apply 顺序)
4. ❌ **不要把 `.patch` 放仓根** —— 必须在 `versions/<v>/patches/`
5. ❌ **不要填 enum 之外的状态** —— `status` 仅 5 选 1,`type` 仅 2 选 1
6. ❌ **不要混改** —— 一个 PR 一个主题(新增 / 状态变更 / 白名单,分开)
7. ❌ **不要把 `whitelist_reason` 留空** —— status=whitelisted 时 ≥30 字符硬性要求
8. ❌ **不要写 `pr:` 单数字段** —— 是 `upstream_pr:` 数组

---

## 6. 失败排查速查

| 报错 | 修复 |
|---|---|
| `drift: WHITELIST.yaml` / `missing: docs/PATCHES-STATUS.md` | 跑 `sync-manifest.py --write` 或等 CI auto-fix |
| `patches[<i>].type='foo' not in {ecological, project}` | enum 填错,改对 |
| `patches[<i>].status='xxx' not in {pending, ...}` | enum 填错 |
| `status=submitted but upstream_pr[] empty` | 补 PR URL 列表 |
| `status=whitelisted but whitelist_reason <30 chars` | 写够 30 字符 |
| `apply 失败(单 patch)` | warning 不阻塞;owner 检查 baseline 漂移 / patch 是否需 rebase |
| `trailing whitespace` | `sed -i 's/[[:space:]]*$//' <patch>` |

---

## 7. 深入阅读

| 文档 | 用途 |
|---|---|
| `docs/MANIFEST-PROCESS.md` | sync-manifest 生成逻辑 / `out/patches-manifest.json` 协议 |
| `docs/WHITELIST-PROCESS.md` | 白名单字段语义 / 季度评审 |
| `docs/EXCEPTION-PROCESS.md` | `exception` 块机制(7 字段 / 90 天复审) |
| `docs/PATCHES-NAMING.md` | 文件名 `NNNN-{category}-{topic}` 规范 |
| `docs/build-perf.md` | `build-perf.yml` 链路 + 本地复现 |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR 必填 checklist |
| `BoostKit-Patch-Governance-Spec*.md` | 规范总—分架构(本仓根目录的 `D:\AI\github_cli\` 下) |

---

## 8. 完成清单

新人跑完本指南应能:

- [ ] 克隆仓 + 跑 `verify.sh` 看到绿
- [ ] 在 `version.yaml` 改一个 patch 的 status,跑 `sync-manifest.py --check` 看到绿
- [ ] 跑 `sync-manifest.py --write`,看 PATCHES.yaml / WHITELIST.yaml / docs/PATCHES-STATUS.md 自动更新
- [ ] 新增一个 patch 文件 + yaml 条目,本地全过
- [ ] 开 PR → CI 5 阶段全绿 → squash merge