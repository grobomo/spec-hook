#!/usr/bin/env bash
# Reusable screenshot tool for evidence gathering.
#
# Modes:
#   desktop  — Full desktop screenshot (shows taskbar clock)
#   command  — Run a command in a new terminal, wait, screenshot desktop
#   remote   — SSH into a worker, run a command inside container, screenshot desktop
#
# Usage:
#   bash take-screenshot.sh desktop <output.png>
#   bash take-screenshot.sh command <output.png> <command...>
#   bash take-screenshot.sh remote  <output.png> <worker_num> <command...>
#
# Dependencies: Python 3 with Pillow (pip install Pillow)
# All screenshots are full desktop with taskbar clock visible.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="${1:?Usage: take-screenshot.sh <desktop|command|remote> <output.png> [args...]}"
OUTPUT="${2:?Usage: take-screenshot.sh <mode> <output.png> [args...]}"
shift 2

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT")"

# Core: take a desktop screenshot via Python PIL
snap() {
  python -c "
from PIL import ImageGrab
img = ImageGrab.grab()
img.save(r'$1')
print('Screenshot: $1 (' + str(img.size[0]) + 'x' + str(img.size[1]) + ')')
"
}

case "$MODE" in
  desktop)
    # Just screenshot now
    snap "$OUTPUT"
    ;;

  command)
    # Open a new mintty/cmd window, run the command, wait, then screenshot
    CMD="$*"
    TMPSCRIPT=$(mktemp /tmp/ss-cmd-XXXXXX.sh)
    cat > "$TMPSCRIPT" << CMDEOF
#!/usr/bin/env bash
echo "=== Evidence Capture: \$(date '+%Y-%m-%d %H:%M:%S') ==="
echo "Command: $CMD"
echo ""
$CMD
echo ""
echo "=== Done: \$(date '+%Y-%m-%d %H:%M:%S') ==="
touch "${TMPSCRIPT}.done"
read -p "Press enter to close..." _
CMDEOF
    chmod +x "$TMPSCRIPT"

    # Launch in a visible, maximized terminal window
    if command -v mintty >/dev/null 2>&1; then
      mintty --title "SHTD Evidence" --size 200,50 --position 0,0 -e bash "$TMPSCRIPT" &
    elif command -v cmd.exe >/dev/null 2>&1; then
      cmd.exe //c start /MAX "SHTD Evidence" bash "$TMPSCRIPT" &
    else
      echo "No terminal emulator found (mintty or cmd.exe)"
      exit 1
    fi
    TERM_PID=$!

    # Wait for command to finish (poll for "=== Done ===" in terminal)
    # The read -p at the end keeps the window open after completion
    echo "Waiting for command to finish..."
    waited=0
    while [ $waited -lt 120 ]; do
      sleep 2
      waited=$((waited + 2))
      # Check if the temp script process finished (command done, waiting on read)
      # We detect this by checking if a sentinel file exists
      if [ -f "${TMPSCRIPT}.done" ]; then break; fi
    done
    # Extra pause for terminal to fully render
    sleep 2
    snap "$OUTPUT"

    # Kill the waiting terminal
    kill $TERM_PID 2>/dev/null || true
    rm -f "$TMPSCRIPT" "${TMPSCRIPT}.done"
    ;;

  remote)
    # SSH into a CCC worker container and run a command
    WORKER="${1:?Usage: take-screenshot.sh remote <output.png> <worker_num> <command...>}"
    shift
    CMD="$*"
    KEY_DIR="${HOME}/.ssh/ccc-keys"

    declare -A IPS=([1]="18.219.224.145" [2]="18.223.188.176" [3]="3.143.229.17" [4]="52.14.228.211")
    IP="${IPS[$WORKER]:-}"
    [ -z "$IP" ] && echo "Unknown worker: $WORKER" && exit 1

    TMPSCRIPT=$(mktemp /tmp/ss-remote-XXXXXX.sh)
    cat > "$TMPSCRIPT" << REMEOF
#!/usr/bin/env bash
echo "=== Evidence Capture: $(date '+%Y-%m-%d %H:%M:%S') ==="
echo "Worker: $WORKER ($IP) | Container: claude-portable"
echo "Command: $CMD"
echo ""
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "${KEY_DIR}/worker-${WORKER}.pem" ubuntu@"$IP" "docker exec claude-portable bash -c '$CMD'"
echo ""
echo "=== Done ==="
read -p "Press enter to close..." _
REMEOF
    chmod +x "$TMPSCRIPT"

    if command -v mintty >/dev/null 2>&1; then
      mintty --title "SHTD Evidence — Worker $WORKER" --size 120,40 -e bash "$TMPSCRIPT" &
    else
      cmd.exe //c start "SHTD Evidence" bash "$TMPSCRIPT" &
    fi
    TERM_PID=$!

    sleep 5
    snap "$OUTPUT"

    kill $TERM_PID 2>/dev/null || true
    rm -f "$TMPSCRIPT"
    ;;

  *)
    echo "Unknown mode: $MODE"
    echo "Usage: take-screenshot.sh <desktop|command|remote> <output.png> [args...]"
    exit 1
    ;;
esac
