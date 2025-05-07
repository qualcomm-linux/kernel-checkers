#!/bin/bash

# Parse arguments
while [[ "$#" -gt 0 ]]; do
	case $1 in
		--kernel-src) kernel_src="$2"; shift ;;
		--pr-number) pr_number="$2"; shift ;;
		--branch) branch="$2"; shift ;;
		*) echo "Unknown parameter passed: $1"; exit 1 ;;
	esac
	shift
done

# Validate arguments
if [[ -z "$pr_number" ]]; then
	echo "No PR number provided. Exiting..."
	exit 1
fi

if [[ -z "$branch" ]]; then
	exit 1
fi

if [[ -z "$kernel_src" ]]; then
	echo "No Kernel Directory path provided. Exiting..."
	exit 1
else
	# Save the current working directory and resolve the kernel source path
	current_dir=$(pwd)
	kernel_src=$(realpath "$kernel_src")
	cd "$kernel_src" || { echo "Failed to change directory to $kernel_src"; exit 1; }
	echo "Changing directory to $kernel_src"
	echo ""
fi

# Fetch the PR and checkout to a temporary branch
git pull origin "$branch"
git fetch origin pull/"$pr_number"/head:temp
git checkout temp

# Get the SHA hashes for the base and new commits
new_commit=$(git rev-parse temp)
base_commit=$(git rev-parse temp~$(git log --oneline "$branch"..temp -- . | wc -l))
echo ""
echo "Base commit: $base_commit"
echo "New commit: $new_commit"
echo ""

# Define the scripts to run
scripts=(
	"checkpatch.sh"
	"check-uapi-headers.sh"
	"sparse-check.sh"
)

exit_status=0
# Run the scripts and collect the results
log_summary=""
for script in "${scripts[@]}"; do
	echo ""
	echo "Running $script script..."
	echo ""
	"$current_dir/$script" "$kernel_src" "$base_commit" "$new_commit"
	status=$?
	if [ $status -eq 0 ]; then
		log_summary+="$script passed\n"
	else
		exit_status=1
		log_summary+="$script failed\n"
	fi
done

# Print log summary
echo ""
echo -e "Log Summary:\n$log_summary"

# Clean the workspace
git checkout "$branch" > /dev/null 2>&1
git branch -D temp > /dev/null 2>&1

# Change back to the original directory
cd "$current_dir" || { echo "Failed to change back to the original directory"; exit 1; }
exit $exit_status