#!/bin/bash

set -e

# VAULT_VERSION="1.16.0"
# OUTPUT_FILE="output.txt"
CONFIG_FILE="configure.hcl"

echo "[*] Installing dependencies..."
sudo apt-get update -y
sudo apt-get install -y wget unzip curl jq

echo "[*] Downloading Vault ${VAULT_VERSION}..."
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault

#echo "[*] Creating Vault user and directories..."
#sudo useradd --system --home /etc/vault.d --shell /bin/false vault
#sudo mkdir -p /opt/vault/data
#sudo chown -R vault:vault /opt/vault

echo "[*] Creating Vault config file..."
cat <<EOF > ${CONFIG_FILE}
ui = true
disable_mlock = true

storage "raft" {
  path = "/opt/vault/data"
  node_id = "vault-node-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"
EOF

echo "[*] Starting Vault in background..."
sudo -u vault vault server -config=${CONFIG_FILE} > vault.log 2>&1 &
sleep 5

export VAULT_ADDR='http://127.0.0.1:8200'

# Wait for Vault to be reachable
echo "[*] Waiting for Vault to be ready..."
until curl -s $VAULT_ADDR/v1/sys/health | jq -e '.initialized == false' > /dev/null 2>&1; do
  sleep 2
done

echo "[*] Initializing Vault..."
INIT_OUTPUT=$(vault operator init -key-shares=5 -key-threshold=3)

# Extract unseal keys and root token from INIT_OUTPUT
UNSEAL_KEY_1=$(echo "$INIT_OUTPUT" | grep 'Unseal Key 1' | awk '{print $NF}')
UNSEAL_KEY_2=$(echo "$INIT_OUTPUT" | grep 'Unseal Key 2' | awk '{print $NF}')
UNSEAL_KEY_3=$(echo "$INIT_OUTPUT" | grep 'Unseal Key 3' | awk '{print $NF}')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | grep 'Initial Root Token' | awk '{print $NF}')

echo "[*] Vault initialized. Root token and unseal keys retrieved."

# Unseal the Vault using the first 3 unseal keys
echo "[*] Unsealing Vault..."
vault operator unseal "$UNSEAL_KEY_1"
vault operator unseal "$UNSEAL_KEY_2"
vault operator unseal "$UNSEAL_KEY_3"

echo "[*] Vault unsealed."

# Export root token for further usage
export VAULT_TOKEN=$ROOT_TOKEN

echo "[*] Vault is ready to use with root token:"
echo "$ROOT_TOKEN" > /home/ubuntu/root_token.txt

echo "[*] Vault UI available at: http://127.0.0.1:8200"
