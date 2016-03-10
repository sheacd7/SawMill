#!/bin/bash

# experiment 1 - strip pattern from large array of text
# init
TEMP_FILE="/cygdrive/c/Users/sheacd/GitHub/SawMill/logs/import_log.txt"
mapfile -t uniques < <(sort "${TEMP_FILE}" | uniq -c | sort -r )
# print array, pipe to cut, redirect to array
time $( \
  for i in {1..10}; do 
    mapfile -t unique_strings < <(printf '%s\n' "${uniques[@]}" | cut -b 8- )
    mapfile -t unique_counts < <(printf '%s\n' "${uniques[@]}" | cut -b -7 )
    unset unique_strings
    unset unique_counts
  done  
)

# array parameter substitution
time $( \
  for i in {1..10}; do 
    unique_strings=( "${uniques[@]#????????}" )
    unique_strings=( "${uniques[@]%%[^ 0-9]*}" )
    unset unique_strings
    unset unique_counts
  done  
)

real    0m9.273s
user    0m3.535s
sys     0m6.580s

real    0m1.340s
user    0m1.341s
sys     0m0.000s
