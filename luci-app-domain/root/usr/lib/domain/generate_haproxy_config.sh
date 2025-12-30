#!/bin/sh
# domain HAProxy Config Generator
# Copyright (c) 2026 domain Maintainers
# Licensed under the Apache License 2.0

set -e

# 配置
CONFIG_FILE="/etc/config/domain"
HAPROXY_CONF="/var/etc/haproxy.conf"
LOG_FILE="/var/log/domain-haproxy.log"

# 输出颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message"
            ;;
        *)
            echo "[$level] $message"
            ;;
    esac
    
    # 记录到文件
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# 获取配置值
get_config() {
    local section="$1"
    local option="$2"
    uci -q get "${CONFIG_FILE}.${section}.${option}"
}

# 获取配置列表
get_config_list() {
    local section="$1"
    local option="$2"
    uci -q get "${CONFIG_FILE}.${section}.${option}" 2>/dev/null || true
}

# 生成HAProxy全局配置
generate_global() {
    cat << EOF
# 全局设置
global
    daemon
    maxconn 2000
    log /dev/log local0 info
    stats socket /var/run/haproxy.sock mode 600 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    tune.ssl.default-dh-param 2048

# 默认设置
defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http
EOF
}

# 生成HAProxy前端配置
generate_frontend() {
    local section="$1"
    local name=$(get_config "$section" "name" || echo "unnamed")
    local enabled=$(get_config "$section" "enabled" || echo "1")
    
    if [ "$enabled" != "1" ]; then
        return
    fi
    
    local frontend_name=$(get_config "$section" "frontend_name" || echo "frontend_$section")
    local listen_address=$(get_config "$section" "listen_address" || echo "0.0.0.0")
    local listen_port=$(get_config "$section" "listen_port" || echo "80")
    local ssl=$(get_config "$section" "ssl" || echo "0")
    local ssl_cert=$(get_config "$section" "ssl_cert" || "")
    
    cat << EOF

# 前端: $name ($frontend_name)
frontend $frontend_name
    bind $listen_address:$listen_port
EOF
    
    if [ "$ssl" = "1" ] && [ -n "$ssl_cert" ]; then
        echo "    bind *:443 ssl crt $ssl_cert"
    fi
    
    # 添加ACL规则
    local acl_rules=$(get_config_list "$section" "frontend_acl")
    if [ -n "$acl_rules" ]; then
        echo "    # ACL规则"
        echo "$acl_rules" | while IFS= read -r rule; do
            echo "    $rule"
        done
    fi
    
    # 添加后端选择规则
    local use_backend_rules=$(get_config_list "$section" "frontend_use_backend")
    if [ -n "$use_backend_rules" ]; then
        echo "    # 后端选择规则"
        echo "$use_backend_rules" | while IFS= read -r rule; do
            echo "    $rule"
        done
    fi
    
    # 没有匹配规则时的默认后端
    local backend_name=$(get_config "$section" "backend_name" || echo "backend_$section")
    echo "    default_backend $backend_name"
}

# 生成HAProxy后端配置
generate_backend() {
    local section="$1"
    local name=$(get_config "$section" "name" || echo "unnamed")
    local enabled=$(get_config "$section" "enabled" || echo "1")
    
    if [ "$enabled" != "1" ]; then
        return
    fi
    
    local backend_name=$(get_config "$section" "backend_name" || echo "backend_$section")
    local balance=$(get_config "$section" "backend_balance" || echo "roundrobin")
    
    cat << EOF

# 后端: $name ($backend_name)
backend $backend_name
    balance $balance
EOF
    
    # 添加后端服务器
    local backend_servers=$(get_config_list "$section" "backend_servers")
    if [ -n "$backend_servers" ]; then
        echo "    # 后端服务器"
        echo "$backend_servers" | while IFS= read -r server; do
            echo "    $server"
        done
    else
        # 如果新格式中没有定义服务器，则回退到旧配置
        local backend_ip=$(get_config "$section" "backend_ip" || "")
        local backend_port=$(get_config "$section" "backend_port" || "8080")
        if [ -n "$backend_ip" ]; then
            echo "    server server1 $backend_ip:$backend_port check"
        fi
    fi
}

# 主函数
generate_config() {
    log "INFO" "Generating HAProxy configuration..."
    
    # 如果输出目录不存在则创建
    mkdir -p "$(dirname "$HAPROXY_CONF")"
    
    # 开始生成配置
    generate_global > "$HAPROXY_CONF"
    
    # 为每个代理部分生成配置
    uci -q show "$CONFIG_FILE" | grep -E "$CONFIG_FILE\.(@proxy\[[0-9]+\]|proxy_[0-9a-f]+)\." | \
    awk -F'.' '{print $2}' | sort -u | \
    while read -r section; do
        log "DEBUG" "Processing proxy section: $section"
        generate_frontend "$section" >> "$HAPROXY_CONF"
        generate_backend "$section" >> "$HAPROXY_CONF"
    done
    
    log "INFO" "HAProxy configuration generated successfully: $HAPROXY_CONF"
    
    # 验证配置
    if haproxy -c -f "$HAPROXY_CONF" >/dev/null 2>&1; then
        log "INFO" "HAProxy configuration is valid"
        return 0
    else
        log "ERROR" "HAProxy configuration validation failed"
        haproxy -c -f "$HAPROXY_CONF" 2>&1 | log "ERROR"
        return 1
    fi
}

# 重启HAProxy服务
restart_haproxy() {
    log "INFO" "Restarting HAProxy service..."
    if /etc/init.d/haproxy restart >/dev/null 2>&1; then
        log "INFO" "HAProxy service restarted successfully"
        return 0
    else
        log "ERROR" "Failed to restart HAProxy service"
        return 1
    fi
}

# 主执行
main() {
    log "INFO" "domain HAProxy Config Generator started"
    
    local action="$1"
    case "$action" in
        "generate")
            generate_config
            ;;
        "restart")
            generate_config && restart_haproxy
            ;;
        "generate-restart")
            generate_config && restart_haproxy
            ;;
        *)
            echo "Usage: $0 {generate|restart|generate-restart}"
            exit 1
            ;;
    esac
    
    log "INFO" "domain HAProxy Config Generator finished"
}

# 运行主函数
main "$@"

