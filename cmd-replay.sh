#!/usr/bin/env bash
# cmd-replay.sh - replay a list of shell commands with timed pauses and screen
# clears. Made for recording README demos: start your recorder, run this, stop
# the recorder, and the same demo comes out every time.
#
#   ./cmd-replay.sh scripts/demo.script
#   ./cmd-replay.sh --pace 3 -w 45 scripts/demo.script
#   printf 'ls\n@sleep 1\npwd\n' | ./cmd-replay.sh -
#
# This only drives the terminal, it does not encode anything: pair it with a
# screen recorder (ScreenToGif on Windows, or VHS if you want the gif
# re-renderable from source).
#
# Requires bash 4+ (mapfile) and bash 5+ for --pace ($EPOCHREALTIME). Works in
# Git Bash on Windows too.

set -uo pipefail

pause=2          # seconds after each command
pace=''          # if set, per-step time budget instead of a fixed pause
type_ms=0        # 0 = print commands instantly, >0 = type them out
clear=1          # clear before each step
stop_on_error=0

# ---- prompt --------------------------------------------------------------
# The prompt is assembled from these plain strings and drawn before every
# command, the way a real Git Bash prompt looks. Edit them to match your shell.
p_user='lglen'
p_host='omen-lg'
p_env='MINGW64'
p_cwd='~/projects/cmd-replay'
p_branch='main'          # '' omits the "(main)" part

# One colour per segment: an ANSI colour number (30-37, 90-97) or '' for the
# terminal default.
col_user=32
col_env=35
col_cwd=33
col_branch=36

sgr() { if [ -n "$1" ]; then printf '\033[%sm' "$1"; fi; }

build_prompt() {
    prompt=$(sgr "$col_user")$p_user@$p_host' '
    prompt+=$(sgr "$col_env")$p_env' '
    prompt+=$(sgr "$col_cwd")$p_cwd
    [ -n "$p_branch" ] && prompt+=' '$(sgr "$col_branch")'('$p_branch')'
    prompt+=$'\033[0m'$'\n$ '
}
build_prompt

die() { printf 'cmd-replay.sh: %s\n' "$*" >&2; exit 2; }

is_num() { awk -v x="$1" 'BEGIN { exit !(x ~ /^[0-9]+([.][0-9]+)?$/) }'; }

# directive values are read as text, never expanded or eval'd
need_secs() { # $1 = directive, $2 = its value
    is_num "$2" || die "$1 needs a number of seconds, got '$2' (literal numbers only, no \$vars)"
}

usage() {
    cat <<'EOF'
cmd-replay.sh - replay commands with timed pauses and screen clears

usage: cmd-replay.sh [options] [SCRIPT]

  SCRIPT               file of commands, one per line ('-' or omitted = stdin)

options:
  -p, --pause SEC      seconds to wait after each command (default 2)
      --pace SEC       instead of a fixed pause, give each step a SEC budget:
                       wait only for the time the command itself didn't use
  -w, --type MS        type each command out at MS milliseconds per char
  -C, --no-clear       don't clear the screen
  -e, --stop-on-error  stop if a command exits non-zero
  -h, --help           this help

script syntax:
  some command         run it (eval'd, so pipes, &&, cd and export persist --
                       note `exit` therefore ends the replay)
  @sleep SEC           wait SEC extra seconds, leaving the screen as it is
  @delay SEC           wait SEC after printing the next command line, before
                       running it, so its output shows up that much later
  @pause SEC           override the pause after the command above it
  @start_output        begin literal output for the preceding command
  @end_output          end the block (the command is displayed, not run)
  # comment            ignored (blank lines too, outside output blocks)

notes:
  no pause is added after the last command. Put a trailing `@sleep SEC` in the
  script if you want the final screen to linger. The exit status is that of the
  last command that failed (0 if none did).

examples:
  ./cmd-replay.sh scripts/demo.script
  ./cmd-replay.sh --pace 3 -w 45 scripts/demo3.script
  printf 'ls\n@sleep 1\npwd\n' | ./cmd-replay.sh -
  ./cmd-replay.sh -C <<'EOS'
  git status --short
  git log --oneline -5
  EOS
EOF
}

# ---- args ----------------------------------------------------------------
while (($#)); do
    case $1 in
        -p|--pause)
            [ $# -ge 2 ] || die "$1 needs a value"
            is_num "$2" || die "$1 needs a number of seconds, got '$2'"
            pause=$2; shift 2
            ;;
        --pace)
            [ $# -ge 2 ] || die "--pace needs a value"
            is_num "$2" || die "--pace needs a number of seconds, got '$2'"
            pace=$2; shift 2
            ;;
        -w|--type)
            [ $# -ge 2 ] || die "$1 needs a value"
            is_num "$2" || die "$1 needs milliseconds per char, got '$2'"
            type_ms=$2; shift 2
            ;;
        -C|--no-clear)      clear=0; shift ;;
        -e|--stop-on-error) stop_on_error=1; shift ;;
        -h|--help)          usage; exit 0 ;;
        -|-)                break ;;
        --)                 shift; break ;;
        -*)                 die "unknown option '$1' (try --help)" ;;
        *)                  break ;;
    esac
done

[ $# -gt 1 ] && die "expected one script, got $#"
src=${1:-}

if [ -z "$src" ] || [ "$src" = "-" ]; then
    [ -t 0 ] && die "no script given and stdin is a terminal (try --help)"
    mapfile -t lines
else
    [ -f "$src" ] || die "no such file: $src"
    mapfile -t lines < "$src"
    # a shebang means a program was handed over instead of a replay script
    # (scripts/mashup.sh generates one, so it has to be run, not replayed)
    case ${lines[0]-} in
        '#!'*) die "$src is a program, run it directly: ./$src" ;;
    esac
fi

cls() { ((clear)) && printf '\033[2J\033[3J\033[H'; }

# Typing one char per sleep means one process spawn per char. That is harmless
# on Linux, but Git Bash (MSYS) falls over when it forks hundreds of times in a
# few seconds ("dofork: child died unexpectedly"), so type in chunks and cap
# spawns per line. The per-chunk delay keeps the apparent speed identical.
max_frames=40

emit() { # print "$ prompt + command", optionally typed out
    local s=$1 n i step ms d
    n=${#s}
    if ((type_ms <= 0 || n == 0)); then
        printf '%s%s\n' "$prompt" "$s"
        return
    fi
    step=$(((n + max_frames - 1) / max_frames))
    ms=$((step * type_ms))
    d=$(printf '%d.%03d' $((ms / 1000)) $((ms % 1000)))
    printf '%s' "$prompt"
    for ((i = 0; i < n; i += step)); do
        printf '%s' "${s:i:step}"
        sleep "$d"
    done
    printf '\n'
}

# ---- parse the script into parallel arrays --------------------------------
cmds=()        # command to run
pre_sleep=()   # extra wait before this command (@sleep)
pre_run=()     # wait between the command line and its output (@delay)
post_pause=()  # pause after this command overriding the default (@pause)
mock_output=() # literal output, including its line endings
has_output=()  # distinguishes an empty block from a real command
in_output=0

pending_sleep=0
pending_delay=0
for raw in ${lines[@]+"${lines[@]}"}; do
    line=${raw%$'\r'}                       # tolerate CRLF
    if ((in_output)); then
        case $line in
            @end_output) in_output=0 ;;
            @start_output) die "nested @start_output" ;;
            *) mock_output[$((${#cmds[@]} - 1))]+="$line"$'\n' ;;
        esac
        continue
    fi
    line=${line#"${line%%[![:space:]]*}"}   # ltrim
    line=${line%"${line##*[![:space:]]}"}   # rtrim
    [ -z "$line" ] && continue
    case $line in \#*) continue ;; esac

    case $line in
        @start_output)
            [ ${#cmds[@]} -gt 0 ] || die "@start_output needs a preceding command"
            idx=$((${#cmds[@]} - 1))
            [ "${has_output[idx]}" = 0 ] || die "command already has an output block"
            has_output[idx]=1
            in_output=1
            continue
            ;;
        @end_output) die "@end_output without @start_output" ;;
        '@sleep '*|'@wait '*)
            secs=${line#* }
            need_secs @sleep "$secs"
            pending_sleep=$secs
            continue
            ;;
        '@delay '*)
            secs=${line#* }
            need_secs @delay "$secs"
            pending_delay=$secs
            continue
            ;;
        '@pause '*)
            secs=${line#* }
            need_secs @pause "$secs"
            # applies to the gap after the command above it, hence the last one
            [ ${#cmds[@]} -gt 0 ] && post_pause[$((${#cmds[@]} - 1))]=$secs
            continue
            ;;
    esac

    cmds+=("$line")
    pre_sleep+=("$pending_sleep")
    pre_run+=("$pending_delay")
    post_pause+=('')
    mock_output+=('')
    has_output+=(0)
    pending_sleep=0
    pending_delay=0
done
((in_output)) && die "@start_output without @end_output"

# ---- replay ---------------------------------------------------------------
last=$((${#cmds[@]} - 1))
final_rc=0
for ((i = 0; i <= last; i++)); do
    # wait before clearing, so the previous output stays on screen meanwhile
    [ "${pre_sleep[i]}" != 0 ] && sleep "${pre_sleep[i]}"

    cls   # every step starts on a clean screen, the launching line included

    emit "${cmds[i]}"

    # hold on the finished command line, so an instant command still looks like
    # it took a moment; the clock starts first, so --pace counts the hold
    start=$EPOCHREALTIME
    [ "${pre_run[i]}" != 0 ] && sleep "${pre_run[i]}"

    if [ "${has_output[i]}" = 1 ]; then
        printf '%s' "${mock_output[i]}"
        rc=0
    else
        eval "${cmds[i]}"
        rc=$?
    fi
    end=$EPOCHREALTIME

    if ((rc != 0)); then
        printf '\033[31m[exit %s]\033[0m\n' "$rc"
        final_rc=$rc
        ((stop_on_error)) && exit "$rc"
    fi

    ((i == last)) && break   # nothing to wait for after the final command

    if [ -n "${post_pause[i]}" ]; then
        wait_for=${post_pause[i]}
    elif [ -n "$pace" ]; then
        elapsed=$(awk -v a="$start" -v b="$end" 'BEGIN { printf "%.3f", b - a }')
        wait_for=$(awk -v p="$pace" -v d="$elapsed" \
            'BEGIN { x = p - d; if (x < 0) x = 0; printf "%.3f", x }')
    else
        wait_for=$pause
    fi

    sleep "$wait_for"
done

# a trailing @sleep is a deliberate hold on the final screen
if [ "$pending_sleep" != 0 ]; then
    sleep "$pending_sleep"
fi

# report the last failure even when -e is off, so callers notice
exit "$final_rc"
