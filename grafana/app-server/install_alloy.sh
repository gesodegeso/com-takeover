#!/bin/bash
# ============================================
# install_alloy.sh
# Grafana Alloy インストール＆セットアップスクリプト
# ============================================
#
# 使い方:
#   chmod +x install_alloy.sh
#   sudo ./install_alloy.sh <GRAFANA_SERVER_IP>
#
# 例:
#   sudo ./install_alloy.sh 192.168.1.100
#
# ============================================

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <GRAFANA_SERVER_IP>"
    echo "Example: $0 192.168.1.100"
    exit 1
fi

GRAFANA_SERVER_IP="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo " Grafana Alloy セットアップ"
echo " Grafana Server: ${GRAFANA_SERVER_IP}"
echo "============================================"

# -----------------------------------------------
# 1. インストール
# -----------------------------------------------
if [ -f /etc/debian_version ]; then
    echo "[INFO] Debian/Ubuntu を検出"
    sudo mkdir -p /etc/apt/keyrings/
    wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
    echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
    sudo apt-get update
    sudo apt-get install -y alloy

elif [ -f /etc/redhat-release ]; then
    echo "[INFO] RHEL/CentOS/Rocky を検出"
    sudo rpm --import https://rpm.grafana.com/gpg.key
    cat <<'EOF' | sudo tee /etc/yum.repos.d/grafana.repo
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
EOF
    sudo dnf install -y alloy || sudo yum install -y alloy
else
    echo "[ERROR] サポートされていない OS です"
    exit 1
fi

# -----------------------------------------------
# 2. ログディレクトリの準備
# -----------------------------------------------
echo "[INFO] ログディレクトリを準備中..."

sudo mkdir -p /var/log/mysql /var/log/myapp
sudo chown mysql:mysql /var/log/mysql 2>/dev/null || true
sudo chmod 755 /var/log/mysql /var/log/myapp

# Alloy ユーザーにログ読み取り権限を付与
sudo usermod -aG adm alloy 2>/dev/null || true
sudo usermod -aG mysql alloy 2>/dev/null || true
sudo usermod -aG www-data alloy 2>/dev/null || true   # Debian Nginx
sudo usermod -aG nginx alloy 2>/dev/null || true       # RHEL Nginx

# ACL（利用可能な場合）
if command -v setfacl &> /dev/null; then
    for dir in /var/log/nginx /var/log/mysql /var/log/myapp; do
        if [ -d "$dir" ]; then
            sudo setfacl -R -m u:alloy:rX "$dir"
            sudo setfacl -R -d -m u:alloy:rX "$dir"
        fi
    done
    echo "[INFO] ACL を設定しました"
fi

# -----------------------------------------------
# 3. 設定ファイルの配置
# -----------------------------------------------
echo "[INFO] 設定ファイルを配置中..."

if [ -f "${SCRIPT_DIR}/alloy/config.alloy" ]; then
    sudo cp "${SCRIPT_DIR}/alloy/config.alloy" /etc/alloy/config.alloy
    sudo sed -i "s/GRAFANA_SERVER_IP/${GRAFANA_SERVER_IP}/g" /etc/alloy/config.alloy
    echo "[INFO] config.alloy を配置し、IP を ${GRAFANA_SERVER_IP} に設定しました"
else
    echo "[WARN] alloy/config.alloy が見つかりません。手動で /etc/alloy/config.alloy を配置してください"
fi

# -----------------------------------------------
# 4. systemd ジャーナルアクセス権
# -----------------------------------------------
sudo mkdir -p /etc/systemd/system/alloy.service.d/
cat <<EOF | sudo tee /etc/systemd/system/alloy.service.d/override.conf
[Service]
SupplementaryGroups=systemd-journal
EOF

# -----------------------------------------------
# 5. 起動
# -----------------------------------------------
sudo systemctl daemon-reload
sudo systemctl enable alloy
sudo systemctl restart alloy

# -----------------------------------------------
# 6. 検証
# -----------------------------------------------
echo ""
echo "============================================"
echo " セットアップ完了"
echo "============================================"

sleep 2
if sudo systemctl is-active --quiet alloy; then
    echo "[OK] Alloy が正常に起動しています"
else
    echo "[FAIL] Alloy の起動に失敗しました"
    sudo journalctl -u alloy --no-pager -n 20
    exit 1
fi

echo ""
echo "  管理 UI:  http://$(hostname -I | awk '{print $1}'):12345"
echo "  ログ確認: sudo journalctl -u alloy -f"
echo ""
echo "  ★ 環境に合わせて設定を調整してください:"
echo "  sudo vim /etc/alloy/config.alloy"
echo "  sudo systemctl restart alloy"
echo ""
