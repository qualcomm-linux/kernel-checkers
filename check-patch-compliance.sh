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
commits=$(git rev-list --no-merges --reverse ${base_sha}..${head_sha})

# Iterate over each commit
for commit in $commits; do
  commit_message=$(git log -1 --pretty=format:"%b" $commit)
  commit_summary=$(git log -1 --pretty=format:"%s" $commit)

  echo "Checking commit: $commit_summary"

  # Check if summary starts with one of the required prefixes
  if ! echo "$commit_summary" | grep -qE '^(FROMLIST|FROMGIT|UPSTREAM|BACKPORT)'; then
    echo "Commit summary does not start with a required prefix"
    exit_status=1
    continue
  fi

  # Check for 'Link:' in the commit message body
  if ! echo "$commit_message" | grep -q '^Link:'; then
    echo "No 'Link' found in commit message"
    exit_status=1
  else
    #Extract the Link URL from the commit message
    link=$(echo "$commit_message" | grep '^Link:' | sed 's/Link:[[:space:]]*//I')

    mkdir out
    # Fetch patch using b4
    run_in_kmake_image_with_passwd b4 am --single-message -C -l -3 $link -o out > /dev/null 2>&1

    # Check if patch was fetched successfully
    if [ -z "$(ls -A out)" ]; then
      echo "Something seems wrong with the provided link. Please verify it"
      echo "Try below command to run locally-"
      echo "b4 am --single-message -C -l -3 $link"
      exit_status=1
    else
      # Extract code changes from both sources
      awk '/^diff --git /, /^--$/ { print }' out/*.mbx | grep -E '^[+-][^+-]' > out/from_mbox
      git format-patch -1 $commit --stdout | grep -E '^[+-][^+-]' > out/from_git_commit

      # Compare the changes
      if ! diff out/from_git_commit out/from_mbox > /dev/null; then
        echo "Change is different from the one mentioned in Link"
	exit_status=1
      fi

      # Extract author from mbox downloaded
      mbox_author=$(grep -m 1 '^From:' out/*.mbx | sed 's/^From:[[:space:]]*//' | sed 's/"//g')

      # Extract the author from local commit
      git_author=$(git show -s --format='%an <%ae>' $commit)

      # Compare authors
      if [ ! "$mbox_author" = "$git_author" ]; then
        echo "Author mismatch:"
        echo "  Original author: $mbox_author"
        echo "  Commit author : $git_author"
        exit_status=1
      fi
    fi

    rm -rf out
  fi

  echo ""
done

if [ "$exit_status" -eq 0 ]; then
    echo "$0 passed"
fi

# Cleanup
leave_kernel_dir

exit $exit_status
