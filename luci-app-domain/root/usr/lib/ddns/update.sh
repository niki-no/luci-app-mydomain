#!/bin/sh
# domain DDNS Update Script
# Copyright (c) 2026 domain Maintainers
# Licensed under the Apache License 2.0

# 设置错误处理
set -e

# 配置
CONFIG_FILE="/etc/config/domain"
LOG_FILE="/var/log/domain-ddns.log"
MAX_LOG_SIZE=1048576 # 1MB
MAX_LOG_FILES=5

# 输出颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

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

# 日志轮换函数
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        local size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null)
        if [ "$size" -gt "$MAX_LOG_SIZE" ]; then
            for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
                if [ -f "${LOG_FILE}.$i" ]; then
                    mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i + 1))"
                fi
            done
            mv "$LOG_FILE" "${LOG_FILE}.1"
            log "INFO" "Rotated log file"
        fi
    fi
}

# 获取配置值
get_config() {
    local section="$1"
    local option="$2"
    uci -q get "${CONFIG_FILE}.${section}.${option}"
}

# 设置配置值
set_config() {
    local section="$1"
    local option="$2"
    local value="$3"
    uci set "${CONFIG_FILE}.${section}.${option}=${value}"
    uci commit domain
}

# 获取当前公网IP
get_public_ip() {
    local method="$1"
    local ip=""
    local response=""
    
    case "$method" in
        "ipify")
            response=$(curl -s -4 --connect-timeout 10 https://myip.ipip.net 2>/dev/null || \
                      curl -s -6 --connect-timeout 10 https://speed.neu6.edu.cn/getIP.php 2>/dev/null)
            ;;
        "icanhazip")
            response=$(curl -s -4 --connect-timeout 10 https://ddns.oray.com/checkip 2>/dev/null || \
                      curl -s -6 --connect-timeout 10 https://v6.ident.me 2>/dev/null)
            ;;
        "ident")
            response=$(curl -s -4 --connect-timeout 10 https://ip.3322.net 2>/dev/null || \
                      curl -s -6 --connect-timeout 10 https://6.ipw.cn 2>/dev/null)
            ;;
        "ifconfig")
            response=$(curl -s -4 --connect-timeout 10 https://4.ipw.cn 2>/dev/null || \
                      curl -s -6 --connect-timeout 10 https://v6.yinghualuo.cn/bejson 2>/dev/null)
            ;;
        *)
            # 尝试所有方法
            ip=$(get_public_ip "ipify" || get_public_ip "icanhazip" || get_public_ip "ident" || get_public_ip "ifconfig")
            echo "$ip"
            return
            ;;
    esac
    
    # 从响应中提取IP地址
    if [ -n "$response" ]; then
        # 提取IPv4地址
        ip=$(echo "$response" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        
        # 如果没有找到IPv4地址，尝试提取IPv6地址
        if [ -z "$ip" ]; then
            ip=$(echo "$response" | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}' | head -1)
        fi
    fi
    
    echo "$ip"
}

# 验证IP地址
validate_ip() {
    local ip="$1"
    
    # IPv4验证
    if echo "$ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
        [ "$i1" -le 255 ] && [ "$i2" -le 255 ] && [ "$i3" -le 255 ] && [ "$i4" -le 255 ] && \
        [ "$i1" -ge 0 ] && [ "$i2" -ge 0 ] && [ "$i3" -ge 0 ] && [ "$i4" -ge 0 ]
        return $?
    fi
    
    # IPv6验证（简化版）
    if echo "$ip" | grep -qE '^([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}$'; then
        return 0
    fi
    
    return 1
}

# 获取当前DNS记录
get_dns_record() {
    local domain="$1"
    local record_type="${2:-A}"
    
    # 首先尝试使用dig命令
    if command -v dig >/dev/null 2>&1; then
        dig +short "$record_type" "$domain" @8.8.8.8 2>/dev/null | head -1
    # 回退使用nslookup命令
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup -type="$record_type" "$domain" 8.8.8.8 2>/dev/null | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1
    else
        log "ERROR" "Neither dig nor nslookup found"
        return 1
    fi
}

# 通过domain API更新DNS记录
update_dns_record() {
    local domain="$1"
    local ip="$2"
    local record_type="${3:-A}"
    local ttl="${4:-300}"
    
    local api_url="http://localhost:8080/api/dns/update"
    local auth_token=$(get_config "ddns" "api_token")
    
    if [ -z "$auth_token" ]; then
        log "ERROR" "API token not configured"
        return 1
    fi
    
    local response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $auth_token" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain\": \"$domain\",
            \"type\": \"$record_type\",
            \"value\": \"$ip\",
            \"ttl\": $ttl
        }" \
        "$api_url")
    
    local http_code=$(echo "$response" | tail -1)
    local body=$(echo "$response" | head -1)
    
    if [ "$http_code" = "200" ]; then
        log "INFO" "Successfully updated DNS record for $domain to $ip"
        return 0
    else
        log "ERROR" "Failed to update DNS record: $body (HTTP $http_code)"
        return 1
    fi
}

# 更新Cloudflare DNS
update_cloudflare_dns() {
    local domain="$1"
    local ip="$2"
    local record_type="${3:-A}"
    
    local zone_id=$(get_config "ddns" "cloudflare_zone_id")
    local api_token=$(get_config "ddns" "cloudflare_api_token")
    
    if [ -z "$zone_id" ] || [ -z "$api_token" ]; then
        log "ERROR" "Cloudflare credentials not configured"
        return 1
    fi
    
    # 获取记录ID
    local record_name=$(echo "$domain" | cut -d'.' -f1)
    local zone_name=$(echo "$domain" | cut -d'.' -f2-)
    
    local record_response=$(curl -s \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records?type=$record_type&name=$domain")
    
    local record_id=$(echo "$record_response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    if [ -z "$record_id" ]; then
        log "ERROR" "DNS record not found for $domain"
        return 1
    fi
    
    # 更新记录
    local update_response=$(curl -s \
        -X PUT \
        -H "Authorization: Bearer $api_token" \
        -H "Content-Type: application/json" \
        -d "{
            \"type\": \"$record_type\",
            \"name\": \"$domain\",
            \"content\": \"$ip\",
            \"ttl\": 120,
            \"proxied\": false
        }" \
        "https://api.cloudflare.com/client/v4/zones/$zone_id/dns_records/$record_id")
    
    local success=$(echo "$update_response" | grep -o '"success":[^,]*' | cut -d':' -f2)
    
    if [ "$success" = "true" ]; then
        log "INFO" "Successfully updated Cloudflare DNS record for $domain to $ip"
        return 0
    else
        log "ERROR" "Failed to update Cloudflare DNS record"
        return 1
    fi
}

# 更新AWS Route53 DNS
update_route53_dns() {
    local domain="$1"
    local ip="$2"
    local record_type="${3:-A}"
    
    local access_key=$(get_config "ddns" "aws_access_key")
    local secret_key=$(get_config "ddns" "aws_secret_key")
    local hosted_zone_id=$(get_config "ddns" "aws_hosted_zone_id")
    
    if [ -z "$access_key" ] || [ -z "$secret_key" ] || [ -z "$hosted_zone_id" ]; then
        log "ERROR" "AWS credentials not configured"
        return 1
    fi
    
    # 这需要安装AWS CLI
    # 简化版本 - 在生产环境中，您应该使用AWS CLI或SDK
    log "WARN" "Route53 update not fully implemented"
    return 1
}

# 更新DNS提供商
update_dns_provider() {
    local provider="$1"
    local domain="$2"
    local ip="$3"
    local record_type="$4"
    
    case "$provider" in
        "domain")
            update_dns_record "$domain" "$ip" "$record_type"
            ;;
        "cloudflare")
            update_cloudflare_dns "$domain" "$ip" "$record_type"
            ;;
        "route53")
            update_route53_dns "$domain" "$ip" "$record_type"
            ;;
        "custom")
            # 执行自定义更新脚本
            local script=$(get_config "ddns" "custom_script")
            if [ -n "$script" ] && [ -x "$script" ]; then
                "$script" "$domain" "$ip" "$record_type"
            else
                log "ERROR" "Custom script not found or not executable"
                return 1
            fi
            ;;
        *)
            log "ERROR" "Unknown DNS provider: $provider"
            return 1
            ;;
    esac
}

# 等待DNS传播
wait_for_propagation() {
    local domain="$1"
    local expected_ip="$2"
    local max_attempts="${3:-30}"
    local wait_seconds="${4:-10}"
    local record_type="${5:-A}"
    
    log "INFO" "Waiting for DNS propagation..."
    
    local attempts=0
    while [ $attempts -lt $max_attempts ]; do
        local current_ip=$(get_dns_record "$domain" "$record_type")
        
        if [ "$current_ip" = "$expected_ip" ]; then
            log "INFO" "DNS propagated successfully after $((attempts * wait_seconds)) seconds"
            return 0
        fi
        
        attempts=$((attempts + 1))
        if [ $attempts -lt $max_attempts ]; then
            sleep "$wait_seconds"
        fi
    done
    
    log "WARN" "DNS propagation check timed out"
    return 1
}

# 主更新函数
do_update() {
    local force="${1:-false}"
    
    log "INFO" "Starting DDNS update process"
    
    # 获取配置
    local enabled=$(get_config "ddns" "enabled")
    if [ "$enabled" != "1" ] && [ "$force" != "true" ]; then
        log "INFO" "DDNS is disabled"
        return 0
    fi
    
    local domain=$(get_config "ddns" "domain")
    local provider=$(get_config "ddns" "provider")
    local ip_method=$(get_config "ddns" "ip_method")
    local record_type=$(get_config "ddns" "record_type")
    local check_interval=$(get_config "ddns" "check_interval")
    local force_ipv6=$(get_config "ddns" "force_ipv6")
    
    if [ -z "$domain" ]; then
        log "ERROR" "No domain configured"
        return 1
    fi
    
    # 根据配置或自动检测确定记录类型
    if [ -z "$record_type" ]; then
        if [ "$force_ipv6" = "1" ]; then
            record_type="AAAA"
        else
            record_type="A"
        fi
    fi
    
    # 获取当前公网IP
    log "INFO" "Getting current public IP using method: ${ip_method:-auto}"
    local current_ip=$(get_public_ip "$ip_method")
    
    if [ -z "$current_ip" ]; then
        log "ERROR" "Failed to get public IP"
        return 1
    fi
    
    if ! validate_ip "$current_ip"; then
        log "ERROR" "Invalid IP address: $current_ip"
        return 1
    fi
    
    log "INFO" "Current public IP: $current_ip"
    
    # 获取上次已知IP
    local last_ip=$(get_config "ddns" "last_ip")
    local last_update=$(get_config "ddns" "last_update")
    
    # 检查IP是否已更改
    if [ "$current_ip" = "$last_ip" ] && [ "$force" != "true" ]; then
        log "INFO" "IP hasn't changed since last update ($last_update)"
        return 0
    fi
    
    # 获取当前DNS记录
    log "INFO" "Checking current DNS record for $domain"
    local dns_ip=$(get_dns_record "$domain" "$record_type")
    
    if [ -n "$dns_ip" ]; then
        log "INFO" "Current DNS record: $dns_ip"
        
        if [ "$dns_ip" = "$current_ip" ] && [ "$force" != "true" ]; then
            log "INFO" "DNS record is already up to date"
            # 更新最后检查时间
            set_config "ddns" "last_check" "$(date +%s)"
            return 0
        fi
    else
        log "WARN" "No DNS record found for $domain"
    fi
    
    # 更新DNS记录
    log "INFO" "Updating DNS record for $domain to $current_ip"
    if update_dns_provider "$provider" "$domain" "$current_ip" "$record_type"; then
        # 更新配置
        set_config "ddns" "last_ip" "$current_ip"
        set_config "ddns" "last_update" "$(date +%s)"
        set_config "ddns" "last_check" "$(date +%s)"
        
        log "INFO" "DNS update successful"
        
        # 如果配置了，等待传播
        local wait_propagation=$(get_config "ddns" "wait_propagation")
        if [ "$wait_propagation" = "1" ]; then
            wait_for_propagation "$domain" "$current_ip"
        fi
        
        # 如果配置了通知，则发送通知
        send_notification "$domain" "$current_ip" "$last_ip"
        
        return 0
    else
        log "ERROR" "DNS update failed"
        return 1
    fi
}

# 发送通知
send_notification() {
    local domain="$1"
    local new_ip="$2"
    local old_ip="$3"
    
    local notify_enabled=$(get_config "ddns" "notify_enabled")
    if [ "$notify_enabled" != "1" ]; then
        return 0
    fi
    
    local notify_method=$(get_config "ddns" "notify_method")
    local notify_email=$(get_config "ddns" "notify_email")
    local notify_webhook=$(get_config "ddns" "notify_webhook")
    
    local message="domain DDNS Update: $domain changed from $old_ip to $new_ip"
    
    case "$notify_method" in
        "email")
            if [ -n "$notify_email" ] && command -v sendmail >/dev/null 2>&1; then
                echo "Subject: domain DDNS Update
                
                $message
                
                Timestamp: $(date)
                Domain: $domain
                Old IP: $old_ip
                New IP: $new_ip" | sendmail "$notify_email"
                log "INFO" "Email notification sent to $notify_email"
            fi
            ;;
        "webhook")
            if [ -n "$notify_webhook" ]; then
                curl -s -X POST \
                    -H "Content-Type: application/json" \
                    -d "{\"text\":\"$message\"}" \
                    "$notify_webhook" >/dev/null 2>&1
                log "INFO" "Webhook notification sent"
            fi
            ;;
        "telegram")
            local telegram_bot_token=$(get_config "ddns" "telegram_bot_token")
            local telegram_chat_id=$(get_config "ddns" "telegram_chat_id")
            
            if [ -n "$telegram_bot_token" ] && [ -n "$telegram_chat_id" ]; then
                curl -s -X POST \
                    -H "Content-Type: application/json" \
                    -d "{\"chat_id\":\"$telegram_chat_id\",\"text\":\"$message\"}" \
                    "https://api.telegram.org/bot$telegram_bot_token/sendMessage" >/dev/null 2>&1
                log "INFO" "Telegram notification sent"
            fi
            ;;
    esac
}

# 清理函数
cleanup() {
    log "INFO" "DDNS update script finished"
}

# 错误处理函数
error_handler() {
    local exit_code="$?"
    local line_no="$1"
    local command="$2"
    
    log "ERROR" "Script failed at line $line_no: $command (exit code: $exit_code)"
    cleanup
    exit $exit_code
}

# 设置错误陷阱
trap 'error_handler ${LINENO} "$BASH_COMMAND"' ERR

# 主执行
main() {
    rotate_log
    
    local action="$1"
    case "$action" in
        "update")
            do_update "${2:-false}"
            ;;
        "force-update")
            do_update "true"
            ;;
        "check")
            # 仅检查IP而不更新
            local ip=$(get_public_ip)
            if validate_ip "$ip"; then
                log "INFO" "Current IP: $ip"
                echo "$ip"
            else
                log "ERROR" "Failed to get valid IP"
                exit 1
            fi
            ;;
        "status")
            # 显示状态
            local enabled=$(get_config "ddns" "enabled")
            local domain=$(get_config "ddns" "domain")
            local last_ip=$(get_config "ddns" "last_ip")
            local last_update=$(get_config "ddns" "last_update")
            
            echo "Status: $([ "$enabled" = "1" ] && echo "Enabled" || echo "Disabled")"
            echo "Domain: $domain"
            echo "Last IP: $last_ip"
            if [ -n "$last_update" ]; then
                echo "Last Update: $(date -d @$last_update)"
            fi
            ;;
        "enable")
            set_config "ddns" "enabled" "1"
            log "INFO" "DDNS enabled"
            ;;
        "disable")
            set_config "ddns" "enabled" "0"
            log "INFO" "DDNS disabled"
            ;;
        "test")
            # 测试DNS提供商
            local provider=$(get_config "ddns" "provider")
            local domain=$(get_config "ddns" "domain")
            local test_ip="8.8.8.8"
            
            log "INFO" "Testing DNS provider: $provider"
            if update_dns_provider "$provider" "$domain" "$test_ip" "A"; then
                log "INFO" "DNS provider test successful"
            else
                log "ERROR" "DNS provider test failed"
                exit 1
            fi
            ;;
        "log")
            # 显示日志
            if [ -f "$LOG_FILE" ]; then
                tail -50 "$LOG_FILE"
            else
                echo "Log file not found"
            fi
            ;;
        "rotate-log")
            # 强制日志轮换
            if [ -f "$LOG_FILE" ]; then
                mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d_%H%M%S)"
                log "INFO" "Log file rotated manually"
            fi
            ;;
        *)
            echo "Usage: $0 {update|force-update|check|status|enable|disable|test|log|rotate-log}"
            exit 1
            ;;
    esac
    
    cleanup
}

# 运行主函数
main "$@"
