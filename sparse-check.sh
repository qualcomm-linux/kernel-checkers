#!/bin/bash

# Usage:
# ./sparse-check.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

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

# Change to kernel source directory
pushd "$kernel_src" > /dev/null || exit 1
echo "Changed directory to $kernel_src"

# Initialize return status and log file
exit_status=0
log_file="sparse_errors.log"
temp_out="temp-out"

# Docker wrapper for make
kmake_image_make() {
    docker run -i --rm \
        --user "$(id -u):$(id -g)" \
        --workdir="$PWD" \
        -v "$(dirname "$PWD")":"$(dirname "$PWD")" \
        kmake-image make "$@"
}

# Check if there are any .c or .h files that were added or modified
if [ $(git diff-tree -r --name-only -M100% --diff-filter=AM $base_sha..$head_sha | grep -E '\.(c|h)$' | wc -l) -eq 0 ]; then
    echo "Skipping sparse check as nothing changed"
    popd
    exit 0
fi

kmake_image_make -s -j$(nproc) O="$temp_out" defconfig
kmake_image_make -j$(nproc) O="$temp_out" -j$(nproc) C=2 | while read -r line; do
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
echo "Leaving $kernel_src"
popd

exit $exit_status