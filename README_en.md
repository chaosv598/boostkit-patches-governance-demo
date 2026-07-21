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
`select` / `default` semantics; plus `tools/gen_inventory.py` (Buildroot `pkg-stats` /
OpenWrt `metadata.pl` style).

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
│       ├── ci.yml                       # 4 steps: verify + patch header lint + features lint + inventory check
│       └── build-perf.yml               # skeleton workflow (matrix: clean apply + echo steps)
├── tools/
│   ├── verify.sh                        # root hygiene + upstream.yaml schema (delegates apply --features) + inventory refresh
│   ├── apply_patch.sh                   # ★ Buildroot-style series applier + v5.0 --features mode (inline compose)
│   └── gen_inventory.py                 # inventory.json generator (Buildroot/OpenWrt style)
├── docs/
│   ├── governance.md                    # ★ Design rationale + 5 industry references
│   ├── version-yaml-spec.md             # ★ Authoritative field definitions
│   └── (product guides zh/en retained)
└── versions/
    └── <upstream-id>/                   # e.g. redis-7.0.15
        ├── upstream.yaml                # Yocto recipe fields + upstream pin + governance
        └── patches/
            ├── features.yaml            # ★ Feature declaration (OpenWrt Config.in style, single source)
            ├── features/<feature>/      # one feature per directory
            │   └── *.patch              # DEP-3 mail-style header (6 required) + diff
            └── inventory.json           # derived (gitignored)
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
  feature-A:
    title: "Kunpeng ARM HW acceleration (io_uring adapt + DTOE DMA network path)"
    patches:
      - 0001-hw-kunpeng-adapt-iouring.patch
      - 0002-perf-kunpeng-adapt-dtoe.patch
    depends: []
    default: true                                # enabled by default
    upstream_status_summary:
      Submitted: 1
      Inappropriate: 1
  feature-B:
    title: "jemalloc ARM64 pointer-tag + GC decay strategy"
    patches:
      - 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
    depends: []
    default: false                               # not enabled by default
  feature-C:
    title: "AOF fallback when RDB corrupted"
    patches:
      - 0001-perf-rdb-fallback-aof.patch
    depends: []
    default: true
```

Physical patches are organized by feature:

```text
versions/redis-7.0.15/patches/features/
├── feature-A/
│   ├── 0001-hw-kunpeng-adapt-iouring.patch
│   └── 0002-perf-kunpeng-adapt-dtoe.patch
├── feature-B/
│   └── 0001-perf-jemalloc-arm64-pointer-tag-and-gc.patch
└── feature-C/
    └── 0001-perf-rdb-fallback-aof.patch
```

### 2. Local validation

```bash
# 1. Root hygiene + upstream.yaml schema + clean clone + apply features.yaml + inventory refresh
#    (delegates to tools/apply_patch.sh --features internally)
bash tools/verify.sh

# 2. DEP-3 patch header schema (6 required: Description/Origin/Upstream-Status/Applies-To/Maintainer/Last-Update)
python3 .github/lint_patch_headers.py versions/*/patches/

# 3. features.yaml schema + depends resolution + DEP-3 required fields
python3 .github/lint_series.py versions/*/patches/

# 4. inventory.json matches patch headers + features.yaml (ignores generated_at timestamp)
python3 tools/gen_inventory.py --check versions/*/
```

### 2.5 Feature combos (subsets on the same upstream)

Pick a feature subset via `ACTIVE_FEATURES` (env var) or `--active` (CLI flag):

```bash
# Default combo = union of features.yaml `default:true` (here: feature-A + feature-C)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build

# Customer A: reliability-only (just feature-C)
ACTIVE_FEATURES="feature-C" bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build-a

# Customer B: full bundle (also enables default-off feature-B)
ACTIVE_FEATURES="feature-A feature-B feature-C" bash tools/apply_patch.sh ... --features ... /tmp/build-b

# Equivalent --active flag (better for CI / tests)
bash tools/apply_patch.sh ... --features ... --active "feature-B feature-C" /tmp/build-c
```

The `depends` field makes features auto-include their dependencies (e.g. if `feature-C.depends=[feature-A]`,
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
- **Operations (add/retire patch)**: [docs/governance.md §4](./docs/governance.md#4-common-operations)

Industry references (5-way alignment + 1 repo extension):
- **Yocto/OpenEmbedded** — recipe fields (SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION) +
  `Upstream-Status` 8-state semantics
- **DEP-3** (Debian) — patch header schema with 6 required fields
- **Buildroot** `apply-patches.sh` — series applier single source
- **OpenWrt** `package/<name>/Config.in` + `Makefile` — feature declaration + conditional `PATCHFILES` (v5.0 primary)
- **Linux kernel** `Kconfig` — `depends` / `select` / `default` semantics (depth-first resolution + cycle detection)
- **Repo extension** — `tools/gen_inventory.py` derived inventory.json (Buildroot `pkg-stats` / OpenWrt `metadata.pl`)

**v5.0 key upgrade**: `patches/features.yaml` (OpenWrt Config.in style) replaces v4.0's
`series.<profile>`; customers pick feature combos via `ACTIVE_FEATURES`. Compose logic
is **integrated into `apply_patch.sh` internally** (no new script).

## Contributing

PR-only workflow. No direct pushes to master.

1. Add patch → place under `patches/features/<feature>/` + write DEP-3 header (6 required) +
   add entry to `features.yaml`
2. Run all 4 local tools, all green
3. Open PR → triggers `ci.yml` 4 steps + `build-perf.yml` matrix (skeleton)
4. Maintainer review → merge

## License

- This overlay: Apache 2.0 (see [LICENSE.txt](./LICENSE.txt))
- Upstream Redis: BSD-3-Clause (preserved in each patch header)
- Product docs: CC-BY 4.0 (see [docs/LICENSE](./docs/LICENSE))

## Change Log

- **2026-07-21** v5.0: upgrade to OpenWrt Config.in-style **feature + combo** model.
  `patches/features.yaml` centrally declares features (`title`/`patches`/`depends`/
  `default`); patches are physically organized by `features/<feature>/`. **Compose
  logic integrated into `apply_patch.sh` internally** (inline python heredoc,
  **no new script**). Customers pick feature combos via `ACTIVE_FEATURES="f1 f2"`
  or `--active "f1 f2"`; `depends` field auto-includes dependencies and applies
  them first. inventory.json gains `features`/`combos` sections. `lint_series.py`
  now lints `features.yaml` (schema + depends + DEP-3 required). v4.0's
  `series`/`series.<profile>` files are removed.
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