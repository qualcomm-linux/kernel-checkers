#!/bin/bash

# Usage:
# ./run_scripts.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

# Load shared utilities
source "$(dirname "$0")/script-utils.sh"

# Parse and validate input arguments
parse_args "$@"
validate_args

scripts=(
  "checkpatch.sh"
  "check-uapi-headers.sh"
  "sparse-check.sh"
  "dt-binding-check.sh"
  "dtb-check.sh"
  "check-patch-compliance.sh"
)

# Initialize variables
exit_status=0
log_summary=""

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

leave_kernel_dir
echo -e "Log Summary:\n$log_summary"
exit $exit_status
