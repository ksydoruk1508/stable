#!/usr/bin/env bash
# Pretty usage dashboard for Stable node (disk / CPU / RAM)
# Works on Ubuntu/Debian. Needs: bash, awk, ps, pgrep, df, du, numfmt, curl, jq (jq optional).
# Author: N3R helper

set -Eeuo pipefail

# ---------- defaults (можно переопределить флагами) ----------
SERVICE_NAME="stabled"
BIN_NAME="stabled"
HOME_DIR="/root/.stabled"
RPC_PORT="26657"

# ---------- parse args ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --service) SERVICE_NAME="${2:?}"; shift 2 ;;
    --home)    HOME_DIR="${2:?}"; shift 2 ;;
    --bin)     BIN_NAME="${2:?}"; shift 2 ;;
    --rpc)     RPC_PORT="${2:?}"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--service NAME] [--home PATH] [--bin BIN] [--rpc PORT]
Defaults: service=stabled, home=/root/.stabled, bin=stabled, rpc=26657
EOF
      exit 0
      ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# ---------- colors / ui ----------
cG=$'\033[0;32m'; cC=$'\033[0;36m'; cB=$'\033[0;34m'; cR=$'\033[0;31m'
cY=$'\033[1;33m'; cM=$'\033[1;35m'; c0=$'\033[0m'; cBold=$'\033[1m'; cDim=$'\033[2m'
hr(){ echo -e "${cDim}────────────────────────────────────────────────────────────${c0}"; }
badge_ok(){ echo -e "${cG}OK${c0}"; }
badge_warn(){ echo -e "${cY}WARN${c0}"; }
badge_err(){ echo -e "${cR}ERROR${c0}"; }

# ---------- helpers ----------
need(){ command -v "$1" &>/dev/null || { echo "Missing '$1'"; exit 1; }; }
fmt_bytes(){ numfmt --to=iec --suffix=B --format="%.2f" "${1:-0}" 2>/dev/null || echo "${1}B"; }

get_mem_total_kb(){ awk '/MemTotal:/ {print $2}' /proc/meminfo; }
get_mem_avail_kb(){ awk '/MemAvailable:/ {print $2}' /proc/meminfo; }

# Sum ps columns for PIDs
sum_ps_field(){
  local field="$1"; shift
  local total=0
  # shellcheck disable=SC2068
  for pid in $@; do
    val=$(ps -o "$field"= -p "$pid" 2>/dev/null | awk '{print $1}')
    [[ -n "$val" ]] || val=0
    # rss is in KB, %cpu/%mem are floats — аккуратно
    if [[ "$field" == "rss" ]]; then
      total=$(( total + ${val%.*} ))
    else
      # суммирование float
      total=$(awk -v a="$total" -v b="$val" 'BEGIN{printf "%.2f", a+b}')
    fi
  done
  echo "$total"
}

oldest_etime(){
  local et=""; local p
  for p in "$@"; do
    cur=$(ps -o etime= -p "$p" | head -n1 | tr -d ' ')
    [[ -z "$et" ]] && et="$cur" && continue
    # не усложняем парсер, просто вернём первый попавшийся если несколько
  done
  [[ -n "$et" ]] && echo "$et" || echo "-"
}

# ---------- data collection ----------
need awk; need ps; need pgrep; need df; need du; need numfmt

# PIDs by service name first, fallback by binary name
PIDS=$(pgrep -x "$SERVICE_NAME" || true)
if [[ -z "$PIDS" ]]; then
  PIDS=$(pgrep -x "$BIN_NAME" || true)
fi

SERVICE_ACTIVE="inactive"
if command -v systemctl &>/dev/null; then
  if systemctl is-active --quiet "$SERVICE_NAME"; then SERVICE_ACTIVE="active"; fi
fi

# Disk usage (node home, data, wasmd/tendermint style)
HOME_BYTES=$(du -sb "$HOME_DIR" 2>/dev/null | awk '{print $1}')
DATA_BYTES=$(du -sb "$HOME_DIR/data" 2>/dev/null | awk '{print $1}')
APPDB_BYTES=$(du -sb "$HOME_DIR/data/application.db" 2>/dev/null | awk '{print $1}')
BLOCKS_BYTES=$(du -sb "$HOME_DIR/data/blockstore.db" 2>/dev/null | awk '{print $1}')
SNAP_BYTES=$(du -sb "$HOME_DIR/data/snapshots" 2>/dev/null | awk '{print $1}')

# Filesystem usage
FS_USED_PCT=$(df -h "$HOME_DIR" 2>/dev/null | awk 'NR==2{gsub("%","",$5);print $5}')
FS_SIZE=$(df -h "$HOME_DIR" 2>/dev/null | awk 'NR==2{print $2}')
FS_AVAIL=$(df -h "$HOME_DIR" 2>/dev/null | awk 'NR==2{print $4}')

# CPU/RAM for process group
CPU_PCT="0.00"; MEM_PCT="0.00"; RSS_KB=0; ETIME="-"; THREADS=0; FD_COUNT="-"
if [[ -n "$PIDS" ]]; then
  CPU_PCT=$(sum_ps_field "%cpu" $PIDS)
  MEM_PCT=$(sum_ps_field "%mem" $PIDS)
  RSS_KB=$(sum_ps_field "rss" $PIDS)
  ETIME=$(oldest_etime $PIDS)
  THREADS=$(ps -o nlwp= -p $(echo $PIDS | awk '{print $1}') 2>/dev/null | awk '{sum+=$1}END{print sum+0}')
  if command -v lsof &>/dev/null; then
    FD_COUNT=$(lsof -p "$(echo $PIDS | awk '{print $1}')" 2>/dev/null | wc -l | awk '{print $1}')
  fi
fi

RSS_BYTES=$(( RSS_KB * 1024 ))
RSS_HUMAN=$(fmt_bytes "$RSS_BYTES")

MEM_TOTAL_KB=$(get_mem_total_kb || echo 0)
MEM_AVAIL_KB=$(get_mem_avail_kb || echo 0)
MEM_USED_SYS_PCT=$(awk -v t="$MEM_TOTAL_KB" -v a="$MEM_AVAIL_KB" 'BEGIN{if(t>0){printf "%.0f", (100- (a*100.0/t))}else{print 0}}')

# RPC stats (опционально)
SYNC_TXT="—"
PEERS_TXT="—"
if command -v curl &>/dev/null && command -v jq &>/dev/null; then
  SYNC=$(curl -s "http://127.0.0.1:${RPC_PORT}/status" | jq -r '.result.sync_info.catching_up' 2>/dev/null || true)
  if [[ "$SYNC" == "false" ]]; then SYNC_TXT="synced"; elif [[ "$SYNC" == "true" ]]; then SYNC_TXT="syncing"; fi
  PEERS=$(curl -s "http://127.0.0.1:${RPC_PORT}/net_info" | jq -r '.result.n_peers' 2>/dev/null || true)
  [[ -n "${PEERS:-}" ]] && PEERS_TXT="$PEERS"
fi

# ---------- output ----------
clear
hr
echo -e "${cBold}${cM}Stable Node — Usage Dashboard${c0}"
hr

# Service / process
echo -e "${cBold}${cB}Сервис:${c0}           $SERVICE_NAME  | статус: $( [[ "$SERVICE_ACTIVE" == "active" ]] && echo -e "$(badge_ok)" || echo -e "$(badge_warn)")"
echo -e "${cBold}${cB}Процесс:${c0}          ${BIN_NAME}    | PID(s): ${PIDS:-none}"
echo -e "${cBold}${cB}Аптайм процесса:${c0} ${ETIME}"
echo -e "${cBold}${cB}Потоки/FD:${c0}        ${THREADS:-0} threads  | fd: ${FD_COUNT}"

hr
# CPU / RAM
cpu_badge="$(badge_ok)"; cpu_val="$CPU_PCT%"
cpu_num=$(printf "%.2f" "${CPU_PCT}")
awk -v v="$cpu_num" 'BEGIN{exit !(v>=300)}' || cpu_badge="$(badge_warn)"
echo -e "${cBold}${cC}CPU (сумма по PID):${c0}  $cpu_val  | $cpu_badge  ${cDim}(на всех ядрах)${c0}"

echo -e "${cBold}${cC}RAM процесса:${c0}       ${RSS_HUMAN}  (${MEM_PCT}% из всей RAM)"
echo -e "${cBold}${cC}RAM системы:${c0}        занято ~${MEM_USED_SYS_PCT}%"

hr
# Disk
echo -e "${cBold}${cG}Диск (FS для ${HOME_DIR}):${c0} used ${FS_USED_PCT}%  of ${FS_SIZE}, free ${FS_AVAIL}"
echo -e "${cBold}${cG}Нода — всего:${c0}       $(fmt_bytes "${HOME_BYTES:-0}")  ${cDim}(${HOME_DIR})${c0}"
echo -e "${cBold}${cG}data:${c0}               $(fmt_bytes "${DATA_BYTES:-0}")"
printf "%-20s %s\n" "  application.db:" "$(fmt_bytes "${APPDB_BYTES:-0}")"
printf "%-20s %s\n" "  blockstore.db:"   "$(fmt_bytes "${BLOCKS_BYTES:-0}")"
printf "%-20s %s\n" "  snapshots:"       "$(fmt_bytes "${SNAP_BYTES:-0}")"

hr
# Network / sync
echo -e "${cBold}${cM}Sync:${c0}              ${SYNC_TXT}    | ${cBold}${cM}Peers:${c0} ${PEERS_TXT}"
echo
echo -e "${cDim}Подсказки:${c0}"
echo -e " • CPU > 300% на 4 ядрах — это ~3 ядра под нагрузкой."
echo -e " • RAM процесса — резидентная память (RSS)."
echo -e " • Размер диска — реальный объём каталога ноды, удобно для планирования."
hr
