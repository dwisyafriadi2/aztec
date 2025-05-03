#!/bin/bash

# Memuat logo dari repositori
if ! type curl >/dev/null 2>&1; then
  echo "curl tidak ditemukan, menginstall curl terlebih dahulu..."
  sudo apt-get update -y && sudo apt-get install -y curl
fi
source <(curl -fsSL https://raw.githubusercontent.com/dwisyafriadi2/logo/refs/heads/main/logo.sh)

# Pastikan PATH ke Aztec CLI
export PATH="$HOME/.aztec/bin:$PATH"

# Kode warna
RESET="\033[0m"
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
LIGHT_GREEN="\033[1;32m"
LIGHT_CYAN="\033[1;36m"

# Fungsi update apt
function update_apt() {
  sudo apt-get update -y
}

# 1. Install Docker
function install_docker() {
  if command -v docker &>/dev/null; then
    echo -e "${LIGHT_GREEN}Docker sudah terpasang: $(docker --version)${RESET}"
  else
    echo -e "${CYAN}Menginstall Docker...${RESET}"
    update_apt
    sudo apt-get upgrade -y
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
      sudo apt-get remove -y $pkg 2>/dev/null
    done
    sudo apt-get install -y --no-install-recommends ca-certificates curl gnupg
    sudo install -d -m0755 /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || exit 1
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    update_apt
    sudo apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl enable docker && sudo systemctl restart docker
    echo -e "${LIGHT_GREEN}Docker berhasil diinstall.${RESET}"
  fi
  read -p "Tekan Enter untuk kembali ke menu utama..."
}

# 2. Install Dependencies
function install_dependencies() {
  echo -e "${CYAN}Menginstall dependensi...${RESET}"
  update_apt
  sudo apt-get install -y curl net-tools psmisc jq
  echo -e "${LIGHT_GREEN}Dependensi berhasil diinstall.${RESET}"
  read -p "Tekan Enter untuk kembali ke menu utama..."
}

# 3. Install Sequencer Node
function install_sequencer_node() {
  echo -e "${CYAN}Install & setup Sequencer Node...${RESET}"
  if [ -d "$HOME/.aztec/alpha-testnet" ]; then
    rm -rf "$HOME/.aztec/alpha-testnet"
  fi
  mkdir -p ~/.aztec/bin
  curl -fsSL https://install.aztec.network | bash
  grep -qxF 'export PATH="$HOME/.aztec/bin:$PATH"' ~/.bashrc || \
    echo 'export PATH="$HOME/.aztec/bin:$PATH"' >> ~/.bashrc
  source ~/.bashrc
  export PATH="$HOME/.aztec/bin:$PATH"

  echo -e "${CYAN}Inisialisasi alpha-testnet...${RESET}"
  if ! command -v aztec-up &>/dev/null; then
    echo -e "${YELLOW}Pastikan \$HOME/.aztec/bin di PATH.${RESET}"
    read -p "Tekan Enter untuk kembali ke menu utama..."
    return
  fi
  aztec-up alpha-testnet

  IP=$(curl -s https://api.ipify.org)
  read -p "RPC URL ETH Sepolia: " L1_RPC_URL
  read -p "Beacon URL ETH Sepolia: " L1_CONSENSUS_URL
  read -p "Validator Private Key: " VALIDATOR_PRIVATE_KEY
  read -p "Coinbase Address: " COINBASE_ADDRESS

  cat > ~/start_aztec_node.sh <<EOF
#!/bin/bash
export PATH=\$HOME/.aztec/bin:\$PATH
exec aztec start --node --archiver --sequencer \
  --network alpha-testnet \
  --port 8080 \
  --l1-rpc-urls $L1_RPC_URL \
  --l1-consensus-host-urls $L1_CONSENSUS_URL \
  --sequencer.validatorPrivateKey $VALIDATOR_PRIVATE_KEY \
  --sequencer.coinbase $COINBASE_ADDRESS \
  --p2p.p2pIp $IP \
  --p2p.maxTxPoolSize 10000
EOF
  chmod +x ~/start_aztec_node.sh
  echo -e "${LIGHT_GREEN}Setup selesai. Gunakan menu 'Run Sequencer Node' untuk jalankan node.${RESET}"
  read -p "Tekan Enter untuk kembali ke menu utama..."
}

# 4. Cek Blok
function check_block_number() {
  echo -e "${CYAN}Block number proven:${RESET}"
  curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":1}' \
    http://localhost:8080 | jq -r '.result.proven.number'
  read -p "Tekan Enter..."
}

# 5. Cek Archive Sibling Path
function check_archive_sibling_path() {
  read -p "Block number: " bn
  curl -s -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"node_getArchiveSiblingPath","params":["'"$bn"'","'"$bn"'"],"id":1}' \
    http://localhost:8080 | jq -r .result
  read -p "Tekan Enter..."
}

# 6. Add Validator
function add_validator() {
  if ! command -v aztec &>/dev/null; then
    echo -e "${RED}Aztec CLI belum terinstal. Jalankan instalasi Sequencer Node!${RESET}"
    read -p "Tekan Enter..."
    return
  fi
  read -p "RPC URL ETH Sepolia: " RPC
  read -p "Private Key: " PK
  read -p "Validator Address: " ADDR
  aztec add-l1-validator --l1-rpc-urls "$RPC" --private-key "$PK" \
    --attester "$ADDR" --proposer-eoa "$ADDR" \
    --staking-asset-handler 0xF739D03e98e23A7B65940848aBA8921fF3bAc4b2 \
    --l1-chain-id 11155111
  read -p "Tekan Enter..."
}

# 7. Run Sequencer Node
function run_node() {
  if [ -f ~/start_aztec_node.sh ]; then
    nohup bash ~/start_aztec_node.sh > ~/aztec.log 2>&1 &
    echo -e "${LIGHT_GREEN}Node berjalan (PID: $!). Log: ~/aztec.log${RESET}"
  else
    echo -e "${RED}Script start_aztec_node.sh tidak ditemukan!${RESET}"
  fi
  read -p "Tekan Enter..."
}

# 8. Cek Logs
function check_logs() {
  if [ -f ~/aztec.log ]; then
    tail -f ~/aztec.log
  else
    echo -e "${YELLOW}aztec.log tidak ada, coba 'screen -r aztec'?${RESET}"
  fi
  read -p "Tekan Enter..."
}

# 9. Uninstall
function uninstall_all() {
  PID=$(pgrep -f start_aztec_node.sh)
  [[ -n "$PID" ]] && kill $PID
  rm -rf ~/.aztec start_aztec_node.sh aztec.log
  echo -e "${LIGHT_GREEN}Node & data dihapus.${RESET}"
  read -p "Tekan Enter..."
}

# 10. Stop Node
function stop_node() {
  PID=$(pgrep -f start_aztec_node.sh)
  if [[ -n "$PID" ]]; then
    kill $PID
    echo -e "${YELLOW}Node dihentikan (PID: $PID).${RESET}"
  else
    echo -e "${RED}Node tidak ditemukan sedang berjalan.${RESET}"
  fi
  read -p "Tekan Enter..."
}

# Menu Utama
function main_menu() {
  clear
  declare -f logo &>/dev/null && logo
  echo -e "${LIGHT_CYAN}1) Install Docker
2) Install Dependencies
3) Install Sequencer Node
4) Cek Blok
5) Cek Archive Sibling Path
6) Add Validator
7) Run Sequencer Node
8) Cek Logs
9) Uninstall
10) Stop Node
0) Keluar${RESET}"
  read -p "Pilih menu: " opt
  case $opt in
    1) install_docker;;
    2) install_dependencies;;
    3) install_sequencer_node;;
    4) check_block_number;;
    5) check_archive_sibling_path;;
    6) add_validator;;
    7) run_node;;
    8) check_logs;;
    9) uninstall_all;;
    10) stop_node;;
    0) exit 0;;
    *) echo -e "${RED}Pilihan tidak valid!${RESET}"; sleep 1;;
  esac
  main_menu
}

main_menu
