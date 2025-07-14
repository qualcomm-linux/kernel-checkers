#!/bin/bash

# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

# Usage:
# ./check-patch-complaince.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

# Load shared utilities
source "$(dirname "$0")/script-utils.sh"

# Parse and validate input arguments
parse_args "$@"
validate_args

# Enter kernel source directory
enter_kernel_dir

# Initialize variables
exit_status=0

# Get the list of commits between the two SHAs
commits=$(git rev-list --reverse ${base_sha}..${head_sha})

# Iterate over each commit
for commit in $commits; do
  commit_message=$(git log -1 --pretty=format:"%b" $commit)
  commit_summary=$(git log -1 --pretty=format:"%s" $commit)

  echo "Checking commit: $commit_summary"

  # Check for 'Link:' in the commit message body
  if ! echo "$commit_message" | grep -q '^Link:'; then
    echo "No 'Link' found in commit message"
    exit_status=1
  fi

  # Check if summary starts with one of the required prefixes
  if ! echo "$commit_summary" | grep -qE '^(FROMLIST|FROMGIT|UPSTREAM|BACKPORT)'; then
    echo "Commit summary does not start with a required prefix"
    exit_status=1
  fi

  echo ""
done

if [ "$exit_status" -eq 0 ]; then
    echo "$0 passed"
fi

# Cleanup
leave_kernel_dir

exit $exit_status
