#!/usr/bin/env bash
# sandbox.sh - run a second AwesomeWM on its own headless Xvfb display and dbus
# session, so visual checks (hover, click, popups, screenshots) never touch the
# user's real display, pointer or keyboard.
#
# Exit codes: 0 ok, 1 runtime failure (Xvfb/awesome did not come up), 2 bad usage.
# Prints only what the caller needs (the sandbox id, command output, errors).
set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_NAME="$(basename "${SCRIPT_PATH}")"

STATE_ROOT="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/awesome-sandbox"
AWESOME_RC="${AWESOME_RC:-${HOME}/.config/awesome/rc.lua}"
DEFAULT_SIZE='1920x1080'
SIZE_PATTERN='^[0-9]{3,5}x[0-9]{3,5}$'
CROP_PATTERN='^[0-9]+x[0-9]+\+[0-9]+\+[0-9]+$'
STARTUP_TIMEOUT_S=30
SANDBOX_GUARD='AWESOME_SANDBOX'

COMMANDS=(start exec shot stop list)
FLAGS=(--size --crop --help --completion)
SHELLS=(bash zsh fish)

usage() {
    cat <<EOF
${SCRIPT_NAME} - nested AwesomeWM on a private Xvfb display (never the user's)

Usage:
  ${SCRIPT_NAME} start [--size WxH]          start a sandbox, print its id
  ${SCRIPT_NAME} exec ID -- CMD [ARGS...]    run CMD inside sandbox ID
  ${SCRIPT_NAME} shot ID FILE [--crop WxH+X+Y]  screenshot sandbox ID to FILE (png)
  ${SCRIPT_NAME} stop ID                     stop sandbox ID and clean up
  ${SCRIPT_NAME} list                        list sandboxes and every X server in use
  ${SCRIPT_NAME} --completion bash|zsh|fish  print a completion script

Options:
  --size WxH          screen size for start            default: ${DEFAULT_SIZE}
  --crop WxH+X+Y      region for shot                  default: whole screen
  -h, --help          show this help

The display number comes from Xvfb -displayfd (the server picks a free one), so
concurrent sandboxes and other projects' Xvfb/Xephyr sessions never collide.
Each sandbox gets its own dbus session, so awesome-client inside it talks to the
sandboxed awesome, not yours. ${SANDBOX_GUARD}=1 is exported: the config skips
autostart and tag persistence. XDG_STATE_HOME points at the sandbox's temp dir.

Examples:
  # start a sandbox and keep its id
  id=\$(${SCRIPT_NAME} start)
  # confirm a clean startup inside it
  ${SCRIPT_NAME} exec "\${id}" -- awesome-client 'return tostring(awesome.startup_errors)'
  # hover a bar cell and screenshot the tooltip (the sandbox's own pointer)
  ${SCRIPT_NAME} exec "\${id}" -- xdotool mousemove 1240 12
  ${SCRIPT_NAME} shot "\${id}" /tmp/tip.png --crop 800x200+800+0
  # tear it down
  ${SCRIPT_NAME} stop "\${id}"
  # check what else is running before starting (other projects' displays)
  ${SCRIPT_NAME} list
  # bash completion (one-time, then open a new shell)
  ${SCRIPT_NAME} --completion bash > ~/.local/share/bash-completion/completions/${SCRIPT_NAME}
  # zsh
  ${SCRIPT_NAME} --completion zsh > ~/.zsh/completions/_${SCRIPT_NAME}
  # fish
  ${SCRIPT_NAME} --completion fish > ~/.config/fish/completions/${SCRIPT_NAME}.fish
EOF
}

die_usage() {
    echo "error: $1" >&2
    echo "try: ${SCRIPT_NAME} --help" >&2
    exit 2
}

die() {
    echo "error: $1" >&2
    exit 1
}

completion() {
    local fn="_${SCRIPT_NAME//[^A-Za-z0-9_]/_}"
    case "$1" in
    bash)
        cat <<EOF
${fn}() {
    local cur="\${COMP_WORDS[COMP_CWORD]}" prev="\${COMP_WORDS[COMP_CWORD-1]}"
    case "\${prev}" in
    --completion) COMPREPLY=(\$(compgen -W "${SHELLS[*]}" -- "\${cur}")); return ;;
    --size|--crop) COMPREPLY=(); return ;;
    shot) COMPREPLY=(\$(compgen -f -- "\${cur}")); return ;;
    esac
    if [[ \${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=(\$(compgen -W "${COMMANDS[*]} ${FLAGS[*]}" -- "\${cur}"))
    else
        COMPREPLY=(\$(compgen -W "${FLAGS[*]}" -- "\${cur}"))
    fi
}
complete -F ${fn} ${SCRIPT_NAME}
EOF
        ;;
    zsh)
        cat <<EOF
#compdef ${SCRIPT_NAME}
_arguments \\
    '1:command:(${COMMANDS[*]})' \\
    '--size[screen size WxH]:size:' \\
    '--crop[region WxH+X+Y]:crop:' \\
    '--completion[print completion]:shell:(${SHELLS[*]})' \\
    '(-h --help)'{-h,--help}'[show help]' \\
    '*:file:_files'
EOF
        ;;
    fish)
        local c
        for c in "${COMMANDS[@]}"; do
            echo "complete -c ${SCRIPT_NAME} -n __fish_use_subcommand -a ${c}"
        done
        echo "complete -c ${SCRIPT_NAME} -l size -r -d 'screen size WxH'"
        echo "complete -c ${SCRIPT_NAME} -l crop -r -d 'region WxH+X+Y'"
        echo "complete -c ${SCRIPT_NAME} -l completion -x -a '${SHELLS[*]}'"
        echo "complete -c ${SCRIPT_NAME} -s h -l help -d 'show help'"
        ;;
    *) die_usage "--completion must be bash|zsh|fish, got '$1'" ;;
    esac
}

state_file() {
    echo "${STATE_ROOT}/$1.env"
}

load_state() {
    local id="$1"
    [[ "${id}" =~ ^[0-9]+$ ]] || die_usage "sandbox id must be a display number, got '${id}'"
    local file
    file="$(state_file "${id}")"
    [[ -r "${file}" ]] || die_usage "no sandbox ${id} (see: ${SCRIPT_NAME} list)"
    # shellcheck source=/dev/null
    source "${file}"
}

alive() {
    [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null
}

cmd_start() {
    local size="${DEFAULT_SIZE}"
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --size) [[ $# -ge 2 ]] || die_usage "--size needs a value"; size="$2"; shift 2 ;;
        --size=*) size="${1#*=}"; shift ;;
        *) die_usage "unknown argument for start: '$1'" ;;
        esac
    done
    [[ "${size}" =~ ${SIZE_PATTERN} ]] || die_usage "--size must be WxH, got '${size}'"
    local dep
    for dep in Xvfb awesome dbus-daemon awesome-client; do
        command -v "${dep}" >/dev/null || die "missing command: ${dep}"
    done
    [[ -r "${AWESOME_RC}" ]] || die "config not readable: ${AWESOME_RC}"
    grep -rqs "${SANDBOX_GUARD}" "$(dirname "${AWESOME_RC}")/rc/autostart.lua" \
        || die "config has no ${SANDBOX_GUARD} guard in rc/autostart.lua: a nested awesome would rerun autostart"

    mkdir -p "${STATE_ROOT}"
    local tmp
    tmp="$(mktemp -d "${STATE_ROOT}/run.XXXXXX")"
    local display_fifo="${tmp}/displayfd"
    mkfifo "${display_fifo}"

    Xvfb -displayfd 3 -screen 0 "${size}x24" -nolisten tcp 3>"${display_fifo}" >"${tmp}/xvfb.log" 2>&1 &
    local xvfb_pid=$!
    local display=''
    read -r -t "${STARTUP_TIMEOUT_S}" display <"${display_fifo}" || true
    if [[ ! "${display}" =~ ^[0-9]+$ ]]; then
        kill "${xvfb_pid}" 2>/dev/null || true
        die "Xvfb did not report a display (log: ${tmp}/xvfb.log)"
    fi

    local dbus_out dbus_address dbus_pid
    dbus_out="$(dbus-daemon --session --fork --print-address=1 --print-pid=1)"
    dbus_address="$(sed -n 1p <<<"${dbus_out}")"
    dbus_pid="$(sed -n 2p <<<"${dbus_out}")"

    mkdir -p "${tmp}/state"
    DISPLAY=":${display}" \
        DBUS_SESSION_BUS_ADDRESS="${dbus_address}" \
        XDG_STATE_HOME="${tmp}/state" \
        AWESOME_SANDBOX=1 \
        awesome --config "${AWESOME_RC}" >"${tmp}/awesome.log" 2>&1 &
    local awesome_pid=$!

    cat >"$(state_file "${display}")" <<EOF
SANDBOX_DISPLAY=${display}
SANDBOX_TMP=${tmp}
SANDBOX_DBUS=${dbus_address}
SANDBOX_XVFB_PID=${xvfb_pid}
SANDBOX_DBUS_PID=${dbus_pid}
SANDBOX_AWESOME_PID=${awesome_pid}
EOF

    local waited=0
    until DISPLAY=":${display}" DBUS_SESSION_BUS_ADDRESS="${dbus_address}" \
        awesome-client 'return 1' >/dev/null 2>&1; do
        if ! alive "${awesome_pid}" || ((waited >= STARTUP_TIMEOUT_S)); then
            cmd_stop "${display}" >/dev/null 2>&1 || true
            die "awesome did not come up on :${display} (log was ${tmp}/awesome.log)"
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "${display}"
}

cmd_exec() {
    [[ $# -ge 1 ]] || die_usage "exec needs a sandbox id"
    load_state "$1"
    shift
    [[ "${1:-}" == "--" ]] && shift
    [[ $# -ge 1 ]] || die_usage "exec needs a command after the id"
    alive "${SANDBOX_AWESOME_PID}" || die "sandbox ${SANDBOX_DISPLAY} is not running (stop it and start a new one)"
    DISPLAY=":${SANDBOX_DISPLAY}" \
        DBUS_SESSION_BUS_ADDRESS="${SANDBOX_DBUS}" \
        AWESOME_SANDBOX=1 \
        "$@"
}

cmd_shot() {
    [[ $# -ge 2 ]] || die_usage "shot needs a sandbox id and an output file"
    local id="$1" file="$2" crop=''
    shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --crop) [[ $# -ge 2 ]] || die_usage "--crop needs a value"; crop="$2"; shift 2 ;;
        --crop=*) crop="${1#*=}"; shift ;;
        *) die_usage "unknown argument for shot: '$1'" ;;
        esac
    done
    [[ -z "${crop}" || "${crop}" =~ ${CROP_PATTERN} ]] || die_usage "--crop must be WxH+X+Y, got '${crop}'"
    [[ -n "${file}" ]] || die_usage "output file is empty"
    [[ -d "$(dirname "${file}")" && -w "$(dirname "${file}")" ]] || die_usage "cannot write to $(dirname "${file}")"
    command -v import >/dev/null || die "missing command: import (imagemagick)"
    local crop_args=()
    [[ -n "${crop}" ]] && crop_args=(-crop "${crop}")
    cmd_exec "${id}" -- import -window root "${crop_args[@]}" "${file}"
}

cmd_stop() {
    [[ $# -eq 1 ]] || die_usage "stop needs exactly one sandbox id"
    load_state "$1"
    local pid
    for pid in "${SANDBOX_AWESOME_PID}" "${SANDBOX_DBUS_PID}" "${SANDBOX_XVFB_PID}"; do
        if alive "${pid}"; then
            kill "${pid}" 2>/dev/null || true
        fi
    done
    case "${SANDBOX_TMP}" in
    "${STATE_ROOT}"/run.*) rm -rf -- "${SANDBOX_TMP}" ;;
    *) die "refusing to remove unexpected path: ${SANDBOX_TMP}" ;;
    esac
    rm -f -- "$(state_file "${SANDBOX_DISPLAY}")"
}

cmd_list() {
    [[ $# -eq 0 ]] || die_usage "list takes no arguments"
    echo "sandboxes:"
    local file found=0
    for file in "${STATE_ROOT}"/*.env; do
        [[ -e "${file}" ]] || continue
        found=1
        (
            # shellcheck source=/dev/null
            source "${file}"
            local status='dead'
            alive "${SANDBOX_AWESOME_PID}" && status='running'
            echo "  :${SANDBOX_DISPLAY}  ${status}"
        )
    done
    ((found)) || echo "  (none)"
    echo "X servers in use (any project, any user):"
    local sock
    for sock in /tmp/.X11-unix/X*; do
        [[ -e "${sock}" ]] || continue
        local n="${sock##*/X}"
        local owner
        if [[ -e "$(state_file "${n}")" ]]; then
            owner="awesome sandbox (${SCRIPT_NAME})"
        else
            # Xvfb -displayfd / xvfb-run -a do not put :N on the command line
            owner="$(pgrep -af "(Xvfb|Xephyr|Xorg|X) :${n}( |$)" | head -1 || true)"
        fi
        echo "  :${n}  ${owner:-unknown}"
    done
}

[[ $# -ge 1 ]] || { usage; exit 2; }
case "$1" in
-h | --help) usage ;;
--completion)
    [[ $# -eq 2 ]] || die_usage "--completion needs exactly one of: ${SHELLS[*]}"
    completion "$2"
    ;;
--completion=*) completion "${1#*=}" ;;
start | exec | shot | stop | list)
    sub="$1"
    shift
    "cmd_${sub}" "$@"
    ;;
*) die_usage "unknown command '$1'" ;;
esac
