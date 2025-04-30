#!/bin/bash

# Usage:
# ./checkpatch.sh <KERNEL_SRC_PATH> <START_SHA> <END_SHA>

KERNEL_SRC_PATH=$(realpath "$1")
START_SHA=$2
END_SHA=$3

# Check if kernel source directory exists
if [ ! -d "$KERNEL_SRC_PATH" ]; then
    echo "Error: $KERNEL_SRC_PATH directory does not exist."
    exit 1
fi

# Initialize return status and log file
exit_status=0
log_file="checkpatch_errors.log"

# Run checkpatch.pl script and redirect output to log file
$KERNEL_SRC_PATH/scripts/checkpatch.pl --strict -q --summary-file --ignore FILE_PATH_CHANGES --git $START_SHA..$END_SHA > "$log_file"

# Print the log file and update the return status
if [ -s "$log_file" ]; then
    cat "$log_file"
    exit_status=1
else
    echo "Checkpatch exited without a problem."
fi

# Clean up
rm -f "$log_file"
exit $exit_status
