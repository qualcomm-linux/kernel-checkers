#!/bin/bash

# Usage:
# ./sparse-check.sh <KERNEL_SRC_PATH> <START_SHA> <END_SHA>

# Define variables
KERNEL_SRC_PATH=$(realpath "$1")
START_SHA=$2
END_SHA=$3

# Initialize return status and log file
exit_status=0
log_file="sparse_errors.log"

# Define a function to run the make command inside a Docker container
kmake_image_make() {
    docker run -it --rm --user $(id -u):$(id -g) --workdir="$PWD" -v "$(dirname $PWD)":"$(dirname $PWD)" kmake-image make "$@"
}

# Function to process sparse errors
process_sparse_errors() {
    local log_file=$1
    if [ -s $log_file ]; then
        echo "Processing sparse errors..."
        sort -u $log_file | while read -r line; do
            local fi=${line%%:*}
            local num=${line#*:}
            num=${num%%:*}
            echo "$line"
            sed -n "${num}p" "$fi"
        done
        rm -f $log_file
    fi
}

# Check if there are any .c or .h files that were added or modified
if [ $(git diff-tree -r --name-only -M100% --diff-filter=AM $START_SHA..$END_SHA | grep -E '\.(c|h)$' | wc -l) -eq 0 ]; then
    echo "Skipping sparse check as nothing changed"
    exit 0
fi

kmake_image_make -s O=../obj defconfig > /dev/null 2>&1
kmake_image_make -s O=../obj -j$(nproc) C=2 | while read -r line; do
    # Ignore lines that don't start with the current directory
    case "$line" in
        "$PWD/"*) ;;
        *) continue ;;
    esac

    # Extract file and line number from the log line
    line=${line##$PWD/}
    fi=${line%%:*}
    num=${line#*:}
    num=${num%%:*}
	
	if [[ $num =~ ^[0-9]+$ ]]; then
		# Check if the line is present in both the diff and sparse output
		git blame -L$num,+1 $START_SHA..$END_SHA -l -- "$fi" | grep -q -v '^\^' > /dev/null 2>&1
		if test $? -eq 0 ; then
			exit_status=1
			echo "$line" >> $log_file
		fi
	fi
done

# Process sparse errors if any
process_sparse_errors $log_file

# Clean up and exit
rm -rf obj
exit $exit_status
