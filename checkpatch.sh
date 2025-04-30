#!/bin/bash

# Usage:
# ./checkpatch.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

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

# Initialize return status and log file
exit_status=0
log_file="checkpatch_errors.log"

# Run checkpatch.pl script and redirect output to log file
$kernel_src/scripts/checkpatch.pl --strict --summary-file --ignore FILE_PATH_CHANGES --git $base_sha..$head_sha |& tee "$log_file"

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
fi

# Cleanup
rm -f "$log_file"
echo "Leaving $kernel_src"
popd

exit $exit_status