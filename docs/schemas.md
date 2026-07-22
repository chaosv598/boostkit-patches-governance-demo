# Schema 权威定义 (v6.0)

## 目录结构

```
<repo>/
├── .github/
│   ├── lint.py                 # patch 头 + manifest 校验
│   └── workflows/ci.yml        # CI（3 步）
├── tools/
│   ├── apply_patch.sh          # Buildroot 风格 patch 应用器
│   └── verify.sh               # 一键验证
├── docs/
│   ├── schemas.md              # 本文档
│   ├── zh/                     # 产品文档：特性指南 + 版本说明书
│   └── en/
└── src/
    └── <Upstream-Version>/     # 例: Redis-7.0.15
        ├── manifest.yaml       # ★ 唯一配置文件
        ├── <feature>/          # feature = 含 .patch 的子目录
        │   └── *.patch         # DEP-3 邮件式头
        ├── deps/               # 构建依赖（可选）
        └── rpm_build/          # RPM 打包（可选）
```

## 1. Patch 邮件式头（DEP-3）

| 字段 | 类型 | 必填 | 语义 |
|------|------|:--:|------|
| `From` | `Name <email>` | 是 | 作者 |
| `Subject` | string | 是 | 标题 |
| `Description` | string ≥20 | 是 | 改了什么 + 为何改 |
| `Origin` | URL/string | 是 | 出处 |
| `Upstream-Status` | enum | 是 | Pending/Submitted/Accepted/Rejected/Backport/Inappropriate/Denied/Inactive-Upstream |
| `Applies-To` | string | 是 | 适用上游版本 |
| `Maintainer` | `Name <email>` | 是 | 维护人 |
| `Last-Update` | `YYYY-MM-DD` | 是 | 最后更新日期 |
| `Signed-off-by` | `Name <email>` | 是 | DCO 签名 |
| `Upstream-PR` | URL | 条件 | Submitted/Accepted/Backport 时必填 |
| `Upstream-Commit` | 40-char SHA | 条件 | Accepted/Backport 时必填 |
| `Whitelist-Reason` | string ≥30 | 条件 | Rejected/Inappropriate/Denied/Inactive-Upstream 时必填 |

## 2. manifest.yaml

一个文件 = 版本 pin + 可选 feature 关系 + 可选 install。YAML 字段给脚本，注释给人。

### 必填

| 字段 | 类型 | 语义 |
|------|------|------|
| `repo` | URL | 上游 git URL |
| `version` | string | upstream tag/version |
| `commit` | 40-char SHA | immutable pin |

### features（可选）

仅当 feature 间有依赖或冲突时才声明。文件系统可推导的信息不在此出现。

| 字段 | 类型 | 语义 |
|------|------|------|
| `features.<name>.depends` | list[str] | 依赖项，列表顺序 = apply 顺序，DFS 解析 |
| `features.<name>.conflicts` | list[str] | 互斥 feature，不能同时激活 |

```yaml
features:
  rdb-aof-fallback:
    depends: [kunpeng-hw-accel]    # C 依赖 A
    conflicts: []
  kunpeng-hw-accel:
    depends: []
    conflicts: [kbaio, native-aio] # 和 kbaio 互斥
```

### install（可选）

声明编译步骤，`apply_patch.sh` 在 apply 后自动执行。

| 字段 | 类型 | 语义 |
|------|------|------|
| `install.deps` | list[str] | build 依赖文件清单（相对版本目录） |
| `install.configure` | string | configure 命令 |
| `install.build` | string | build 命令 |

### 模板

```yaml
# 使用: bash tools/apply_patch.sh src/Redis-7.0.15 /tmp/build

repo: https://github.com/redis/redis
version: 7.0.15
commit: f35f36a265403c07b119830aa4bb3b7d71653ec9

features:
  rdb-aof-fallback:
    depends: [kunpeng-hw-accel]

install:
  build: make -j$(nproc) USE_KRAIO=1
  deps:
    - rpm_build/lib/libkraio.so
```

## 3. apply_patch.sh

```bash
# 全量
apply_patch.sh src/Redis-7.0.15 /tmp/build

# 子集
apply_patch.sh --features "rdb-aof-fallback" src/Redis-7.0.15 /tmp/build
apply_patch.sh --features "f1 f2" src/Redis-7.0.15 /tmp/build
```

repo/version/commit 从 manifest.yaml 自动读取，不需要传参。`--features` 不传则全量 apply。

## 4. 业界出处映射

| 维度 | v6.0 | 业界出处 |
|------|------|------|
| patch 发现 + 排序 | 目录遍历，文件名序 | **Buildroot** `apply-patches.sh` |
| 配置载体 | manifest.yaml（一个文件） | **Buildroot** `.mk` / **OpenWrt** `Makefile` / **RPM** `.spec` |
| 依赖解析 | depends DFS + 环检测 | **Linux Kconfig** `depends on`（scripts/kconfig/symbol.c） |
| 冲突检查 | conflicts 集合 | **Kconfig** `depends on !` / **Debian** `Conflicts:` |
| patch 头规范 | 6 必填 + 条件必填 | **DEP-3** (Debian) + **Yocto** Upstream-Status |
| feature 子集 | --features CLI | **OpenWrt** `CONFIG_FOO=y` + **Yocto** `DISTRO_FEATURES` |
| 编译验证 | install: configure/build | **Buildroot** `BUILD_CMDS` / **RPM** `%build` |
| 文档分层 | README → manifest → schemas → docs/zh/en | **Linux kernel** `Kconfig` + `Documentation/` |

## 5. 校验矩阵

| 校验项 | 命令 |
|--------|------|
| patch 头 6 必填 + 条件必填 | `python3 .github/lint.py headers src/*/` |
| manifest schema + depends + conflicts + DEP-3 | `python3 .github/lint.py manifest src/*/` |
| 结构 + clean apply | `bash tools/verify.sh` |
