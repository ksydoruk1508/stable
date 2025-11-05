#!/usr/bin/env bash
# =====================================================================
# Stable — Installer/Manager (RU/EN), styled like Blockcast script
# Target: Ubuntu/Debian (root required)
# Version: 1.1.0
# =====================================================================
set -Eeuo pipefail

# -----------------------------
# Colors / UI
# -----------------------------
cG=$'\033[0;32m'; cC=$'\033[0;36m'; cB=$'\033[0;34m'; cR=$'\033[0;31m'
cY=$'\033[1;33m'; cM=$'\033[1;35m'; c0=$'\033[0m'; cBold=$'\033[1m'; cDim=$'\033[2m'

ok()   { echo -e "${cG}[OK]${c0} ${*}"; }
info() { echo -e "${cC}[INFO]${c0} ${*}"; }
warn() { echo -e "${cY}[WARN]${c0} ${*}"; }
err()  { echo -e "${cR}[ERROR]${c0} ${*}"; }
hr()   { echo -e "${cDim}────────────────────────────────────────────────────────${c0}"; }

logo(){ cat <<'EOF'
 _   _           _  _____      
| \ | |         | ||____ |     
|  \| | ___   __| |    / /_ __ 
| . ` |/ _ \ / _` |    \ \ '__|
| |\  | (_) | (_| |.___/ / |   
\_| \_/\___/ \__,_|\____/|_|
      Stable. Full Node
 Канал: https://t.me/NodesN3R
EOF
}

# -----------------------------
# App constants (original)
# -----------------------------
APP_NAME="Stable"
SERVICE_NAME="stabled"                     
BIN_PATH="/usr/bin/stabled"
HOME_DIR="/root/.stabled"
CHAIN_ID="stabletestnet_2201-1"

# ссылки и проверка
STABLED_URL="https://stable-testnet-data.s3.us-east-1.amazonaws.com/stabled-1.1.0-linux-amd64-testnet.tar.gz"
GENESIS_ZIP_URL="https://stable-testnet-data.s3.us-east-1.amazonaws.com/stable_testnet_genesis.zip"
RPC_CFG_ZIP_URL="https://stable-testnet-data.s3.us-east-1.amazonaws.com/rpc_node_config.zip"
SNAPSHOT_URL="https://stable-snapshot.s3.eu-central-1.amazonaws.com/snapshot.tar.lz4"

# ожидаемый sha256 для genesis 
GENESIS_SHA256_EXPECTED="66afbb6e57e6faf019b3021de299125cddab61d433f28894db751252f5b8eaf2"

# peers и сетевые правки
PEERS="5ed0f977a26ccf290e184e364fb04e268ef16430@37.187.147.27:26656,128accd3e8ee379bfdf54560c21345451c7048c7@37.187.147.22:26656"

# -----------------------------
# Language (RU/EN)
# -----------------------------
SCRIPT_VERSION="1.1.0"
LANG="ru"

choose_lang(){
  clear; logo
  echo -e "\n${cBold}${cM}Select language / Выберите язык${c0}"
  echo "1) Русский"
  echo "2) English"
  read -rp "> " a
  case "${a:-}" in
    2) LANG="en" ;;
    *) LANG="ru" ;;
  esac
}

tr(){
  local k="${1:-}"; [[ -z "$k" ]] && return 0
  if [[ "$LANG" == "en" ]]; then
    case "$k" in
      need_root)             echo "Run as root: sudo ./$(basename "$0")" ;;
      press)                 echo "Press Enter to return to menu..." ;;
      menu_title)            echo "${APP_NAME} Node — installer & manager" ;;
      m1) echo "Prepare server (update/upgrade, deps)";;
      m2) echo "Install node";;
      m3) echo "Start node";;
      m4) echo "Node logs (follow)";;
      m5) echo "Node status";;
      m6) echo "Restart node";;
      m7) echo "Remove node (binary, service, data)";;
      m8) echo "Node version";;
      m9) echo "Health check";;
      m0) echo "Exit";;

      prep_start)            echo "Updating APT and installing dependencies...";;
      prep_done)             echo "Server is ready.";;
      ask_moniker)           echo "Moniker (node name):";;
      bin_fetch)             echo "Downloading and installing stabled binary...";;
      init_node)             echo "Initializing node with chain-id ${CHAIN_ID}...";;
      genesis_fetch)         echo "Fetching genesis...";;
      genesis_ok)            echo "genesis checksum OK.";;
      genesis_bad)           echo "genesis checksum mismatch";;
      cfg_fetch)             echo "Fetching prebuilt configs (config.toml, app.toml)...";;
      cfg_patch)             echo "Patching configs (peers, RPC, limits, CORS, moniker)...";;
      svc_write)             echo "Writing systemd service ${SERVICE_NAME}.service...";;
      svc_enable)            echo "Enabling service...";;
      snap_ask)              echo "Apply snapshot now? [y/N]:";;
      snap_do)               echo "Applying snapshot...";;
      snap_done)             echo "Snapshot applied.";;
      install_done)          echo "Installation completed.";;
      start_ok)              echo "Node started.";;
      restart_ok)            echo "Node restarted.";;
      remove_ask)            echo "Remove binary, service and all node data? [y/N]:";;
      remove_cancel)         echo "Canceled.";;
      remove_done)           echo "Node and its logs removed.";;
      invalid_choice)        echo "Invalid choice.";;
      ver_title)             echo "Stable Node Version";;
      ver_bin)               echo "Binary version:";;
      ver_fail)              echo "Failed to read binary version";;

      hc_title)              echo "Stable Node Health Check";;
      hc_running)            echo "Service is running";;
      hc_stopped)            echo "Service is not running";;
      hc_synced)             echo "Node is synced";;
      hc_syncing)            echo "Node is syncing";;
      hc_peers_ok)           echo "Connected peers:";;
      hc_peers_low)          echo "Low peer count:";;
      hc_disk_ok)            echo "Disk usage";;
      hc_disk_high)          echo "High disk usage";;
      hc_mem_ok)             echo "Memory usage";;
      hc_mem_high)           echo "High memory usage";;
      hc_done)               echo "Health Check Complete";;
    esac
  else
    case "$k" in
      need_root)             echo "запусти от root: sudo ./$(basename "$0")" ;;
      press)                 echo "Нажмите Enter для возврата в меню..." ;;
      menu_title)            echo "Нода ${APP_NAME} — установщик и менеджер" ;;
      m1) echo "Подготовка сервера";;
      m2) echo "Установка ноды";;
      m3) echo "Запустить ноду";;
      m4) echo "Логи ноды";;
      m5) echo "Статус ноды";;
      m6) echo "Рестарт ноды";;
      m7) echo "Удалить ноду";;
      m8) echo "Версия ноды";;
      m9) echo "Проверка состояния (Health check)";;
      m0) echo "Выход";;

      prep_start)            echo "Обновляю APT и ставлю зависимости...";;
      prep_done)             echo "Сервер готов.";;
      ask_moniker)           echo "Монникер (имя узла):";;
      bin_fetch)             echo "Скачиваю и устанавливаю бинарь stabled...";;
      init_node)             echo "Инициализирую ноду с chain-id ${CHAIN_ID}...";;
      genesis_fetch)         echo "Скачиваю genesis...";;
      genesis_ok)            echo "genesis checksum ок.";;
      genesis_bad)           echo "checksum genesis не совпал";;
      cfg_fetch)             echo "Скачиваю готовые конфиги (config.toml, app.toml)...";;
      cfg_patch)             echo "Правлю конфиги (peers, RPC, лимиты, CORS, moniker)...";;
      svc_write)             echo "Пишу systemd сервис ${SERVICE_NAME}.service...";;
      svc_enable)            echo "Включаю сервис...";;
      snap_ask)              echo "Подтянуть снапшот сейчас? [y/N]:";;
      snap_do)               echo "Применяю снапшот...";;
      snap_done)             echo "Снапшот применён.";;
      install_done)          echo "Установка завершена.";;
      start_ok)              echo "Нода запущена.";;
      restart_ok)            echo "Нода перезапущена.";;
      remove_ask)            echo "Удалить бинарь, сервис и все данные ноды? [y/N]:";;
      remove_cancel)         echo "Отмена.";;
      remove_done)           echo "Нода и её логи удалены.";;
      invalid_choice)        echo "Неверный выбор.";;
      ver_title)             echo "Версия ноды Stable";;
      ver_bin)               echo "Версия ноды:";;
      ver_fail)              echo "Не удалось получить версию бинаря";;
      
      hc_title)              echo "Проверка состояния ноды Stable";;
      hc_running)            echo "Сервис запущен";;
      hc_stopped)            echo "Сервис не запущен";;
      hc_synced)             echo "Нода синхронизирована";;
      hc_syncing)            echo "Нода синхронизируется";;
      hc_peers_ok)           echo "Подключённых пиров:";;
      hc_peers_low)          echo "Мало пиров:";;
      hc_disk_ok)            echo "Занято диска";;
      hc_disk_high)          echo "Высокая загрузка диска";;
      hc_mem_ok)             echo "Занято памяти";;
      hc_mem_high)           echo "Высокая загрузка памяти";;
      hc_done)               echo "Проверка завершена";;
    esac
  fi
}

pause(){ read -rp "$(tr press)" _; }
need(){ command -v "$1" &>/dev/null || { err "not found '$1'"; exit 1; }; }

# -----------------------------
# Functions (logic unchanged)
# -----------------------------
prepare_server(){
  info "$(tr prep_start)"
  apt update && apt upgrade -y
  apt install -y curl wget tar unzip jq lz4 pv
  ok "$(tr prep_done)"
}

install_node(){
  need wget; need unzip; need jq; need curl

  read -r -p "$(tr ask_moniker) " MONIKER
  MONIKER=${MONIKER:-StableNodeN3R}

  # бинарь
  info "$(tr bin_fetch)"
  cd /root
  wget -O stabled.tar.gz "$STABLED_URL"
  tar -xvzf stabled.tar.gz
  mv -f stabled "$BIN_PATH"
  chmod +x "$BIN_PATH"
  rm -f stabled.tar.gz
  "$BIN_PATH" version || true

  # init
  info "$(tr init_node)"
  "$BIN_PATH" init "$MONIKER" --chain-id "$CHAIN_ID"

  # genesis
  info "$(tr genesis_fetch)"
  wget -O stable_testnet_genesis.zip "$GENESIS_ZIP_URL"
  unzip -o stable_testnet_genesis.zip
  cp -f genesis.json "$HOME_DIR/config/genesis.json"
  sha=$(sha256sum "$HOME_DIR/config/genesis.json" | awk '{print $1}')
  if [[ "$sha" != "$GENESIS_SHA256_EXPECTED" ]]; then
    warn "$(tr genesis_bad): got $sha, expected $GENESIS_SHA256_EXPECTED"
  else
    ok "$(tr genesis_ok)"
  fi

  # готовые конфиги
  info "$(tr cfg_fetch)"
  wget -O rpc_node_config.zip "$RPC_CFG_ZIP_URL"
  unzip -o rpc_node_config.zip
  cp -f config.toml "$HOME_DIR/config/config.toml"
  cp -f app.toml "$HOME_DIR/config/app.toml"

 
  info "$(tr cfg_patch)"
  # config.toml
  sed -i "s/^moniker = \".*\"/moniker = \"${MONIKER}\"/" "$HOME_DIR/config/config.toml"
  sed -i 's/^cors_allowed_origins = .*/cors_allowed_origins = ["*"]/' "$HOME_DIR/config/config.toml"
  sed -i "s|^persistent_peers = \".*\"|persistent_peers = \"${PEERS}\"|" "$HOME_DIR/config/config.toml"
  sed -i 's/^max_num_inbound_peers = .*/max_num_inbound_peers = 50/' "$HOME_DIR/config/config.toml"
  sed -i 's/^max_num_outbound_peers = .*/max_num_outbound_peers = 30/' "$HOME_DIR/config/config.toml"

  # app.toml [json-rpc]
  sed -i 's/^\(\s*enable\s*=\s*\).*/\1true/' "$HOME_DIR/config/app.toml"
  sed -i 's|^\(\s*address\s*=\s*\).*|\1"0.0.0.0:8545"|' "$HOME_DIR/config/app.toml"
  sed -i 's|^\(\s*ws-address\s*=\s*\).*|\1"0.0.0.0:8546"|' "$HOME_DIR/config/app.toml"
  sed -i 's/^\(\s*allow-unprotected-txs\s*=\s*\).*/\1true/' "$HOME_DIR/config/app.toml"

  # systemd
  info "$(tr svc_write)"
  tee /etc/systemd/system/${SERVICE_NAME}.service >/dev/null <<EOF
[Unit]
Description=Stable Daemon Service
After=network-online.target

[Service]
User=root
ExecStart=${BIN_PATH} start --chain-id ${CHAIN_ID}
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF

  info "$(tr svc_enable)"
  systemctl daemon-reload
  systemctl enable ${SERVICE_NAME}

  # снапшот (как ты делал)
  read -r -p "$(tr snap_ask) " use_snap
  if [[ "${use_snap,,}" =~ ^y ]]; then
    info "$(tr snap_do)"
    mkdir -p /root/stable-backup /root/snapshot
    cp -r "$HOME_DIR/data" /root/stable-backup/ 2>/dev/null || true
    cd /root/snapshot
    wget -c "$SNAPSHOT_URL" -O snapshot.tar.lz4
    rm -rf "$HOME_DIR/data"/* || true
    pv snapshot.tar.lz4 | tar -I lz4 -xf - -C "$HOME_DIR/"
    rm -f snapshot.tar.lz4
    ok "$(tr snap_done)"
  fi

  ok "$(tr install_done)"
}

start_node(){ systemctl start ${SERVICE_NAME}; ok "$(tr start_ok)"; }
logs_node(){ journalctl -u ${SERVICE_NAME} -f -n 200; }
status_node(){ systemctl status ${SERVICE_NAME}; }
restart_node(){ systemctl restart ${SERVICE_NAME}; ok "$(tr restart_ok)"; }

remove_node(){
  read -r -p "$(tr remove_ask) " yn
  [[ "${yn,,}" =~ ^y ]] || { warn "$(tr remove_cancel)"; return; }

  # остановить и выключить
  for UNIT in stabled stable; do
    systemctl stop "$UNIT" 2>/dev/null || true
    systemctl disable "$UNIT" 2>/dev/null || true
    rm -f "/etc/systemd/system/${UNIT}.service" 2>/dev/null || true
  done
  systemctl daemon-reload

  # добить ручные процессы
  pkill -f "[s]tabled" 2>/dev/null || true
  sleep 1
  pkill -9 -f "[s]tabled" 2>/dev/null || true

  # локи БД на всякий
  rm -f "$HOME_DIR/data/LOCK" "$HOME_DIR/data/application.db/LOCK" "$HOME_DIR/data/snapshots/LOCK" 2>/dev/null || true

  # снести данные и бинарь
  rm -rf "$HOME_DIR" /root/snapshot /root/stable-backup /tmp/stable_genesis /tmp/rpc_cfg 2>/dev/null || true
  rm -f  "$BIN_PATH" 2>/dev/null || true

  # снести только наши логи (другие сервисы не трогаем)
  rm -rf /var/log/stabled 2>/dev/null || true

  ok "$(tr remove_done)"
}

version_node(){
  clear; hr
  echo -e "${cBold}${cM}=== $(tr ver_title) ===${c0}\n"
  if out="$("${BIN_PATH}" version 2>/dev/null)"; then
    echo -e "${cG}✓${c0} $(tr ver_bin) ${out}"
  elif out="$(stabled version 2>/dev/null)"; then
    echo -e "${cG}✓${c0} $(tr ver_bin) ${out}"
  else
    err "$(tr ver_fail)"
  fi
}

# -----------------------------
# Health Check (added)
# -----------------------------
health_check(){
  need curl; need jq
  clear; hr
  echo -e "${cBold}${cM}=== $(tr hc_title) ===${c0}\n"

  if systemctl is-active --quiet "${SERVICE_NAME}"; then
    echo -e "${cG}✓${c0} $(tr hc_running)"
  else
    echo -e "${cR}✗${c0} $(tr hc_stopped)"
    echo
    echo -e "${cDim}systemctl status ${SERVICE_NAME}${c0}"
    systemctl status "${SERVICE_NAME}" --no-pager || true
    echo
    echo -e "${cDim}journalctl -u ${SERVICE_NAME} -n 200 --no-pager${c0}"
    journalctl -u "${SERVICE_NAME}" -n 200 --no-pager || true
    return 1
  fi

  # Sync status
  SYNC_STATUS=$(curl -s localhost:26657/status | jq -r '.result.sync_info.catching_up' 2>/dev/null || echo "unknown")
  if [[ "$SYNC_STATUS" == "false" ]]; then
    echo -e "${cG}✓${c0} $(tr hc_synced)"
  elif [[ "$SYNC_STATUS" == "true" ]]; then
    echo -e "${cY}⚠${c0} $(tr hc_syncing)"
  else
    echo -e "${cY}⚠${c0} $(tr hc_syncing) (unknown)"
  fi

  # Peers
  PEERS=$(curl -s localhost:26657/net_info | jq -r '.result.n_peers' 2>/dev/null || echo 0)
  if [[ "${PEERS:-0}" -ge 3 ]]; then
    echo -e "${cG}✓${c0} $(tr hc_peers_ok) ${PEERS}"
  else
    echo -e "${cY}⚠${c0} $(tr hc_peers_low) ${PEERS}"
  fi

  # Disk
  DISK_USAGE=$(df -h / | awk 'NR==2 {gsub("%","",$5); print $5}')
  if [[ "${DISK_USAGE:-0}" -lt 80 ]]; then
    echo -e "${cG}✓${c0} $(tr hc_disk_ok): ${DISK_USAGE}%"
  else
    echo -e "${cY}⚠${c0} $(tr hc_disk_high): ${DISK_USAGE}%"
  fi

  # Memory
  MEM_AVAILABLE=$(free -m | awk 'NR==2 {print $7}')
  MEM_TOTAL=$(free -m | awk 'NR==2 {print $2}')
  if [[ -n "${MEM_AVAILABLE}" && -n "${MEM_TOTAL}" && "${MEM_TOTAL}" -gt 0 ]]; then
    MEM_PERCENT=$((100 - (MEM_AVAILABLE * 100 / MEM_TOTAL)))
  else
    MEM_PERCENT=0
  fi
  if [[ "${MEM_PERCENT:-0}" -lt 80 ]]; then
    echo -e "${cG}✓${c0} $(tr hc_mem_ok): ${MEM_PERCENT}%"
  else
    echo -e "${cY}⚠${c0} $(tr hc_mem_high): ${MEM_PERCENT}%"
  fi

  echo -e "\n${cBold}${cM}=== $(tr hc_done) ===${c0}"
}

# -----------------------------
# Menu (Blockcast-style)
# -----------------------------
menu(){
  clear; logo; hr
  echo -e "${cBold}${cM}$(tr menu_title)${c0} ${cDim}(v${SCRIPT_VERSION})${c0}\n"
  echo "1) $(tr m1)"
  echo "2) $(tr m2)"
  echo "3) $(tr m3)"
  echo "4) $(tr m4)"
  echo "5) $(tr m5)"
  echo "6) $(tr m6)"
  echo "7) $(tr m7)"
  echo "8) $(tr m8)"
  echo "9) $(tr m9)"
  echo "0) $(tr m0)"

  hr
  read -rp "> " c
  case "${c:-}" in
    1) prepare_server; pause ;;
    2) install_node;   pause ;;
    3) start_node;     pause ;;
    4) logs_node ;;                # follow
    5) status_node;    pause ;;
    6) restart_node;   pause ;;
    7) remove_node;    pause ;;
    8) version_node;   pause ;;
    9) health_check;   echo; pause ;;
    0) exit 0 ;;
    *) err "$(tr invalid_choice)"; pause ;;
  esac
}

# -----------------------------
# Bootstrap
# -----------------------------
main(){
  choose_lang
  if [[ "$EUID" -ne 0 ]]; then
    err "$(tr need_root)"; exit 1
  fi
  while true; do menu; done
}

main
