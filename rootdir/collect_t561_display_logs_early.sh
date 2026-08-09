#!/system/bin/sh

# Early boot display logger for Samsung SM-T561 / gtel3g.
#
# This script is meant to be started by Android init, not through ADB. It
# stores an unpacked directory under /cache so it can be pulled from recovery
# after the test boot.

umask 022

CAPTURE_SECONDS="${1:-300}"
POLL_SECONDS="${2:-5}"
BASE_DIR="${T561_LOG_DIR:-/cache/t561-display-logs}"
LOGCAT_PID=""

case "$CAPTURE_SECONDS" in
    ''|*[!0-9]*) CAPTURE_SECONDS=300 ;;
esac

case "$POLL_SECONDS" in
    ''|*[!0-9]*) POLL_SECONDS=5 ;;
esac

[ "$CAPTURE_SECONDS" -gt 0 ] 2>/dev/null || CAPTURE_SECONDS=300
[ "$POLL_SECONDS" -gt 0 ] 2>/dev/null || POLL_SECONDS=5

boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '-' | cut -c1-12)"
[ -n "$boot_id" ] || boot_id="$(date +%s 2>/dev/null)"
[ -n "$boot_id" ] || boot_id="unknown"

RUN_DIR="$BASE_DIR/boot-$boot_id"

mkdir -p "$RUN_DIR/dmesg-snapshots" || exit 1
chmod 0755 "$BASE_DIR" "$RUN_DIR" "$RUN_DIR/dmesg-snapshots" 2>/dev/null
echo "$RUN_DIR" > "$BASE_DIR/LAST"

exec >> "$RUN_DIR/collector.log" 2>&1

cleanup() {
    if [ -n "$LOGCAT_PID" ]; then
        kill "$LOGCAT_PID" 2>/dev/null
        wait "$LOGCAT_PID" 2>/dev/null
        LOGCAT_PID=""
    fi
}

trap cleanup EXIT INT TERM

snapshot_command() {
    output_name="$1"
    shift
    "$@" > "$RUN_DIR/$output_name" 2>&1 || true
}

copy_tree_if_present() {
    source_path="$1"
    target_name="$2"

    if [ -e "$source_path" ]; then
        mkdir -p "$RUN_DIR/$target_name"
        cp -R "$source_path" "$RUN_DIR/$target_name/" 2>/dev/null || true
    fi
}

echo "SM-T561 early display logger"
echo "run_dir=$RUN_DIR"
echo "capture_seconds=$CAPTURE_SECONDS"
echo "poll_seconds=$POLL_SECONDS"
echo "started_at=$(date 2>/dev/null)"
echo "uptime=$(cat /proc/uptime 2>/dev/null)"
echo "getenforce=$(getenforce 2>/dev/null)"
id 2>/dev/null || true

# Save everything already present in the ring buffers before starting the live
# reader. logcat/logd normally starts before post-fs-data, so this includes the
# events emitted before this service was launched.
snapshot_command "logcat-before.txt" logcat -b all -v threadtime -d
snapshot_command "dmesg-before.txt" dmesg
snapshot_command "getprop-before.txt" getprop
snapshot_command "proc-cmdline.txt" cat /proc/cmdline
snapshot_command "proc-meminfo-before.txt" cat /proc/meminfo
snapshot_command "proc-fb-before.txt" cat /proc/fb

logcat -b all -v threadtime > "$RUN_DIR/logcat-live.txt" 2> "$RUN_DIR/logcat-live-errors.txt" &
LOGCAT_PID=$!

start_epoch="$(date +%s)"
end_epoch=$((start_epoch + CAPTURE_SECONDS))
sample=0

while :; do
    now_epoch="$(date +%s)"
    [ "$now_epoch" -lt "$end_epoch" ] || break

    sample_name="$(printf '%04d' "$sample")"
    dmesg > "$RUN_DIR/dmesg-snapshots/$sample_name.txt" 2>&1 || true

    {
        echo
        echo "===== sample=$sample host_epoch=$now_epoch elapsed=$((now_epoch - start_epoch))s ====="
        echo "device_date=$(date 2>/dev/null)"
        echo "uptime=$(cat /proc/uptime 2>/dev/null)"
        echo "sys.boot_completed=$(getprop sys.boot_completed)"
        echo "dev.bootcomplete=$(getprop dev.bootcomplete)"
        echo "init.svc.surfaceflinger=$(getprop init.svc.surfaceflinger)"
        echo "init.svc.bootanim=$(getprop init.svc.bootanim)"
        echo "service.bootanim.exit=$(getprop service.bootanim.exit)"
        echo "service.bootanim.progress=$(getprop service.bootanim.progress)"

        for sysfs_file in \
            /sys/class/graphics/fb0/blank \
            /sys/class/graphics/fb0/state \
            /sys/class/graphics/fb0/mode \
            /sys/class/graphics/fb0/virtual_size \
            /sys/class/graphics/fb0/stride \
            /sys/class/graphics/fb0/bits_per_pixel; do
            if [ -r "$sysfs_file" ]; then
                printf '%s=' "$sysfs_file"
                cat "$sysfs_file" 2>/dev/null
            fi
        done
    } >> "$RUN_DIR/timeline.txt" 2>&1

    sample=$((sample + 1))
    sleep "$POLL_SECONDS"
done

cleanup

snapshot_command "logcat-after.txt" logcat -b all -v threadtime -d
snapshot_command "dmesg-after.txt" dmesg
snapshot_command "getprop-after.txt" getprop
snapshot_command "ps.txt" ps -A
snapshot_command "service-list.txt" service list
snapshot_command "lshal.txt" lshal
snapshot_command "surfaceflinger.txt" dumpsys SurfaceFlinger
snapshot_command "display-service.txt" dumpsys display
snapshot_command "window-service.txt" dumpsys window
snapshot_command "activity-processes.txt" dumpsys activity processes
snapshot_command "meminfo-surfaceflinger.txt" dumpsys meminfo surfaceflinger
snapshot_command "proc-interrupts.txt" cat /proc/interrupts
snapshot_command "proc-fb-after.txt" cat /proc/fb
snapshot_command "proc-meminfo-after.txt" cat /proc/meminfo
snapshot_command "mounts.txt" cat /proc/mounts
snapshot_command "graphics-nodes.txt" ls -la /dev/graphics /dev/ion /dev/mali /dev/mali0
snapshot_command "last-kmsg.txt" cat /proc/last_kmsg

{
    for sysfs_file in /sys/class/graphics/fb0/*; do
        if [ -f "$sysfs_file" ] && [ -r "$sysfs_file" ]; then
            echo "===== $sysfs_file ====="
            cat "$sysfs_file" 2>/dev/null
        fi
    done
} > "$RUN_DIR/fb-sysfs.txt" 2>&1

{
    for debug_file in \
        /d/ion/clients \
        /d/ion/heaps \
        /d/ion/ion_system_heap \
        /sys/kernel/debug/ion/clients \
        /sys/kernel/debug/ion/heaps; do
        if [ -r "$debug_file" ]; then
            echo "===== $debug_file ====="
            cat "$debug_file" 2>/dev/null
        fi
    done
} > "$RUN_DIR/ion-debug.txt" 2>&1

{
    for debug_root in /d /sys/kernel/debug; do
        if [ -d "$debug_root" ]; then
            echo "===== $debug_root ====="
            find "$debug_root" -maxdepth 3 -type f 2>/dev/null | \
                grep -Ei '(sprd|dispc|dsi|display|framebuffer|/fb|ion|mali|gpu)' | \
                head -n 500
        fi
    done
} > "$RUN_DIR/debugfs-display-list.txt" 2>&1

copy_tree_if_present "/data/tombstones" "tombstones"
copy_tree_if_present "/sys/fs/pstore" "pstore"

{
    echo "SM-T561 DISPLAY TEST SUMMARY"
    echo "Generated: $(date 2>/dev/null)"
    echo
    echo "Important event counts:"

    for pattern in \
        "SPRD HIDL FB copy kick" \
        "ion_invalidate_for_cpu" \
        "Fatal signal" \
        "SIGILL" \
        "SIGSEGV" \
        "BootAnimation" \
        "SurfaceFlinger"; do
        count="$(grep -hFic "$pattern" \
            "$RUN_DIR/logcat-before.txt" \
            "$RUN_DIR/logcat-live.txt" \
            "$RUN_DIR/dmesg-after.txt" 2>/dev/null | \
            awk '{ total += $1 } END { print total + 0 }')"
        printf '%-32s %s\n' "$pattern" "$count"
    done

    echo
    echo "Final boot properties:"
    grep -E '^\[(sys\.boot_completed|dev\.bootcomplete|init\.svc\.(surfaceflinger|bootanim)|service\.bootanim\.(exit|progress))\]:' \
        "$RUN_DIR/getprop-after.txt" 2>/dev/null || true

    echo
    echo "Focused display/GPU events:"
    grep -hiE \
        'SPRD HIDL FB copy kick|sprdfb|dispc|dsi|framebuffer|fb0|ion_|dma.?buf|mali|gralloc|hwcomposer|SurfaceFlinger|BootAnimation|Fatal signal|SIGILL|SIGSEGV' \
        "$RUN_DIR/logcat-before.txt" \
        "$RUN_DIR/logcat-live.txt" \
        "$RUN_DIR/dmesg-after.txt" 2>/dev/null | \
        tail -n 2000 || true
} > "$RUN_DIR/summary.txt"

echo "completed_at=$(date 2>/dev/null)" > "$RUN_DIR/DONE"
sync

echo "Collection complete: $RUN_DIR"
trap - EXIT INT TERM

