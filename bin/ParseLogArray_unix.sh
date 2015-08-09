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
  # add length to message type to disambiguate messages with identical first word
  # concatenate start line of message to list
  messages["${msg}_${msg_length}"]+="$b_ln,"
done

# handle last message (rather than use a conditional test inside loop)
idx=$(( ${#headers[@]} - 1 ))
b_ln=${headers[$idx]}
msg="${arr[$b_ln]%%\ *}"
# look for matching message type and use its message length, concatenate to list
msg_type=$( printf '%s\n' "${!messages[@]}" | grep -F -m 1 "${msg}" )
messages["${msg_type}"]+="$b_ln"

# for each message type get diff lines and words
declare -A diff_codes
# note: parameter substitution doesn't work with associative indices
for msg_type in "${!messages[@]}"; do
  echo "$msg_type"
  msg_length="${msg_type##*_}"
  # parse start line indices and save in a new array
  declare -a msg_starts
  # quoting here puts everything in one line
  msg_starts=( ${messages[$msg_type]//,/ } )
#  read -a msg_starts <<< $(printf '%s\n' ${messages[$msg_type]//,/ } )
  # get diff-code tree of line and word numbers from first 2 messages of each type
  # then use array index and awk to grab the unique fields
  #  unexpectedly this saves each word as an element instead of each line
  read -a diff_lines <<< $( diff \
    <(printf '%s\n' "${arr[@]:${msg_starts[0]}:$msg_length}") \
    <(printf '%s\n' "${arr[@]:${msg_starts[1]}:$msg_length}") )

  # get word nums for diff code and midpoint '>'
  declare -a diff_line_nums
  declare -a diff_line_idcs
  declare -a msg_bounds
  for idx in "${!diff_lines[@]}"; do
    if [[ "${diff_lines[$idx]}" =~ ^[0-9]{1,}[,0-9]{0,}c[0-9]{1,}[,0-9]{0,}$ ]]; then
      echo "${diff_lines[$idx]}"
      line_span="${diff_lines[$idx]%%c*}"
      line_first="${line_span%%,*}"
      line_last="${line_span##*,}"
      # append each word number in diff line span
      for (( num=$line_first ; num <= $line_last ; num++ )); do
        diff_line_nums+=($num)
      done
      diff_line_idcs+=($idx)
    fi
    [[ "${diff_lines[$idx]}" == ">" ]] && msg_bounds+=($idx)
  done
#  printf '%s\n' "${diff_lines[@]}"
  # for each line diff get word diff
  for idx in "${!diff_line_idcs[@]}"; do 
    start1=$(( ${diff_line_idcs[$idx]} + 2 ))
    length=$(( ${msg_bounds[$idx]} - 1 - $start1 ))
    start2=$(( ${msg_bounds[$idx]} + 1 ))
#    echo "$start1, $length, $start2"
    read -a diff_words <<< $( diff \
        <(printf '%s\n' "${diff_lines[@]:$start1:$length}") \
        <(printf '%s\n' "${diff_lines[@]:$start2:$length}") )
    # get word diff codes
#    printf '%s\n' "${diff_words[@]}"
    declare -a diff_word_nums
    for widx in "${!diff_words[@]}"; do 
      if [[ "${diff_words[$widx]}" =~ ^[0-9]{1,}[,0-9]{0,}c[0-9]{1,}[,0-9]{0,}$ ]]; then
        echo "${diff_words[$widx]}"
        word_span="${diff_words[$widx]%%c*}"
        word_first="${word_span%%,*}"
        word_last="${word_span##*,}"
        # append each word number in diff word span
        for (( num=$word_first ; num <= $word_last ; num++ )); do
          diff_word_nums+=($num)
        done
     fi
    done
    # append word diff nums to line diff num
    for widx in "${!diff_word_nums[@]}"; do
      diff_codes["${msg_type}"]+="${diff_line_nums[$idx]}W${diff_word_nums[$widx]},"
    done
  done
  unset msg_starts
  unset diff_lines
  unset diff_line_nums
  unset diff_line_idcs
  unset msg_bounds
  unset diff_words 
  unset diff_word_nums
done
for code_key in "${!diff_codes[@]}"; do
  printf '%s\n' "$code_key"
  printf '%s\n' "${diff_codes[$code_key]}"
done
# traverse line-word diff code tree
for msg_type in "${!diff_codes[@]}"; do
  # set start line for each message of this type
  declare -a msg_starts
  msg_starts=( ${messages[$msg_type]//,/ } ) 

  # unpack lines and words
  codes=( ${diff_codes[$msg_type]//,/ } )

  # for each code 
  for code in "${codes[@]}"; do
    # parse line and word numbers
    line="${code%%W*}"
    word="${code##*W}"
    # print every message at this line and word
    for start in "${msg_starts[@]}"; do
      printf '%s\n' "${arr[$(( $start + $line - 1 ))]}" 
    done | awk -v field=$word '{print $field}' > "$msg_type"."$line"."$word".txt
  done
done


# scratch ======================================================================

# diff formatting
  # --unchanged-line-format=""
  # --old-line-format=""
  # --new-line-format='%L'
# diff code: ##c## or ##,##c##,##
# < value
# ---
# > value
# ------------------------------------------------------------------------------

# Report format
# message_type, count
#   message_details with numbered placeholders for variable words
#   list of variable words, 1 row for each event

# clean up temp dir
#(  && rm -r ${TEMP_DIR} )

