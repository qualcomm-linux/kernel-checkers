#!/bin/bash

# Usage:
# ./dt-binding-check.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

set -euo pipefail

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

# Docker wrapper for make
kmake_image_make() {
    docker run -i --rm \
        --user "$(id -u):$(id -g)" \
        --workdir="$PWD" \
        -v "$(dirname "$PWD")":"$(dirname "$PWD")" \
        kmake-image make "$@"
}

# Initialize
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
    popd
    exit 0
fi

# Function to validate a binding
validate_binding() {
    local binding=$1
    local check_command=$2

    kmake_image_make -j$(nproc) O="$temp_out" "$check_command" DT_SCHEMA_FILES="$binding" |& tee $log_file
    if grep -q "$binding" "$log_file"; then
        rm -f "$log_file"
        return 1
    fi
    rm -f "$log_file"
    return 0
}
# Build defconfig
kmake_image_make -s -j$(nproc) O="$temp_out" defconfig

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
echo "Leaving $kernel_src"
popd

# Print summary
echo ""
echo -e "Log Summary:\n$log_summary"

exit $exit_status