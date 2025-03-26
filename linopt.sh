#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Please run as root${NC}"
  exit 1
fi

declare -A OPTIMIZED_SYSCTL=(
  [net.core.somaxconn]=65535
  [net.core.netdev_max_backlog]=65535
  [net.core.rmem_max]=16777216
  [net.core.wmem_max]=16777216
  [net.ipv4.tcp_rmem]="4096 87380 16777216"
  [net.ipv4.tcp_wmem]="4096 65536 16777216"
  [net.ipv4.tcp_window_scaling]=1
  [net.ipv4.tcp_fin_timeout]=15
  [net.ipv4.tcp_fastopen]=3
  [net.ipv4.tcp_tw_reuse]=1
)

SYSCTL_CONF="/etc/sysctl.d/99-network-performance.conf"
LIMITS_CONF="/etc/security/limits.conf"
SYSTEMD_CONF="/etc/systemd/system.conf"
USER_SYSTEMD_CONF="/etc/systemd/user.conf"
NGINX_CONF="/etc/nginx/nginx.conf"

print_header() {
    echo -e "${CYAN}\n=== $1 ===${NC}"
}

backup_file() {
    local file=$1
    [ -f "$file" ] && cp "$file" "${file}.bak-$(date +%F_%T)"
}

check_values() {
    print_header "Current vs Optimized System Values"
    printf "${YELLOW}%-35s %-20s %-20s %-10s${NC}\n" "Parameter" "Current" "Optimized" "Status"
    for key in "${!OPTIMIZED_SYSCTL[@]}"; do
        current=$(sysctl -n "$key" 2>/dev/null || echo "N/A")
        expected="${OPTIMIZED_SYSCTL[$key]}"
        if [ "$current" == "$expected" ]; then
            status="${GREEN}TRUE${NC}"
        else
            status="${RED}FALSE${NC}"
        fi
        printf "%-35s %-20s %-20s %b\n" "$key" "$current" "$expected" "$status"
    done
}

apply_sysctl() {
    print_header "Applying Kernel/Network Optimizations"
    backup_file "$SYSCTL_CONF"
    {
      for key in "${!OPTIMIZED_SYSCTL[@]}"; do
        echo "$key = ${OPTIMIZED_SYSCTL[$key]}"
      done
    } > "$SYSCTL_CONF"
    sysctl --system
}

apply_limits() {
    print_header "Applying Limits Configuration"
    backup_file "$LIMITS_CONF"
    echo -e "* soft nofile 65535\n* hard nofile 65535" >> "$LIMITS_CONF"
    sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=65535/' "$SYSTEMD_CONF" || true
    sed -i 's/^#DefaultLimitNOFILE=.*/DefaultLimitNOFILE=65535/' "$USER_SYSTEMD_CONF" || true
}

apply_nginx_config() {
    print_header "Applying NGINX Optimizations"
    backup_file "$NGINX_CONF"
    sed -i 's/worker_processes.*/worker_processes auto;/' "$NGINX_CONF" || true
    sed -i 's/worker_connections.*/worker_connections 65535;/' "$NGINX_CONF" || true

    cat <<EOF >> "$NGINX_CONF"

events {
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    keepalive_requests 10000;
    client_body_buffer_size 16K;
    client_header_buffer_size 1k;
    client_max_body_size 10M;
    large_client_header_buffers 4 8k;
    send_timeout 30;
    client_body_timeout 30;
    client_header_timeout 30;
    gzip on;
    gzip_disable "msie6";
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
}
EOF
}

verify_sysctl_applied() {
    print_header "Verification: sysctl values"
    all_ok=true
    for key in "${!OPTIMIZED_SYSCTL[@]}"; do
        current=$(sysctl -n "$key" 2>/dev/null)
        expected="${OPTIMIZED_SYSCTL[$key]}"
        if [ "$current" != "$expected" ]; then
            echo -e "${RED}Mismatch:$NC $key = $current (expected: $expected)"
            all_ok=false
        fi
    done
    $all_ok && echo -e "${GREEN}✅ All sysctl values correctly applied.${NC}"
}

install_xanmod_kernel() {
    print_header "🔧 Installing XanMod Kernel"

    if uname -r | grep -iq xanmod; then
        echo -e "${GREEN}XanMod kernel already installed: $(uname -r)${NC}"
        return
    fi

    if ! grep -qiE 'ubuntu|debian' /etc/os-release; then
        echo -e "${RED}❌ Unsupported OS. XanMod supports Ubuntu or Debian only.${NC}"
        return
    fi

    echo -e "${CYAN}Adding XanMod repository and installing latest stable kernel...${NC}"

    apt update
    apt install -y gnupg software-properties-common curl

    curl -fsSL https://dl.xanmod.org/gpg.key | gpg --dearmor | tee /etc/apt/trusted.gpg.d/xanmod.gpg > /dev/null
    echo 'deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/xanmod.gpg] https://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-kernel.list

    apt update
    if apt install -y linux-xanmod; then
        echo -e "${GREEN}✅ XanMod kernel installed successfully.${NC}"
        echo -e "${YELLOW}🔁 Please reboot your system to activate XanMod kernel.${NC}"
    else
        echo -e "${RED}❌ Installation failed. Visit https://xanmod.org for manual install.${NC}"
    fi
}

verify_xanmod_kernel() {
    print_header "🔍 XanMod Kernel Verification"
    if uname -r | grep -iq xanmod; then
        echo -e "${GREEN}✅ XanMod kernel is ACTIVE: $(uname -r)${NC}"
    else
        echo -e "${RED}❌ XanMod is NOT active.${NC}"
        echo -e "${YELLOW}If you installed XanMod, please reboot and run this check again.${NC}"
    fi
}

main_menu() {
    while true; do
        echo -e "\n${CYAN}Ubuntu Network + NGINX Optimization Menu${NC}"
        echo "0) Check current vs optimized values"
        echo "1) Apply sysctl network optimizations"
        echo "2) Apply file descriptor + systemd limits"
        echo "3) Apply NGINX optimizations"
        echo "4) Verify sysctl changes were applied"
        echo "5) Apply ALL optimizations"
        echo "6) Install and configure XanMod Kernel"
        echo "q) Quit"
        echo -n "Select an option: "
        read -r choice
        case $choice in
            0) check_values ;;
            1) apply_sysctl ;;
            2) apply_limits ;;
            3) apply_nginx_config ;;
            4) verify_sysctl_applied ;;
            5)
                apply_sysctl
                apply_limits
                apply_nginx_config
                ;;
            6)
                install_xanmod_kernel
                verify_xanmod_kernel
                ;;
            q|Q) echo "Exiting..."; exit 0 ;;
            *) echo -e "${RED}Invalid choice, try again.${NC}" ;;
        esac
    done
}

main_menu
