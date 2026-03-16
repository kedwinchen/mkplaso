#!/usr/bin/env bash

set -eEuo pipefail

# Comma-separated list of parsers to use
# It is recommended to do multiple passes to reduce processing time to get the first "useable" timeline,
# since often times we do not immediately care about things like $MFT, $UsnJrnl, SystemD journal, or file stat,
# despite those data sources taking the longest to parse.
# Recommended parsers for dedicated passes:
# - Windows: mft,usnjrnl,filestat
# - Linux: systemd_journal,filestat
# Default is to run all parsers, to ensure all relevant information is collected, though
PARSERS_REQUESTED="${1:-all}"

# Leader file to process (relative to plaso_input)
# This is used for processing files such as multi-part VMDK
# or multi-part EWF files (e.g., .E01, .E02, .E03, ...)
LEADER_FILE="${2:+/${2}}"

# Extra arguments to pass to log2timeline
# For example, you can pass `--credential recovery_password:XXXXXX-XXXXXX-...`
# to decrypt a Bitlocker volume
EXTRA_ARGS=("${@:3}")

# Set this to true if running this script outside of a container
RUN_LOCALLY="${RUN_LOCALLY:-false}"

# Set this to true if running are running in an interactive console
# This will make the status view prettier and update more often
INTERACTIVE_CONSOLE="${INTERACTIVE_CONSOLE:-false}"

# If running in container, this should be empty
BASE_DIR=''

# Set some configurations if running locally
if [[ "${RUN_LOCALLY}" == 'true' ]]; then
  BASE_DIR="$(realpath "$(pwd)")"
  INTERACTIVE_CONSOLE='true'
fi

# Note that if running locally, the current working directory must have a plaso_input directory
PLASO_INPUT_DIR="${BASE_DIR}/plaso_input"
# Please be sure that the plaso_output directory can be written to if it exists,
# or that the user can create it.
PLASO_OUTPUT_DIR="${BASE_DIR}/plaso_output"
PLASO_TMP_DIR="${BASE_DIR}/plaso_tmp"

# This is better for non-interactive environments where control characters are not ideal
PLASO_STATUS_VIEW='linear'
PLASO_STATUS_INTERVAL='60'

if [[ "${INTERACTIVE_CONSOLE}" == 'true' ]]; then
  PLASO_STATUS_VIEW='window'
  PLASO_STATUS_INTERVAL='3'
fi

# Use as many workers as possible unless otherwise specified
PLASO_WORKERS="${PLASO_WORKERS:-$(nproc --ignore=1)}"

# TODO: evaluate better naming conventions
OUTPUT_NAME="$(printf 'output_%s_%s.plaso' \
  "$(printf '%s' "${PARSERS_REQUESTED}" | sed 's/!/no-/g' | tr ',' '-')" \
  "$(date --utc '+%Y%m%d_%H%M%S')")"
OUTPUT_PATH="${PLASO_OUTPUT_DIR}/${OUTPUT_NAME}"

if [[ ! -d "${PLASO_INPUT_DIR}" ]]; then
  printf '[FATAL] INPUT DIRECTORY DOES NOT EXIST!\n' >>/dev/stderr
  exit 1
fi

# Just in case they do not exist (more likely if running locally), create them
[[ ! -d "${PLASO_OUTPUT_DIR}" ]] && mkdir -vp "${PLASO_OUTPUT_DIR}"
[[ ! -d "${PLASO_TMP_DIR}" ]] && mkdir -vp "${PLASO_TMP_DIR}"

# Start Redis server
# Using Redis to store data can enable faster processing at the cost of memory usage
# as workers' outputs do not need to be saved to disk
redis-server --daemonize yes --appendonly no --save ''

if [[ "${PARSERS_REQUESTED}" == 'all' ]]; then
  PARSERS_REQUESTED=''
fi

PLASO_INPUT_FILE_PATH="${PLASO_INPUT_DIR}${LEADER_FILE}"

# Change to tmpdir as working directory, so any log2timeline logs are preserved
cd "${PLASO_TMP_DIR}"

log2timeline \
  --unattended \
  --quiet \
  --status-view "${PLASO_STATUS_VIEW}" \
  --status-view-interval "${PLASO_STATUS_INTERVAL}" \
  --workers "${PLASO_WORKERS}" \
  --temporary_directory "${PLASO_TMP_DIR}" \
  --worker-memory-limit 0 \
  --process-memory-limit 0 \
  --task-storage-format redis \
  --parsers "${PARSERS_REQUESTED}" \
  --volumes all \
  --archives all \
  --partitions all \
  --storage-file "${OUTPUT_PATH}" \
  "${EXTRA_ARGS[@]}" \
  "${PLASO_INPUT_FILE_PATH}"

# Clean up
redis-cli shutdown nosave
# Temporary files may contain information needed for debugging or other tracking purposes
# rm -rvf "${PLASO_TMP_DIR}"

set +eEuo pipefail
