#!/bin/bash
# ============================================
# install_grafana_stack.sh
# Grafana + Loki + Prometheus + Tempo
# ネイティブインストール（Docker不使用）
# ============================================
#
# 使い方:
#   chmod +x install_grafana_stack.sh
#   sudo ./install_grafana_stack.sh
#
# 対応 OS: Ubuntu 22.04/24.04, Debian 12, RHEL 8/9, Rocky 8/9
# ============================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo " Grafana Observability Stack インストール"
echo " (Docker 不使用 / ネイティブインストール)"
echo "============================================"
echo ""

# -----------------------------------------------
# OS 判定
# -----------------------------------------------
if [ -f /etc/debian_version ]; then
    OS_FAMILY="debian"
    echo "[INFO] Debian/Ubuntu を検出"
elif [ -f /etc/redhat-release ]; then
    OS_FAMILY="rhel"
    echo "[INFO] RHEL/CentOS/Rocky を検出"
else
    echo "[ERROR] サポートされていない OS です"
    exit 1
fi

# -----------------------------------------------
# 共通: ユーザー・ディレクトリ作成
# -----------------------------------------------
create_service_user() {
    local user=$1
    if ! id "$user" &>/dev/null; then
        sudo useradd --system --no-create-home --shell /usr/sbin/nologin "$user"
        echo "[INFO] ユーザー ${user} を作成しました"
    fi
}

# ============================================
# 1. Grafana のインストール
# ============================================
install_grafana() {
    echo ""
    echo "============================================"
    echo " [1/4] Grafana のインストール"
    echo "============================================"

    if [ "$OS_FAMILY" = "debian" ]; then
        sudo apt-get install -y apt-transport-https software-properties-common wget
        sudo mkdir -p /etc/apt/keyrings/
        wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
        echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
        sudo apt-get update
        sudo apt-get install -y grafana
    else
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
        sudo dnf install -y grafana
    fi

    # プロビジョニングディレクトリの作成
    sudo mkdir -p /etc/grafana/provisioning/datasources

    echo "[INFO] Grafana インストール完了"
}

# ============================================
# 2. Loki のインストール
# ============================================
install_loki() {
    echo ""
    echo "============================================"
    echo " [2/4] Loki のインストール"
    echo "============================================"

    # 最新バージョンの取得
    LOKI_VERSION=$(curl -s https://api.github.com/repos/grafana/loki/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [ -z "$LOKI_VERSION" ]; then
        LOKI_VERSION="3.4.2"
        echo "[WARN] バージョン自動取得に失敗。v${LOKI_VERSION} を使用します"
    fi
    echo "[INFO] Loki v${LOKI_VERSION} をインストール中..."

    # バイナリのダウンロード
    cd /tmp
    wget -q "https://github.com/grafana/loki/releases/download/v${LOKI_VERSION}/loki-linux-amd64.zip"
    unzip -o loki-linux-amd64.zip
    chmod +x loki-linux-amd64
    sudo mv loki-linux-amd64 /usr/local/bin/loki
    rm -f loki-linux-amd64.zip

    # ユーザー・ディレクトリ作成
    create_service_user "loki"
    sudo mkdir -p /etc/loki /var/lib/loki
    sudo chown loki:loki /var/lib/loki

    echo "[INFO] Loki インストール完了 ($(loki --version 2>&1 | head -1))"
}

# ============================================
# 3. Prometheus のインストール
# ============================================
install_prometheus() {
    echo ""
    echo "============================================"
    echo " [3/4] Prometheus のインストール"
    echo "============================================"

    PROM_VERSION=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [ -z "$PROM_VERSION" ]; then
        PROM_VERSION="2.53.0"
        echo "[WARN] バージョン自動取得に失敗。v${PROM_VERSION} を使用します"
    fi
    echo "[INFO] Prometheus v${PROM_VERSION} をインストール中..."

    cd /tmp
    wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
    tar xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
    cd "prometheus-${PROM_VERSION}.linux-amd64"

    sudo mv prometheus /usr/local/bin/
    sudo mv promtool /usr/local/bin/

    # コンソールテンプレート
    sudo mkdir -p /etc/prometheus /var/lib/prometheus
    sudo mv consoles console_libraries /etc/prometheus/ 2>/dev/null || true

    # ユーザー・権限
    create_service_user "prometheus"
    sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

    # クリーンアップ
    cd /tmp
    rm -rf "prometheus-${PROM_VERSION}.linux-amd64" "prometheus-${PROM_VERSION}.linux-amd64.tar.gz"

    echo "[INFO] Prometheus インストール完了 ($(prometheus --version 2>&1 | head -1))"
}

# ============================================
# 4. Tempo のインストール
# ============================================
install_tempo() {
    echo ""
    echo "============================================"
    echo " [4/4] Tempo のインストール"
    echo "============================================"

    TEMPO_VERSION=$(curl -s https://api.github.com/repos/grafana/tempo/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
    if [ -z "$TEMPO_VERSION" ]; then
        TEMPO_VERSION="2.7.1"
        echo "[WARN] バージョン自動取得に失敗。v${TEMPO_VERSION} を使用します"
    fi
    echo "[INFO] Tempo v${TEMPO_VERSION} をインストール中..."

    cd /tmp
    wget -q "https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/tempo_${TEMPO_VERSION}_linux_amd64.tar.gz"
    tar xzf "tempo_${TEMPO_VERSION}_linux_amd64.tar.gz"
    chmod +x tempo
    sudo mv tempo /usr/local/bin/tempo
    rm -f "tempo_${TEMPO_VERSION}_linux_amd64.tar.gz"

    # ユーザー・ディレクトリ作成
    create_service_user "tempo"
    sudo mkdir -p /etc/tempo /var/lib/tempo
    sudo chown -R tempo:tempo /var/lib/tempo

    echo "[INFO] Tempo インストール完了 ($(tempo --version 2>&1 | head -1))"
}

# ============================================
# 5. 設定ファイルの配置
# ============================================
deploy_configs() {
    echo ""
    echo "============================================"
    echo " 設定ファイルを配置中..."
    echo "============================================"

    # Loki 設定
    if [ -f "${SCRIPT_DIR}/config/loki-config.yaml" ]; then
        sudo cp "${SCRIPT_DIR}/config/loki-config.yaml" /etc/loki/loki-config.yaml
        sudo chown loki:loki /etc/loki/loki-config.yaml
        echo "[INFO] Loki 設定ファイルを配置しました"
    else
        echo "[WARN] config/loki-config.yaml が見つかりません"
    fi

    # Prometheus 設定
    if [ -f "${SCRIPT_DIR}/config/prometheus.yml" ]; then
        sudo cp "${SCRIPT_DIR}/config/prometheus.yml" /etc/prometheus/prometheus.yml
        sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml
        echo "[INFO] Prometheus 設定ファイルを配置しました"
    else
        echo "[WARN] config/prometheus.yml が見つかりません"
    fi

    # Tempo 設定
    if [ -f "${SCRIPT_DIR}/config/tempo.yaml" ]; then
        sudo cp "${SCRIPT_DIR}/config/tempo.yaml" /etc/tempo/tempo.yaml
        sudo chown tempo:tempo /etc/tempo/tempo.yaml
        echo "[INFO] Tempo 設定ファイルを配置しました"
    else
        echo "[WARN] config/tempo.yaml が見つかりません"
    fi

    # Grafana データソース プロビジョニング
    if [ -f "${SCRIPT_DIR}/config/datasources.yaml" ]; then
        sudo cp "${SCRIPT_DIR}/config/datasources.yaml" /etc/grafana/provisioning/datasources/datasources.yaml
        sudo chown root:grafana /etc/grafana/provisioning/datasources/datasources.yaml
        echo "[INFO] Grafana データソース設定を配置しました"
    else
        echo "[WARN] config/datasources.yaml が見つかりません"
    fi

    # systemd ユニットファイル
    for unit in loki.service prometheus.service tempo.service; do
        if [ -f "${SCRIPT_DIR}/systemd/${unit}" ]; then
            sudo cp "${SCRIPT_DIR}/systemd/${unit}" "/etc/systemd/system/${unit}"
            echo "[INFO] ${unit} を配置しました"
        fi
    done

    sudo systemctl daemon-reload
}

# ============================================
# 6. サービスの有効化と起動
# ============================================
start_services() {
    echo ""
    echo "============================================"
    echo " サービスを起動中..."
    echo "============================================"

    for svc in loki prometheus tempo grafana-server; do
        sudo systemctl enable "$svc"
        sudo systemctl start "$svc"
        if sudo systemctl is-active --quiet "$svc"; then
            echo "[OK]   ${svc} が起動しました"
        else
            echo "[FAIL] ${svc} の起動に失敗しました"
            sudo journalctl -u "$svc" --no-pager -n 10
        fi
    done
}

# ============================================
# 7. ファイアウォール設定
# ============================================
setup_firewall() {
    echo ""
    echo "============================================"
    echo " ファイアウォールを設定中..."
    echo "============================================"

    if command -v ufw &> /dev/null; then
        echo "[INFO] UFW を使用"
        sudo ufw allow 3000/tcp comment "Grafana Web UI"
        sudo ufw allow 3100/tcp comment "Loki (log push from app servers)"
        sudo ufw allow 9090/tcp comment "Prometheus (remote_write from app servers)"
        sudo ufw allow 4317/tcp comment "Tempo OTLP gRPC (trace push from app servers)"
        sudo ufw allow 4318/tcp comment "Tempo OTLP HTTP"
        echo "[INFO] UFW ルールを追加しました"

    elif command -v firewall-cmd &> /dev/null; then
        echo "[INFO] firewalld を使用"
        sudo firewall-cmd --permanent --add-port=3000/tcp  # Grafana
        sudo firewall-cmd --permanent --add-port=3100/tcp  # Loki
        sudo firewall-cmd --permanent --add-port=9090/tcp  # Prometheus
        sudo firewall-cmd --permanent --add-port=4317/tcp  # Tempo gRPC
        sudo firewall-cmd --permanent --add-port=4318/tcp  # Tempo HTTP
        sudo firewall-cmd --reload
        echo "[INFO] firewalld ルールを追加しました"

    else
        echo "[WARN] ファイアウォールが見つかりません。手動で以下のポートを開放してください:"
        echo "  3000 (Grafana), 3100 (Loki), 9090 (Prometheus), 4317/4318 (Tempo)"
    fi
}

# ============================================
# 8. 検証
# ============================================
verify() {
    echo ""
    echo "============================================"
    echo " セットアップ完了 - 検証"
    echo "============================================"

    echo ""
    echo "[CHECK] サービス状態:"
    for svc in grafana-server loki prometheus tempo; do
        status=$(sudo systemctl is-active "$svc" 2>/dev/null || echo "inactive")
        printf "  %-20s : %s\n" "$svc" "$status"
    done

    echo ""
    echo "[CHECK] ポート確認:"
    sleep 3
    for port in 3000 3100 9090 4317; do
        if ss -tlnp | grep -q ":${port} "; then
            printf "  :%s  ✓ LISTENING\n" "$port"
        else
            printf "  :%s  ✗ NOT LISTENING\n" "$port"
        fi
    done

    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo ""
    echo "============================================"
    echo " アクセス情報"
    echo "============================================"
    echo ""
    echo "  Grafana:    http://${SERVER_IP}:3000"
    echo "  初期ID/PW:  admin / admin（初回ログイン時に変更を求められます）"
    echo ""
    echo "  Loki:       http://${SERVER_IP}:3100"
    echo "  Prometheus: http://${SERVER_IP}:9090"
    echo "  Tempo:      http://${SERVER_IP}:3200"
    echo ""
    echo "============================================"
    echo " 次のステップ"
    echo "============================================"
    echo ""
    echo "  アプリサーバー4台に Alloy をインストールしてください:"
    echo "  sudo ./install_alloy.sh ${SERVER_IP}"
    echo ""
}

# -----------------------------------------------
# メイン処理
# -----------------------------------------------
install_grafana
install_loki
install_prometheus
install_tempo
deploy_configs
start_services
setup_firewall
verify
