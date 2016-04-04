#!/bin/bash
# META =========================================================================
# Title: DigestLog.sh
# Usage: DigestLog.sh -i [log file] -o [digest file]
# Description: Digest event log file into unique elements.
# Author: Colin Shea
# Created: 2015-06-30

# TODO:
#   coalesce monoline groups with multiline groups
#   figure out sensible unique word output formatting
#     try to collate columns of related fields
#   condense numeric lists into ranges
#   condense paths to tree
#   diff within words on [^a-zA-Z0-9]
#   formalize criterion for splitting between high-freq and low-freq lines

# DONE:
#   find merge-able mono-line groups in first loop to avoid looping over groups
#     multiple times (once per level of nested fields)
#   handle literal '[' and ']' in log text (breaking regex match)
#   calculate substring position for to split strings w/ parameter substitution
#   fix match_string regex to handle internal words

scriptname=$(basename $0)
function usage {
  echo "Usage: $scriptname -i [log file] -o [digest file]"
  echo "Parse a log file."
  echo ""
  echo "  -i, --log-file    log file to parse"
  echo "  -o, --digest      output digest file"
  echo "  -h, --help        display help"
}

# set input values from command line arguments 
while [[ $# > 0 ]]; do
  arg="$1"
  case $arg in
    -h|--help) usage; exit;;               # print help
    -i|--log-file)  LOG_FILE="$2"; shift;; # input log file to parse
    -o|--digest) DIGEST_FILE="$2"; shift;; # output digest file
    *) echo "Unknown option: $1";;
  esac
  shift
done

# set temp filename
base_name=$(basename ${LOG_FILE})
dir_name=$(dirname ${LOG_FILE})
TEMP_FILE="${dir_name}/${base_name%.*}_temp.txt"

# strip blank lines
if [[ ! -f "${TEMP_FILE}" ]]; then
  sed '/^$/d' "${LOG_FILE}" > "${TEMP_FILE}"
fi

# functions
diff_regex='^[0-9]{1,}[,0-9]{0,}c[0-9]{1,}[,0-9]{0,}$'
word_regex="[^ ]+"
# applies diff to two strings
# outputs (to global namespace):
#   diff_word_nums - array of words/fields that differ between strings
#   match_regex    - a regex pattern that will match both strings
#   match_string   - a string consisting of only the words in both strings
function diff_strings {
  string1=${1}
  string2=${2}

  # diff strings (each word as separate line)
  read -a diff_output <<< $( diff \
    <(printf '%s\n' ${string1} ) \
    <(printf '%s\n' ${string2} ) )

  # build array of fields/words that are different
  diff_word_nums=()
  for idx in "${!diff_output[@]}"; do 
    # only match 'c'hanged words (ignore 'a'dded/'d'eleted)
    if [[ "${diff_output[$idx]}" =~ $diff_regex ]]; then
#      echo "${diff_output[$idx]}"
      diff_span="${diff_output[$idx]%%c*}"
      diff_first="${diff_span%%,*}"
      diff_last="${diff_span##*,}"
      # append each word number in diff span
      for (( num=$diff_first ; num<=$diff_last ; num++ )); do
        diff_word_nums+=($num)
      done
    fi
  done

  # construct new string without diff_words
  same_words=()
  IFS=' ' read -r -a same_words <<< ${string1}
  for num in ${diff_word_nums[@]}; do 
  # words[$(( $num - 1 ))]='"[^ ]*"'
    same_words[$(( $num - 1 ))]="${word_regex}"
  done
  # save as string to match against other unique lines
  printf -v match_regex '%s ' ${same_words[@]}
  # escape any literal '[' or ']' in regex
  match_regex="${match_regex// \[ / \\[ }"
  match_regex="${match_regex// \] / \\] }"
  # remove trailing space
  match_regex="${match_regex% }"
  match_string="${match_regex//"$word_regex"/}"
}


# assemble multi-line structure of each message from frequency analysis
# high skewness in frequency distribution: few v.high freq items, many unique

# sort unique lines by most frequent to least
mapfile -t uniques < <(sort "${TEMP_FILE}" | uniq -c | sort -r )
#mapfile -t uniques < <( printf '%s\n' "${arr[@]}" | sort | uniq -c | sort -r )

# get index of last "high-freq" line
#

# get length of count field
# calculate num chars at front from uniq -c formatting (whitespace and count #)
x="${uniques[0]%%[0-9] *}"
pos=$(( ${#x} + 2))
mask=""
for ((i=0; i<$pos; i++)); do
  mask="$mask?"
done
unique_strings=( "${uniques[@]#$mask}" )
unique_counts=( "${uniques[@]%%[^ 0-9]*}" )
unique_counts=( "${unique_counts[@]// /}" )
#unique_counts=( "${uniques[@]:0:$pos}" )
#unique_strings=( "${uniques[@]#????????}" )

# for the high-frequency items
#   coalesce multi-line records that are always together
#   group by frequency count
#   grep line number of first match of each line in group
declare -a count_groups   # [count]:(indices of unique lines)
declare -a first_line     # [index in uniques]:(first line number in log)
for ((i=0; i<39; i++)); do
  count="${unique_counts[$i]}"
  string="${unique_strings[$i]}"
  count_groups[$count]="${count_groups[$count]},$i"
  first_line[$i]=$( grep -Fnxm 1 "${string}" "${TEMP_FILE}" | cut -d ':' -f 1 )
done

# for each count group
#   save description of each contiguous multi-line group
declare -a multiline_string_indcs # key, indices of unique strings in group
declare -a multiline_group_counts # key, count
declare -a multiline_line_numbers # key, line numbers of first string in group
mlg_key=0
for count in "${!count_groups[@]}"; do
  # sort by first line num
  mapfile -t ordered_strings < \
  <(for idx in ${count_groups[$count]//,/ }; do
    printf '%s,%s\n' "${first_line[$idx]}" "$idx"
  done | sort -g)

  # coalesce into groups of continuous runs
  mlg_line=0
  for line_idx in "${ordered_strings[@]}"; do
    line="${line_idx%%,*}"
    idx="${line_idx##*,}"
    # if not part of same contiguous multi-line group
    if [[ $line -ne $(( $mlg_line + 1 )) ]]; then
      # new group; increment multiline group key
      : $(( mlg_key++ ))
      multiline_group_counts[$mlg_key]="${count}"
    fi
    # append index to multiline group
    multiline_string_indcs[$mlg_key]+=",$idx"
    mlg_line=$line 
  done
done

# get list of line numbers for first string in each group
for mlg_key in "${!multiline_string_indcs[@]}"; do
  multiline_string_indcs[$mlg_key]="${multiline_string_indcs[$mlg_key]:1}"
  first_index="${multiline_string_indcs[$mlg_key]%%,*}"
  first_string="${unique_strings[$first_index]}"
  multiline_line_numbers[$mlg_key]=$(grep -Fxn "${first_string}" "${TEMP_FILE}" | \
    cut -d ':' -f 1 | \
    tr '\n' ',')
done

# print all multi-line group data
for key in "${!multiline_group_counts[@]}"; do
  printf '%s:%s\n' "key"   "${key}"
  printf '%s:%s\n' "count" "${multiline_group_counts[$key]}"
  for idx in ${multiline_string_indcs[$key]//,/ }; do
    printf '  %s\n' "${unique_strings[$idx]}"
  done
  printf '%s\n' "${multiline_line_numbers[$key]}"
done > "${DIGEST_FILE}"

# save description of each mono-line group
declare -a monoline_string_indcs # key, indices of unique strings in group
declare -a monoline_group_counts # key, count (number of identical lines)
declare -a monoline_line_numbers # key, line numbers of each group in file
declare -a monoline_field_nums   # key, field numbers (words) that differ in group
declare -a monoline_strings      # key, string (words) that is the same in group

# for the low-frequency items
mlg_key=0
for ((i=39; i<${#unique_strings[@]}; i++)); do 
  : $(( mlg_key++ ))
  j=$(($i + 1))

  # calculate diff between consecutive strings
  diff_strings "${unique_strings[$i]}" "${unique_strings[$j]}"

  # get run length of matching strings in unique_strings
  length=1
  # if current two strings have some matching words
  if [[ ${#diff_word_nums[@]} -ne ${#same_words[@]} ]]; then
    for ((k=$j; k<${#unique_strings[@]}; k++)); do
      if [[ "${unique_strings[$k]}" =~ ${match_regex} ]]; then
        : $((length++))
      else
        # get new diff_word_nums, match_regex, match_string
        old_diff_word_nums=( "${diff_word_nums[@]}" )
        old_match_string="${match_string}"
        old_match_regex="${match_regex}"
        diff_strings "${unique_strings[$i]}" "${unique_strings[$k]}"
        # re-check that #diff_word_nums -ne #same_words
        if [[ ${#diff_word_nums[@]} -ne ${#same_words[@]} ]]; then
          : $((length++))
        else
          diff_word_nums=( "${old_diff_word_nums[@]}" )
          match_string="${old_match_string}"
          match_regex="${old_match_regex}"
          break
        fi
      fi
    done
  # else these strings comprise separate groups (no matching words)
  else
    match_regex="${unique_strings[$i]}"
    match_string="${unique_strings[$i]}"
    diff_word_nums=()
  fi

  # save group data
  monoline_string_indcs[$mlg_key]="${i},${length}"
  monoline_group_counts[$mlg_key]="${unique_counts[$i]}"  #"${count1}"
  monoline_strings[$mlg_key]="${match_string}"
  printf -v monoline_field_nums[$mlg_key] '%s,' "${diff_word_nums[@]}"
  monoline_field_nums[$mlg_key]="${monoline_field_nums[$mlg_key]%,}"
  monoline_line_numbers[$mlg_key]=$(grep -Exn "${match_regex}" "${TEMP_FILE}" | \
    cut -d ':' -f 1 | \
    tr '\n' ',')
  # advance iterator by run length
  : $((i += $length - 1 ))
done

# print all data for mono-line groups
for key in "${!monoline_group_counts[@]}"; do 
  printf '%s:%s\n' "key"   "${key}"
  printf '%s:%s\n' "count" "${monoline_group_counts[$key]}"

  first_length="${monoline_string_indcs[$key]}"
  first="${first_length%%,*}"
  length="${first_length##*,}"
  printf '%s:%s\n' "matches" "${length}"
#  printf '  %s\n' "${unique_strings[$first]}"
  printf '  %s\n' "${monoline_strings[$key]}"

  printf '%s\n' "${monoline_line_numbers[$key]}"

#  printf '%s\n' "${unique_strings[@]:$first:$length}" | \
#    awk -v fields="${monoline_field_nums[$key]}" \
#    'BEGIN { split(fields, f, ",") }
#    { for (field in f) {print $f[field]} }' 
done >> "${DIGEST_FILE}"


# coalesce groups
#   group by count/matches?
#   get first index in string_indcs
#   

#   assemble unique values into digests

# ==============================================================================
# Open questions
# faster to printf and grep or search through pre-loaded array?
#   first match or all matches?
# < <() vs <<< $()
# is it worth the time to pass through sed to remove blank lines?


# useful functions to have
#   sort array by keys or by values
#   "grep" pattern in array
#     pattern can be literal or regex
#     return indices(line nums), values
#   given an array of word/field indices, return string with/without those words


# scratch
#   inflection in distribution of unique line counts
#   901 -    8
#   898 -    1
#   895 -    2
#   875 -    6
#    40 -    1
#    20 -    4
#     8 -    2
#     6 -    2
#     3 -   13
#     2 ~  900
#     1 ~ 3400

#   if (1b - 1a) < (2a - 1a)
#     likely to be part of same message structure

# how to coalesce groups into multi-group structures?
# 901-875; messages match most of the time, but where do they not?
#   get array of line numbers for 901-bin and 875-bin messages
#  mapfile -t lines1 < \
#    <(grep -Fn "${h1}" GitHub/SawMill/logs/import_log.txt | cut -d ':' -f 1)
#  mapfile -t lines2 < \
#    <(grep -Fn "${h1}" GitHub/SawMill/logs/import_log.txt | cut -d ':' -f 1)
#  
#  # find line numbers where 875-bin messages don't appear at expected interval
#  offset=0
#  for ((i=0; i<${#lines1[@]}; i++)); do 
#    if [[ $(( ${lines1[$i]} + 9)) -ne ${lines2[$(($i - $offset))]} ]]; then 
#      : $((offset++))
#      echo "$i"
#    fi
#  done 
#   message at line numbers of expected interval represent distinct clumps


# log file
# hierarchical levels
#   stanzas    (all lines in stanza are identical)
#   lines [\n] (all words in line are identical)
#   words [\s] (all elems in word are identical)
#   elems [^a-zA-Z0-9]

# at each level
#   sort, uniq count, sort reverse order
#   group by count

#   note: lines need to use grep to get position info
#         words already have position info within lines
#         elems "       "                       " words
#   for each count, further group by position
#     coalesce adjacent elements into same group
#     split non-adjacent elements into new group

#   coalesce groups into multi-group structures
#     use line numbers to find consistent intervals for line groups
#     word/field numbers already known for word groups
#     lines with unique words ~ multi-line groups with unique intercalated lines


# stanza
#   [stanza id] (line ids)
#   [stanza id] (count)
#   [stanza id] ()
# line 
#   [line id] (string)
#   [line id] (diff word nums)
# word group
#   [word id] (values)

# group stanzas by positions

