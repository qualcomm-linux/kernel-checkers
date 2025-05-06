#!/bin/bash

# Usage:
# ./check-uapi-headers.sh <KERNEL_SRC_PATH> <START_SHA> <END_SHA>

# Function to check if a file contains sysfs implementation
file_has_sysfs() {
	local -r file="$1"
	grep -q 'sysfs_create_file' "$file"

	return 1
}

# Function to check if module parameters are unmodified
file_module_params_unmodified() {
	local -r file="$1"
	local -r err_log="$2"
	local -r pre_change="$(mktemp)"
	local -r post_change="$(mktemp)"

	git show "$base_sha:${file}" | awk '/^ *module_param.*\(/,/.*\);/' > "$pre_change"
	git show "$new_sha:${file}" | awk '/^ *module_param.*\(/,/.*\);/' > "$post_change"

	# Process the param data to come up with a normalized associative array of param names to param data
	# For example:
	#	 module_param_call(foo, set_result, get_result, NULL, 0600);
	#
	# is processed into:
	#	 pre_change_params[foo]="set_result,get_result,NULL,0600"
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
			{
				echo "Module parameter \"$param_name\" removed!"
				echo "	Original args: ${pre_change_params[$param_name]}"
			} | tee -a "$err_log"
			mods=$((mods + 1))
			continue
		fi

		pre="${pre_change_params[$param_name]}"
		post="${post_change_params[$param_name]}"
		if [ "$pre" != "$post" ]; then
			{
				echo "Module parameter \"$param_name\" changed!"
				echo "	Original args: $pre"
				echo "			 New args: $post"
			} | tee -a "$err_log"
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

KERNEL_SRC_PATH=$(realpath "$1")
START_SHA=$2
END_SHA=$3

# Check if kernel source directory exists
if [ ! -d "$KERNEL_SRC_PATH" ]; then
    echo "Error: $KERNEL_SRC_PATH directory does not exist."
    exit 1
fi

log="$(mktemp)"
err_log="$(mktemp)"
trap 'rm -f "$log" "$err_log"' EXIT

ret=0

# Define a function
kmake_image_run() {
	docker run -it --rm --user $(id -u):$(id -g) --workdir="$PWD" -v "$(dirname $PWD)":"$(dirname $PWD)" kmake-image "$@"
}

kmake_image_run "${KERNEL_SRC_PATH}/scripts/check-uapi.sh" -b "$END_SHA" -p "$START_SHA" -l "$log" && uapi_ret="$?" || uapi_ret="$?"

if [ "$uapi_ret" -ne 0 ]; then
	{
		tail -n 30 "$log"
	} | tee -a "$err_log"
	ret=1
fi

while read -r modified_file; do
	if file_has_sysfs "$modified_file"; then
		echo "File containing sysfs implementation modified: $modified_file" | tee -a "$err_log"
		ret=1
	fi

	if ! file_module_params_unmodified "$modified_file" "$err_log"; then
		echo "Module parameter(s) modified in $modified_file" | tee -a "$err_log"
		ret=1
	fi
done < <(git diff --name-only --diff-filter=AM "$START_SHA" "$END_SHA")

exit $ret