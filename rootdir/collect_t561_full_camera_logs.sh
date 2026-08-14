#!/system/bin/sh
#
# Samsung SM-T561 / gtel3g LineageOS 16
# Full boot/system logger + camera-focused automatic extraction.
#
# Behaviour:
#   - starts automatically from init at post-fs-data
#   - captures early boot logs immediately
#   - keeps FULL logcat running with rotation
#   - watches camera provider PID and snapshots every restart/start
#   - keeps full kernel/system snapshots
#   - refreshes camera/linker/DCAM/SELinux/crash filters while running
#   - runs until /cache/t561-camera-logs/STOP exists
#
# No archives are created.
#
# You do NOT need to catch a 180-second window anymore.
#
# Test procedure:
#   1) boot Android
#   2) reproduce camera issue whenever convenient
#   3) wait ~15-30 seconds after the failure
#   4) adb shell touch /cache/t561-camera-logs/STOP
#   5) wait until: getprop init.svc.t561-camera-logs = stopped
#   6) adb pull /cache/t561-camera-logs .
#

PATH=/sbin:/system/sbin:/system/bin:/system/xbin:/vendor/bin
export PATH

LOGDIR=/cache/t561-camera-logs
STOPFILE=$LOGDIR/STOP

MAX_BOOT_WAIT=300
WATCH_INTERVAL=2
FILTER_INTERVAL=10
FULL_SNAPSHOT_INTERVAL=60

# logcat rotation: 16 MiB x 8 files ~= 128 MiB maximum
LOGCAT_ROTATE_KB=16384
LOGCAT_ROTATE_COUNT=8

LAST_PROVIDER_PID=""
LOGCAT_PID=""
START_EPOCH=$(date +%s 2>/dev/null)

kmsg()
{
    echo "SM_T561_CAMERA_LOGS: $*" > /dev/kmsg 2>/dev/null
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
    F="$1"
    if [ -r "$F" ]; then
        cat "$F" 2>&1
    elif [ -e "$F" ]; then
        echo "EXISTS BUT NOT READABLE: $F"
    else
        echo "MISSING: $F"
    fi
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

camera_provider_pid()
{
    pidof android.hardware.camera.provider@2.4-service 2>/dev/null | awk '{print $1}'
}

start_live_logcat()
{
    if [ -n "$LOGCAT_PID" ] && kill -0 "$LOGCAT_PID" 2>/dev/null; then
        return
    fi

    echo "$(date) restarting full live logcat" >> "$LOGDIR/logger_events.txt"

    logcat -b all -v threadtime \
        -f "$LOGDIR/logcat_live.txt" \
        -r "$LOGCAT_ROTATE_KB" \
        -n "$LOGCAT_ROTATE_COUNT" \
        >/dev/null 2>&1 &

    LOGCAT_PID=$!
    echo "logcat_pid=$LOGCAT_PID" >> "$LOGDIR/logger_events.txt"
}

save_early()
{
    dmesg > "$LOGDIR/dmesg_early.txt" 2>&1
    logcat -b all -v threadtime -d > "$LOGDIR/logcat_early.txt" 2>&1
    getprop > "$LOGDIR/getprop_early.txt" 2>&1

    if [ -r /proc/config.gz ]; then
        cp /proc/config.gz "$LOGDIR/kernel_config.gz" 2>/dev/null
    fi

    if [ -r /proc/last_kmsg ]; then
        cat /proc/last_kmsg > "$LOGDIR/last_kmsg.txt" 2>&1
    fi

    if ls /sys/fs/pstore/console-ramoops* >/dev/null 2>&1; then
        cat /sys/fs/pstore/console-ramoops* \
            > "$LOGDIR/console-ramoops.txt" 2>&1
    fi

    if ls /sys/fs/pstore/pmsg-ramoops* >/dev/null 2>&1; then
        cat /sys/fs/pstore/pmsg-ramoops* \
            > "$LOGDIR/pmsg-ramoops.txt" 2>&1
    fi
}

save_full_snapshot()
{
    TAG="$1"

    {
        section "TIME / UPTIME"
        date
        uptime 2>&1
        cat /proc/uptime 2>&1

        section "BOOT STATE"
        echo "sys.boot_completed=$(getprop sys.boot_completed)"
        echo "dev.bootcomplete=$(getprop dev.bootcomplete)"
        echo "camera_provider_pid=$(camera_provider_pid)"
        echo "camera_provider_service=$(getprop init.svc.vendor.camera-provider-2-4)"
        echo "camera_logger_service=$(getprop init.svc.t561-camera-logs)"
        echo "selinux=$(getenforce 2>/dev/null)"

        section "ALL PROPERTIES"
        getprop 2>&1

        section "PROCESSES"
        ps -A 2>&1

        section "PROCESS THREADS"
        ps -A -T 2>&1

        section "SERVICE LIST"
        service list 2>&1

        section "HIDL SERVICES"
        lshal 2>&1

        section "MOUNTS"
        cat /proc/mounts 2>&1

        section "FILESYSTEMS"
        cat /proc/filesystems 2>&1

        section "MEMORY"
        cat /proc/meminfo 2>&1

        section "VMSTAT"
        cat /proc/vmstat 2>&1

        section "INTERRUPTS"
        cat /proc/interrupts 2>&1

        section "MODULES"
        cat /proc/modules 2>&1

        section "KERNEL"
        uname -a 2>&1
        cat /proc/version 2>&1
        cat /proc/cmdline 2>&1

        section "DISK"
        df -h 2>&1
        echo
        df -T 2>&1

        section "DEV"
        ls -lanZ /dev 2>&1

        section "CAMERA/SPRD DEVICES"
        ls -lanZ \
            /dev/video* /dev/media* /dev/ion \
            /dev/sprd* /dev/dcam* /dev/isp* \
            /dev/jpg* /dev/jpeg* 2>&1

        section "CAMERA HAL FILES"
        ls -lanZ \
            /vendor/lib/hw/camera*.so \
            /system/vendor/lib/hw/camera*.so \
            /system/lib/hw/camera*.so 2>&1

        section "CAMERA/MEDIA PROPERTIES"
        getprop | grep -iE \
            "camera|cam\.|media\.|sprd|sc8830|sensor|isp|jpeg|ion"

    } > "$LOGDIR/${TAG}_full_system.txt" 2>&1

    dumpsys > "$LOGDIR/${TAG}_dumpsys_all.txt" 2>&1
    dumpsys media.camera > "$LOGDIR/${TAG}_dumpsys_media_camera.txt" 2>&1
    dmesg > "$LOGDIR/${TAG}_dmesg.txt" 2>&1
}

save_provider_snapshot()
{
    PID="$1"
    WHY="$2"
    TS=$(date +%Y%m%d-%H%M%S 2>/dev/null)
    [ -n "$TS" ] || TS="unknown"

    OUT="$LOGDIR/provider_${TS}_${PID:-none}"

    {
        section "EVENT"
        echo "time=$(date)"
        echo "reason=$WHY"
        echo "pid=$PID"
        echo "sys.boot_completed=$(getprop sys.boot_completed)"
        echo "service=$(getprop init.svc.vendor.camera-provider-2-4)"

        section "CAMERA FILES"
        ls -lanZ \
            /vendor/lib/hw/camera*.so \
            /system/vendor/lib/hw/camera*.so \
            /system/lib/hw/camera*.so 2>&1

        section "CAMERA WRAPPER MARKERS"
        for F in \
            /vendor/lib/hw/camera.sc8830.so \
            /system/vendor/lib/hw/camera.sc8830.so; do
            [ -r "$F" ] || continue
            echo "--- $F ---"
            strings "$F" 2>/dev/null | \
                grep -Ei \
                "T561_CAMWRAP|Samsung T561|camera.vendor.sc8830|Camera HAL1 Wrapper" \
                | head -n 100
        done

        if [ -n "$PID" ] && [ -d "/proc/$PID" ]; then
            section "STATUS"
            safe_cat "/proc/$PID/status"

            section "CMDLINE"
            tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null
            echo

            section "MAPS FULL"
            safe_cat "/proc/$PID/maps"

            section "MAPS CAMERA/SPRD"
            grep -Ei \
                "camera|sc8830|sprd|sensor|isp|ion|skia|exif|uvdenoise|morpho|secnative|stlport" \
                "/proc/$PID/maps" 2>&1

            section "FDS"
            for FD in /proc/$PID/fd/*; do
                TARGET=$(readlink "$FD" 2>/dev/null)
                [ -n "$TARGET" ] || continue
                echo "$FD -> $TARGET"
            done
        else
            section "PROVIDER NOT RUNNING"
            echo "No provider process at snapshot time"
        fi

        section "CAMERA SERVICE"
        dumpsys media.camera 2>&1

        section "HIDL CAMERA"
        lshal 2>&1 | grep -iE "camera|provider"

        section "CAMERA DEVICES"
        ls -lanZ \
            /dev/video* /dev/media* /dev/ion \
            /dev/sprd* /dev/dcam* /dev/isp* \
            /dev/jpg* /dev/jpeg* 2>&1

    } > "${OUT}.txt" 2>&1

    dmesg > "${OUT}_dmesg.txt" 2>&1

    echo "$(date) provider event reason=$WHY pid=$PID snapshot=${OUT}.txt" \
        >> "$LOGDIR/logger_events.txt"
}

save_crash_state()
{
    {
        section "TOMBSTONES"
        ls -lanZ /data/tombstones 2>&1

        for F in /data/tombstones/tombstone_*; do
            [ -r "$F" ] || continue
            echo
            echo "===== $F ====="
            cat "$F" 2>&1
        done

        section "ANR"
        ls -lanZ /data/anr 2>&1

        for F in /data/anr/*; do
            [ -r "$F" ] || continue
            echo
            echo "===== $F ====="
            cat "$F" 2>&1
        done

        section "DROPBOX"
        dumpsys dropbox --print 2>&1

    } > "$LOGDIR/crash_anr_all.txt" 2>&1
}

all_logcat()
{
    for F in "$LOGDIR"/logcat_early.txt "$LOGDIR"/logcat_boot.txt \
             "$LOGDIR"/logcat_live.txt* "$LOGDIR"/logcat_final.txt; do
        [ -r "$F" ] && cat "$F"
    done
}

all_dmesg()
{
    for F in "$LOGDIR"/dmesg_early.txt "$LOGDIR"/boot_dmesg.txt \
             "$LOGDIR"/dmesg_final.txt; do
        [ -r "$F" ] && cat "$F"
    done
}

make_filters()
{
    TMP="$LOGDIR/.filter.$$"

    all_logcat | grep -iE \
        "T561_CAMWRAP|CameraWrapper|camera\.sc8830|camera\.vendor\.sc8830|cameraserver|CameraService|CameraProvider|CameraProviderManager|camera provider|HAL1|hw_get_module|dlopen|linker|cannot locate symbol|CANNOT LINK EXECUTABLE|library.*not found|namespace|vndksupport|libskia|libisp|libuvdenoise|morpho|secnative|stlport|startPreview|stopPreview|takePicture|recording|autofocus|focus|preview|ERROR_CAMERA|CAMERA_ERROR|device error|service error|Fatal signal|SIGSEGV|SIGBUS|SIGABRT|tombstone|crash_dump|avc:.*denied" \
        > "$TMP" 2>/dev/null
    mv "$TMP" "$LOGDIR/filtered_camera_ALL.txt"

    all_logcat | grep -iE \
        "T561_CAMWRAP|camera\.vendor\.sc8830|camera\.sc8830|hw_get_module|HAL.*load|dlopen|linker|cannot locate symbol|CANNOT LINK EXECUTABLE|library.*not found|namespace|vndksupport|libskia|libisp|libuvdenoise|morpho|secnative|stlport" \
        > "$TMP" 2>/dev/null
    mv "$TMP" "$LOGDIR/filtered_wrapper_linker.txt"

    all_logcat | grep -iE \
        "CameraService|CameraProvider|CameraProviderManager|CameraDevice|CameraClient|camera provider|HAL1|startPreview|stopPreview|takePicture|recording|autofocus|focus|preview|ERROR_CAMERA|CAMERA_ERROR" \
        > "$TMP" 2>/dev/null
    mv "$TMP" "$LOGDIR/filtered_camera_framework.txt"

    all_dmesg | grep -iE \
        "camera|dcam|isp|sensor|s5k4ec|sr200|i2c|v4l2|video[0-9]|jpeg|jpg|ion|gsp|sprd.*cam|cam.*sprd|timeout|timed out|failed|error|I/O error|overflow|underflow|dma|iommu" \
        > "$TMP" 2>/dev/null
    mv "$TMP" "$LOGDIR/filtered_camera_kernel.txt"

    {
        all_logcat
        all_dmesg
    } | grep -iE "avc:.*denied|selinux.*denied" \
        > "$TMP" 2>/dev/null
    mv "$TMP" "$LOGDIR/filtered_selinux.txt"

    all_logcat | grep -iE \
        "FATAL EXCEPTION|Fatal signal|SIGSEGV|SIGBUS|SIGABRT|ANR in|am_anr|am_crash|tombstone|crash_dump|backtrace:|Abort message|FORTIFY|heap corruption" \
        > "$TMP" 2>/dev/null
    mv "$TMP" "$LOGDIR/filtered_crashes.txt"

    rm -f "$TMP" 2>/dev/null
}

save_summary()
{
    {
        echo "SM-T561 full camera diagnostic summary"
        echo "updated=$(date)"
        echo "elapsed_seconds=$(elapsed)"
        echo "sys.boot_completed=$(getprop sys.boot_completed)"
        echo "provider_pid=$(camera_provider_pid)"
        echo "provider_service=$(getprop init.svc.vendor.camera-provider-2-4)"
        echo

        echo "===== CAMERA COUNT ====="
        dumpsys media.camera 2>&1 | \
            grep -E \
            "Number of camera devices|Number of normal camera devices|Camera Provider HAL|camera devices"
        echo

        echo "===== LOADED CAMERA HALS ====="
        P=$(camera_provider_pid)
        if [ -n "$P" ] && [ -r "/proc/$P/maps" ]; then
            grep -Ei \
                "camera\.sc8830|camera\.vendor|libskia|libisp|libuvdenoise|morpho|secnative|stlport" \
                "/proc/$P/maps" 2>&1
        else
            echo "provider not running"
        fi
        echo

        echo "===== LAST WRAPPER/LINKER EVENTS ====="
        tail -n 120 "$LOGDIR/filtered_wrapper_linker.txt" 2>/dev/null
        echo

        echo "===== LAST CAMERA KERNEL EVENTS ====="
        tail -n 120 "$LOGDIR/filtered_camera_kernel.txt" 2>/dev/null
        echo

        echo "===== LOGGER EVENTS ====="
        tail -n 100 "$LOGDIR/logger_events.txt" 2>/dev/null

    } > "$LOGDIR/SUMMARY.txt" 2>&1
}

cleanup()
{
    if [ -n "$LOGCAT_PID" ]; then
        kill "$LOGCAT_PID" 2>/dev/null
        wait "$LOGCAT_PID" 2>/dev/null
    fi
}

trap cleanup EXIT INT TERM

kmsg "started"

if [ "$LOGDIR" != "/cache/t561-camera-logs" ]; then
    kmsg "unsafe LOGDIR; aborting"
    exit 1
fi

mkdir -p "$LOGDIR" || exit 1
rm -rf "$LOGDIR"/*
chmod 0777 "$LOGDIR"

{
    echo "script_started=$(date)"
    echo "mode=autostart_continuous_until_STOP"
    echo "watch_interval=$WATCH_INTERVAL"
    echo "filter_interval=$FILTER_INTERVAL"
    echo "full_snapshot_interval=$FULL_SNAPSHOT_INTERVAL"
    echo "logcat_rotate_kb=$LOGCAT_ROTATE_KB"
    echo "logcat_rotate_count=$LOGCAT_ROTATE_COUNT"
    echo "stop_file=$STOPFILE"
    echo "initial_sys.boot_completed=$(getprop sys.boot_completed)"
    echo "initial_dev.bootcomplete=$(getprop dev.bootcomplete)"
} > "$LOGDIR/status.txt" 2>&1

echo "$(date) logger started" > "$LOGDIR/logger_events.txt"

save_early
start_live_logcat

WAITED=0
while [ "$(getprop sys.boot_completed)" != "1" ] && \
      [ "$WAITED" -lt "$MAX_BOOT_WAIT" ] && \
      [ ! -e "$STOPFILE" ]; do

    start_live_logcat

    P=$(camera_provider_pid)
    if [ "$P" != "$LAST_PROVIDER_PID" ]; then
        save_provider_snapshot "$P" "provider_pid_changed_during_boot"
        LAST_PROVIDER_PID="$P"
    fi

    sleep "$WATCH_INTERVAL"
    WAITED=$((WAITED + WATCH_INTERVAL))
done

logcat -b all -v threadtime -d > "$LOGDIR/logcat_boot.txt" 2>&1
dmesg > "$LOGDIR/boot_dmesg.txt" 2>&1
save_full_snapshot bootcomplete
make_filters
save_summary

LAST_FILTER=$(elapsed)
LAST_FULL=$(elapsed)

while [ ! -e "$STOPFILE" ]; do

    start_live_logcat

    P=$(camera_provider_pid)
    if [ "$P" != "$LAST_PROVIDER_PID" ]; then
        save_provider_snapshot "$P" "provider_pid_changed"
        LAST_PROVIDER_PID="$P"
    fi

    NOW=$(elapsed)

    if [ $((NOW - LAST_FILTER)) -ge "$FILTER_INTERVAL" ]; then
        {
            section "KERNEL SAMPLE elapsed=${NOW}s"
            date
            dmesg 2>&1 | tail -n 700 | \
                grep -iE \
                "camera|dcam|isp|sensor|s5k4ec|sr200|i2c|v4l2|jpeg|jpg|ion|gsp|timeout|timed out|failed|error|I/O error"
        } >> "$LOGDIR/kernel_camera_timeline.txt" 2>&1

        make_filters
        save_summary
        LAST_FILTER="$NOW"
    fi

    if [ $((NOW - LAST_FULL)) -ge "$FULL_SNAPSHOT_INTERVAL" ]; then
        TS=$(date +%Y%m%d-%H%M%S 2>/dev/null)
        save_full_snapshot "periodic_${TS}"
        LAST_FULL="$NOW"
    fi

    sleep "$WATCH_INTERVAL"
done

echo "$(date) STOP file detected" >> "$LOGDIR/logger_events.txt"

cleanup
LOGCAT_PID=""
trap - EXIT INT TERM

logcat -b all -v threadtime -d > "$LOGDIR/logcat_final.txt" 2>&1
dmesg > "$LOGDIR/dmesg_final.txt" 2>&1

save_provider_snapshot "$(camera_provider_pid)" "final"
save_full_snapshot final
save_crash_state
make_filters
save_summary

{
    echo "capture_finished=$(date)"
    echo "elapsed_seconds=$(elapsed)"
    echo "result=complete"
    echo "pull_command=adb pull /cache/t561-camera-logs ."
} >> "$LOGDIR/status.txt" 2>&1

find "$LOGDIR" -type f -exec chmod 0644 {} \; 2>/dev/null
find "$LOGDIR" -type d -exec chmod 0755 {} \; 2>/dev/null
chmod 0777 "$LOGDIR" 2>/dev/null

sync
kmsg "done logs=$LOGDIR"
exit 0
