# Kunpeng BoostKit Redis

> Patch overlay governance demo. Design: [docs/governance.md](./docs/governance.md), schema: [docs/schemas.md](./docs/schemas.md).

Kunpeng BoostKit Redis layers ARM/Kunpeng platform optimization patches on top of a fixed upstream Redis version, using a **version-centric + feature declaration** model that combines best practices from Yocto, DEP-3, Buildroot, OpenWrt, and Linux Kconfig.

## Quick Start

```bash
# Full verification (root hygiene + upstream.yaml schema + clean clone + apply)
bash tools/verify.sh

# Patch header lint (DEP-3 6 required + conditional)
python3 .github/lint.py headers versions/*/patches/

# features.yaml lint (schema + depends + orphan detection)
python3 .github/lint.py features versions/*/patches/

# Or run both at once
python3 .github/lint.py all versions/*/patches/
```

**Feature combos**: select feature subsets via `ACTIVE_FEATURES` env var; `apply_patch.sh` auto-resolves dependencies:

```bash
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    --features versions/redis-7.0.15/patches/features.yaml \
    versions/redis-7.0.15/patches \
    /tmp/build

# Subset selection
ACTIVE_FEATURES="rdb-aof-fallback" bash tools/apply_patch.sh ... --features ... /tmp/build-a
```

## Design

See the docs:
- **[docs/governance.md](./docs/governance.md)** — design rationale + 5 industry references + workflows + operations + FAQ
- **[docs/schemas.md](./docs/schemas.md)** — authoritative YAML/header field definitions + validation matrix
- **Product guides** — `docs/zh/` (Chinese) / `docs/en/` (English): feature usage, compatibility, build steps
- **[docs/research/openEuler-patch-mgmt.md](./docs/research/openEuler-patch-mgmt.md)** — openEuler patch management research & comparison

## Contributing

PR-only workflow:

1. Add patch → place under `patches/features/<feature>/` + write DEP-3 header (6 required) + update `features.yaml`
2. Run all 3 local tools green (`verify.sh` + `lint.py headers` + `lint.py features`)
3. Open PR → triggers `ci.yml` (3 steps) + `build-perf.yml` matrix
4. Maintainer review → merge

## License

- This overlay: Apache 2.0 ([LICENSE.txt](./LICENSE.txt))
- Upstream Redis: BSD-3-Clause (preserved in each patch header)
- Product docs: CC-BY 4.0 ([docs/LICENSE](./docs/LICENSE))
