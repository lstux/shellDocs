#!/bin/sh
#https://trac.ffmpeg.org/wiki/Encode/H.264
# @REQUIRED_BINS="ffmpeg dvdbackup"

BASEDIR="$(dirname "$(realpath "${0}")")"
OUTDIR="${OUTDIR:-${BASEDIR}}"
TMPDIR="${TMPDIR:-${BASEDIR}/tmp}"
DVD_DEVICE="${DVD_DEVICE:-/dev/sr0}"
ENCODE_MODE="720p"
COMBINE="false"
NICENESS="15" # -20 (top prio) to 19
DELTEMP="true"

usage() {
  exec >&2
  printf "Usage : %s [options]\n" "$(basename "${0}")"
  printf "  Rip a DVD and endcode using ffmpeg\n"
  printf "Options :\n"
  printf "  -C         : combine chapter videos to one video\n"
  printf "  -o outdir  : place encoded video(s) in outdir [%s]\n" "${OUTDIR}"
  printf "  -t tmpdir  : place temp files in tmpdir [%s]\n" "${TMPDIR}"
  printf "  -d device  : use device as DVD reader [%s]\n" "${DVD_DEVICE}"
  printf "  -m mode    : encoding mode (vtech|480p|[720p]|1080p)\n"
  printf "  -n nice    : set process niceness from -20 (top priority) to 19 [%d]\n" "${NICENESS}"
  printf "  -r tmp/dir : resume from encoding step, assuming ripped files are correct\n"
  printf "  -k         : keep temp files\n"
  printf "  -h         : display this help message\n"
  exit 1
}

ask_yesno() {
  prompt="${1}" default="${2:-}"
  case "${default}" in
    y) prompt="${prompt} ([y]/n)"; default=0;;
    n) prompt="${prompt} (y/[n])"; default=1;;
    *) prompt="${prompt} (y/n)";   default="";;
  esac
  while true; do
    printf "%s " "${prompt}" >&2
    read -r a
    case "${a}" in
      y)  return 0;;
      n)  return 1;;
      "") [ ${default} -ge 0 ] 2>/dev/null && return ${default};;
    esac
    printf "please answer with 'y' for yes or 'n' for no\n" >&2
  done
}

checkdir() {
  dir="${1}"
  [ -d "${dir}" ] && return 0
  ask_yesno "'${dir}' directory does not exist, create it now?" y || usage
  mkdir -p "${dir}" && return 0
  printf "Error : failed to create '%s' directory\n" "${dir}" >&2
  return 1
}

checkdevice() {
  dev="${1}"
  [ -b "${dev}" ] && return 0
  printf "Error : %s, no such device\n" "${dev}" >&2
  usage
}

checkinteger() {
  v="${1}" min="${2:-0}" max="${3}"
  if [ -n "${max}" ]; then
    [ "${v}" -ge "${min}" ] && [ "${v}" -le "${max}" ] && return 0
    printf "Error : value '%s' should be integer value >=%s and <=%s\n" "${v}" "${min}" "${max}" >&2
  else
    [ "${v}" -ge "${min}" ] && return 0
    printf "Error : value '%s' should be intger >=%s\n" "${v}" "${min}" >&2
  fi
  usage
}

dvdtitle() { LC_ALL=C dvdbackup -i "${DVD_DEVICE}" -I 2>/dev/null | sed -n 's/^.* with title "\([^"]\+\)".*/\1/p'; }

dorip() {
  if [ -n "$(ls "${TMPDIR}/${DVD_TITLE}/VIDEO_TS/"*.VOB 2>/dev/null)" ]; then
    printf "Warning : Seems like DVD was already ripped to '%s'\n" "${TMPDIR}/${DVD_TITLE}" >&2;
    printf "  Skipping to encoding step, remove folder if you want to force DVD rip\n" >&2;
    sleep 2
  else
    tstart="$(date +%s)"
    nice -n "${NICENESS}" dvdbackup -i "${DVD_DEVICE}" -F -p -o "${TMPDIR}"
    tend="$(date +%s)"
    duration=$((tend - tstart))
    printf "Ripped DVD in %d seconds\n" "${duration}" >&2
  fi
}

vobencode() {
  videocodec="libx264" audiocodec="aac"
  case "${1}" in
    "1080p"|"fullhd") resolution="1920:1080"; videobitrate="2M";    audiobitrate="256k";;
    "720p"|"hdready") resolution="1280:720";  videobitrate="2M";    audiobitrate="160k";;
    "480p"|"dvd")     resolution="720:480";   videobitrate="1536k"; audiobitrate="96k";;
    "vtech")          resolution="1024:578";  videobitrate="2M";    audiobitrate="128k";;
    *)                resolution="1280:720";  videobitrate="2M";    audiobitrate="160k";;
  esac
  ffmpeg_opts="-vf scale=\"${resolution}\" -c:v \"${videocodec}\" -b:v \"${videobitrate}\" -c:a \"${audiocodec}\" -b:a \"${audiobitrate}\""
  tstart="$(date +%s)"
  if ${COMBINE}; then
    inopts=""; for video in "${TMPDIR}/${DVD_TITLE}/VIDEO_TS/"*.VOB; do inopts="${inopts} -i \"${video}\""; done
    eval "nice -n \"${NICENESS}\" ffmpeg ${inopts} ${ffmpeg_opts} \"${OUTDIR}/${DVD_TITLE}.mp4\""
  else
    for video in "${TMPDIR}/${DVD_TITLE}/VIDEO_TS/"*.VOB; do
      eval "nice -n \"${NICENESS}\" ffmpeg -i \"${video}\" ${ffmpeg_opts} \"${OUTDIR}/${DVD_TITLE}/$(basename "${video}" .VOB).mp4\""
    done
  fi
  tend="$(date +%s)"
  duration=$((tend - tstart))
  printf "Encoded video in %d seconds\n" "${duration}" >&2
}


RESUMEDIR=""
while getopts Co:t:d:m:n:r:kh opt; do case "${opt}" in
  C) COMBINE=true;;
  o) OUTDIR="${OPTARG}";;
  t) TMPDIR="${OPTARG}";;
  d) DVD_DEVICE="${OPTARG}";;
  m) ENCODE_MODE="${OPTARG}";;
  n) NICENESS="${OPTARG}"; checkinteger "${NICENESS}" -20 19;;
  r) RESUMEDIR="${OPTARG}"; [ -d "${RESUMEDIR}" ] || usage;;
  k) DELTEMP="false";;
  *) usage;;
esac; done
[ -n "${OUTDIR}" ] || OUTDIR="${BASEDIR}"
[ -n "${TMPDIR}" ] || TMPDIR="${BASEDIR}/dvdbackup_tmp"


if [ -d "${RESUMEDIR}" ]; then
  DVD_TITLE="$(basename "${RESUMEDIR}")"
else
  checkdevice "${DVD_DEVICE}" || usage
  DVD_TITLE="$(dvdtitle)"
  [ -n "${DVD_TITLE}" ] || { printf "Error : can't get DVD title, is a disc inserted?..\n" >&2; usage; }
fi

printf "*** %s ***\n" "${DVD_TITLE}"
printf "  Outdir : %s\n" "${OUTDIR}"
printf "  Tmpdir : %s\n" "${TMPDIR}"
[ -d "${RESUMEDIR}" ] && printf "  Resuming\n"
printf "Press Enter to proceed, Ctrl+C to abort\n" >&2; read -r a
${COMBINE} || checkdir "${OUTDIR}/${DVD_TITLE}"
for d in "${OUTDIR}" "${TMPDIR}"; do checkdir "${d}"; done

if ! [ -d "${RESUMEDIR}" ]; then
  dorip || { rm -rf "${TMPDIR:-?}/${DVD_TITLE}"; exit 2; }
fi
if vobencode "${ENCODE_MODE}"; then
  ${DELTEMP} && rm -rf "${TMPDIR:?}/${DVD_TITLE}"
  exit 0
else
  { ${DELTEMP} && ask_yesno "Encoding failed, do you want to keep temp files?" y; } || rm -rf "${TMPDIR:?}/${DVD_TITLE}"
  exit 3
fi
