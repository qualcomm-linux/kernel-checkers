# Copyright (c) Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause-Clear

#!/bin/bash

aws_s3_data_dump() {
    local log_file="$1"
    local uapi_ret="$2"
    local topic_repo="$3"
    local base_sha="$4"
    local head_sha="$5"
    local pr="$6"

    BUCKET="s3://qli-prd-armor-gh-artifacts"

    YYYY="$(date -u +'%Y')"
    MM="$(date -u +'%m')"
    DD="$(date -u +'%d')"
    HH="$(date -u +'%H')"
    HOST="$(printf '%s' "${GITHUB_SERVER_URL}" | sed -E 's#^[a-zA-Z]+://##; s#/.*$##')"

    PREFIX="${YYYY}/${MM}/${DD}/${HH}/${HOST}/${topic_repo}/${GITHUB_REF_NAME}/${GITHUB_RUN_ID}/files"

    # temp dir
    FOLDER="$(mktemp -d 2>/dev/null || mktemp -d -t tmpdir.XXXXXX)"

    METADATA_JSON="${FOLDER}/uapi_metadata.json"
    : > "$METADATA_JSON"

    # Copy log file if exists
    if [[ -e "$log_file" ]]; then
        cp "$log_file" "$FOLDER"
    fi

    ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

    # Determine PR (JSON null or number)
    if [[ -n "${pr:-}" ]]; then
        pr_json="$pr"
    else
        pr_json="null"
    fi

    compat=$([[ ${uapi_ret:-0} -eq 1 ]] && echo "Incompatible" || echo "Compatible")

    jq -n \
      --arg topic_repo "$topic_repo" \
      --arg branch "$GITHUB_REF_NAME" \
      --arg event "$GITHUB_EVENT_NAME" \
      --arg base_sha "$base_sha" \
      --arg head_sha "$head_sha" \
      --arg timestamp "$ts" \
      --arg compat "$compat" \
      --argjson pr "$pr_json" \
      '
      {
        topic_repo: $topic_repo,
        branch:     $branch,
        event:      $event,
        base_sha:   $base_sha,
        head_sha:   $head_sha,
        pr_number:  $pr,
        timestamp:  $timestamp,
        compatibility: $compat
      }
      ' > "$METADATA_JSON"

    ERR_FILE="$(mktemp)"

    set +e
    aws s3 cp "${FOLDER}/" "${BUCKET}/${PREFIX}" \
        --recursive \
        --content-type "application/octet-stream" \
        --only-show-errors \
        2> "$ERR_FILE"
    rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
        echo "S3 upload succeeded."
    else
        reason="$(cat "$ERR_FILE")"
        echo "::error :: S3 upload FAILED (rc=$rc)"
        echo "::error :: Reason: ${reason:-No error output captured}"
    fi

    rm -f "$ERR_FILE"
}