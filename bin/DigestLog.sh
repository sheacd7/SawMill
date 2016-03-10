#!/bin/bash
# META =========================================================================
# Title: DigestLog.sh
# Usage: DigestLog.sh -i [log file] -o [digest file]
# Description: Digest event log file into unique elements.
# Author: Colin Shea
# Created: 2015-06-30

# TODO:
#   fix match_string regex to handle internal words
#   coalesce monoline groups 
#   get substring position for unique_strings parameter substitution by regex
#   figure out sensible unique word output formatting
#   condense numeric lists into ranges
#   diff within words on [^a-zA-Z0-9]

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
    -i|--log-file) LOG_FILE="$2";  shift;; # input log file to parse
    -o|--digest) DIGEST_FILE="$2"; shift;; # output digest file
    *) echo "Unknown option: $1";;
  esac
  shift
done

# set temp filename
TEMP_FILE="${LOG_FILE%.*}_temp.txt"

# strip blank lines
if [[ ! -f "${TEMP_FILE}" ]]; then
  sed '/^$/d' "${LOG_FILE}" > "${TEMP_FILE}"
fi

# assemble multi-line structure of each message from frequency analysis
# high skewness in frequency distribution: few v.high freq items, many unique

# sort unique lines by most frequent to least
mapfile -t uniques < <(sort "${TEMP_FILE}" | uniq -c | sort -r )
#mapfile -t uniques < <( printf '%s\n' "${arr[@]}" | sort | uniq -c | sort -r )

# [count]:(indices of unique lines)
declare -a count_groups
# [index in uniques]:(first and second line numbers in log)
declare -a log_first

# get index of last "high-freq" line
#

# get length of count field
  # calculate num bytes to cut to get exact string as it appears in log
unique_strings=( "${uniques[@]#????????}" )
unique_counts=( "${uniques[@]%%[^ 0-9]*}" )
#mapfile -t unique_strings < <(printf '%s\n' "${uniques[@]}" | cut -b 8- )
#mapfile -t unique_counts < <(printf '%s\n' "${uniques[@]}" | cut -b -7 )


# for the high-frequency items
#   coalesce multi-line records that are always together
#   group by frequency count
#   grep line number of first match of each line in group
for ((i=0; i<39; i++)); do
  count="${unique_counts[$i]}"
  string="${unique_strings[$i]}"
  count_groups[$count]="${count_groups[$count]},$i"
#  log_strings[$i]="${string}"
  log_first[$i]=$( grep -Fnxm 1 "${string}" "${LOG_FILE}" | cut -d ':' -f 1 )
done

# for each count group
#   save description of each discrete multi-line group
#     key, multi-line string
#     key, list of first lines
declare -A multiline_groups
for key in "${!count_groups[@]}"; do
#  printf '%s:\n' "$key" 
  # sort by first-match line numbers
  mapfile -t ordered_strings < \
  <(for index in ${count_groups[$key]//,/ }; do
    printf '%s,%s\n' "${log_first[$index]}" "$index"
  done | sort -g)
  # coalesce into discrete groups of continuous runs
  mlg_index=0
  mlg_line=0
  for line_index in "${ordered_strings[@]}"; do
    line="${line_index%%,*}"
    index="${line_index##*,}"
    # if not part of same contiguous multi-line group
    if [[ $line -ne $(( $mlg_line + 1 )) ]]; then
      # increment multiline group index
      : $(( mlg_index++ ))
    fi
    # append index to multiline group
    multiline_groups["$key,$mlg_index"]="${multiline_groups[$key,$mlg_index]},$index"
    mlg_line=$line 
  done
done

# print all multi-line groups
for key in "${!multiline_groups[@]}"; do
  printf '%s:\n' "$key"
  for index in ${multiline_groups[$key]//,/ }; do
    printf '  %s\n' "${unique_strings[$index]}"
  done
done > "${DIGEST_FILE}"

# group: first index in unique_strings
#        length/num indices in unique_strings
#        field nums for unique words in string
declare -A monoline_groups
declare -A monoline_fields
diff_regex='^[0-9]{1,}[,0-9]{0,}c[0-9]{1,}[,0-9]{0,}$'
# for the low-frequency items
for ((i=39; i<${#unique_strings[@]}; i++)); do # i<${#unique_strings[@]}; i++)); do 
  j=$(($i + 1))
  count1="${unique_counts[$i]}"
  string1="${unique_strings[$i]}"
  count2="${unique_counts[$j]}"
  string2="${unique_strings[$j]}"
  printf '%s\n' "$i"
  # sorting should put similar items near each other
  # diff with next item in frequency class
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
    same_words[$(( $num - 1 ))]=""
  done
  # save as string to match against other unique lines
  printf -v match_string '%s ' ${same_words[@]}
#  printf '%s\n' "${match_string}"

  # get run length of matching strings from unique_strings
  length=1
  # if current two strings have some matching words
  if [[ "${match_string}" != " " ]]; then
    for ((k=$j; k<${#unique_strings[@]}; k++)); do
      if [[ "${unique_strings[$k]}" =~ ${match_string} ]]; then
        : $((length++))
      else
        break
      fi
    done
  else
    match_string="${string1}"
    diff_word_nums=()
  fi
  printf '%s\n' "${match_string}"
  monoline_groups["${match_string}"]="${i},${length}"
  #  monoline_fields["${match_string}"]="${diff_word_nums[@]}"
  printf -v monoline_fields["${match_string}"] '%s,' "${diff_word_nums[@]}"
  monoline_fields["${match_string}"]="${monoline_fields["${match_string}"]%%,}"
  : $((i += $length - 1 ))
done

for string in "${!monoline_groups[@]}"; do 
  first_length="${monoline_groups[${string}]}"
  first="${first_length%%,*}"
  length="${first_length##*,}"

  printf '%s:\n' "${length}"
  printf '  %s\n' "${string}"
#  printf '  %s\n' "${unique_fields[@]}"
  printf '%s\n' "${monoline_fields["${string}"]}"
#  printf '%s\n' "${unique_strings[@]:$first:$length}" | \
#    awk -v fields="${monoline_fields["${string}"]}" \
#    'BEGIN { split(fields, f, ",") }
#    { for (field in f) {print $f[field]} }' 
done >> "${DIGEST_FILE}"

# print each high-frequency group
# printf '%s\n' "${words}" # group template with placeholders for uniq words
# printf '%s\n' "${uniques[@]:start:length}" | awk '{print $a $b $c...}'

#   coalesce groups that match except for these fields/words

#   assemble unique values into digests

# ==============================================================================
# Open questions
# faster to grep or search through pre-loaded array?
#   first match or all matches?
# < <() vs <<< $()
#
# useful functions to have
#   sort array by keys or by values
#   "grep" pattern in array
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
#  #   find line numbers where 875-bin messages don't appear at expected interval
#  offset=0
#  for ((i=0; i<${#lines1[@]}; i++)); do 
#    if [[ $(( ${lines1[$i]} + 9)) -ne ${lines2[$(($i - $offset))]} ]]; then 
#      : $((offset++))
#      echo "$i"
#    fi
#  done 
#   message at line numbers of expected interval represent distinct clumps
