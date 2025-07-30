# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

#!/bin/bash

# Usage:
# ./dtb-check.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

set -x
set -euo pipefail

# Load shared utilities
source "$(dirname "$0")/script-utils.sh"

# Parse and validate input arguments
parse_args "$@"
validate_args

# Enter kernel source directory
enter_kernel_dir

# Initialize variables
exit_status=0
log_summary=()
dt_dir="arch/arm64/boot/dts"
log_file="dtbs_errors.log"
temp_out="temp-out"

# Check for devicetree changes
if ! git diff --name-only "$base_sha" "$head_sha" -- "$dt_dir" | grep -q .; then
    echo "No changes in Devicetree"
    leave_kernel_dir
    exit 0
fi

# Build DTBs at base SHA
git checkout $base_sha > /dev/null 2>&1
run_in_kmake_image make -s -j$(nproc) O="$temp_out" defconfig
run_in_kmake_image make -s -j$(nproc) O="$temp_out" dtbs

# Checkout to head SHA and run make dtbs to
# get the list of devicetree files impacted
# by the head_sha
git checkout $head_sha > /dev/null 2>&1
run_in_kmake_image make -s -j$(nproc) O="$temp_out" defconfig
dtb_files=$(run_in_kmake_image make -j$(nproc) O=temp-out dtbs | grep -oP 'arch/arm64/boot/dts/.*?\.dtb')

# Get the nodes modified by PR
modified_nodes=$(git diff "$base_sha".."$head_sha" -- "$dt_dir" | \
                   grep -oE '[a-zA-Z0-9_-]+@[0-9a-fA-F]+' || true | sort -u | uniq)

# Validate each DTB file
for devicetree in $dtb_files; do
    echo "Validating $devicetree"
    run_in_kmake_image make -j"$(nproc)" O="$temp_out" CHECK_DTBS=y "$(echo "$devicetree" | sed 's|^arch/arm64/boot/dts/||')" |& tee "$log_file"

    # Extract error node names from the log file
    error_nodes=$(grep -oP '[a-zA-Z0-9_-]+@[0-9a-fA-F]+' "$log_file" || true | sort -u | uniq)

    # Compare modified nodes with error nodes
    common_nodes=$(comm -12 <(echo "$modified_nodes") <(echo "$error_nodes"))
    if [[ -n "$common_nodes" ]]; then
        log_summary+="dtbs_check failed for $devicetree...\n"
        exit_status=1
    else
        log_summary+="dtbs_check passed for $devicetree...\n"
        exit_status=0
    fi
    echo ""
done

# Cleanup
rm -f $log_file
rm -rf "$temp_out"
leave_kernel_dir

# Print summary
echo ""
echo -e "Log Summary:\n$log_summary"

exit $exit_status
