#!/bin/bash
# META =========================================================================
# Title: perf.sh
# Usage: perf.sh
# Description: Performance testing scratch file.
# Author: Colin Shea
# Created: 2015-07-14

# prepare temp dir, temp files
source /cygdrive/c/users/sheacd/locals/SawMill_local_env.sh 
mkdir -p "${TEMP_DIR}" 
cp "${LOG_FILE}" "${TEMP_DIR}"/
cd "${TEMP_DIR}"
IN_FILE="$(basename $LOG_FILE)"

# -s: silent/quiet mode - don't print file sizes
# -z: elide empty output files (useful when pattern matches first line) 
# -n: use n digits in filename (may need to increase to 7)
# - : use stdin as input (from pipe command)
# use "depth" line as separator (part of ImportHandles log structure)
# {*}: no limit on number of pattern matches (repeat count until input exhausted)

# parse log by [$1] with csplit to multiple text files (events)
time $(cat "${IN_FILE}" | sed '/^$/d' | csplit -s -n 5 -f event- - '/^depth/' '{*}')

time $(csplit -s -z -n 5 -f event- ${IN_FILE} '/^depth/' '{*}')


# for each event
#for event in $( find -name "event-*" | sort ); do
  # split on [$2] into header, message
#  csplit -s -n 2 -f ${event}- ${event} '/^Ingesting\ package/1' '{*}'
#done


