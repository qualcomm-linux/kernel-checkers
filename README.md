# kernel-checkers
This repository provides a suite of shell scripts designed to validate
Linux kernel patches for correctness. These scripts can be run independently
or collectively using the run_scripts.sh wrapper.

### Overview
Each script performs a specific validation task, such as checking patch
formatting, validating device tree bindings, or running static analysis.
These tools are useful for kernel developers and maintainers to ensure
patch quality before submission.


## Features
**Independent Checks**: Each script can be run individually to perform a specific validation.

**Batch Execution**: Use run_scripts.sh to execute all checks in one go.

**Shell-based**: Lightweight and easy to integrate into CI pipelines.


## Scripts
**checkpatch.sh:** Runs checkpatch.pl to validate patch formatting.

**dt-binding-check.sh:** Validates device tree bindings.

**dtb-check.sh:** Checks compiled device tree blobs.

**sparse-check.sh:** Runs sparse static analysis.

**check-uapi-headers.sh:** Ensures UAPI headers are consistent.

**run_scripts.sh:** Executes all the above scripts in sequence.

## Parameters

Each script accepts the following parameters:

```
--kernel-src	Path to the Linux kernel source tree
--base		Git SHA of the base commit (typically the commit before your patch series)
--head		Git SHA of the head commit (typically the tip of your patch series)
```

## Requirements
This project depends on the [*kmake-image*](https://github.com/qualcomm-linux/kmake-image/tree/main) project,
which provides a Docker image preconfigured with all the necessary tools required to run these scripts,
including abigail-tools, sparse, yamllint, dt-schema.
Using the Docker image ensures a consistent and reproducible environment for running the checks.

### Before You Begin
You must build the Docker image from the kmake-image repository before running any of the scripts:
```
git clone https://github.com/qualcomm-linux/kmake-image.git
cd kmake-image
docker build -t kmake-image .
```

## Usage

### Run All Checks
```
./run_scripts.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>
```

### Run Individual Check
```
./checkpatch.sh --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>
```
Replace checkpatch.sh with any other script name as needed.

## License
kernel-checkers is licensed under the [*BSD-3-clause License*](https://spdx.org/licenses/BSD-3-Clause.html). See [*LICENSE*](https://github.com/qualcomm-linux/kernel-checkers/blob/main/LICENSE) for the full license text.
