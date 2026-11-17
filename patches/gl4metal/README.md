# Custom gl4metal snapshot

This patch bundles the 3D image, SSBO, and compute implementation from the sibling
gl4metal working tree. It includes the runtime changes, shader translator,
portable tests, optional device tests and documentation. It excludes build output
and Git metadata. Original code and modifications remain under gl4metal's license.

`manifest.json` records the exact upstream commit and SHA-256 of the patch.
`scripts/apply_gl4metal_patch.py` checks both before applying it. The development
workflow checks out that commit and applies this patch before compiling Hynis.

The patch captures a point in time. For additional renderer changes, regenerate
it against the pinned commit and update the checksum, or explicitly use a changed
checkout through `GL4METAL_SOURCE_DIR` for a local build.
