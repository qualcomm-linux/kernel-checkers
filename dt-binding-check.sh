# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

#!/bin/bash

# Usage:
# ./dt-binding-check.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

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
bindings_dir="Documentation/devicetree/bindings"
log_file="dt-binding-check.log"
temp_out="temp-out"

# Get the list of changed files
changed_files=$(git diff --name-only $base_sha $head_sha -- "$bindings_dir")

# Check if there are any changes
if [ -z "$changed_files" ]; then
    echo "No changes in $bindings_dir"
    leave_kernel_dir
    exit 0
fi

# Function to validate a binding
validate_binding() {
    local binding=$1
    local check_command=$2

    run_in_kmake_image make -j$(nproc) O="$temp_out" "$check_command" DT_SCHEMA_FILES="$binding" |& tee $log_file
    if grep -q "$binding" "$log_file"; then
        rm -f "$log_file"
        return 1
    fi
    rm -f "$log_file"
    return 0
}
# Build defconfig
run_in_kmake_image make -s -j$(nproc) O="$temp_out" defconfig

# Process each changed file
for binding in $changed_files; do
    case "$binding" in
        *.txt)
            echo $binding
            echo "Please submit the Documentation change in YAML format"
            exit_status=1
            ;;
        *.yaml)
            echo "Validating $binding"
            if validate_binding "$binding" "dt_binding_check"; then
                log_summary+="dt_binding_check passed for $binding...\n"
                echo "Validating $binding against DTBs"
                if validate_binding "$binding" "dtbs_check"; then
                    log_summary+="dtbs_check passed for $binding...\n"
                else
                    log_summary+="dtbs_check failed for $binding...\n"
                    exit_status=1
                fi
            else
                log_summary+="dt_binding_check failed for $binding...\n"
                exit_status=1
            fi
            ;;
    esac
done

# Cleanup
rm -rf "$temp_out"
leave_kernel_dir

# Print summary
echo ""
echo -e "Log Summary:\n$log_summary"

exit $exit_status
