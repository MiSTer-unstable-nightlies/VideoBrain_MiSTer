#!/bin/bash
set -eu

DEVICE=/dev/ttyS1
STATE=/run/videobrain-telehack
LOG=/tmp/videobrain-telehack.log

if [ "${1:-}" = --bridge ]; then
    bridge_pid=
    previous=
    cleanup() {
        trap - EXIT INT TERM
        if [ -n "$bridge_pid" ]; then
            kill "$bridge_pid" 2>/dev/null || true
            wait "$bridge_pid" 2>/dev/null || true
        fi
        if [ -n "$previous" ]; then
            stty -F "$DEVICE" "$previous" || true
        fi
        rm -f "$STATE/pid"
    }
    trap cleanup EXIT
    trap 'exit 0' INT TERM
    echo "$$" > "$STATE/pid"
    exec 8<>"$DEVICE"
    flock -n 8 || { echo 'UART is in use.'; exit 1; }
    previous=$(stty -F "$DEVICE" -g)
    stty -F "$DEVICE" 300 raw -echo -ixon -ixoff -crtscts \
        cs8 -parenb -cstopb clocal istrip
    echo 'Waiting for F5 (Carriage Return) from Timeshare.'
    while IFS= read -r -N 1 key <&8; do
        # Bash can translate CR to LF when reading from a terminal.
        if [ "$key" = $'\r' ] || [ "$key" = $'\n' ]; then
            echo 'Connecting to Telehack.'
            TERM=dumb socat -d -d FILE:"$DEVICE" \
                EXEC:'telnet telehack.com 23',pty,setsid,ctty,rawer,echo=0 \
                8>&- 9>&- &
            bridge_pid=$!
            wait "$bridge_pid"
            exit $?
        fi
    done
    exit 1
fi

for command in flock nohup readlink stty socat telnet; do
    command -v "$command" >/dev/null || {
        echo "Required command missing: $command"
        exit 1
    }
done
[ -c "$DEVICE" ] || { echo "UART not found: $DEVICE"; exit 1; }
mkdir -p "$STATE"
exec 9>"$STATE/lock"
if ! flock -n 9; then
    if [ -r "$STATE/pid" ]; then
        read -r pid < "$STATE/pid"
        case "$pid" in
            ''|*[!0-9]*) echo 'Invalid bridge PID.'; exit 1 ;;
        esac
        kill -TERM "$pid"
        echo 'Telehack bridge stopping. Run this script again to reconnect.'
    else
        echo 'Telehack bridge is starting or stopping. Try again shortly.'
    fi
    exit 0
fi

rm -f "$STATE/pid"
nohup /bin/bash "$(readlink -f "$0")" --bridge \
    </dev/null >"$LOG" 2>&1 &
echo 'Telehack bridge started.'
echo 'Load VideoBrain, Expander 1 firmware and Timeshare.'
echo 'Set UART connection to None and UART Output to Modem.'
echo 'Return to Timeshare and press F5 to connect at 300 baud.'
echo 'Run this script again to stop the bridge.'
echo "Connection status and errors: $LOG"
