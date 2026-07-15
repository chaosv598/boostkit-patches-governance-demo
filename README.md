# boostkit-patches-governance-demo

> BoostKit Redis patch overlay demo —— 演示 [`BoostKit-Patch-Governance-Spec`](https://github.com/chaosv598/BoostKit-Patch-Governance-Spec) 规范的端到端工作流

本仓是规范本身的**最小可运行示例**,包含:

- 2 个 Redis 版本 (`redis-6.0.20` / `redis-7.0.15`) 的 patch overlay
- 完整的 CI 流水线(sync-check → auto-fix → verify → lint → audit)
- 自动生成的 `PATCHES.yaml` / `WHITELIST.yaml` / `docs/PATCHES-STATUS.md`

---

## 📦 Patch 安装方式

> ⚠️ 本节与 master 当前状态强一致。CI 在每次 PR 时校验 `README.md` 中列出的 patch 必须真实存在于 `versions/*/patches/`,任何改动 README 也要同步修改。

### 快速开始(以 redis-7.0.15 为例)

```bash
# 1. 克隆本仓 + 上游 Redis
git clone https://github.com/chaosv598/boostkit-patches-governance-demo.git
git clone https://github.com/redis/redis.git
cd redis

# 2. 切到与 version.yaml upstream_base.commit 对齐的 commit
git checkout f35f36a265403c07b119830aa4bb3b7d71653ec9

# 3. 顺序 apply patch(顺序由 version.yaml 中 patches[] 数组顺序决定)
PATCH_DIR=../boostkit-patches-governance-demo/versions/redis-7.0.15/patches
for p in "$PATCH_DIR"/*.patch; do
  git apply --check "$p" || { echo "❌ FAIL: $p"; exit 1; }
  git apply "$p"
done

# 4. 编译 + 启动
make -j$(nproc) BUILD_TLS=no
./src/redis-server --port 6399    # PONG ✓
```

### redis-7.0.15 已交付 patch 清单

| 序号 | patch | status | 用途 |
|---|---|---|---|
| 0001 | [hw-kunpeng-adapt-iouring.patch](versions/redis-7.0.15/patches/0001-hw-kunpeng-adapt-iouring.patch) | submitted | Adapt io_uring for Kunpeng ARM |
| 0002 | [perf-kunpeng-adapt-dtoe.patch](versions/redis-7.0.15/patches/0002-perf-kunpeng-adapt-dtoe.patch) | whitelisted | Enable dtoe network optimization on Kunpeng(永久下游携带) |
| 0003 | [perf-jemalloc-arm64-pointer-tag-and-gc.patch](versions/redis-7.0.15/patches/0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch) | submitted | Adapt jemalloc ARM64 pointer-tag + GC |
| 0004 | [perf-rdb-fallback-aof.patch](versions/redis-7.0.15/patches/0004-perf-rdb-fallback-aof.patch) | submitted | AOF fallback when RDB load fails at startup |

### redis-6.0.20 已交付 patch 清单

| 序号 | patch | status | 用途 |
|---|---|---|---|
| 0001 | [hw-kunpeng-adapt-iouring-on-6.0.15-6.0.20.patch](versions/redis-6.0.20/patches/0001-hw-kunpeng-adapt-iouring-on-6.0.15-6.0.20.patch) | pending | Adapt io_uring for Kunpeng ARM(backport) |

> 完整状态仪表盘:[docs/PATCHES-STATUS.md](docs/PATCHES-STATUS.md)(自动生成)
> 白名单视图:[WHITELIST.yaml](WHITELIST.yaml)(自动生成)

---

## 🌿 分支与贡献

**`master` 是本仓唯一交付面**——所有 patch overlay 在 master 完整呈现。

| 分支类型 | 命名 | 用途 |
|---|---|---|
| `master` | — | 单一交付面,只接受 PR |
| `feature/<owner>-<topic>` | 例:`feature/twwang-add-iouring` | 业务自建开发分支 |
| `hotfix/<owner>-<topic>` | 例:`hotfix/dev-rdb-fallback` | 紧急修复 |
| `backport/<owner>-to-redis-<v>` | 例:`backport/twwang-to-redis-6.0.20` | 跨版本 backport |

### 业务开发流程

```
1. 从 master 拉 feature/<owner>-<topic> 分支
2. 编辑 versions/<v>/version.yaml + 添加 patches/*.patch
3. push → CI 自动跑(sync-check / verify / lint / audit)
4. CI green → 开 PR 到 master
5. review → squash merge → master 自动同步 PATCHES.yaml / WHITELIST.yaml / docs/PATCHES-STATUS.md
6. master CI 再跑一次,确认合入后无 drift
```

**业务分支不要求长期保留**,merge 后可删除。详细规范见 [§5 分支管理](https://github.com/chaosv598/BoostKit-Patch-Governance-Spec#5-分支管理)。

---

## 🛠️ 本地工具链

```bash
# 提交 PR 前必跑
python3 tools/sync-manifest.py --check    # PATCHES.yaml 与 version.yaml 一致性
bash tools/verify.sh                       # schema + upstream apply dry-run
bash tools/upstream-lint.sh versions/*/patches/*.patch   # 风格检查
python3 tools/whitelist-audit.py --strict  # 白名单审计

# 调试
python3 tools/sync-manifest.py --report    # 打印人读报表
python3 tools/sync-manifest.py --write     # 手动写回(不推荐,CI 自动)
```

---

## 📋 仓库结构

```
.
├── versions/                    ◀── 开发者手写入口
│   ├── redis-7.0.15/
│   │   ├── version.yaml
│   │   └── patches/*.patch
│   └── redis-6.0.20/
│       ├── version.yaml
│       └── patches/*.patch
├── PATCHES.yaml                 ◀── 自动生成:全量 patch 清单
├── WHITELIST.yaml               ◀── 自动生成:白名单 patch 视图
├── docs/PATCHES-STATUS.md       ◀── 自动生成:人读仪表盘
├── tools/
│   ├── sync-manifest.py         # version.yaml → 3 个自动产物
│   ├── verify.sh                # schema + upstream apply dry-run
│   ├── whitelist-audit.py       # 白名单审计
│   └── upstream-lint.sh         # patch 风格检查
└── .github/workflows/ci.yml     # CI:5 步流水线
```

---

## 🔗 相关链接

- **规范文档**:[BoostKit-Patch-Governance-Spec.md](https://github.com/chaosv598/BoostKit-Patch-Governance-Spec)
- **原始 master 仓**:[Redis-mvp-demo](https://github.com/chaosv598/Redis-mvp-demo) —— 真实业务仓
- **上游 Redis**:[redis/redis](https://github.com/redis/redis)

---

## 📄 许可证

见 [LICENSE.txt](LICENSE.txt)。
