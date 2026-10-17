#!/data/data/com.termux/files/usr/bin/bash

# ===== 設定 =====
PROXY_PORT=1080
CHECK_INTERVAL=5
MIN_BATTERY=20

RISH="$HOME/rish"
PID_FILE="$HOME/.proxy-bypass.pid"
LOG_PREFIX="[ProxyBypass]"

LAST_STATE=""

run_shell() {
    RISH_APPLICATION_ID=com.termux \
        sh "$RISH" -c "$1"
}

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_PREFIX $1"
}

# 防止重複啟動
if [ -f "$PID_FILE" ]; then
    OLD_PID="$(cat "$PID_FILE" 2>/dev/null)"

    if [ -n "$OLD_PID" ] &&
       kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Proxy Bypass 已在執行，PID=$OLD_PID"
        exit 1
    fi
fi

echo "$$" > "$PID_FILE"

proxy_is_listening() {
    timeout 2 bash -c \
        "exec 3<>/dev/tcp/127.0.0.1/${PROXY_PORT}" \
        >/dev/null 2>&1
}

get_current_bypass() {
    run_shell 'settings get system pass_through' |
        tr -d '\r\n'
}

set_bypass() {
    local desired="$1"
    local current

    current="$(get_current_bypass)"

    if [ "$current" = "$desired" ]; then
        return
    fi

    if run_shell \
        "settings put system pass_through $desired"; then

        log_message \
            "Battery Bypass：${current:-null} → $desired"
    else
        log_message \
            "錯誤：無法設定 pass_through=$desired"
    fi
}

cleanup() {
    trap - EXIT INT TERM

    log_message "監控停止，關閉 Battery Bypass"
    run_shell \
        'settings put system pass_through 0' \
        >/dev/null 2>&1

    rm -f "$PID_FILE"
    exit 0
}

trap cleanup EXIT INT TERM

log_message \
    "開始監控 SOCKS5 TCP port $PROXY_PORT"

while true; do
    # 確認 Shizuku 還活著
    if ! run_shell 'id' >/dev/null; then
        if [ "$LAST_STATE" != "SHIZUKU_OFFLINE" ]; then
            log_message "Shizuku 尚未啟動或 rish 未授權"
            LAST_STATE="SHIZUKU_OFFLINE"
        fi

        sleep "$CHECK_INTERVAL"
        continue
    fi

    DESIRED_BYPASS=0
    CURRENT_STATE="PROXY_OFF"

    if proxy_is_listening; then
        DESIRED_BYPASS=1
        CURRENT_STATE="BYPASS_ON"
    fi

    set_bypass "$DESIRED_BYPASS"

    if [ "$CURRENT_STATE" != "$LAST_STATE" ]; then
        log_message \
            "狀態=$CURRENT_STATE 電量=${BATTERY_LEVEL:-unknown}% 有線供電=$WIRED_POWER"

        LAST_STATE="$CURRENT_STATE"
    fi

    sleep "$CHECK_INTERVAL"
done