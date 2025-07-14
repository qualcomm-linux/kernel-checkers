# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

#!/bin/bash

# Usage:
# ./checkpatch.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

# Load shared utilities
source "$(dirname "$0")/script-utils.sh"

# Parse and validate input arguments
parse_args "$@"
validate_args

# Enter kernel source directory
enter_kernel_dir

# Initialize variables
exit_status=0
log_file="checkpatch_errors.log"

# Run checkpatch.pl script and redirect output to log file
run_in_kmake_image $kernel_src/scripts/checkpatch.pl --strict --summary-file --ignore FILE_PATH_CHANGES --git $base_sha..$head_sha |& tee "$log_file"

while IFS= read -r line; do
    errors=$(echo $line | awk '{print $1}')
    warnings=$(echo $line | awk '{print $3}')
    checks=$(echo $line | awk '{print $5}')

    # Check if any of the numbers is not zero
    if [ "$errors" -ne 0 ] || [ "$warnings" -ne 0 ] || [ "$checks" -ne 0 ]; then
        exit_status=1
    fi
done< <(cat "$log_file" | grep -oP '\d+ errors, \d+ warnings, \d+ checks')

if [ "$exit_status" -ne 0 ]; then
    echo ""
    echo "To reproduce the error locally, run below command -"
    echo "./scripts/checkpatch.pl --strict --summary-file --ignore FILE_PATH_CHANGES --git $base_sha..$head_sha"
    exit_status=1
else
    echo ""
    echo "$0 passed"
fi

# Cleanup
rm -f "$log_file"
leave_kernel_dir

exit $exit_status
