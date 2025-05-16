#!/bin/bash

# Usage:
# ./dtb-check.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

set -euo pipefail

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --kernel-src) kernel_src=$(realpath "$2"); shift ;;
        --base) base_sha="$2"; shift ;;
        --head) head_sha="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Validate arguments
if [[ -z "$base_sha" || -z "$head_sha" || -z "$kernel_src" ]]; then
    echo "Usage: $0 --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>"
    echo "Please pass the required arguments. Exiting..."
    exit 1
fi

# Check if kernel source directory exists
if [ ! -d "$kernel_src" ]; then
    echo "Error: $kernel_src directory does not exist."
    exit 1
fi

# Change to kernel source directory
pushd "$kernel_src" > /dev/null || exit 1
echo "Changed directory to $kernel_src"

# Docker wrapper for make
kmake_image_make() {
    docker run -it --rm \
        --user "$(id -u):$(id -g)" \
        --workdir="$PWD" \
        -v "$(dirname "$PWD")":"$(dirname "$PWD")" \
        kmake-image make "$@"
}

# Initialize
exit_status=0
log_summary=()
dt_dir="arch/arm64/boot/dts"
log_file="dtbs_errors.log"
temp_out="temp-out"

# Check for devicetree changes
if ! git diff --name-only "$base_sha" "$head_sha" -- "$dt_dir" | grep -q .; then
    echo "No changes in Devicetree"
    exit 0
fi

# Build DTBs at base SHA
git checkout $base_sha > /dev/null 2>&1
kmake_image_make -s -j$(nproc) O="$temp_out" defconfig
kmake_image_make -s -j$(nproc) O="$temp_out" dtbs
git switch - > /dev/null 2>&1

# Checkout to head SHA and run make dtbs to
# get the list of devicetree files impacted
# by the head_sha
git checkout $base_sha > /dev/null 2>&1
dtb_files=$(kmake_image_make -j$(nproc) O=temp-out dtbs | grep -oP 'arch/arm64/boot/dts/.*?\.dtb')

# Switch back to original branch
git switch - > /dev/null 2>&1

# Validate each DTB file
for devicetree in $dtb_files; do
    echo "Validating $devicetree"
    kmake_image_make -j"$(nproc)" O="$temp_out" CHECK_DTBS=y "$(echo "$devicetree" | sed 's|^arch/arm64/boot/dts/||')" |& tee "$log_file"
    if grep -q "$devicetree" $log_file; then
        log_summary+="dtbs_check passed for $devicetree...\n"
        exit_status=1
    else
        log_summary+="dtbs_check passed for $devicetree...\n"
    fi
    echo ""
done

# Cleanup
rm -f $log_file
rm -rf "$temp_out"
echo "Leaving $kernel_src"
popd

# Print summary
echo ""
echo -e "Log Summary:\n$log_summary"

exit $exit_status