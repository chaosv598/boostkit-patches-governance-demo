# 仓治理总纲 —— 设计原理

> **本文档**:讲清「为什么这样设计」;流程细节见 `DEVELOPER-GUIDE.md`。
> **配套**:规范总—分架构在仓外 `D:\AI\github_cli\BoostKit-Patch-Governance-Spec-v2.md`。

---

## 0. 30 秒速读

| 维度 | 取值 |
|---|---|
| 开发者契约 | `versions/<v>/version.yaml`(一版本一 yaml,patches 用数组) |
| 自动派生 | `PATCHES.yaml` / `WHITELIST.yaml` / `docs/PATCHES-STATUS.md`(sync-manifest 写,**禁手改**) |
| 本地工具 | `verify.sh` + `sync-manifest.py` + `whitelist-audit.py`(+ `build-perf.sh` 可选) |
| CI 工作流 | `ci.yml`(5 阶段门禁,含 drift auto-fix)+ `build-perf.yml`(改 patch 自动触发) |
| Patch 状态 | **5** 个:`pending` / `submitted` / `accepted` / `rejected` / `whitelisted` |
| Patch 分类 | `type=ecological`(推上游合入)/ `type=project`(本仓独享) |
| 单一交付面 | `master`(只接受 PR,禁直推) |

---

## 1. 核心原则

### 1.1 单一真相源

**开发者的唯一手写入口**:`versions/<v>/version.yaml` + `versions/<v>/patches/<name>.patch`。

其他所有产物(PATCHES.yaml / WHITELIST.yaml / docs/PATCHES-STATUS.md)**全部由 CI 派生**,开发者不动手改;改了也会被覆盖。

### 1.2 数组顺序 = apply 顺序

`patches[]` 数组的**顺序就是 git apply 的顺序**。`dependence` 字段只作文档提示,verify.sh 不做拓扑校验,依赖关系靠「数组中靠前」自然形成。

### 1.3 派生即真相(CI 自动修复)

`sync-manifest.py --check` 在 CI 跑;检测到 drift,自动跑 `--write` + 自动 commit + 自动 push(带 `[skip ci]`)。**开发者无需关心派生物的同步**。

### 1.4 master = 单一交付面

`master` 永远只通过 PR 进入;不接受直推。CI 5 阶段绿才允许 merge。

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
whitelisted(走 whitelist_reason ≥30 字符 描述永久保留理由)
```

| status | 含义 | 必填字段 |
|---|---|---|
| `pending` | patch 已加入但未发 PR | — |
| `submitted` | 已发上游 PR,等审核 | `upstream_pr[]` ≥1 |
| `accepted` | 上游已 merge / 本仓已落地 | `upstream_pr[]` ≥1(accepted ecological 时) |
| `rejected` | 上游明确拒绝 | `whitelist_reason`(填拒绝原因) |
| `whitelisted` | 永久携带,不再追求上游合入 | `whitelist_reason` ≥30 字符 |

详细字段说明见 `DEVELOPER-GUIDE.md §1` + `docs/PATCHES-NAMING.md` + `docs/WHITELIST-PROCESS.md`。

---

## 3. 工具矩阵

| 工具 | 类型 | 作用 | 何时跑 |
|---|---|---|---|
| `tools/verify.sh` | bash | 仓根禁放 + yaml 字段 + patches[] 一致 + upstream apply dry-run | 改完本地必跑 + CI 第 3 阶段 |
| `tools/sync-manifest.py` | python | version.yaml → PATCHES.yaml / WHITELIST.yaml / docs/PATCHES-STATUS.md(派生) | `--check` CI 第 1 阶段 / `--write` CI drift 时自动跑 |
| `tools/whitelist-audit.py` | python | 白名单 reason 字数 + 季度评审提醒 | `--strict` CI 第 5 阶段 + 季度手动跑 |
| `tools/build-perf.sh` | bash | 真实编译 + memtier_benchmark 性能基准 | 可选本地复现 + CI `build-perf.yml` |

**为什么 sync-manifest.py 是核心**:它是**把 yaml 契约「翻译」成机器视图(WHITELIST.yaml)和人视图(PATCHES-STATUS.md)的唯一通道**。没有它,YAML 改了视图不会自动跟。

---

## 4. CI 工作流

### 4.1 `ci.yml`(5 阶段门禁)

```
PR opened / push master
    ↓
[1] sync-manifest --check (drift 检测)
    ↓ drift? → 自动 [1.5] sync-manifest --write + commit + push [skip ci]
    ↓
[2] verify.sh (字段 + apply dry-run)
[3] verify.sh (仓根禁放)
[4] verify.sh (patches[] vs patches/ 一致)
[5] whitelist-audit --strict
    ↓ 全部绿
允许 merge
```

### 4.2 `build-perf.yml`(改 patch 自动触发)

由 `dorny/paths-filter` 检测 PR 是否改 `versions/<v>/**`;改了才触发,纯文档 PR 跳过。每个改动的 version 跑:clone upstream → apply patches → make → memtier_benchmark → 上传 artifact + Job Summary。

详见 `docs/build-perf.md` + `docs/ci-github-actions.md`。

### 4.3 失败策略

| 失败 | 行为 |
|---|---|
| ci.yml 任何阶段 fail | **block merge**(reject PR) |
| build-perf:build fail | block merge(说明 patch 让 upstream 编不过) |
| build-perf:bench fail | **warn 不 block**(性能波动,reviewer 决定) |
| sync-manifest drift | **auto-fix**(自动 commit 修复并 push) |

---

## 5. 为什么是这套设计(取舍)

### 5.1 为什么一版本一 yaml 而不是一 patch 一 yaml

- 一 patch 一 yaml → N×版本数量 yaml 文件,每次 rebase 要同步 N 份
- 一版本一 yaml → `cp -r versions/<v_old> versions/<v_new>` 一条命令搞定 rebase
- 配合「数组顺序 = apply 顺序」,无需单独的 series/sequence 文件

### 5.2 为什么 5 状态而不是 3 状态

- `rejected` 区分「上游拒绝」(有原因)和「pending 没发」(没原因),审计友好
- `whitelisted` 是 BoostKit 真实业务需求——KRAIO / DTOE 等鲲鹏专属特性**不追求上游合入**,需要一个明确的永久携带状态
- 3 状态强行把 rejected 折回 pending,丢失了审计信号

### 5.3 为什么 sync-manifest 自动写 PATCHES.yaml 而不是让开发者手填

- 「开发者手填派生视图」 = 双写 = 必然漂移 = 必然 CI 报错 = 必然吵
- 「CI 自动派生 + drift 时 auto-commit」 = 开发者零额外负担 = 视图永远一致
- 代价:CI 需要 `permissions: contents: write` 和一个 bot 身份(已配 `boostkit-bot`)

### 5.4 为什么 build-perf 用 paths-filter 而不是全跑

- 纯文档 PR 不应该浪费 2min 编译时间
- paths-filter 检测 `versions/<v>/**` 改动 → 只跑改动的版本,其他跳过
- 矩阵自动:改 2 个 version → 2 个并行 job;改 0 个 version → 0 个 job

---

## 6. 与历代版本的对比

| 时间 | 工具数 | 状态机 | 元数据粒度 | CI job |
|---|---|---|---|---|
| 治理前 | 0 | 无 | 无 | 无 |
| v5 MVP 初版 | 14 | 7 | 一 patch 一 yaml | 7 |
| simplify-v1 | 6 | 5 | 一 patch 一 yaml | 1 |
| simplify-v2 | 4 | 5 | 一 patch 一 yaml | 1 |
| simplify-v3 | 1 | 3 | 一版本一 yaml | 1 |
| **当前(v2 spec 落地版)** | **5** | **5** | **一版本一 yaml** | **ci.yml 5 阶段 + build-perf.yml** |

> 简化过程快照(`1 工具 + 3 状态 + 1 CI job`)见 `docs/_archive/simplify-v3/`,仅作历史参考。

---

## 7. 相关文档

| 文档 | 用途 |
|---|---|
| `docs/DEVELOPER-GUIDE.md` | **开发者上手手册**(流程、字段、PR 全流程) |
| `docs/MANIFEST-PROCESS.md` | sync-manifest 详细协议 |
| `docs/WHITELIST-PROCESS.md` | 白名单字段语义 + 季度评审 |
| `docs/EXCEPTION-PROCESS.md` | `exception` 块机制 |
| `docs/PATCHES-NAMING.md` | 文件名规范 |
| `docs/build-perf.md` | build-perf 链路 |
| `docs/_archive/simplify-v3/` | 历代简化版快照(历史参考,不维护) |
| `CLAUDE.md` | 给 AI 助手的仓背景 |