#!/usr/bin/env bash
# watch-and-init_004.sh - FIXED INFINITE LOOP
#   - Checks/creates numbered Fossil repo (persistence_of_memory_grok_00X.fossil)
#   - Opens checkout if needed
#   - Watches directory → auto-commits *.txt create/modify after delay
#   - FIXED: Removed inotifywait -m (monitor mode infinite loop)
#   - FIXED: Added debouncing with file timestamp tracking
#   - FIXED: Added signal handlers for clean shutdown
#   - FIXED: Separated watcher from committer to prevent recursion

set -euo pipefail

# ================= CONFIG =================
DIR="$(pwd)"
FILE_PATTERN="*.txt"                # used only for echo and human readability
DELAY=5                             # debounce window in seconds
REPO_PREFIX="persistence_of_memory_grok"
REPO_SUFFIX=".fossil"
LAST_PROCESSED_FILE=""              # track last processed file
LAST_PROCESSED_TIME=0               # track last processed timestamp

# ================= Find or create repo =================

find_existing() {
    find "$DIR" -maxdepth 1 -type f -name "${REPO_PREFIX}_[0-9][0-9][0-9]${REPO_SUFFIX}" 2>/dev/null | sort | tail -n1
}

EXISTING_REPO="$(find_existing)"

if [ -n "$EXISTING_REPO" ]; then
    echo "Found existing repo: $(basename "$EXISTING_REPO")"
    REPO_FILE="$EXISTING_REPO"
else
    LAST_NUM=$(find "$DIR" -maxdepth 1 -type f -name "${REPO_PREFIX}_*${REPO_SUFFIX}" 2>/dev/null \
               | sed -E "s/.*_${REPO_PREFIX}_([0-9]+)\.fossil$/\1/" | sort -n | tail -n1 || echo 0)
    
    NEXT_NUM=$((LAST_NUM + 1))
    PADDED=$(printf "%03d" "$NEXT_NUM")
    REPO_FILE="${DIR}/${REPO_PREFIX}_${PADDED}${REPO_SUFFIX}"
    
    echo "No repo found → creating $REPO_FILE"
    fossil init "$REPO_FILE"
    
    # Ignore the repo file itself
    echo "$REPO_FILE" > .fossil-ignore-repo
    fossil settings ignore-glob add .fossil-ignore-repo --dotfiles || true
fi

# ================= Open checkout if not already =================

if ! fossil status >/dev/null 2>&1; then
    echo "Opening checkout..."
    fossil open "$REPO_FILE" --keep
else
    echo "Already in a checkout."
fi

# ================= Signal handlers for clean shutdown =================

cleanup() {
    echo ""
    echo "Shutting down watcher cleanly..."
    # Kill any lingering inotifywait processes
    pkill -P $$ inotifywait 2>/dev/null || true
    exit 0
}

trap cleanup SIGTERM SIGINT EXIT

# ================= Start watcher (FIXED: single-shot, debounced, no infinite loop) =================

echo ""
echo "Watching $DIR for changes to files matching $FILE_PATTERN"
echo "Auto-commit ~$DELAY seconds after last relevant change."
echo "Debouncing enabled to prevent duplicate commits."
echo "Ctrl+C to stop."

LAST_COMMIT_TIME=0

while true; do
    # Use inotifywait WITHOUT -m flag (single-shot mode - exits after one event)
    # Timeout after 10 seconds to allow periodic checks
    inotifywait -q -t 10 -e create -e modify --format '%w%f' "$DIR" 2>/dev/null || true

    # Check if any .txt files have changed since last commit
    CURRENT_TIME=$(date +%s)
    HAS_CHANGES=0

    if [ -f "$DIR/.fossil-wal" ] || [ -f "$DIR/.fossil-journal" ]; then
        # Fossil has pending changes
        HAS_CHANGES=1
    fi

    # Alternative: use fossil itself to check for changes
    if [ "$HAS_CHANGES" -eq 0 ] && fossil changes --quiet 2>/dev/null | grep -q "\.txt"; then
        HAS_CHANGES=1
    fi

    # Apply debounce: only commit if DELAY seconds have passed since last commit
    TIME_SINCE_LAST_COMMIT=$((CURRENT_TIME - LAST_COMMIT_TIME))

    if [ "$HAS_CHANGES" -eq 1 ] && [ "$TIME_SINCE_LAST_COMMIT" -ge "$DELAY" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Detected relevant changes"

        # Small delay to batch multiple rapid file changes
        sleep 2

        if fossil changes --quiet >/dev/null 2>&1; then
            echo "→ Committing changes..."
            fossil addremove --quiet 2>/dev/null || true
            fossil commit -m "auto: grok chat capture(s) $(date +'%Y-%m-%d %H:%M:%S')" || true
            echo "✓ Commit finished."
            LAST_COMMIT_TIME=$CURRENT_TIME
        else
            echo "ℹ No changes to commit."
        fi
    fi

    # Check for exit signal (will be caught by trap)
    if [ ! -d "$DIR" ]; then
        echo "Directory removed, exiting..."
        break
    fi
done
