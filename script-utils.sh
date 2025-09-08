#!/bin/bash

# Parse command-line arguments
parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
      --kernel-src) kernel_src=$(realpath "$2"); shift ;;
      --base) base_sha="$2"; shift ;;
      --head) head_sha="$2"; shift ;;
      *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
  done
}

# Validate required arguments
validate_args() {
  if [[ -z "$base_sha" || -z "$head_sha" || -z "$kernel_src" ]]; then
    echo "Usage: $0 --kernel-src <KERNEL_SRC_PATH> --base <BASE_SHA> --head <HEAD_SHA>"
    echo "Please pass the required arguments. Exiting..."
    exit 1
  fi

  if [ ! -d "$kernel_src" ]; then
    echo "Error: $kernel_src directory does not exist."
    exit 1
  fi
}

# Enter the kernel source directory
enter_kernel_dir() {
  pushd "$kernel_src" > /dev/null || exit 1
  echo "Changed directory to $kernel_src"
}

# Leave the kernel source directory
leave_kernel_dir() {
  echo "Leaving $kernel_src"
  popd
}

# Unified Docker wrapper function
run_in_kmake_image() {
  local cmd="$1"
  shift
  docker run -i --rm \
    --user "$(id -u):$(id -g)" \
    --workdir="$PWD" \
    -v "$(dirname "$PWD")":"$(dirname "$PWD")" \
    kmake-image "$cmd" "$@"
}

run_in_kmake_image_with_passwd() {
  local cmd="$1"
  shift

  passwd_b4=$(mktemp)
  echo "user:x:$(id -u):$(id -g):User:$PWD:/bin/bash" > "$passwd_b4"
  docker run -i --rm \
    --user "$(id -u):$(id -g)" \
    --workdir="$PWD" \
    -v "$(dirname "$PWD")":"$(dirname "$PWD")" \
    -v "$passwd_b4":/etc/passwd:ro \
    kmake-image "$cmd" "$@"

  rm -f "$passwd_b4"
}
