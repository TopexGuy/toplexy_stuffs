#!/bin/bash
set -o pipefail
set -u
shopt -s lastpipe

# Haha Tokens? lemme take ur time! Do ur Best ;)
BOT_TOKEN="8621768947:AAGh9WvQI5SMqeW2zetK63jxNlOaWERmqUI"
CHAT_ID="-1003937000666"

DEVICE_CODE="sky"
BUILD_HOSTNAME="topex"

USE_REPO_INIT=true
USE_REPO_SYNC=true
USE_CRAVE_RESYNC=true

PRE_INIT_CMDS=(
)

REPO_INIT_CMD="repo init -u https://gitlab.e.foundation/e/os/android.git -b a16 --git-lfs"

REMOVE_PATHS=(
)

CLONE_REPOS=(
  "https://github.com/anonytry/device_xiaomi_sky|17|device/xiaomi/sky"
)

EXPORTS=(
#  "SAKURA=true"
#  "SUVM=true"
#  "VND=true"
#  "ALRMQ=true"
)

EXTRA_CMDS=(
  "KEYS_DIR="vendor/signify/keys" SKIP_OTA=true bash <(curl -s https://raw.githubusercontent.com/TopexGuy/Signify/main/signify.sh) --auto"
)

KERNELSU_ENABLED=true
KERNELSU_BRANCH="dev"
SUSFS_ENABLED=false
SUSFS_BRANCH="gki-android12-5.10-dev"
KERNELSU_PATH="kernel/xiaomi/sky"

BUILD_CMD=". build/envsetup.sh && brunch sky user"

export TZ="Asia/Kolkata"
export BUILD_HOSTNAME
export NINJA_STATUS="[%p %f/%t] "

for dep in curl jq repo git; do
  command -v "$dep" &>/dev/null || {
    echo "missing dependency: $dep"
    exit 1
  }
done

mkdir -p out

send_msg() {
  curl -s --max-time 15 \
    -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode text="$1" \
    -d parse_mode=HTML > /dev/null \
    || echo "[warn] telegram send_msg failed" >&2
}

send_msg_id() {
  local id
  if ! id=$(curl -s --max-time 15 \
    -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode text="$1" \
    -d parse_mode=HTML \
    | jq -r '.result.message_id // empty'); then
    echo "[warn] telegram send_msg_id failed" >&2
  fi
  printf '%s' "${id:-0}"
}

edit_msg() {
  [[ "$1" == "0" || -z "$1" ]] && return 0
  curl -s --max-time 10 \
    -X POST "https://api.telegram.org/bot$BOT_TOKEN/editMessageText" \
    -d chat_id="$CHAT_ID" \
    -d message_id="$1" \
    --data-urlencode text="$2" \
    -d parse_mode=HTML > /dev/null \
    || echo "[warn] telegram edit_msg failed (id=$1)" >&2
}

format_time() {
  printf "%02dh %02dm %02ds" $(($1/3600)) $(($1%3600/60)) $(($1%60))
}

prop() {
  [[ -z "${PROP:-}" || ! -f "$PROP" ]] && return
  grep "^$1=" "$PROP" | cut -d= -f2- | head -n1
}

send_log() {
  sleep 2
  tail -n 5000 out/error.log > out/error_tail.log 2>/dev/null
  awk '
    /FAILED:/              { capture=1 }
    capture                { print }
    /missing dependencies/ { print }
    /DT_NEEDED/            { print }
    /shared_libs/          { print }
    /undefined reference/  { print }
    /duplicate symbol/     { print }
    /ninja: build stopped/ { print; capture=0 }
  ' out/error_tail.log > out/errors_only.log 2>/dev/null

  local LOG="out/errors_only.log"
  [[ ! -s "$LOG" ]] && LOG="out/error.log"

  if [[ -s "$LOG" ]]; then
    curl -s --max-time 60 \
      -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
      -F chat_id="$CHAT_ID" \
      -F document=@"$LOG" \
      -F caption="❌ Build Error Log" > /dev/null
  else
    send_msg "⚠️ No errors captured"
  fi

  rm -f out/error_tail.log out/errors_only.log
}

clone_repo() {
  local url=$1
  local branch=$2
  local dest=$3

  if [[ -d "$dest/.git" ]]; then
    echo "skip $dest"
    return 0
  fi

  [[ -d "$dest" ]] && rm -rf "$dest"

  if [[ "$branch" == "." ]]; then
    git clone --depth=1 "$url" "$dest" || {
      CLONE_OK=0
      CLONE_FAILED="$dest"
      return 1
    }
  else
    git clone --depth=1 -b "$branch" "$url" "$dest" || {
      CLONE_OK=0
      CLONE_FAILED="$dest"
      return 1
    }
  fi
}

trap 'USER_CANCELLED=1' INT TERM

LAST_EDIT_TIME=0
USER_CANCELLED=0
BUILD_STATE="Dirty"
START=$(date +%s)

send_msg "🚀 <b>Build Started</b>

📱 $DEVICE_CODE
🖥 $BUILD_HOSTNAME
⏱ $(date)"

BUILD_MARKER=$(mktemp)
touch "$BUILD_MARKER"

STEP=$(send_msg_id "⚙️ Cleaning local manifests...")
rm -rf .repo/local_manifests
edit_msg "$STEP" "✅ Cleaning local manifests"

if [[ ${#PRE_INIT_CMDS[@]} -gt 0 ]]; then
  STEP=$(send_msg_id "⚙️ Pre-init setup...")
  PRE_INIT_OK=1

  for cmd in "${PRE_INIT_CMDS[@]}"; do
    eval "$cmd" || {
      PRE_INIT_OK=0
      edit_msg "$STEP" "⚠️ Pre-init Failed: $cmd"
      break
    }
  done

  [[ $PRE_INIT_OK -eq 1 ]] && edit_msg "$STEP" "✅ Pre-init setup"
fi

if [[ $USE_REPO_INIT == true ]]; then
  STEP=$(send_msg_id "⚙️ Repo Init...")
  if $REPO_INIT_CMD >> out/error.log 2>&1; then
    edit_msg "$STEP" "✅ Repo Init"
  else
    edit_msg "$STEP" "❌ Repo Init Failed"
    send_log
    exit 1
  fi
fi

STEP=$(send_msg_id "⚙️ Syncing sources...")

SYNC_OK=0
DIRTY=0
SYNC_SKIPPED=0
SYNC_METHOD=""

SYNC_FLAGS="-c -v -j$(nproc --all) --force-sync --no-clone-bundle --no-tags"

if [[ $USE_CRAVE_RESYNC == true && -x /opt/crave/resync.sh ]]; then
  stdbuf -oL -eL /opt/crave/resync.sh 2>&1 | tee -a out/error.log
  if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    SYNC_METHOD="Crave Resync"
    SYNC_OK=1
  fi
fi

if [[ $USE_REPO_SYNC == true ]]; then
  PYTHONUNBUFFERED=1 stdbuf -oL -eL \
    repo sync $SYNC_FLAGS 2>&1 | tee -a out/error.log
  if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
    [[ -n "$SYNC_METHOD" ]] \
      && SYNC_METHOD="$SYNC_METHOD + Repo Sync" \
      || SYNC_METHOD="Repo Sync"
    SYNC_OK=1
  fi
fi

[[ $SYNC_OK -eq 0 ]] && DIRTY=1

if [[ $USE_CRAVE_RESYNC == false && $USE_REPO_SYNC == false ]]; then
  SYNC_SKIPPED=1
fi

if [[ $SYNC_SKIPPED -eq 1 ]]; then
  BUILD_STATE="Dirty"
  edit_msg "$STEP" "⏸️ Sync Skipped"
elif [[ $SYNC_OK -eq 1 ]]; then
  [[ $DIRTY -eq 0 ]] && BUILD_STATE="Clean"
  [[ $DIRTY -eq 1 ]] \
    && edit_msg "$STEP" "✅ Sync Complete (dirty)" \
    || edit_msg "$STEP" "✅ $SYNC_METHOD Done"
else
  edit_msg "$STEP" "⚠️ Sync Failed (Continuing...)"
fi

if [[ ${#REMOVE_PATHS[@]} -gt 0 ]]; then
  STEP=$(send_msg_id "⚙️ Cleaning paths...")
  for path in "${REMOVE_PATHS[@]}"; do
    rm -rf "$path"
  done
  edit_msg "$STEP" "✅ Cleaning paths"
fi

STEP=$(send_msg_id "⚙️ Cloning repos...")

CLONE_OK=1
CLONE_FAILED=""

for entry in "${CLONE_REPOS[@]}"; do
  IFS='|' read -r url branch dest <<< "$entry"
  clone_repo "$url" "$branch" "$dest"
done

if [[ $CLONE_OK -eq 1 ]]; then
  edit_msg "$STEP" "✅ Cloning repos"
else
  edit_msg "$STEP" "⚠️ Clone Failed: $CLONE_FAILED"
fi

for exp in "${EXPORTS[@]}"; do
  export "$exp"
done

set +u
. build/envsetup.sh
set -u

if [[ ${#EXTRA_CMDS[@]} -gt 0 ]]; then
  STEP=$(send_msg_id "⚙️ Extra setup...")
  EXTRA_OK=1

  for cmd in "${EXTRA_CMDS[@]}"; do
    eval "$cmd" || {
      EXTRA_OK=0
      edit_msg "$STEP" "⚠️ Extra setup Failed: $cmd"
      break
    }
  done

  [[ $EXTRA_OK -eq 1 ]] && edit_msg "$STEP" "✅ Extra setup"
fi

STEP=$(send_msg_id "⚙️ KernelSU setup...")

if [[ $KERNELSU_ENABLED == false ]]; then
  edit_msg "$STEP" "⏸️ KernelSU Skipped"
elif ! cd "$KERNELSU_PATH" 2>/dev/null; then
  edit_msg "$STEP" "⚠️ KernelSU Failed: path not found ($KERNELSU_PATH)"
else
  KSU_OK=1

  if [[ ! -d KernelSU && ! -d KernelSU-Next ]]; then
    curl -LSs \
      "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" \
      | bash -s "$KERNELSU_BRANCH" || KSU_OK=0

    if [[ $KSU_OK -eq 1 && $SUSFS_ENABLED == true ]]; then
      cd KernelSU-Next || KSU_OK=0

      if [[ $KSU_OK -eq 1 ]]; then
        wget -qO susfs_ksun.patch \
          "https://gitlab.com/simonpunk/susfs4ksu/-/raw/${SUSFS_BRANCH}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch?ref_type=heads" \
          || KSU_OK=0
      fi

      if [[ $KSU_OK -eq 1 ]]; then
        patch -p1 < susfs_ksun.patch || KSU_OK=0
      fi

      cd ..
    fi
  fi

  cd - >/dev/null

  if [[ $KSU_OK -eq 1 ]]; then
    [[ $SUSFS_ENABLED == true ]] \
      && edit_msg "$STEP" "✅ KernelSU + SUSFS setup" \
      || edit_msg "$STEP" "✅ KernelSU setup (SUSFS skipped)"
  else
    edit_msg "$STEP" "⚠️ KernelSU/SUSFS setup Failed"
  fi
fi

send_msg "🛠 <b>Build Started</b>"

rm -f out/error.log
touch out/error.log
echo "── Build started at $(date) ──" >> out/error.log

MSG_ID=$(send_msg_id "⚙️ Preparing build...")
edit_msg "$MSG_ID" "⚙️ Blueprint..."

BUILD_STARTED=0
BUILD_MSG_ID=""

MILESTONES=(1 7 17 27 37 50 60 67 78 86 94 99)
MILESTONE_IDX=0
LAST_P=0
MAX_P=0

EXIT_FILE=$(mktemp)

NINJA_FLAG=$(mktemp)
rm -f "$NINJA_FLAG"
NINJA_WATCH_LOG="out/ninja_watch.log"
> "$NINJA_WATCH_LOG"

# Watcher: out/target/product/ sirf actual ninja lines me hota hai
# soong/make module parsing me kabhi nahi — exact detection
(
  tail -f "$NINJA_WATCH_LOG" 2>/dev/null | while IFS= read -r wline; do
    if [[ "$wline" =~ \[[[:space:]]*[0-9]+%[[:space:]]+[0-9]+/[0-9]+ ]] && \
       [[ "$wline" == *"out/target/product/"* ]]; then
      touch "$NINJA_FLAG"
      break
    fi
  done
) &
NINJA_WATCHER_PID=$!

while read -r line; do
  printf '%s\n' "$line"

  if [[ $USER_CANCELLED -eq 1 ]]; then
    kill -- -$$ 2>/dev/null
    break
  fi

  if [[ $BUILD_STARTED -eq 0 && "$line" == *"Running globs"* ]]; then
    edit_msg "$MSG_ID" "✅ Blueprint
⚙️ Generating Ninja..."
  fi

  if [[ $BUILD_STARTED -eq 0 && "$line" == *"initializing Make module parser"* ]]; then
    edit_msg "$MSG_ID" "✅ Blueprint
✅ Generating Ninja
⚙️ Parsing Modules..."
  fi

  if [[ $BUILD_STARTED -eq 0 && -f "$NINJA_FLAG" ]]; then
    BUILD_STARTED=1

    rm -f "$NINJA_FLAG" "$NINJA_WATCH_LOG"
    kill "$NINJA_WATCHER_PID" 2>/dev/null

    sleep 2

    edit_msg "$MSG_ID" "✅ Blueprint
✅ Generating Ninja
✅ Parsing Modules"

    sleep 1

    BUILD_MSG_ID=$(send_msg_id "🛠 <b>Compilation Started</b>
⚙️ Progress: 0%")

    LAST_EDIT_TIME=$(date +%s)
  fi

  if [[ "$line" =~ \[[[:space:]]*([0-9]+)%[[:space:]]+([0-9]+)/([0-9]+) ]]; then
    P=${BASH_REMATCH[1]}
    N=${BASH_REMATCH[3]}

    (( P > MAX_P )) && MAX_P=$P

    if [[ $BUILD_STARTED -eq 1 ]]; then
      if (( MILESTONE_IDX < ${#MILESTONES[@]} )); then
        TARGET=${MILESTONES[$MILESTONE_IDX]}
        if (( P >= TARGET )); then
          edit_msg "$BUILD_MSG_ID" "🛠 <b>Compilation Started</b>
⚙️ Progress: ${TARGET}%"
          MILESTONE_IDX=$((MILESTONE_IDX + 1))
          LAST_EDIT_TIME=$(date +%s)
        fi
      fi

      NOW=$(date +%s)
      if (( NOW - LAST_EDIT_TIME >= 180 )); then
        edit_msg "$BUILD_MSG_ID" "🛠 <b>Compilation Started</b>
⚙️ Progress: ${P}%"
        LAST_EDIT_TIME=$NOW
      fi
    fi

    LAST_P=$P
  fi

done < <(
  set +u

  OUTER_PID=$BASHPID

  (
    sleep 30
    while kill -0 $OUTER_PID 2>/dev/null; do
      sleep 60
    done

    if [[ ! -f "$EXIT_FILE" && $USER_CANCELLED -eq 0 ]]; then
      curl -s \
        -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d text="⚠️ <b>Warning:</b> Build process disappeared unexpectedly (Server Disconnect/OOM)!" \
        -d parse_mode=HTML > /dev/null
    fi
  ) &

  WATCHDOG_PID=$!

  bash -c "$BUILD_CMD" 2>&1 | tee -a out/error.log out/ninja_watch.log

  echo "${PIPESTATUS[0]}" > "$EXIT_FILE"

  kill $WATCHDOG_PID 2>/dev/null
)

STATUS_CODE=$(cat "$EXIT_FILE" 2>/dev/null || echo 1)
rm -f "$EXIT_FILE" "$NINJA_FLAG" "$NINJA_WATCH_LOG"
kill "$NINJA_WATCHER_PID" 2>/dev/null

END=$(date +%s)
TIME=$(format_time $((END - START)))

TARGET_ID=${BUILD_MSG_ID:-$MSG_ID}

if [[ $USER_CANCELLED -eq 1 ]]; then

  edit_msg "$TARGET_ID" "⛔ <b>Build Cancelled</b>
⏱ $TIME"

  send_log

elif [[ $STATUS_CODE -ne 0 ]]; then

  FINAL_ERROR=$(grep "^FAILED:" out/error.log | tail -n1)

  [[ -z "$FINAL_ERROR" ]] && \
  FINAL_ERROR=$(grep -iE \
    "fatal error|error:|undefined reference|duplicate symbol|missing dependencies|DT_NEEDED" \
    out/error.log | tail -n1)

  edit_msg "$TARGET_ID" "❌ <b>Build Failed</b>

<code>${FINAL_ERROR:-Unknown Error}</code>

⏱ $TIME"

  send_log

else

  edit_msg "$TARGET_ID" "📦 Finalizing Build..."

  ZIP=$(find out/target/product/$DEVICE_CODE \
    -name "*.zip" \
    -newer "$BUILD_MARKER" \
    | grep -vE "ota|target_files|symbols" \
    | head -n1)

  rm -f "$BUILD_MARKER"

  if [[ -f "$ZIP" ]]; then

    NAME=$(basename "$ZIP")
    SIZE=$(du -h "$ZIP" | cut -f1)
    SHA256=$(sha256sum "$ZIP" | cut -d' ' -f1)

    PROP=$(find out/target/product/$DEVICE_CODE \
      -path "*/system/build.prop" | head -n1)
    [[ -z "$PROP" ]] && PROP=$(find out/target/product/$DEVICE_CODE \
      -name build.prop | head -n1)

    AV="N/A"
    SP="N/A"
    BUILD_TYPE="N/A"
    BUILD_UTC="N/A"
    BUILD_LOCAL="N/A"

    if [[ -n "$PROP" && -f "$PROP" ]]; then
      AV=$(prop ro.build.version.release)
      SP=$(prop ro.build.version.security_patch)
      BUILD_TYPE=$(prop ro.build.type)
      BUILD_UTC=$(prop ro.build.date)
      BUILD_LOCAL=$(TZ=Asia/Kolkata \
        date -d "@$(prop ro.build.date.utc)" \
        "+%a %b %d %I:%M:%S %p IST %Y" 2>/dev/null)
    fi

    UP_ID=$(send_msg_id "📤 Uploading build...")

    UPLOAD_OK=0

    SERVERS=$(curl -s --max-time 10 \
      https://api.gofile.io/servers \
      | jq -r '.data.servers[].name' 2>/dev/null \
      | head -n2)

    for SERVER in $SERVERS; do
      LINK=$(curl -s --max-time 1200 \
        -F "file=@$ZIP" \
        "https://$SERVER.gofile.io/uploadFile" \
        | jq -er '.data.downloadPage // empty' 2>/dev/null)
      if [[ -n "$LINK" ]]; then
        UPLOAD_OK=1
        break
      fi
    done

    if [[ $UPLOAD_OK -eq 1 ]]; then
      edit_msg "$UP_ID" "🚀 <b>Build Released</b>

<pre>
Device          : $DEVICE_CODE
Android         : $AV
Build Type      : $BUILD_TYPE
Build Status    : $BUILD_STATE
Security Patch  : $SP
Size            : $SIZE
Build Time      : $TIME
Date (UTC)      : $BUILD_UTC
Local Time      : $BUILD_LOCAL
</pre>

🔐 <b>SHA256</b>
<code>$SHA256</code>

📦 <b>Filename</b>
<code>$NAME</code>

⬇️ <a href=\"$LINK\">Download Build</a>"

    else
      edit_msg "$UP_ID" "⚠️ Gofile Upload Failed"
    fi

  else
    send_msg "❌ ZIP not found"
  fi

fi

rm -f out/error_tail.log out/errors_only.log
