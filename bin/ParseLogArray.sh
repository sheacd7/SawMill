#!/bin/bash
# META =========================================================================
# Title: ParseLogArray.sh
# Usage: ParseLogArray.sh -i [log file]
# Description: Parse an event log file.
# Author: Colin Shea
# Created: 2015-06-30
# TODO:
#   - rewrite to use arrays instead of temp files
#     - instead of csplit, use grep to get line numbers, save to array
#   - assemble unique values into reports
#     [message_type]-[message_num]-[line_diff_code]-[word_diff_code]-[a|b]


scriptname=$(basename $0)
function usage {
  echo "Usage: $scriptname -i [log file]"
  echo "Parse a log file."
  echo ""
  echo "  -i, --log-file    log file to parse"
  echo "  -o, --report      output report file"
  echo "  -h, --help        display help"
}

# set input values from command line arguments 
while [[ $# > 0 ]]; do
  arg="$1"
  case $arg in
    # print help
    -h|--help)
    usage
    exit
    ;;
    # log file to parse
    -i|--log-file)
    LOG_FILE="$2"
    shift
    ;;
    # output report file
    -o|--report)
    REPORT_FILE="$2"
    shift
    ;;
    *)
    # unknown option
    echo "Unknown option: $1"
    ;;
  esac
  shift
done

# prepare temp dir, temp files
source /cygdrive/c/users/sheacd/locals/SawMill_local_env.sh 
mkdir -p "${TEMP_DIR}" 
cp "${LOG_FILE}" "${TEMP_DIR}"/
cd "${TEMP_DIR}"
IN_FILE="$(basename $LOG_FILE)"

# general form
# event seperator
# ^depth
# event header string
# ^Ingesting\ package

# read file into array, strip blank lines
# - up-front performance hit, but loading into memory should be faster for 
#   subsequent tasks
# -t remove trailing newline from each line
mapfile -t arr < <( sed '/^$/d' ${IN_FILE} )

# parse log by [$1] (event line numbers)
# mapfile -t removes trailing newline
# use process substitution since pipes are processed in separate subshell
# use printf to add newlines since awk works with lines
# use awk with FNR to print line number(-1) for each match of pattern
# use - as stdin to read from pipe instead of a file
mapfile -t events < \
  <(printf '%s\n' "${arr[@]}" | awk '/^depth/ {print FNR-1}' - )

# parse log by [$2] (event header separator line numbers)
# NB: use FNR without array-indexing offset because we actually want next line
mapfile -t headers < \
  <(printf '%s\n' "${arr[@]}" | awk '/^Ingesting\ package/ {print FNR}' - )

# - message - not same for all events
# create associative array
#   key: message type (first word of each message + length in lines)
#   value: list of first line numbers
declare -A messages
# loop through messages with line numbers from headers 
# - except the last message: no end line number because we parse on the first line
for (( idx=0 ; idx < $(( ${#headers[@]} - 1 )) ; idx++ )); do
  b_ln=${headers[$idx]}
  e_ln=${events[$idx+1]}
  msg_length=$(( $e_ln - $b_ln ))
  # use first word as message type
  msg="${arr[$b_ln]%%\ *}"
  # concatenate start and end lines of message to message type
  messages["${msg}_${msg_length}"]+="$b_ln,"
done

# handle last message
idx=$(( ${#headers[@]} - 1 ))
b_ln=${headers[$idx]}
msg="${arr[$b_ln]%%\ *}"
# look for matching message type and use its message length, concatenate to list
msg_type=$( printf '%s\n' "${!messages[@]}" | grep -F -m 1 "${msg}" )
messages["${msg_type}"]+="$b_ln"

# for each message type
# parameter substitution doesn't  work with associative indices
for message_type in "${!messages[@]}"; do
  msg_length="${message_type##*_}"
  # for each message n>1, diff with n=1
  for msg_start in ${messages[$message_type]//,/ }; do
    diff <(printf '%s\n' "${arr[@]:$msg_start:$msg_length}") \
         <(printf '%s\n' "${arr[@]:$msg_start:$msg_length}")


  done
done


  # for each message_type, diff to find which lines vary using #c#
  for message_detail_file in $(find -name "${message_type}-*" | sed 's/\.\///'); do
    diff "${message_type}"-00000 "${message_detail_file}" |
    csplit -s -z -n 2 -f ${message_detail_file}- - '/^[0-9][0-9]*c[0-9][0-9]*$/' '{*}'

    # for each diff line, get diff words
    for diff_line_file in $(find -name "${message_detail_file}-*" | sed 's/\.\///'); do
      diff_line_code="$(head -1 ${diff_line_file} )"
      diff_line_a=$(grep "^<" $diff_line_file)
      diff_line_a="${diff_line_a/#< /}"
      IFS=' ' read -ra diff_line_a_arr <<< "${diff_line_a}"

      diff_line_b=$(grep "^>" $diff_line_file)
      diff_line_b="${diff_line_b/#> /}"
      IFS=' ' read -ra diff_line_b_arr <<< "${diff_line_b}"

      diff <(printf '%s\n' "${diff_line_a_arr[@]}") <(printf '%s\n' "${diff_line_b_arr[@]}") | 
      csplit -s -z -n 2 -f ${message_detail_file}-${diff_line_code}- - '/^[0-9][0-9]*c[0-9][0-9]*$/' '{*}'

      # for each diff word
      for diff_word_file in $(find -name "${message_detail_file}-${diff_line_code}-0*" | sed 's/\.\///'); do
        diff_word_code="$(head -1 ${diff_word_file} )"
        grep "^<" $diff_word_file | sed 's/^[<|>]\ //' | sed 's/\ /\n/g' \
          > ${diff_word_file}-${diff_word_code}-a
        grep "^>" $diff_word_file | sed 's/^[<|>]\ //' | sed 's/\ /\n/g' \
          > ${diff_word_file}-${diff_word_code}-b
      done
    done
  done

# diff format
# diff code
# < value
# ---
# > value

# [message_type]-[message_num]-[line_diff_code]-[word_diff_code]-[a|b]

# build array of unique diff-code patterns
# 0 - "1c1;16c16"
#   for each unique diff-code pattern
#     compile all diff-lines for each diff code
#     get list of word #s (field #s) that differ
#     use awk to print a list of the variable words
#     compose template from static words with placeholders


#       - lines that vary (#c#)
#         - for each line #
#           - wdiff (word diff): split each word to separate line
#           - list of variables for distinct words


# Report format
# message_type, count
#   message_details with numbered placeholders for variable words
#   list of variable words, 1 row for each event

# clean up temp dir
#(  && rm -r ${TEMP_DIR} )

