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

# awk a file

# load a file into array

# parse log by [$1] with csplit to multiple text files (events)
time $(mapfile arr < ${IN_FILE}; for i in $(seq 1 100); do echo ${arr[@]} > /dev/null; done)

time $(for i in $(seq 1 100); do cat ${IN_FILE}; done)


# for each event
#for event in $( find -name "event-*" | sort ); do
  # split on [$2] into header, message
#  csplit -s -n 2 -f ${event}- ${event} '/^Ingesting\ package/1' '{*}'
#done


