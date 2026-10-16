#!/bin/bash
# Finder supplies selected file paths as separate arguments.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

title='MOV → MP4'
log_file="$HOME/Library/Logs/MOV-to-MP4.log"
work_dir=''
converted=0
failed=0
skipped=0

notify() {
    [ "${MOV_TO_MP4_NO_UI:-0}" = 1 ] && return 0
    /usr/bin/osascript - "$title" "$1" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
    display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
}

report_error() {
    printf '%s\n' "$1" >&2
    [ "${MOV_TO_MP4_NO_UI:-0}" = 1 ] && return 0
    /usr/bin/osascript - "$title" "$1" <<'APPLESCRIPT' >/dev/null 2>&1 || true
on run argv
    display alert (item 1 of argv) message (item 2 of argv) as warning
end run
APPLESCRIPT
}

cleanup() {
    if [ -n "$work_dir" ]; then
        /bin/rm -rf "$work_dir"
        work_dir=''
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

ffmpeg=$(command -v ffmpeg || true)
ffprobe=$(command -v ffprobe || true)
if [ -z "$ffmpeg" ] || [ -z "$ffprobe" ]; then
    report_error 'FFmpeg was not found. Run brew install ffmpeg, then try again.'
    exit 1
fi

if [ "$#" -eq 0 ]; then
    report_error 'Select one or more MOV files in Finder.'
    exit 1
fi

if ! /bin/mkdir -p "${log_file%/*}" || ! touch "$log_file"; then
    report_error "Could not create the log file: $log_file"
    exit 1
fi

notify 'Conversion started. MP4 files will be saved next to the originals.'

# Publish complete files without replacing any existing file, directory or link.
# Hard links are fast on APFS. The exclusive-copy fallback also supports exFAT.
publish() {
    local source_file="$1" base="$2" candidate suffix=0 copy_status
    while :; do
        if [ "$suffix" -eq 0 ]; then
            candidate="${base}.mp4"
        else
            candidate="${base} (${suffix}).mp4"
        fi
        if [ -e "$candidate" ] || [ -L "$candidate" ]; then
            suffix=$((suffix + 1))
            continue
        fi
        if /bin/link "$source_file" "$candidate" 2>/dev/null; then
            printf '%s\n' "$candidate"
            return 0
        fi
        (
            set -o noclobber
            exec 3>"$candidate" || exit 10
            if /bin/cat "$source_file" >&3; then
                exit 0
            fi
            /bin/rm -f "$candidate"
            exit 1
        ) 2>>"$log_file"
        copy_status=$?
        case "$copy_status" in
            0) printf '%s\n' "$candidate"; return 0 ;;
            10)
                if [ -e "$candidate" ] || [ -L "$candidate" ]; then
                    suffix=$((suffix + 1))
                else
                    return 1
                fi
                ;;
            *) return 1 ;;
        esac
    done
}

for input_file in "$@"; do
    case "$input_file" in
        *.[mM][oO][vV]) ;;
        *) skipped=$((skipped + 1)); continue ;;
    esac
    # Absolute paths also prevent leading dashes and protocol names being parsed.
    case "$input_file" in
        /*) ;;
        *) input_file="$PWD/$input_file" ;;
    esac
    if [ ! -f "$input_file" ] || [ ! -r "$input_file" ]; then
        printf 'File is not accessible: %s\n' "$input_file" >>"$log_file"
        failed=$((failed + 1))
        continue
    fi

    printf '\n[%s] %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$input_file" >>"$log_file"
    codec=$("$ffprobe" -v error -select_streams v:0 \
        -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 \
        "$input_file" 2>>"$log_file")
    if [ -z "$codec" ]; then
        printf 'No video stream found.\n' >>"$log_file"
        failed=$((failed + 1))
        continue
    fi

    if ! work_dir=$(/usr/bin/mktemp -d "${input_file%/*}/.mov-to-mp4.XXXXXX" 2>>"$log_file"); then
        failed=$((failed + 1))
        continue
    fi
    case "$codec" in
        h264) video_options=(-c:v copy) ;;
        hevc) video_options=(-c:v copy -tag:v hvc1) ;;
        *) video_options=(-c:v libx264 -preset fast -crf 18
            -vf 'pad=ceil(iw/2)*2:ceil(ih/2)*2' -pix_fmt yuv420p) ;;
    esac
    if "$ffmpeg" -hide_banner -loglevel error -nostdin -n \
        -i "$input_file" -map 0:v:0 -map '0:a?' \
        "${video_options[@]}" -c:a aac -b:a 192k \
        -movflags +faststart "$work_dir/converted.mp4" 2>>"$log_file"; then
        if publish "$work_dir/converted.mp4" "${input_file%.*}"; then
            converted=$((converted + 1))
        else
            printf 'Could not save the MP4 file.\n' >>"$log_file"
            failed=$((failed + 1))
        fi
    else
        failed=$((failed + 1))
    fi
    cleanup
done

if [ "$failed" -gt 0 ]; then
    report_error "MP4 files created: $converted. Failed: $failed. Skipped: $skipped.
Details: $log_file"
    exit 1
fi
if [ "$converted" -eq 0 ]; then
    report_error 'The selection does not contain any MOV videos.'
    exit 1
fi
notify "Done! MP4 files created: $converted. Skipped: $skipped."
