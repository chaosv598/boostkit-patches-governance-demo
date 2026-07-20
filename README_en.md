# Redis Network Optimization Features

## Project Brand Name

Kunpeng BoostKit Redis

## Introduction

Kunpeng BoostKit Redis is a **patch overlay** on top of upstream Redis. The repository
pins a fixed upstream version and layers BoostKit-maintained ARM/Kunpeng optimization
patches on top.

**Core model**: version-centric + explicit `patches/series`. Aligned with industry-proven
schemes — SUSE `kernel-source`, Debian Quilt `debian/patches/series`, Yocto/OpenEmbedded
`Upstream-Status`, ungoogled-chromium `patches/series`. See
[docs/governance.md §2](./docs/governance.md#2-industry-references).

## Repository Layout

```text
boostkit-patches-governance-demo/
├── README.md / README_en.md            # This file
├── LICENSE.txt                          # Upstream license (full text)
├── .github/
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/
│       ├── ci.yml                       # 3 steps: verify + patch header lint + series lint
│       └── build-perf.yml               # matrix: clean clone + make + memtier
├── tools/
│   └── verify.sh                        # root file hygiene + upstream.yaml + clean apply series
├── docs/
│   ├── governance.md                    # ★ Design rationale + industry references
│   ├── version-yaml-spec.md             # ★ Authoritative field definitions
│   └── (product guides zh/en retained)
└── versions/
    └── <upstream-id>/                   # e.g. redis-7.0.15
        ├── upstream.yaml                # upstream pin
        └── patches/
            ├── series                   # ★ Single source of truth for ordering
            └── *.patch                  # RFC822 mail-style header + diff
```

## Quick Start

### 1. Upstream pin + patch order at a glance

`versions/redis-7.0.15/upstream.yaml`:

```yaml
upstream:
  repo: https://github.com/redis/redis
  version: 7.0.15
  commit: f35f36a265403c07b119830aa4bb3b7d71653ec9
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
bash tools/verify.sh

# 2. Patch mail-style header schema (Yocto Upstream-Status aligned)
python3 .github/lint_patch_headers.py versions/*/patches/

# 3. Series consistency (no orphans, no duplicates)
python3 .github/lint_series.py versions/*/patches/
```

### 3. Build on Kunpeng

```bash
# Follow "Local repro" in docs/governance.md §3.2
# 1) clean clone + apply series
git clone --depth=1 https://github.com/redis/redis
cd redis
git fetch origin f35f36a265403c07b119830aa4bb3b7d71653ec9
git checkout f35f36a265403c07b119830aa4bb3b7d71653ec9
while read p; do
  [ -z "$p" ] && continue
  [[ "$p" == \#* ]] && continue
  git apply "../versions/redis-7.0.15/patches/$p"
done < ../versions/redis-7.0.15/patches/series

# 2) build
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

Industry references:
- Quilt / Debian `debian/patches/series` — top-to-bottom order list
- SUSE `kernel-source/series.conf` — explicit list + `Git-commit` metadata validation
- Yocto/OpenEmbedded `Upstream-Status` — 8-state semantics aligned
- ungoogled-chromium `patches/series` — version pin ↔ patches separation
- openEuler `apply-patches` — series + guards (future extension)

## Contributing

PR-only workflow. No direct pushes to master.

1. Add patch → modify one line in `patches/series` + write mail-style header
2. Run all 3 local tools, all green
3. Open PR → triggers `ci.yml` 3 steps + `build-perf.yml` matrix
4. Maintainer review → merge

## License

- This overlay: Apache 2.0 (see [LICENSE.txt](./LICENSE.txt))
- Upstream Redis: BSD-3-Clause (preserved in each patch header)
- Product docs: CC-BY 4.0 (see [docs/LICENSE](./docs/LICENSE))

## Change Log

- **2026-07-20** v2.0 refactor: slim down to `version-centric + patches/series` model.
  Removed `sync-manifest.py` / `whitelist-audit.py` / `build-perf.sh` / generated manifest
  files. Patch metadata migrated to mail-style headers. Aligned with SUSE / Debian Quilt /
  Yocto / ungoogled-chromium industry references.
- **2026-03-05** README rework
- **2025-03-30** added guides + release notes
- **2025-02-28** initial redis 7.0.15 support