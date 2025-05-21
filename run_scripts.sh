# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

#!/bin/bash

# Usage:
# ./run_scripts.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

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
    echo "Usage: ./run_scripts.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>"
    echo "Please pass the required arguments. Exiting..."
    exit 1
fi

# Check if kernel source directory exists
if [ ! -d "$kernel_src" ]; then
    echo "Error: $kernel_src directory does not exist."
    exit 1
fi

# Define the scripts to run
scripts=(
    "checkpatch.sh"
    "check-uapi-headers.sh"
    "sparse-check.sh"
    "dt-binding-check.sh"
    "dtb-check.sh"
)

# Initialize return status and log summary
exit_status=0
log_summary=""

# Run the scripts and collect the results
for script in "${scripts[@]}"; do
    echo ""
    echo "Running $script script..."
    echo ""
    "$(pwd)/$script" --kernel-src "$kernel_src" --base "$base_sha" --head "$head_sha"
    status=$?
    if [ $status -eq 0 ]; then
        log_summary+="$script passed\n"
    else
        exit_status=1
        log_summary+="$script failed\n"
    fi
done

# Print log summary
echo ""
echo -e "Log Summary:\n$log_summary"

exit $exit_status
