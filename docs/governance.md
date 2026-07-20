# Patch Overlay 治理设计

## 1. 模型概述

本仓治理"在固定上游基线上叠加 N 个 patch"的问题,采用业界最广泛采用的
**version-centric + 显式 `patches/series`** 模型:

```
<upstream-id>/
├── upstream.yaml              # 上游基线(repo / version / commit)
└── patches/
    ├── series                 # ★ 唯一权威顺序(自上而下应用)
    └── *.patch                # patch 文件(RFC822 邮件式头 + diff)
```

**核心原则**:

- **唯一权威顺序** = `patches/series`,改顺序只动 1 行
- **filename `0001-` 仅辅助阅读** — 可重命名,不影响顺序
- **patch 元数据物理上紧贴 patch** — 在 patch 文件的邮件式头里
- **`upstream.yaml` 只剩上游基线 + 治理归属** — 易审阅,无冗余
- **不引入 DAG** — 默认线性足够,业界共识

完整字段定义见 [version-yaml-spec.md](./version-yaml-spec.md)。

## 2. 业界出处

本设计综合以下成熟方案的最大公约数。

### 2.1 Quilt / Debian `debian/patches/series`

**出处**: https://salsa.debian.org/kernel-team/linux/-/tree/master/debian/patches

Debian kernel 团队维护上千个 patch,采用:

```text
debian/patches/
├── series
├── bugfix/
├── debian/
└── features/
```

`series` 每行一个 patch 路径,自上而下应用。**文件名仅辅助阅读,顺序由 `series` 权威表达**。
这与本仓 `patches/series` 模型完全一致。

### 2.2 SUSE kernel-source `series.conf` + `Git-commit`

**出处**: https://github.com/openSUSE/kernel-source/blob/master/series.conf

SUSE 把 patch 顺序、上游 commit 引用、guards 条件化放在 `series.conf`:

```text
Patch-mainline: v6.5-rc7
Git-commit: 02c6c24402bf1c1e986899c14ba22a10b510916b
References: CVE-2023-4563 bsc#1214727
Signed-off-by: ...
```

**对齐点**:本仓 patch 头的 `Upstream-Commit:` + `Upstream-Status:` 字段语义
直接对应 SUSE `Git-commit:` + `Patch-mainline:`。

**未对齐点**:本仓 v2.0 **暂不引入 `guards` 机制**——如果未来需要按产品/架构条件化
应用,可在 `patches/series` 之上加 wrapper 工具,参考 `scripts/sequence-patch`。

### 2.3 Yocto/OpenEmbedded `Upstream-Status` 字段

**出处**: https://docs.yoctoproject.org/dev/contributor-guide/recipe-style-guide.html

Yocto 对每个 `.patch` 强制要求 `Upstream-Status:` 头,枚举值:

```text
Upstream-Status: Pending
Upstream-Status: Submitted [mailing-list-or-URL]
Upstream-Status: Backport [upstream commit URL]
Upstream-Status: Denied [reason]
Upstream-Status: Inactive-Upstream [lastcommit: ...]
Upstream-Status: Inappropriate [oe specific]
```

**对齐点**:本仓 `Upstream-Status` **8 个枚举值直接对齐 Yocto 命名**,
包括 `Pending / Submitted / Accepted / Rejected / Backport / Inappropriate /
Denied / Inactive-Upstream`(仅把 Yocto 的 `[mailing-list-or-URL]` 拆为
单独的 `Upstream-PR:` 字段,更结构化)。

### 2.4 ungoogled-chromium `chromium_version.txt` + `patches/series`

**出处**: https://github.com/Eloston/ungoogled-chromium/blob/master/patches/series

ungoogled-chromium 用极简模型:

```text
chromium_version.txt    # 单行 upstream 版本 pin
patches/series          # patch 应用顺序
```

**对齐点**:本仓 `upstream.yaml` 等价于 `chromium_version.txt` 的扩展版本
(多了 `repo` URL + 40-char SHA pin + 治理 owner)。

### 2.5 openEuler `src-openeuler/*` apply-patches

**出处**: https://atomgit.com/src-openeuler/kernel

openEuler 的内核和 redis 包使用:

```text
kernel/
├── kernel.spec
├── patches.addon/
│   └── series
└── apply-patches   # 脚本:接收 series.conf + patchdir + guards
```

小型 RPM 包则用 `Patch0001:` 编号声明在 `.spec` 里,`%autopatch -p1` 应用。

**对齐点**:本仓 v2.0 不引入 RPM spec 表达,改用 `patches/series` 作为唯一
权威顺序;`apply-patches` 的"guards 条件化"功能作为未来扩展选项保留。

## 3. 工作流

### 3.1 `ci.yml`(PR / push master 时触发)

4 步顺序:

| 步骤 | 工具 | 职责 |
|---|---|---|
| 1 | `bash tools/verify.sh` | 仓根禁放 + upstream.yaml schema + clean clone + 按 series apply |
| 2 | `python3 .github/lint_patch_headers.py` | patch 邮件式头 schema + 条件必填字段 |
| 3 | `python3 .github/lint_series.py` | series 一致性(无孤儿 + 无重复 + 所有 entry 存在) |
| 4 | (可选,后续扩展) upstream-test reminder | 不阻塞,仅 Step Summary 提示 |

### 3.2 `build-perf.yml`(PR 时触发,需 ci.yml 全绿)

paths-filter 检测 `versions/*/patches/` 改动 → 矩阵生成 → build patched redis → memtier_benchmark。

**本地复跑**(给开发者):

```bash
# 1. clean clone upstream + 按 series apply + make
git clone --depth=1 https://github.com/redis/redis /tmp/r
cd /tmp/r
git fetch origin f35f36a265403c07b119830aa4bb3b7d71653ec9
git checkout f35f36a265403c07b119830aa4bb3b7d71653ec9
while read p; do
  [ -z "$p" ] && continue
  [[ "$p" == \#* ]] && continue
  git apply "$OLDPWD/versions/redis-7.0.15/patches/$p"
done < "$OLDPWD/versions/redis-7.0.15/patches/series"

# 2. build + bench
make distclean
make -j$(nproc) USE_KRAIO=0
src/redis-server --port 6399 --daemonize yes --dbfilename dump.rdb \
                  --save '' --appendonly no --maxmemory 256mb \
                  --logfile /tmp/redis.log
src/redis-benchmark -p 6399 -c 200 -d 3 -n 10000000 -r 10000000 \
                     -t set,get --threads 20 -q
```

## 4. 常见操作

### 4.1 新增 patch

```bash
# 1. 在 versions/<upstream-id>/patches/ 加 .patch 文件
cp my-new.patch versions/redis-7.0.15/patches/0005-my-new.patch

# 2. 编辑邮件式头,至少填:
#    From / Date / Subject / Upstream-Status / Signed-off-by
#    (其余字段按 Upstream-Status 状态条件必填)

# 3. 在 versions/redis-7.0.15/patches/series 末尾追加一行
echo "0005-my-new.patch" >> versions/redis-7.0.15/patches/series

# 4. 本地验证
bash tools/verify.sh
python3 .github/lint_patch_headers.py versions/redis-7.0.15/patches/*.patch
python3 .github/lint_series.py versions/redis-7.0.15/patches/

# 5. 提交 PR(只接受 PR,不接受直推 master)
```

### 4.2 改 patch 状态(例如 Submitted → Accepted)

编辑 `*.patch` 邮件式头:

```diff
-Upstream-Status: Submitted
-Upstream-PR: https://github.com/redis/redis/pull/12345
+Upstream-Status: Accepted
+Upstream-PR: https://github.com/redis/redis/pull/12345
+Upstream-Commit: deadbeef1234567890abcdef1234567890abcdef
```

无需改 `series` 或 `upstream.yaml`。

### 4.3 改上游版本(升级 redis 7.0.15 → 7.0.16)

**推荐:新建版本目录,不删除旧版**:

```bash
cp -r versions/redis-7.0.15 versions/redis-7.0.16
# 编辑 versions/redis-7.0.16/upstream.yaml:
#   version: 7.0.16
#   commit: <7.0.16 的 40-char SHA>
# 然后逐 patch verify.sh apply,失败的 patch 需要 rebase 或删除
```

**废弃旧版本**:删除整个 `versions/redis-7.0.15/` 目录即可。`series` 不必改
因为 `series` 在版本目录内。

### 4.4 废弃 patch(不再需要)

两条路:

- **暂时废弃**:从 `series` 删除一行(保留 `.patch` 文件,后续可恢复)
- **永久废弃**:从 `series` 删除 + 删除 `.patch` 文件

### 4.5 添加 patch 间的非相邻依赖

编辑 `*.patch` 邮件式头:

```text
Depends-on: 0002-perf-kunpeng-adapt-dtoe.patch
```

(本仓 v2.0 仅做提示性检查,不强制 DAG 排序;SUSE 风格留待未来扩展。)

## 5. FAQ

### Q1: 为什么不用 `version.yaml patches[]` 数组顺序?

数组顺序与元数据合并在一处,改顺序时要动 yaml 大块,且与 filename 编号
形成"两份权威"风险(谁对谁错?).`series` 文件则**唯一权威**,filename
可任意重命名。

### Q2: 为什么 `Upstream-Status` 不是 5 状态而是 8 状态?

Yocto 8 状态语义更精确:`Inappropriate` / `Denied` / `Inactive-Upstream`
分别表达"项目独有"、"上游明确拒收"、"上游不活跃",对应不同的治理动作
(白名单复审、rebase 准备、退役)。旧 5 状态的 `whitelisted` 掩盖了
这三种语义差异。

### Q3: 为什么 patch 元数据不放 sidecar YAML?

业界共识是 **patch 元数据物理上紧贴 patch 内容**(邮件式头)。这样:

- patch 可单独 `git send-email` / `git am` / `git format-patch | git am`
- 重新生成 patch 时元数据跟随,不会漂移
- 阅读 patch 即可看到全部上下文,无需对照 sidecar

SUSE / Yocto / Debian DEP-3 全用这种模式。

### Q4: 为什么 `upstream.yaml` 还要有 `meta.owner`?

`meta.owner` 表达"该 upstream 由谁维护",方便责任追溯。
patch 自己的 `Signed-off-by` 表达"patch 作者",两者职责不同。

### Q5: 未来要支持 guards(条件应用)怎么做?

参考 SUSE `scripts/sequence-patch`:

```bash
# 1. 引入 tools/apply-series.sh,接收 series + guards
bash tools/apply-series.sh versions/redis-7.0.15/patches/series \
    --guard-with-kunpeng

# 2. 在 series 行尾支持条件注释:
0005-kunpeng-only.patch    # guard: kunpeng
```

`guard:` 后跟 guard 名,apply 时按环境变量筛选。这是 v2.x 扩展项,不在 v2.0 范围。