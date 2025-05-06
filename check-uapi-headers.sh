#!/bin/bash

# Usage:
# ./check-uapi-headers.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>

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

# Function to check if a file contains sysfs implementation
file_has_sysfs() {
    local -r file="$1"
    grep -q 'sysfs_create_file' "$file"
    return 1
}

# Function to check if module parameters are unmodified
file_module_params_unmodified() {
    local -r file="$1"
    local -r pre_change="$(mktemp)"
    local -r post_change="$(mktemp)"

    git show "$base_sha:${file}" | awk '/^ *module_param.*\(/,/.*\);/' > "$pre_change"
    git show "$head_sha:${file}" | awk '/^ *module_param.*\(/,/.*\);/' > "$post_change"

    # Process the param data to come up with a normalized associative array of param names to param data
    # For example:
    #     module_param_call(foo, set_result, get_result, NULL, 0600);
    #
    # is processed into:
    #     pre_change_params[foo]="set_result,get_result,NULL,0600"
    #
    # This accounts for line breaks as well.

    declare -A pre_change_params
    while read -r mod_param_args; do
        param_name="$(echo "$mod_param_args" | cut -d ',' -f 1)"
        param_params="$(echo "$mod_param_args" | cut -d ',' -f 2-)"
        pre_change_params[$param_name]=$param_params
    done < <(tr -d '\t\n ' < "$pre_change" | tr ';' '\n' | grep -o '(.*)' | tr -d '()')

    declare -A post_change_params
    while read -r mod_param_args; do
        param_name="$(echo "$mod_param_args" | cut -d ',' -f 1)"
        param_params="$(echo "$mod_param_args" | cut -d ',' -f 2-)"
        post_change_params[$param_name]=$param_params
    done < <(tr -d '\t\n ' < "$post_change" | tr ';' '\n' | grep -o '(.*)' | tr -d '()')

    local mods=0
    for param_name in "${!pre_change_params[@]}"; do
        if [ ! "${post_change_params[$param_name]+set}" ]; then
            echo "Module parameter \"$param_name\" removed!"
            echo "    Original args: ${pre_change_params[$param_name]}"
            mods=$((mods + 1))
            continue
        fi

        pre="${pre_change_params[$param_name]}"
        post="${post_change_params[$param_name]}"
        if [ "$pre" != "$post" ]; then
            echo "Module parameter \"$param_name\" changed!"
            echo "    Original args: $pre"
            echo "             New args: $post"
            mods=$((mods + 1))
            continue
        fi
    done

    rm -f "$post_change" "$pre_change"

    if [ "$mods" -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Initialize return status and log file
exit_status=0
log_file="uapi_errors.log"

# Docker wrapper
kmake_image_run() {
    docker run -it --rm \
        --user "$(id -u):$(id -g)" \
        --workdir="$PWD" \
        -v "$(dirname "$PWD")":"$(dirname "$PWD")" \
        kmake-image "$@"
}

# Check if there are any .c or .h files that were added or modified
if [ $(git diff-tree -r --name-only -M100% --diff-filter=AM $base_sha..$head_sha | grep -E '\.(c|h)$' | wc -l) -eq 0 ]; then
    echo "Skipping uapi check as nothing changed"
    popd
    exit 0
fi

kmake_image_run "${kernel_src}/scripts/check-uapi.sh" -b "$head_sha" -p "$base_sha" -l "$log_file" && uapi_ret="$?" || uapi_ret="$?"

if [ "$uapi_ret" -ne 0 ]; then
    cat "$log_file"
    exit_status=1
fi

while read -r modified_file; do
    if file_has_sysfs "$modified_file"; then
        echo "File containing sysfs implementation modified: $modified_file"
        exit_status=1
    fi

    if ! file_module_params_unmodified "$modified_file"; then
        echo "Module parameter(s) modified in $modified_file"
        exit_status=1
    fi
done < <(git diff --name-only --diff-filter=AM "$base_sha" "$head_sha")

if [ "$exit_status" -ne 0 ]; then
    echo ""
    echo "To reproduce the error locally, run below command -"
    echo "./scripts/check-uapi.sh" -b "$head_sha" -p "$base_sha" -l "$log_file"
    exit_status=1
else
    echo ""
    echo "$0 passed"
fi

# Cleanup
rm -f "$log_file"
echo "Leaving $kernel_src"
popd

exit $exit_status