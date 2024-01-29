#!/bin/sh

TUNES="film animation grain stillimage fastdecode zerolatency"
TUNE=""

PRESETS="ultrafast superfast veryfast faster fast medium slow slower veryslow"
PRESET="slower"

CODEC="x264"

CRF="26" # 23 default, 0=lossless to 51=awfull

AUDIOBITRATE="128" # AAC audio bitrate in kb/s

NICENESS="15" # -20 (top prio) to 19

OUTDIR="" # Same dir as input video if empty

SAYYES=false

usage() {
  exec >&2
  [ -n "${1}" ] && printf "Error : ${1}\n"
  printf "Usage : $(basename "${0}") [options] video [video2 ...]\n"
  printf "  Encode videos with x264/x265 codec\n"
  printf "Options :\n"
  printf "  -5        : use x265 codec instead of x264\n"
  printf "  -p preset : set preset in "
    for p in ${PRESETS}; do [ "${p}" = "${PRESET}" ] && printf "[${p}]" || printf "${p}"; printf ", "; done | sed 's/, $//'; printf "\n"
  printf "  -t tune   : define tuning in "
    for t in ${TUNES}; do [ "${t}" = "${TUNE}" ] && printf "[${t}]" || printf "${t}"; printf ", "; done | sed 's/, $//'; printf "\n"
  printf "  -c x      : CRF value, from 0 (lossless) to 51 (awfull) [${CRF}]\n"
  printf "  -n x      : set process niceness, from -20 (top priority) to 19 [${NICENESS}]\n"
  printf "  -o dir    : place encoded videos in dir [same direcotry as input]\n"
  printf "  -y        : don't ask for confirmation\n"
  exit 1
}

outname() {
  local input="${1}" extension="${2:-mp4}" suffix="${3:-}"
  input="$(realpath "${input}")"
  output="$(basename "${input}")"
  output="${output%%.*}${suffix}.${extension}"
  [ -n "${OUTDIR}" ] && echo "${OUTDIR}/${output}" || echo "$(dirname "${input}")/${output}"
}

inlist() {
  local item="${1}" list=" ${2} "
  echo "${list}" | grep -qE " ${item} "
}

isdir() {
  local dir="$(realpath "${1}")" create="${2:-false}" a
  [ -n "${dir}" ] || return 1
  [ -d "${dir}" ] && return 0
  ${create} 2>/dev/null || return 2
  while true; do
    read -p "Directory '${dir}' does not exist, create it now ? ([y]/n) " a
    case "${a}" in
      ''|'y'|'Y') mkdir -p "${dir}"; return $?;;
      'n'|'N')    return 2;;
      *)          printf "Please answer with 'y' or 'n'...\n" >&2; sleep 1;;
    esac
  done
}


## Parse options
while getopts 5p:t:c:n:o:yh opt; do case "${opt}" in
  5) CODEC="x265";;
  p) inlist "${OPTARG}" "${PRESETS}" || usage "Unsupported preset '${OPTARG}'"; PRESET="${OPTARG}";;
  t) inlist "${OPTARG}" "${TUNES}"   || usage "Unsupported tuning '${OPTARG}'"; TUNE="${OPTARG}";;
  c) [ "${OPTARG}" -ge 0   -a "${OPTARG}" -le 51 ] 2>/dev/null || usage "bad CRF value '${OPTARG}'";  CRF="${OPTARG}";;
  n) [ "${OPTARG}" -ge -20 -a "${OPTARG}" -le 19 ] 2>/dev/null || usage "bad nice value '${OPTARG}'"; NICENESS="${OPTARG}";;
  o) isdir "${OPTARG}" true || usage; OUTDIR="${OPTARG}";;
  y) SAYYES="true";;
  *) usage;;
esac; done
shift $((${OPTIND} - 1))

[ -n "${PRESET}" ] && PRESET="-preset ${PRESET}"
[ -n "${TUNE}"   ] && TUNE="-tune ${TUNE}"
FFMPEG_OPTS=""
FFMPEG_OPTS="-c:v lib${CODEC} -crf ${CRF} ${PRESET} ${TUNE} "
FFMPEG_OPTS="${FFMPEG_OPTS}-c:a aac -b:a ${AUDIOBITRATE}k "


## Summary
printf "%-24s : %s\n" "FFMpeg options"   "${FFMPEG_OPTS}"
printf "%-24s : %s\n" "Output directory" "$([ -n "${OUTDIR}" ] && echo ${OUTDIR} || echo "same as input")"
printf "%-24s : %s\n" "Process niceness" "${NICENESS}"
if ! ${SAYYES}; then
  read -p "> Press Enter to continue, Ctrl+C to abort" a
  echo
fi

## Process files
for i in "$@"; do
  [ -e "${i}" ] || { printf "Error : ${i}, no such file\n" >&2; sleep 1; continue; }
  out="$(outname "${i}")"
  printf "Encoding '${i}' to '${out}', CRF=${CRF}\n" >&2
  nice -n ${NICENESS} ffmpeg -i "${i}" ${FFMPEG_OPTS} "${out}"
done
