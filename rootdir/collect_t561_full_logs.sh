#!/system/bin/sh
#
# Samsung SM-T561 / gtel3g generic debug logger.
#
# Unfiltered logcat, kernel snapshots and rotating device-state snapshots.
# Logs are stored directly in /cache; no archives are created.
#
# Stop and collect:
#   adb root
#   adb shell touch /cache/t561-logs/current/STOP
#   adb shell 'while [ "$(getprop init.svc.t561-debug-logs)" != stopped ]; do sleep 1; done'
#   adb pull /cache/t561-logs .
#

PATH=/sbin:/system/sbin:/system/bin:/system/xbin:/vendor/bin
export PATH

BASE=/cache/t561-logs
CURRENT=$BASE/current
PREVIOUS=$BASE/previous
STOPFILE=$CURRENT/STOP

WATCH_INTERVAL=5
SNAPSHOT_INTERVAL=30
SNAPSHOT_SLOTS=12
MAX_BOOT_WAIT=300
MIN_CACHE_FREE_KB=32768

# Roughly 32 MiB maximum for the continuous Android log.
LOGCAT_ROTATE_KB=4096
LOGCAT_ROTATE_COUNT=8

LOGCAT_PID=""
REQUEST_STOP=0
BOOT_SNAPSHOT_SAVED=0
SNAPSHOT_INDEX=0
START_EPOCH=$(date +%s 2>/dev/null)

umask 022

kmsg()
{
    echo "T561_DEBUG_LOGGER: $*" > /dev/kmsg 2>/dev/null
}

section()
{
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

safe_cat()
{
    FILE="$1"

    if [ -r "$FILE" ]; then
        cat "$FILE" 2>&1
    elif [ -e "$FILE" ]; then
        echo "EXISTS BUT NOT READABLE: $FILE"
    else
        echo "MISSING: $FILE"
    fi
}

dump_files()
{
    for FILE in "$@"; do
        echo
        echo "----- $FILE -----"
        safe_cat "$FILE"
    done
}

dump_existing_globs()
{
    for FILE in "$@"; do
        [ -e "$FILE" ] || continue
        echo
        echo "----- $FILE -----"
        safe_cat "$FILE"
    done
}

elapsed()
{
    NOW=$(date +%s 2>/dev/null)

    if [ -n "$START_EPOCH" ] && [ -n "$NOW" ]; then
        echo $((NOW - START_EPOCH))
    else
        echo 0
    fi
}

request_stop()
{
    REQUEST_STOP=1
}

stop_logcat()
{
    if [ -n "$LOGCAT_PID" ]; then
        kill "$LOGCAT_PID" 2>/dev/null
        wait "$LOGCAT_PID" 2>/dev/null
        LOGCAT_PID=""
    fi
}

start_logcat()
{
    if [ -n "$LOGCAT_PID" ] &&
       kill -0 "$LOGCAT_PID" 2>/dev/null; then
        return
    fi

    echo "$(date) starting logcat" >> "$CURRENT/logger_events.txt"

    logcat -b all -v threadtime \
        -f "$CURRENT/logcat_live.txt" \
        -r "$LOGCAT_ROTATE_KB" \
        -n "$LOGCAT_ROTATE_COUNT" \
        >/dev/null 2>&1 &

    LOGCAT_PID=$!

    echo "$(date) logcat_pid=$LOGCAT_PID" \
        >> "$CURRENT/logger_events.txt"
}

prepare_log_directory()
{
    if [ "$BASE" != "/cache/t561-logs" ]; then
        kmsg "unsafe log directory; aborting"
        exit 1
    fi

    mkdir -p "$BASE" || exit 1

    # Keep one previous session so a failed boot is not erased immediately.
    rm -rf "$PREVIOUS"

    if [ -d "$CURRENT" ]; then
        mv "$CURRENT" "$PREVIOUS"
    elif [ -e "$CURRENT" ]; then
        rm -f "$CURRENT"
    fi

    mkdir -p "$CURRENT" || exit 1

    chmod 0755 "$BASE" "$CURRENT"
    [ ! -d "$PREVIOUS" ] || chmod 0755 "$PREVIOUS"
}

save_pstore()
{
    for FILE in /sys/fs/pstore/*; do
        [ -r "$FILE" ] || continue

        NAME=${FILE##*/}
        cat "$FILE" > "$CURRENT/pstore_$NAME" 2>&1
    done
}

save_early_logs()
{
    dmesg > "$CURRENT/dmesg_early.txt" 2>&1

    logcat -b all -v threadtime -d \
        > "$CURRENT/logcat_early.txt" 2>&1

    getprop > "$CURRENT/getprop_early.txt" 2>&1

    [ ! -r /proc/config.gz ] ||
        cp /proc/config.gz "$CURRENT/kernel_config.gz" 2>/dev/null

    [ ! -r /proc/last_kmsg ] ||
        cat /proc/last_kmsg > "$CURRENT/last_kmsg.txt" 2>&1

    save_pstore
}

save_state_snapshot()
{
    TAG="$1"
    OUT="$CURRENT/${TAG}_state.txt"

    {
        section "TIME / BOOT"

        date
        uptime 2>&1

        echo "elapsed_seconds=$(elapsed)"
        echo "logger_service=$(getprop init.svc.t561-debug-logs)"
        echo "sys.boot_completed=$(getprop sys.boot_completed)"
        echo "dev.bootcomplete=$(getprop dev.bootcomplete)"
        echo "selinux=$(getenforce 2>/dev/null)"

        dump_files \
            /proc/uptime \
            /proc/version \
            /proc/cmdline

        uname -a 2>&1

        section "ALL PROPERTIES"

        getprop 2>&1

        section "PROCESSES / SERVICES"

        ps -A 2>&1
        echo

        ps -A -T 2>&1
        echo

        service list 2>&1
        echo

        lshal 2>&1

        section "FILESYSTEMS / STORAGE"

        dump_files \
            /proc/mounts \
            /proc/filesystems \
            /proc/swaps

        df -h 2>&1
        echo

        df -k 2>&1
        echo

        ls -lanZ \
            /storage \
            /storage/emulated \
            /storage/emulated/0 \
            /mnt \
            /mnt/runtime \
            /mnt/media_rw \
            /data/media \
            /data/media/0 \
            2>&1

        section "MEMORY / INTERRUPTS"

        dump_files \
            /proc/meminfo \
            /proc/vmstat \
            /proc/buddyinfo \
            /proc/interrupts \
            /proc/softirqs

        section "POWER / WAKE"

        dump_files \
            /sys/power/state \
            /sys/power/autosleep \
            /sys/power/wakeup_count \
            /sys/power/wake_lock \
            /sys/power/wake_unlock \
            /sys/kernel/debug/wakeup_sources \
            /proc/wakelocks

        section "CPU"

        dump_existing_globs \
            /sys/devices/system/cpu/online \
            /sys/devices/system/cpu/offline \
            /sys/devices/system/cpu/present \
            /sys/devices/system/cpu/cpu*/online \
            /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq \
            /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq \
            /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq \
            /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor \
            /sys/devices/system/cpu/cpu*/cpufreq/scaling_available_frequencies \
            /sys/devices/system/cpu/cpu*/cpufreq/stats/time_in_state

        section "GPU / DISPLAY"

        dump_existing_globs \
            /sys/module/mali/parameters/gpu_freq_cur \
            /sys/module/mali/parameters/gpu_cur_freq \
            /sys/module/mali/parameters/gpu_freq_max_limit \
            /sys/module/mali/parameters/gpu_freq_min_limit \
            /sys/kernel/debug/mali0/memory_usage \
            /sys/class/graphics/fb0/blank \
            /sys/class/graphics/fb0/state \
            /sys/class/graphics/fb0/mode \
            /sys/class/graphics/fb0/modes \
            /sys/class/graphics/fb0/virtual_size \
            /sys/class/backlight/panel/brightness \
            /sys/class/backlight/panel/actual_brightness \
            /sys/class/backlight/panel/max_brightness \
            /sys/class/backlight/panel/bl_power

        section "INPUT / THERMAL / BATTERY"

        safe_cat /proc/bus/input/devices

        dump_existing_globs \
            /sys/class/input/event*/device/name \
            /sys/class/input/event*/device/device/enable \
            /sys/class/thermal/thermal_zone*/type \
            /sys/class/thermal/thermal_zone*/temp \
            /sys/class/thermal/cooling_device*/type \
            /sys/class/thermal/cooling_device*/cur_state \
            /sys/class/thermal/cooling_device*/max_state \
            /sys/class/power_supply/*/type \
            /sys/class/power_supply/*/online \
            /sys/class/power_supply/*/status \
            /sys/class/power_supply/*/health \
            /sys/class/power_supply/*/capacity \
            /sys/class/power_supply/*/voltage_now \
            /sys/class/power_supply/*/current_now \
            /sys/class/power_supply/*/temp

        section "NETWORK"

        ip address show 2>&1
        echo

        ip route show table all 2>&1
        echo

        ip rule show 2>&1

        dump_files \
            /proc/net/dev \
            /proc/net/route \
            /proc/net/ipv6_route

        section "DEVICE NODES"

        ls -lanZ \
            /proc/cpw \
            /proc/cpt \
            /proc/cpwcn \
            /dev/stty* \
            /dev/spipe* \
            /dev/slog* \
            /dev/vbpipe* \
            /dev/rmnet* \
            /dev/video* \
            /dev/media* \
            /dev/ion \
            /dev/sprd* \
            /dev/dcam* \
            /dev/isp* \
            /dev/jpg* \
            /dev/jpeg* \
            /dev/graphics/* \
            /dev/input/* \
            2>&1

        section "DUMPSYS POWER"

        dumpsys power 2>&1

        section "DUMPSYS DISPLAY"

        dumpsys display 2>&1

        section "DUMPSYS INPUT"

        dumpsys input 2>&1

        section "DUMPSYS BATTERY"

        dumpsys battery 2>&1

        section "DUMPSYS TELEPHONY"

        dumpsys telephony.registry 2>&1

    } > "$OUT" 2>&1

    # Raw kernel buffer, without grep or other creative censorship.
    dmesg > "$CURRENT/${TAG}_dmesg.txt" 2>&1
}

save_process_details()
{
    OUT="$1"

    {
        for PROC in /proc/[0-9]*; do
            [ -d "$PROC" ] || continue

            PID=${PROC##*/}

            echo
            echo "================ PID $PID ================"

            if [ -r "$PROC/cmdline" ]; then
                tr '\0' ' ' < "$PROC/cmdline" 2>/dev/null
                echo
            fi

            safe_cat "$PROC/status"
            safe_cat "$PROC/maps"
        done
    } > "$OUT" 2>&1
}

save_crash_state()
{
    OUT="$1"

    {
        section "TOMBSTONES"

        ls -lanZ /data/tombstones 2>&1

        for FILE in /data/tombstones/tombstone_*; do
            [ -r "$FILE" ] || continue

            echo
            echo "===== $FILE ====="

            cat "$FILE" 2>&1
        done

        section "ANR"

        ls -lanZ /data/anr 2>&1

        for FILE in /data/anr/*; do
            [ -r "$FILE" ] || continue

            echo
            echo "===== $FILE ====="

            cat "$FILE" 2>&1
        done

        section "DROPBOX"

        dumpsys dropbox --print 2>&1

    } > "$OUT" 2>&1
}

save_full_snapshot()
{
    TAG="$1"

    echo "$(date) starting full snapshot: $TAG" \
        >> "$CURRENT/logger_events.txt"

    save_state_snapshot "$TAG"

    dumpsys \
        > "$CURRENT/${TAG}_dumpsys_all.txt" 2>&1

    logcat -b all -v threadtime -d \
        > "$CURRENT/${TAG}_logcat_dump.txt" 2>&1

    {
        section "BINDER"

        dump_files \
            /sys/kernel/debug/binder/state \
            /sys/kernel/debug/binder/stats \
            /sys/kernel/debug/binder/transactions \
            /sys/kernel/debug/binder/transaction_log \
            /sys/kernel/debug/binder/failed_transaction_log

        section "DETAILED MEMORY"

        dump_files \
            /proc/zoneinfo \
            /proc/pagetypeinfo \
            /proc/slabinfo

    } > "$CURRENT/${TAG}_kernel_state.txt" 2>&1

    save_process_details \
        "$CURRENT/${TAG}_processes.txt"

    save_pstore

    echo "$(date) finished full snapshot: $TAG" \
        >> "$CURRENT/logger_events.txt"
}

save_periodic_snapshot()
{
    SLOT=$(printf '%02d' $((SNAPSHOT_INDEX % SNAPSHOT_SLOTS)))
    TAG="periodic_$SLOT"

    rm -f \
        "$CURRENT/${TAG}_state.txt" \
        "$CURRENT/${TAG}_dmesg.txt"

    save_state_snapshot "$TAG"

    SNAPSHOT_INDEX=$((SNAPSHOT_INDEX + 1))

    {
        echo "last_slot=$SLOT"
        echo "last_time=$(date)"
    } > "$CURRENT/periodic_status.txt"
}

check_cache_space()
{
    FREE_KB=$(
        df -k /cache 2>/dev/null |
            tail -n 1 |
            awk '{print $4}'
    )

    [ -n "$FREE_KB" ] || return
    [ "$FREE_KB" -lt "$MIN_CACHE_FREE_KB" ] || return

    echo "$(date) low cache: ${FREE_KB} KiB; removing previous session" \
        >> "$CURRENT/logger_events.txt"

    rm -rf "$PREVIOUS"

    FREE_KB=$(
        df -k /cache 2>/dev/null |
            tail -n 1 |
            awk '{print $4}'
    )

    [ -n "$FREE_KB" ] || return
    [ "$FREE_KB" -lt "$MIN_CACHE_FREE_KB" ] || return

    echo "$(date) cache still low; removing periodic ring" \
        >> "$CURRENT/logger_events.txt"

    rm -f \
        "$CURRENT"/periodic_*_state.txt \
        "$CURRENT"/periodic_*_dmesg.txt

    FREE_KB=$(
        df -k /cache 2>/dev/null |
            tail -n 1 |
            awk '{print $4}'
    )

    [ -n "$FREE_KB" ] || return

    if [ "$FREE_KB" -lt 16384 ]; then
        echo "$(date) cache critically low; stopping" \
            >> "$CURRENT/logger_events.txt"

        REQUEST_STOP=1
    fi
}

prepare_log_directory

{
    echo "script_started=$(date)"
    echo "mode=generic_unfiltered_autostart"
    echo "snapshot_interval=$SNAPSHOT_INTERVAL"
    echo "snapshot_slots=$SNAPSHOT_SLOTS"
    echo "logcat_rotate_kb=$LOGCAT_ROTATE_KB"
    echo "logcat_rotate_count=$LOGCAT_ROTATE_COUNT"
    echo "stop_file=$STOPFILE"
    echo "pull_command=adb pull /cache/t561-logs ."
} > "$CURRENT/status.txt" 2>&1

echo "$(date) logger started" \
    > "$CURRENT/logger_events.txt"

kmsg "started"

trap request_stop INT TERM
trap stop_logcat EXIT

save_early_logs
start_logcat

NEXT_SNAPSHOT=0

while [ ! -e "$STOPFILE" ] &&
      [ "$REQUEST_STOP" -eq 0 ]; do

    start_logcat

    NOW=$(elapsed)

    if [ "$NOW" -ge "$NEXT_SNAPSHOT" ]; then
        save_periodic_snapshot
        check_cache_space

        NEXT_SNAPSHOT=$((NOW + SNAPSHOT_INTERVAL))
    fi

    if [ "$BOOT_SNAPSHOT_SAVED" -eq 0 ]; then
        if [ "$(getprop sys.boot_completed)" = "1" ]; then
            save_full_snapshot bootcomplete
            BOOT_SNAPSHOT_SAVED=1
        elif [ "$NOW" -ge "$MAX_BOOT_WAIT" ]; then
            save_full_snapshot boot_timeout
            BOOT_SNAPSHOT_SAVED=1
        fi
    fi

    sleep "$WATCH_INTERVAL"
done

if [ -e "$STOPFILE" ]; then
    echo "$(date) STOP file detected" \
        >> "$CURRENT/logger_events.txt"
else
    echo "$(date) stop signal detected" \
        >> "$CURRENT/logger_events.txt"
fi

stop_logcat
trap - EXIT INT TERM

save_full_snapshot final

save_crash_state \
    "$CURRENT/final_crash_anr_dropbox.txt"

{
    echo "capture_finished=$(date)"
    echo "elapsed_seconds=$(elapsed)"
    echo "result=complete"
    echo "pull_command=adb pull /cache/t561-logs ."
} >> "$CURRENT/status.txt" 2>&1

find "$BASE" -type f -exec chmod 0644 {} \; 2>/dev/null
find "$BASE" -type d -exec chmod 0755 {} \; 2>/dev/null

sync

kmsg "finished logs=$BASE"

exit 0
