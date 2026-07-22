# Kunpeng BoostKit Redis

> Patch overlay governance. Design: [docs/governance.md](./docs/governance.md), schema: [docs/schemas.md](./docs/schemas.md).

Kunpeng BoostKit Redis layers ARM/Kunpeng optimizations on upstream Redis. v6.0 aligns with Buildroot: directory-as-config, no manifest lists.

## Quick Start

```bash
# Full verification
bash tools/verify.sh

# Patch header lint (DEP-3 6 required + conditional)
python3 .github/lint.py headers versions/*/

# Manifest + DEP-3 lint
python3 .github/lint.py manifest versions/*/

# All-in-one
python3 .github/lint.py all versions/*/
```

**Feature subsets** via `ACTIVE_FEATURES` (unset = all):

```bash
# All features
bash tools/apply_patch.sh \
    https://github.com/redis/redis \
    f35f36a265403c07b119830aa4bb3b7d71653ec9 \
    versions/redis-7.0.15 \
    /tmp/build

# Subset
ACTIVE_FEATURES="rdb-aof-fallback" bash tools/apply_patch.sh ... /tmp/build-a
```

## Layout

```
versions/redis-7.0.15/
├── manifest.yaml          # upstream pin (3 fields)
├── kunpeng-hw-accel/      # feature dir = subdir with *.patch
├── jemalloc-arm64/
└── rdb-aof-fallback/
```

## Docs

- **[docs/governance.md](./docs/governance.md)** — design + industry refs + FAQ
- **[docs/schemas.md](./docs/schemas.md)** — field definitions + validation matrix
- **Product guides** — `docs/zh/` / `docs/en/`
- **[docs/research/openEuler-patch-mgmt.md](./docs/research/openEuler-patch-mgmt.md)** — openEuler research

## Contributing

1. Add patch → drop in feature dir + write DEP-3 header (6 required)
2. Run local tools green (`verify.sh` + `lint.py headers` + `lint.py manifest`)
3. Open PR → `ci.yml` (3 steps)
4. Review → merge

## License

- Overlay: Apache 2.0 ([LICENSE.txt](./LICENSE.txt))
- Upstream Redis: BSD-3-Clause (in patch headers)
- Product docs: CC-BY 4.0 ([docs/LICENSE](./docs/LICENSE))
