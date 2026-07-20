# Redis Network Optimization Features

## Project Brand Name

Kunpeng BoostKit Redis

## Introduction

Kunpeng BoostKit Redis is a **patch overlay** on top of upstream Redis. The repository
pins a fixed upstream version and layers BoostKit-maintained ARM/Kunpeng optimization
patches on top.

**Core model**: version-centric + explicit `patches/series`. Combined from 5 industry-proven
schemes + 2 repo extensions — **Yocto/OpenEmbedded** recipe fields + `Upstream-Status`,
**DEP-3** patch header schema, **Buildroot** `apply-patches.sh`, **OpenWrt** `patches/series`,
**Quilt/Debian** series; plus `series.<profile>` profile files (Buildroot variant pattern)
and `tools/gen_inventory.py` (Buildroot `pkg-stats` / OpenWrt `metadata.pl` style).
See [docs/governance.md §2](./docs/governance.md#2-industry-references).

## Repository Layout

```text
boostkit-patches-governance-demo/
├── README.md / README_en.md            # This file
├── LICENSE.txt                          # Upstream license (full text)
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   ├── lint_patch_headers.py            # DEP-3 6 required fields validator
│   ├── lint_series.py                   # series + series.* profile consistency validator
│   └── workflows/
│       ├── ci.yml                       # 4 steps: verify + patch header lint + series lint + inventory check
│       └── build-perf.yml               # skeleton workflow (matrix: clean apply + echo steps)
├── tools/
│   ├── verify.sh                        # root hygiene + upstream.yaml schema (delegates apply) + inventory refresh
│   ├── apply_patch.sh                   # ★ Buildroot-style series applier (single source)
│   └── gen_inventory.py                 # inventory.json generator (Buildroot/OpenWrt style)
├── docs/
│   ├── governance.md                    # ★ Design rationale + 5 industry references + 2 repo extensions
│   ├── version-yaml-spec.md             # ★ Authoritative field definitions
│   └── (product guides zh/en retained)
└── versions/
    └── <upstream-id>/                   # e.g. redis-7.0.15
        ├── upstream.yaml                # Yocto recipe fields + upstream pin + governance
        └── patches/
            ├── series                   # ★ Single source of truth (default profile)
            ├── series.<profile>         # profile series files (e.g. series.minimal / series.security)
            ├── inventory.json           # derived (gitignored)
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
# 1. Root hygiene + upstream.yaml schema + clean clone + apply series + inventory refresh
#    (delegates to tools/apply_patch.sh internally)
bash tools/verify.sh

# 2. DEP-3 patch header schema (6 required: Description/Origin/Upstream-Status/Applies-To/Maintainer/Last-Update)
python3 .github/lint_patch_headers.py versions/*/patches/

# 3. Series consistency (no orphans, no duplicates; profile files series.* auto-detected)
python3 .github/lint_series.py versions/*/patches/

# 4. inventory.json matches patch headers + series (ignores generated_at timestamp)
python3 tools/gen_inventory.py --check versions/*/
```

### 2.6 Profile series files (subsets on the same upstream)

Apply only a subset of patches by using `series.<profile>` (Buildroot variant pattern):

```bash
# Create profile series file (same plain series format)
cat > versions/redis-7.0.15/patches/series.ci <<'EOF'
# CI smoke profile: only 0001 + 0004, skip 0002 (Kunpeng HW) / 0003 (jemalloc)
0001-hw-kunpeng-adapt-iouring.patch
0004-perf-rdb-fallback-aof.patch
EOF

# profile reuses apply_patch.sh directly (accepts any series file)
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15/patches/series.ci \
    versions/redis-7.0.15/patches \
    /tmp/build-ci

# inventory.json auto-reflects new profile (derived, gitignored)
python3 -c "import json; d=json.load(open('versions/redis-7.0.15/patches/inventory.json')); \
    [print(f\"{p['file']:50s} profiles={p['in_profiles']}\") for p in d['patches']]"
```

See [docs/version-yaml-spec.md §3.3](./docs/version-yaml-spec.md#33-profile-series-filesseriesprofile--repo-extension).

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

Industry references (5-way alignment + 2 repo extensions):
- **Yocto/OpenEmbedded** — recipe fields (SUMMARY/LICENSE/HOMEPAGE/LIC_FILES_CHKSUM/SECTION) +
  `Upstream-Status` 8-state semantics
- **DEP-3** (Debian) — patch header schema with 6 required fields
- **Buildroot** `apply-patches.sh` — series applier single source
- **OpenWrt** `patches/series` + `patch-kernel.sh` — per-package series format
- **Quilt/Debian** `debian/patches/series` — top-to-bottom order list
- **Repo extension** — `series.<profile>` profile files (Buildroot variant pattern)
- **Repo extension** — `tools/gen_inventory.py` derived inventory.json (Buildroot `pkg-stats` / OpenWrt `metadata.pl`)

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
  files. Patch metadata migrated to mail-style headers. Aligned with SUSE / Debian Quilt /
  Yocto / ungoogled-chromium industry references.
- **2026-03-05** README rework
- **2025-03-30** added guides + release notes
- **2025-02-28** initial redis 7.0.15 support