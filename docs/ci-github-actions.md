# CI —— GitHub Actions 配置

> **本文档**:`ci.yml` 5 阶段 + `build-perf.yml` 改 patch 自动触发。
> **配套脚本**:`tools/verify.sh` / `tools/sync-manifest.py` / `tools/whitelist-audit.py` / `tools/build-perf.sh`。
> **设计原理**:`docs/GOVERNANCE.md §4`。
> **历史版本**:`docs/_archive/simplify-v3/ci-github-actions.md`(1 job 时代,已弃用)。

---

## 0. 30 秒速读

| 维度 | 取值 |
|---|---|
| 工作流 | 2 个:`ci.yml`(必跑)+ `build-perf.yml`(改 patch 才跑) |
| ci.yml 阶段 | **5**:`sync-check` / `auto-fix drift` / `verify` / `whitelist-audit` |
| build-perf 触发 | `dorny/paths-filter` 检测 `versions/<v>/**` 改动 |
| 触发器 | `push master` / `pull_request` / `workflow_dispatch` |
| 并发控制 | `cancel-in-progress: true`(同 PR 新 push 取消旧 run) |
| 时长 | ci.yml ~30s(本地 ~5s);build-perf 首次 ~2.5min,带 cache ~1.8min |

---

## 1. `ci.yml` —— 5 阶段门禁

### 1.1 工作流文件

```yaml
name: ci
on:
  pull_request: { branches: [master] }
  push:         { branches: [master] }
  workflow_dispatch:
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
permissions:
  contents: write   # sync-manifest auto-fix 需要
jobs:
  verify:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0, token: ${{ secrets.GITHUB_TOKEN }} }
      - run: pip install pyyaml --quiet

      # 1. sync-manifest drift 检测
      - id: sync-check
        run: |
          set +e
          python3 tools/sync-manifest.py --check; rc=$?
          set -e
          if [ "$rc" = "0" ]; then
            echo "drift=false" >> "$GITHUB_OUTPUT"
            echo "fix_needed=false" >> "$GITHUB_OUTPUT"
          else
            echo "drift=true" >> "$GITHUB_OUTPUT"
            echo "fix_needed=true" >> "$GITHUB_OUTPUT"
          fi

      # 1.5 drift 自动修复 + push
      - if: steps.sync-check.outputs.fix_needed == 'true'
        run: |
          python3 tools/sync-manifest.py --write
          git config user.name "boostkit-bot"
          git config user.email "boostkit-bot@boostkit"
          git add PATCHES.yaml WHITELIST.yaml docs/PATCHES-STATUS.md
          git diff --cached --quiet || \
            git commit -m "manifest: auto-sync from version.yaml [skip ci]" && git push

      # 2-4. verify.sh 4 阶段(仓根禁放 + 字段 + 一致性 + apply dry-run)
      - run: bash tools/verify.sh

      # 5. whitelist audit
      - run: python3 tools/whitelist-audit.py --strict
```

### 1.2 5 阶段流程图

```
PR opened / push master
    ↓
[1] sync-manifest --check
    ↓
drift=true? ──── 是 ──▶ [1.5] --write + commit + push [skip ci]
    │                          ↓
    │                       自动回到 PR 流程
    ↓ 否
[2-4] verify.sh (仓根禁放 / yaml 字段 / patches[] 一致性 / upstream apply dry-run)
    ↓
[5] whitelist-audit --strict (reason 字数 + 季度评审)
    ↓ 全部绿
✅ 允许 merge
```

### 1.3 失败策略

| 阶段失败 | 行为 |
|---|---|
| [1] drift | 自动修复 + push,**不 block** |
| [2-4] verify.sh 任一硬错 | **block merge** |
| [5] whitelist-audit | **block merge**(reason <30 字符) |
| verify.sh 单 patch apply 失败 | **warn 不 block**(owner 检查 baseline) |

---

## 2. `build-perf.yml` —— 改 patch 自动触发

### 2.1 触发逻辑

```
PR opened
    ↓
[Job: changes] dorny/paths-filter 检测 PR diff
    ↓
命中 versions/<v>/**  →  启动 build-perf job (matrix: 每个改动 version 一个)
未命中                 →  跳过(纯文档 PR 节省 ~2min CI)
```

### 2.2 matrix

```yaml
filters: |
  redis_7_0_15:
    - 'versions/redis-7.0.15/**'
  redis_6_0_20:
    - 'versions/redis-6.0.20/**'
```

> filter key 不能含点号(GHA 表达式把 `.` 当属性访问符),所以用下划线。

### 2.3 build-perf job 步骤

```
1. 装依赖 build-essential + tcl-dev + libssl-dev + libevent-dev + liburing-dev + libconfig++-dev (~15s)
2. 编 memtier_benchmark 2.1.0 从源码(~30s)
3. cache key = upstream-<v>-<yaml-hash>,复用 clone
4. tools/build-perf.sh build <v>
   → clone upstream @ upstream_base.commit
   → 按 patches[] 顺序 git apply
   → make -j$(nproc) BUILD_TLS=no (~60s)
5. tools/build-perf.sh bench <v>
   → 启 redis-server :6399
   → memtier_benchmark --threads=2 --clients=10 --test-time=30s
   → shutdown + 解析输出 → artifacts/<v>/summary.md
6. upload-artifact: memtier.log + summary.md (保留 30 天)
7. 写 markdown → GitHub Job Summary
```

### 2.4 失败策略

| 失败 | 行为 |
|---|---|
| `build` 阶段失败 | **block merge**(patch 让 upstream 编不过) |
| `bench` 数据异常 | **warn 不 block**(性能波动,reviewer 决定) |
| paths-filter 跳过 | 不跑(节省 CI) |

详见 `docs/build-perf.md`。

---

## 3. 与 verify workflow 的关系

| 维度 | ci.yml (verify) | build-perf.yml |
|---|---|---|
| 跑的内容 | dry-run `git apply --check` | 真的 `make` + 启 redis + 跑 memtier |
| 时长 | ~30s(CI) | ~2-3min |
| 触发 | 所有 PR + push master | 仅改 patch 的 PR |
| 失败 | 5 阶段任一 fail 即 block | build fail block;bench warn 不 block |
| 报告 | pass/fail | markdown + memtier log artifact |

**判断标准**:
- 普通 patch 改动 → verify 够用(默认 PR 触发)
- 性能敏感改动 / patch 兼容性验证 → build-perf 必跑(改动 patch 自动触发)
- 想跑 baseline 对比 → workflow_dispatch 手动触发任意 version

---

## 4. 权限 / 限制

- **Public 仓库**:完全免费,无分钟数限制
- **Private 仓库**:GitHub Free tier 2000 分钟/月
- 不需要任何 GitHub Secrets 即可跑通(verify.sh 走匿名 clone upstream)
- `ci.yml` 用了 `secrets.GITHUB_TOKEN` 是为了让 auto-fix drift 时能 push;**不开 contents: write 就跑不了 auto-fix**
- 如未来要加私有 upstream,需额外 `GH_TOKEN` + 私有 actions/checkout token

---

## 5. 失败排查

| 报错 | 修复 |
|---|---|
| `drift: WHITELIST.yaml` | 跑 `sync-manifest.py --write` 或等 CI auto-fix |
| `missing: docs/PATCHES-STATUS.md` | 同上 |
| `patches[<i>].type='foo' not in ...` | enum 填错 |
| `patches[<i>].status='xxx' not in ...` | enum 填错 |
| `status=submitted but upstream_pr[] empty` | 补 PR URL 列表 |
| `status=whitelisted but whitelist_reason <30 chars` | 写够 30 字符 |
| `apply 失败(单 patch)` | warning 不阻塞;owner 检查 baseline 漂移 |
| `trailing whitespace` | `sed -i 's/[[:space:]]*$//' <patch>` |
| `unexpected symbol: 0.15` (paths-filter) | filter key 不要含 `.` |
| memtier 慢 / 0 ops | 看 `artifacts/<v>/redis.log`,端口 :6399 可能被占 |

---

## 6. 历史

| 阶段 | 工作流 | 阶段数 | 触发 |
|---|---|---|---|
| 治理前 | 无 | 0 | — |
| simplify-v3(已弃用) | ci.yml | 1 个 job:`verify` | push/PR |
| **当前** | ci.yml + build-perf.yml | **ci 5 阶段** + build-perf 2 job | push/PR + paths-filter |

> simplify-v3 的 `ci-github-actions.md` 见 `docs/_archive/simplify-v3/`,仅作历史参考。