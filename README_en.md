# Redis Network Optimization Features

## Project Brand Name

Kunpeng BoostKit Redis

## Introduction

Kunpeng BoostKit Redis is a **patch overlay** on top of upstream Redis. The repository
pins a fixed upstream version and layers BoostKit-maintained ARM/Kunpeng optimization
patches on top.

**Core model**: version-centric + feature declaration. Combined from 5 industry-proven
schemes — **Yocto/OpenEmbedded** recipe fields + `Upstream-Status`, **DEP-3** patch header
schema, **Buildroot** `apply-patches.sh`, **OpenWrt** `package/<name>/Config.in` +
`Makefile` feature declaration (v5.0 primary), **Linux kernel** `Kconfig` `depends` /
`select` / `default` semantics.

**v5.0 key upgrade**: `patches/features.yaml` (OpenWrt Config.in style) replaces v4.0's
`series.<profile>`; customers pick feature combos via `ACTIVE_FEATURES`. Compose logic
is **integrated into `apply_patch.sh` internally** (no new script).

See [docs/governance.md §2](./docs/governance.md#2-industry-references).

## Repository Layout

```text
boostkit-patches-governance-demo/
├── README.md / README_en.md            # This file
├── LICENSE.txt                          # Upstream license (full text)
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── lint_patch_headers.py            # DEP-3 6 required fields validator
│   ├── lint_series.py                   # v5.0: lints features.yaml (schema + depends + DEP-3 required)
│   └── workflows/
│       ├── ci.yml                       # 3 steps: verify + patch header lint + features lint
│       └── build-perf.yml               # skeleton workflow (matrix: clean apply + echo steps)
├── tools/
│   ├── verify.sh                        # root hygiene + upstream.yaml schema (delegates apply --features)
│   └── apply_patch.sh                   # ★ Buildroot-style series applier + v5.0 --features mode (inline compose)
├── docs/
│   ├── governance.md                    # ★ Design rationale + 5 industry references
│   ├── version-yaml-spec.md             # ★ Authoritative field definitions
│   └── (product guides zh/en retained)
└── versions/
    └── <upstream-id>/                   # e.g. redis-7.0.15
        ├── upstream.yaml                # Yocto recipe fields + upstream pin + governance
        └── patches/
            ├── features.yaml            # ★ Feature declaration (OpenWrt Config.in style, single source)
            └── features/<feature>/      # one feature per directory
                └── *.patch              # DEP-3 mail-style header (6 required) + diff
```

## Quick Start

### 1. Upstream pin + patch order at a glance

`versions/redis-7.0.15/upstream.yaml` (Yocto recipe fields + upstream pin):

```yaml
SUMMARY: "Redis in-memory data structure store with Kunpeng ARM optimizations"
DESCRIPTION: |
  Redis is an open source, in-memory data structure store used as a database,
  cache, message broker, and streaming engine. BoostKit overlay.
HOMEPAGE: "https://redis.io"
LICENSE: "BSD-3-Clause"
LIC_FILES_CHKSUM: "file://COPYING;md5=508cbf69e54be9b31b53b42e7411f8c4"
SECTION: "network/database"

upstream:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9

meta:
  owner: twwang@boostkit
  maintainer: twwang@boostkit
  last_review: 2026-07-20
  lifecycle: active
```

`versions/redis-7.0.15/patches/features.yaml` (OpenWrt Config.in style, single source):

```yaml
# Industry reference: OpenWrt package/<name>/Config.in + Kconfig depends + Yocto conditional SRC_URI
features:
  kunpeng-hw-accel:
    title: "Kunpeng ARM HW acceleration (io_uring adapt + DTOE DMA network path)"
    patches:
      - 0001-hw-kunpeng-adapt-iouring.patch
      - 0002-perf-kunpeng-adapt-dtoe.patch
    depends: []
    default: true                                # enabled by default
    # Yocto/OE 8-state full set (stable shape for dashboard; value = patch count in this feature)
    upstream_status_summary:
      Pending: 0
      Submitted: 1
      Accepted: 0
      Rejected: 0
      Backport: 0
      Denied: 0
      Inappropriate: 1
      Inactive-Upstream: 0
  jemalloc-arm64:
    title: "jemalloc ARM64 pointer-tag + GC decay strategy"
    patches:
      - 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
    depends: []
    default: false                               # not enabled by default
    upstream_status_summary:
      Pending: 0
      Submitted: 1
      Accepted: 0
      Rejected: 0
      Backport: 0
      Denied: 0
      Inappropriate: 0
      Inactive-Upstream: 0
  rdb-aof-fallback:
    title: "AOF fallback when RDB corrupted"
    patches:
      - 0001-perf-rdb-fallback-aof.patch
    depends: []
    default: true
    upstream_status_summary:
      Pending: 0
      Submitted: 1
      Accepted: 0
      Rejected: 0
      Backport: 0
      Denied: 0
      Inappropriate: 0
      Inactive-Upstream: 0
```

Physical patches are organized by feature:

```text
versions/redis-7.0.15/patches/features/
├── kunpeng-hw-accel/
│   ├── 0001-hw-kunpeng-adapt-iouring.patch
│   └── 0002-perf-kunpeng-adapt-dtoe.patch
├── jemalloc-arm64/
│   └── 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
└── rdb-aof-fallback/
    └── 0001-perf-rdb-fallback-aof.patch
```

### 2. Local validation

```bash
# 1. Root hygiene + upstream.yaml schema + clean clone + apply features.yaml
#    (delegates to tools/apply_patch.sh --features internally)
bash tools/verify.sh

# 2. DEP-3 patch header schema (6 required: Description/Origin/Upstream-Status/Applies-To/Maintainer/Last-Update)
python3 .github/lint_patch_headers.py versions/*/patches/

# 3. features.yaml schema + depends resolution + DEP-3 required fields
python3 .github/lint_series.py versions/*/patches/
```

### 2.5 Feature combos (subsets on the same upstream)

Pick a feature subset via `ACTIVE_FEATURES` (env var) or `--active` (CLI flag):

```bash
# Default combo = union of features.yaml `default:true` (here: kunpeng-hw-accel + rdb-aof-fallback)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build

# Customer A: reliability-only (just rdb-aof-fallback)
ACTIVE_FEATURES="rdb-aof-fallback" bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build-a

# Customer B: full bundle (also enables default-off jemalloc-arm64)
ACTIVE_FEATURES="kunpeng-hw-accel jemalloc-arm64 rdb-aof-fallback" bash tools/apply_patch.sh ... --features ... /tmp/build-b

# Equivalent --active flag (better for CI / tests)
bash tools/apply_patch.sh ... --features ... --active "jemalloc-arm64 rdb-aof-fallback" /tmp/build-c
```

The `depends` field makes features auto-include their dependencies (e.g. if `rdb-aof-fallback.depends=[kunpeng-hw-accel]`,
activating C automatically applies A first).

See [docs/version-yaml-spec.md §3](./docs/version-yaml-spec.md#3-patchesfeaturesyamlopenwrt-configin-style--v50-single-source).

### 2.6 Standalone feature apply (Buildroot-style)

```bash
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build
```

### 3. Build on Kunpeng

```bash
# 1) clean clone + apply default features (Buildroot-style single source)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build

# 2) build (requires BoostKit KRAIO kernel module)
cd /tmp/build/upstream
make distclean && make -j$(nproc) -DHAVE_KRAIO
```

## Compatibility

| Dimension | Supported |
|---|---|
| OS | openEuler 22.03 LTS SP4 / 24.03 LTS |
| Redis | 6.0.20 / 7.0.15 (see `versions/`) |
| Architecture | aarch64 (Kunpeng) |
| Kernel | kernel-side KRAIO SDK RPM |

## References

- **Design + industry alignment**: [docs/governance.md](./docs/governance.md)
- **Field definitions**: [docs/version-yaml-spec.md](./docs/version-yaml-spec.md)
- **Tooling → industry reference mapping**: [docs/governance.md §2.7](./docs/governance.md#27-tools-工具脚本--业界出处对照表)
- **Industry alignment quick reference (schema + tooling)**: [docs/version-yaml-spec.md §7](./docs/version-yaml-spec.md#7-与业界对齐速查)
- **Operations (add/retire patch)**: [docs/governance.md §4](./docs/governance.md#4-common-operations)

Industry references (5-way, simplified to pure 5 since v5.1):
- **Yocto/OpenEmbedded** — recipe fields (SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION) +
  `Upstream-Status` 8-state semantics
- **DEP-3** (Debian) — patch header schema with 6 required fields
- **Buildroot** `apply-patches.sh` — series applier single source
- **OpenWrt** `package/<name>/Config.in` + `Makefile` — feature declaration + conditional `PATCHFILES` (v5.0 primary)
- **Linux kernel** `Kconfig` — `depends` / `select` / `default` semantics (depth-first resolution + cycle detection)

**v5.0 key upgrade**: `patches/features.yaml` (OpenWrt Config.in style) replaces v4.0's
`series.<profile>`; customers pick feature combos via `ACTIVE_FEATURES`. Compose logic
is **integrated into `apply_patch.sh` internally** (no new script).

**v5.1 simplification**: removed `tools/gen_inventory.py` + `inventory.json` derived
pipeline (gitignored + CI `--check` is a tautology, low value). `tools/` reduced to 2
scripts; CI to 3 steps; `.gitignore` loses the inventory.json entry. Industry references
simplified to pure 5 (Yocto / DEP-3 / Buildroot / OpenWrt / Kconfig).

## Contributing

PR-only workflow. No direct pushes to master.

1. Add patch → place under `patches/features/<feature>/` + write DEP-3 header (6 required) +
   add entry to `features.yaml`
2. Run all 3 local tools, all green
3. Open PR → triggers `ci.yml` 3 steps + `build-perf.yml` matrix (skeleton)
4. Maintainer review → merge

## License

- This overlay: Apache 2.0 (see [LICENSE.txt](./LICENSE.txt))
- Upstream Redis: BSD-3-Clause (preserved in each patch header)
- Product docs: CC-BY 4.0 (see [docs/LICENSE](./docs/LICENSE))

## Change Log

- **2026-07-21** v5.3: `upstream_status_summary` aligned to the full Yocto/OpenEmbedded
  **8-state set** (Pending / Submitted / Accepted / Rejected / Backport / Denied /
  Inappropriate / Inactive-Upstream) for a stable dashboard shape (all 8 keys present,
  unused entries 0). `lint_series.py` now enforces schema: keys must be from this 8-state
  enum, values must be non-negative integers (invalid keys are reported with the legal
  list). **`depends` field wired end-to-end**: `apply_patch.sh` python inline does DFS
  resolution + hard-fail on cycles, `lint_series.py` validates reference existence +
  no-cycle; `ACTIVE_FEATURES=C` where `C.depends=[B]` and `B.depends=[A]` applies in
  order A → B → C.
- **2026-07-21** v5.2: feature dirs renamed from abstract letters
  (`feature-A` / `feature-B` / `feature-C`) to descriptive kebab-case names
  (`kunpeng-hw-accel` / `jemalloc-arm64` / `rdb-aof-fallback`) per industry
  naming conventions (OpenWrt `package/network/services/dnsmasq/`, Buildroot
  `package/redis/`, Yocto `recipes-core/redis/`). `features.yaml` keys + all
  docs + `apply_patch.sh` usage example aligned.
- **2026-07-21** v5.1: remove `tools/gen_inventory.py` + `inventory.json` derived
  pipeline (user feedback: gitignored + CI `--check` is a tautology, low value).
  `tools/` reduced to 2 scripts; CI to 3 steps; `.gitignore` loses the inventory.json
  entry. Industry references simplified to pure 5 (Yocto / DEP-3 / Buildroot / OpenWrt / Kconfig).
- **2026-07-21** v5.0: upgrade to OpenWrt Config.in-style **feature + combo** model.
  `patches/features.yaml` centrally declares features (`title`/`patches`/`depends`/
  `default`); patches are physically organized by `features/<feature>/`. **Compose
  logic integrated into `apply_patch.sh` internally** (inline python heredoc,
  **no new script**). Customers pick feature combos via `ACTIVE_FEATURES="f1 f2"`
  or `--active "f1 f2"`; `depends` field auto-includes dependencies and applies
  them first. `lint_series.py` now lints `features.yaml` (schema + depends + DEP-3
  required). v4.0's `series`/`series.<profile>` files are removed.
- **2026-07-20** v4.0: add `tools/gen_inventory.py` (Buildroot/OpenWrt-style derived
  inventory.json) and `series.<profile>` profile files. inventory.json is gitignored
  and regenerated by `tools/verify.sh`. CI gains step 4 (`gen_inventory.py --check`).
  `lint_series.py` now auto-discovers `series.<profile>` files.
- **2026-07-20** v3.0: combine Yocto recipe fields + DEP-3 patch header + Buildroot
  `apply-patches.sh`. New: `tools/apply_patch.sh` (single source series applier),
  `upstream.yaml` Yocto-style fields (SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION),
  DEP-3 6-required fields in patch headers (Description/Origin/Upstream-Status/
  Applies-To/Maintainer/Last-Update).
- **2026-07-20** v2.0 refactor: slim down to `version-centric + patches/series` model.
  Removed `sync-manifest.py` / `whitelist-audit.py` / `build-perf.sh` / generated manifest
  files. Patch metadata migrated to mail-style headers. Aligned with SUSE / Yocto /
  OpenWrt industry references.
- **2026-03-05** README rework
- **2025-03-30** added guides + release notes
- **2025-02-28** initial redis 7.0.15 support