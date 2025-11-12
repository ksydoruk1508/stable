#!/usr/bin/env bash
# Stable — snapshot apply + systemd bootstrap
# One file that can:
#  - apply snapshot once
#  - install/enable systemd service+timer
#  - set schedule (daily HH:MM or any OnCalendar)
#  - enable/disable/status/uninstall
#
# Usage examples:
#   stable-apply-snapshot.sh --run
#   stable-apply-snapshot.sh --install --time "02:30"
#   stable-apply-snapshot.sh --install --calendar 'Sun *-*-* 02:00:00'
#   stable-apply-snapshot.sh --set-time "03:15"
#   stable-apply-snapshot.sh --enable | --disable | --status | --uninstall
#   stable-apply-snapshot.sh --run-now   (alias of --run)

set -Eeuo pipefail

# -----------------------------
# Defaults (can be overridden via env)
# -----------------------------
SERVICE_NAME="${SERVICE_NAME:-stabled}"
BIN_PATH="${BIN_PATH:-/usr/bin/stabled}"
HOME_DIR="${HOME_DIR:-/root/.stabled}"
SNAPSHOT_URL="${SNAPSHOT_URL:-https://stable-snapshot.s3.eu-central-1.amazonaws.com/snapshot.tar.lz4}"

UNIT_NAME="${UNIT_NAME:-stable-snapshot.service}"
TIMER_NAME="${TIMER_NAME:-stable-snapshot.timer}"

# schedule defaults: daily at 02:00 local time
TIME_DEFAULT="${TIME_DEFAULT:-02:00}"   # HH:MM
ONCALENDAR_DEFAULT="${ONCALENDAR_DEFAULT:-*-*-* ${TIME_DEFAULT}:00}"

LOG_DIR="${LOG_DIR:-/var/log/stabled}"
LOCK_FILE="${LOCK_FILE:-/var/lock/stable-snapshot.lock}"

# -----------------------------
# Helpers
# -----------------------------
need() { command -v "$1" &>/dev/null || { echo "[ERROR] missing '$1'"; exit 1; }; }
as_root() { [[ $EUID -eq 0 ]] || { echo "[ERROR] run as root"; exit 1; }; }
reload_daemon() { systemctl daemon-reload; }

write_unit() {
  local unit_path="/etc/systemd/system/${UNIT_NAME}"
  cat >"$unit_path" <<EOF
[Unit]
Description=Stable: apply official snapshot (oneshot)
After=network-online.target

[Service]
Type=oneshot
User=root
Environment=SERVICE_NAME=${SERVICE_NAME}
Environment=BIN_PATH=${BIN_PATH}
Environment=HOME_DIR=${HOME_DIR}
Environment=SNAPSHOT_URL=${SNAPSHOT_URL}
ExecStart=/usr/local/bin/stable-apply-snapshot.sh --run
EOF
  echo "[OK] wrote ${unit_path}"
}

write_timer() {
  local oncal="${1:-${ONCALENDAR_DEFAULT}}"
  local timer_path="/etc/systemd/system/${TIMER_NAME}"
  cat >"$timer_path" <<EOF
[Unit]
Description=Stable: schedule snapshot apply

[Timer]
OnCalendar=${oncal}
Persistent=true
RandomizedDelaySec=300
AccuracySec=1min
Unit=${UNIT_NAME}

[Install]
WantedBy=timers.target
EOF
  echo "[OK] wrote ${timer_path} (OnCalendar=${oncal})"
}

current_timer_oncalendar() {
  awk -F= '/^\s*OnCalendar=/ {print $2; found=1} END{if(!found)print ""}' "/etc/systemd/system/${TIMER_NAME}" 2>/dev/null || true
}

# -----------------------------
# Core: apply snapshot once
# -----------------------------
run_once() {
  need wget; need curl; need jq; need tar; need lz4; need flock
  mkdir -p "$LOG_DIR" /root/snapshot

  # prevent parallel runs
  exec 9>"${LOCK_FILE}" || exit 0
  flock -n 9 || { echo "[INFO] another snapshot run in progress, exit."; exit 0; }

  local log="${LOG_DIR}/snapshot-$(date +%F-%H%M%S).log"
  {
    echo "[INFO] $(date) start snapshot apply"
    systemctl stop "${SERVICE_NAME}" || true

    if command -v stabled &>/dev/null; then
      stabled comet unsafe-reset-all --home "${HOME_DIR}" --keep-addr-book || true
    else
      "${BIN_PATH}" comet unsafe-reset-all --home "${HOME_DIR}" --keep-addr-book || true
    fi

    rm -f /root/snapshot/snapshot.tar.lz4
    echo "[INFO] downloading snapshot: ${SNAPSHOT_URL}"
    wget -q --show-progress -O /root/snapshot/snapshot.tar.lz4 "${SNAPSHOT_URL}"

    rm -rf "${HOME_DIR}/data" || true
    mkdir -p "${HOME_DIR}"
    tar -I lz4 -xf /root/snapshot/snapshot.tar.lz4 -C "${HOME_DIR}/"

    systemctl start "${SERVICE_NAME}"
    sleep 10

    local st catch h
    st=$(curl -s http://127.0.0.1:26657/status || true)
    catch=$(jq -r '.result.sync_info.catching_up // empty' <<<"$st" 2>/dev/null || echo "")
    h=$(jq -r '.result.sync_info.latest_block_height // empty' <<<"$st" 2>/dev/null || echo "")
    echo "[INFO] catching_up=${catch:-unknown} height=${h:-unknown}"
    echo "[INFO] $(date) snapshot apply done"
  } | tee -a "$log"
}

# -----------------------------
# Install/Enable/Disable/Status/Uninstall
# -----------------------------
install_timer() {
  as_root
  # ensure deps
  if ! command -v flock &>/dev/null; then
    apt-get update -y && apt-get install -y util-linux
  fi
  for d in curl wget jq lz4 tar; do
    command -v "$d" &>/dev/null || { apt-get update -y && apt-get install -y "$d"; }
  done

  local oncal=""
  local set_time="${1:-}"
  local set_calendar="${2:-}"

  if [[ -n "$set_calendar" ]]; then
    oncal="$set_calendar"
  elif [[ -n "$set_time" ]]; then
    # Normalize HH:MM -> "*-*-* HH:MM:00"
    if [[ "$set_time" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
      oncal="*-*-* ${set_time}:00"
    else
      echo "[ERROR] --time expects HH:MM (00..23:00..59), got '$set_time'"
      exit 1
    fi
  else
    oncal="$ONCALENDAR_DEFAULT"
  fi

  write_unit
  write_timer "$oncal"
  reload_daemon
  systemctl enable --now "${TIMER_NAME}"
  echo "[OK] timer enabled. Next runs:"
  systemctl list-timers "${TIMER_NAME}"
}

enable_timer()  { as_root; systemctl enable --now "${TIMER_NAME}"; systemctl list-timers "${TIMER_NAME}"; }
disable_timer() { as_root; systemctl disable --now "${TIMER_NAME}" || true; echo "[OK] timer disabled"; }
status_timer()  { systemctl status "${TIMER_NAME}" --no-pager || true; echo; systemctl list-timers "${TIMER_NAME}" || true; echo; journalctl -u "${UNIT_NAME}" -n 50 --no-pager || true; }

set_time() {
  as_root
  local t="${1:-}"
  [[ -z "$t" ]] && { echo "[ERROR] --set-time requires HH:MM"; exit 1; }
  if ! [[ "$t" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
    echo "[ERROR] bad time format '$t' (need HH:MM)"; exit 1
  fi
  local oc="*-*-* ${t}:00"
  write_timer "$oc"
  reload_daemon
  systemctl enable --now "${TIMER_NAME}"
  echo "[OK] OnCalendar updated to: ${oc}"
}

set_calendar() {
  as_root
  local oc="${1:-}"
  [[ -z "$oc" ]] && { echo "[ERROR] --set-calendar requires an OnCalendar expression"; exit 1; }
  write_timer "$oc"
  reload_daemon
  systemctl enable --now "${TIMER_NAME}"
  echo "[OK] OnCalendar updated to: ${oc}"
}

uninstall_all() {
  as_root
  systemctl disable --now "${TIMER_NAME}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${TIMER_NAME}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${UNIT_NAME}" 2>/dev/null || true
  reload_daemon
  echo "[OK] removed ${UNIT_NAME} and ${TIMER_NAME}"
}

# -----------------------------
# Arg parsing
# -----------------------------
if [[ $# -eq 0 ]]; then
  cat <<EOF
Usage:
  $0 --run                        # apply snapshot once (now)
  $0 --install [--time HH:MM] [--calendar 'OnCalendar expr'] [--url URL]
  $0 --enable | --disable | --status
  $0 --set-time HH:MM             # daily at HH:MM local
  $0 --set-calendar 'expr'        # arbitrary OnCalendar
  $0 --uninstall
Env overrides:
  SERVICE_NAME BIN_PATH HOME_DIR SNAPSHOT_URL UNIT_NAME TIMER_NAME
Defaults:
  daily at ${TIME_DEFAULT}  (OnCalendar='${ONCALENDAR_DEFAULT}')
EOF
  exit 0
fi

# pre-scan for optional --url to override SNAPSHOT_URL
for arg in "$@"; do
  if [[ "$arg" == "--url" ]]; then
    : # handled below
  fi
done

# simple parser
ACTION=""
TIME_ARG=""
CAL_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --run|--run-now) ACTION="run"; shift ;;
    --install) ACTION="install"; shift ;;
    --enable) ACTION="enable"; shift ;;
    --disable) ACTION="disable"; shift ;;
    --status) ACTION="status"; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --time) TIME_ARG="${2:-}"; shift 2 ;;
    --set-time) ACTION="set-time"; TIME_ARG="${2:-}"; shift 2 ;;
    --calendar) CAL_ARG="${2:-}"; shift 2 ;;
    --set-calendar) ACTION="set-calendar"; CAL_ARG="${2:-}"; shift 2 ;;
    --url) SNAPSHOT_URL="${2:-}"; shift 2 ;;
    *) echo "[WARN] unknown arg: $1"; shift ;;
  esac
done

case "${ACTION:-}" in
  run)         run_once ;;
  install)     install_timer "${TIME_ARG}" "${CAL_ARG}" ;;
  enable)      enable_timer ;;
  disable)     disable_timer ;;
  status)      status_timer ;;
  set-time)    set_time "${TIME_ARG}" ;;
  set-calendar)set_calendar "${CAL_ARG}" ;;
  uninstall)   uninstall_all ;;
  *)           echo "[ERROR] no valid action"; exit 1 ;;
esac
