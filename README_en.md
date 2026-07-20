# Redis Network Optimization Features

## Project Brand Name

Kunpeng BoostKit Redis

## Introduction

Kunpeng BoostKit Redis is a **patch overlay** on top of upstream Redis. The repository
pins a fixed upstream version and layers BoostKit-maintained ARM/Kunpeng optimization
patches on top.

**Core model**: version-centric + explicit `patches/series`. Combined from 5 industry-proven
schemes — **Yocto/OpenEmbedded** recipe fields + `Upstream-Status`, **DEP-3** patch header
schema, **Buildroot** `apply-patches.sh`, **OpenWrt** `patches/series`, **Quilt/Debian** series.
See [docs/governance.md §2](./docs/governance.md#2-industry-references).

## Repository Layout

```text
boostkit-patches-governance-demo/
├── README.md / README_en.md            # This file
├── LICENSE.txt                          # Upstream license (full text)
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── lint_patch_headers.py            # DEP-3 6 required fields validator
│   ├── lint_series.py                   # series consistency validator
│   └── workflows/
│       ├── ci.yml                       # 3 steps: verify + patch header lint + series lint
│       └── build-perf.yml               # skeleton workflow (matrix: clean apply + echo steps)
├── tools/
│   ├── verify.sh                        # root hygiene + upstream.yaml schema (delegates apply)
│   └── apply_patch.sh                   # ★ Buildroot-style series applier (single source)
├── docs/
│   ├── governance.md                    # ★ Design rationale + 5 industry references
│   ├── version-yaml-spec.md             # ★ Authoritative field definitions
│   └── (product guides zh/en retained)
└── versions/
    └── <upstream-id>/                   # e.g. redis-7.0.15
        ├── upstream.yaml                # Yocto recipe fields + upstream pin + governance
        └── patches/
            ├── series                   # ★ Single source of truth for ordering
            └── *.patch                  # DEP-3 mail-style header (6 required) + diff
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

`versions/redis-7.0.15/patches/series` (applied top-to-bottom):

```text
0001-hw-kunpeng-adapt-iouring.patch
0002-perf-kunpeng-adapt-dtoe.patch
0003-perf-jemalloc-arm64-pointer-tag-and-gc.patch
0004-perf-rdb-fallback-aof.patch
```

### 2. Local validation

```bash
# 1. Root hygiene + upstream.yaml schema + clean clone + apply series
#    (delegates to tools/apply_patch.sh internally)
bash tools/verify.sh

# 2. DEP-3 patch header schema (6 required: Description/Origin/Upstream-Status/Applies-To/Maintainer/Last-Update)
python3 .github/lint_patch_headers.py versions/*/patches/

# 3. Series consistency (no orphans, no duplicates)
python3 .github/lint_series.py versions/*/patches/
```

### 2.5 Standalone series apply (Buildroot-style)

```bash
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15/patches/series \
    versions/redis-7.0.15/patches \
    /tmp/build
```

### 3. Build on Kunpeng

```bash
# 1) clean clone + apply series (Buildroot-style single source)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15/patches/series \
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

Industry references (5-way alignment):
- **Yocto/OpenEmbedded** — recipe fields (SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION) +
  `Upstream-Status` 8-state semantics
- **DEP-3** (Debian) — patch header schema with 6 required fields
- **Buildroot** `apply-patches.sh` — series applier single source
- **OpenWrt** `patches/series` + `patch-kernel.sh` — per-package series format
- **Quilt/Debian** `debian/patches/series` — top-to-bottom order list

## Contributing

PR-only workflow. No direct pushes to master.

1. Add patch → write DEP-3 header (6 required) + modify one line in `patches/series`
2. Run all 3 local tools, all green
3. Open PR → triggers `ci.yml` 3 steps + `build-perf.yml` matrix (skeleton)
4. Maintainer review → merge

## License

- This overlay: Apache 2.0 (see [LICENSE.txt](./LICENSE.txt))
- Upstream Redis: BSD-3-Clause (preserved in each patch header)
- Product docs: CC-BY 4.0 (see [docs/LICENSE](./docs/LICENSE))

## Change Log

- **2026-07-20** v3.0: combine Yocto recipe fields + DEP-3 patch header + Buildroot
  `apply-patches.sh`. New: `tools/apply_patch.sh` (single source series applier),
  `upstream.yaml` Yocto-style fields (SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION),
  DEP-3 6-required fields in patch headers (Description/Origin/Upstream-Status/
  Applies-To/Maintainer/Last-Update).
- **2026-07-20** v2.0 refactor: slim down to `version-centric + patches/series` model.
  Removed `sync-manifest.py` / `whitelist-audit.py` / `build-perf.sh` / generated manifest
  files. Patch metadata migrated to mail-style headers. Aligned with SUSE / Debian Quilt /
  Yocto / ungoogled-chromium industry references.
- **2026-03-05** README rework
- **2025-03-30** added guides + release notes
- **2025-02-28** initial redis 7.0.15 support