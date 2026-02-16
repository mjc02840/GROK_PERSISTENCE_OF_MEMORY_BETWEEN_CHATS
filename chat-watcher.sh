#!/usr/bin/env bash
# watch-and-init_004.sh
#   - Checks/creates numbered Fossil repo (persistence_of_memory_grok_00X.fossil)
#   - Opens checkout if needed
#   - Watches directory → auto-commits *.txt create/modify after delay
#   - No --include flag (avoids Debian bug); filters in loop instead

set -euo pipefail

# ================= CONFIG =================
DIR="$(pwd)"
FILE_PATTERN="*.txt"                # used only for echo and human readability
DELAY=15                            # batch window in seconds
REPO_PREFIX="persistence_of_memory_grok"
REPO_SUFFIX=".fossil"

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

# ================= Start watcher (no --include) =================

echo ""
echo "Watching $DIR for changes to files matching $FILE_PATTERN"
echo "Auto-commit ~$DELAY seconds after last relevant change."
echo "Ctrl+C to stop."

inotifywait -m -q -e create -e modify --format '%w%f' "$DIR" |
while read -r file; do
    # Only process if it matches our pattern
    if [[ "$file" == *".txt" ]]; then
        echo "Detected relevant change: $file"
        sleep "$DELAY"
        
        if fossil changes --quiet >/dev/null; then
            echo "→ Committing..."
            fossil addremove --quiet
            fossil commit -m "auto: grok chat capture(s) $(date +'%Y-%m-%d %H:%M:%S')" || true
            echo "Commit finished."
        else
            echo "No changes to commit."
        fi
    fi
done
