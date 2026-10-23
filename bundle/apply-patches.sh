#!/bin/sh
# Apply the Android runtime patches to the DSH packages installed in this image.
#
# The patches are ordinary unified diffs generated from a known base DSH
# version. They are applied here, at image build time, against whatever DSH
# version the build resolved: if upstream moved a patched region, `patch`
# fails and the image build fails instead of publishing a version-mixed image.
#
# The final image is therefore "latest DSH + Android patches" and the client
# does not need to overwrite package files at runtime.
set -eu

patches_dir=${PATCHES_DIR:-/patches/android}
root=${ROOT:-/}
count=0

for patch_file in "$patches_dir"/*.patch; do
    [ -f "$patch_file" ] || continue
    echo "applying $(basename "$patch_file")"
    patch -p1 -d "$root" --batch --no-backup-if-mismatch < "$patch_file"
    count=$((count + 1))
done

if [ "$count" -eq 0 ]; then
    echo "no Android patches found under $patches_dir" >&2
    exit 1
fi

echo "applied $count Android patches"
