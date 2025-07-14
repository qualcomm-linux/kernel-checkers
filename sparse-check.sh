# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

#!/bin/bash

# Usage:
# ./sparse-check.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

# Load shared utilities
source "$(dirname "$0")/script-utils.sh"

# Parse and validate input arguments
parse_args "$@"
validate_args

# Enter kernel source directory
enter_kernel_dir

# Initialize variables
exit_status=0
log_file="sparse_errors.log"
temp_out="temp-out"


# Check if there are any .c or .h files that were added or modified
if [ $(git diff-tree -r --name-only -M100% --diff-filter=AM $base_sha..$head_sha | grep -E '\.(c|h)$' | wc -l) -eq 0 ]; then
    echo "Skipping sparse check as nothing changed..."
    leave_kernel_dir
    exit 0
fi

run_in_kmake_image make -s -j$(nproc) O="$temp_out" defconfig
run_in_kmake_image make -j$(nproc) O="$temp_out" -j$(nproc) C=2 | while read -r line; do
    echo $line
    if ! echo "$line" | grep -q -e "warning:" -e "error:" ; then
        continue
    fi

    # Extract file and line number from the log line
    file=$(echo $line | grep -oP '(\S+):\d+:' | awk -F: '{print $1}' | sed 's#^\.\./##')
    num=$(echo $line | grep -oP '(\S+):\d+:' | awk -F: '{print $2}')

    if [[ -f "$file" && "$num" =~ ^[0-9]+$ ]]; then
        # Check if the line is present in both the diff and sparse output
        git blame -L$num,+1 $base_sha..$head_sha -l -- "$file" | grep -q -v '^\^'
        if test $? -eq 0 ; then
            exit_status=1
            echo "$line" >> $log_file
        fi
    fi
done

# Print sparse errors if any
if [ -s $log_file ]; then
    echo ""
    echo "Processing sparse errors..."
    cat $log_file
    rm -f $log_file
else
    echo ""
    echo "$0 passed"
fi

# Cleanup
rm -rf "$temp_out"
leave_kernel_dir

exit $exit_status
