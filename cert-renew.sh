#!/bin/bash

# 证书自动续期工具
# 自动检查证书过期时间并在需要时续期

# 加载通用函数库
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 设置日志级别
CURRENT_LOG_LEVEL=INFO

# 显示帮助信息
show_help() {
    echo
    echo "${GREEN}证书自动续期工具${NC}"
    echo
    echo "${YELLOW}用法:${NC} $0 [选项] [域名...]"
    echo
    echo "${YELLOW}选项:${NC}"
    echo "    -h, --help              显示此帮助信息"
    echo "    -v, --verbose           显示详细日志"
    echo "    -a, --auto              自动模式，检查所有证书"
    echo "    -f, --force             强制续期，忽略过期时间检查"
    echo "    -w, --warning <天数>    设置续期警告天数（默认：30天）"
    echo "    -r, --root <文件>       指定根证书文件（默认：out/root.crt）"
    echo "    -k, --keep <数量>       保留的历史版本数量（默认：5）"
    echo "    -c, --config <文件>     指定配置文件"
    echo "    -s, --schedule <时间>   设置定时任务（如：每天 2:00）"
    echo
    echo "${BLUE}示例:${NC}"
    echo "  $0 -a                                        # 自动检查所有证书"
    echo "  $0 example.dev cdn.example.dev              # 续期指定域名"
    echo "  $0 -a -w 60 -k 10                          # 60天前续期，保留10个版本"
    echo "  $0 -s '0 2 * * *'                          # 设置每天2点自动检查"
    echo
}

# 默认配置
WARNING_DAYS=30
ROOT_CERT="out/root.crt"
KEEP_VERSIONS=5
AUTO_MODE=false
FORCE_RENEW=false
SCHEDULE=""
CONFIG_FILE=""

# 参数解析
DOMAINS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            CURRENT_LOG_LEVEL=DEBUG
            shift
            ;;
        -a|--auto)
            AUTO_MODE=true
            shift
            ;;
        -f|--force)
            FORCE_RENEW=true
            shift
            ;;
        -w|--warning)
            WARNING_DAYS="$2"
            shift 2
            ;;
        -r|--root)
            ROOT_CERT="$2"
            shift 2
            ;;
        -k|--keep)
            KEEP_VERSIONS="$2"
            shift 2
            ;;
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -s|--schedule)
            SCHEDULE="$2"
            shift 2
            ;;
        -*)
            error_exit "未知选项: $1"
            ;;
        *)
            DOMAINS+=("$1")
            shift
            ;;
    esac
done

# 检查依赖
check_dependencies openssl

# 加载配置文件
load_config() {
    if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
        log INFO "加载配置文件: $CONFIG_FILE"
        source "$CONFIG_FILE"
    elif [[ -f "cert-renew.conf" ]]; then
        log INFO "加载默认配置文件: cert-renew.conf"
        source "cert-renew.conf"
    fi
}

# 获取所有域名
get_all_domains() {
    local domains=()
    
    if [[ ! -d "out" ]]; then
        log WARN "out 目录不存在"
        return 0
    fi
    
    # 查找所有域名目录
    while IFS= read -r -d '' dir; do
        domains+=("$(basename "$dir")")
    done < <(find out -maxdepth 1 -mindepth 1 -type d ! -name "newcerts" ! -name "backups" -print0 2>/dev/null | sort -z)
    
    echo "${domains[@]}"
}

# 检查证书是否需要续期
check_renew_needed() {
    local cert_file="$1"
    
    if [[ ! -f "$cert_file" ]]; then
        log DEBUG "证书文件不存在，需要生成: $cert_file"
        return 0
    fi
    
    if [[ "$FORCE_RENEW" = true ]]; then
        log INFO "强制续期模式"
        return 0
    fi
    
    # 检查证书过期时间
    local expiry_epoch=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
    if [[ -z "$expiry_epoch" ]]; then
        log WARN "无法读取证书过期时间: $cert_file"
        return 0
    fi
    
    local current_epoch=$(date -u +%s)
    local expiry_seconds=$(date -d "$expiry_epoch" -u +%s)
    local days_left=$(( (expiry_seconds - current_epoch) / 86400 ))
    
    log INFO "证书剩余有效期: $days_left 天"
    
    if [[ $days_left -lt $WARNING_DAYS ]]; then
        log WARN "证书即将在 $days_left 天后过期，需要续期"
        return 0
    else
        log INFO "证书仍然有效，无需续期"
        return 1
    fi
}

# 续期单个域名
renew_domain() {
    local domain="$1"
    log INFO "续期域名: $domain"
    
    # 查找现有证书文件以获取配置
    local cert_file="out/$domain/$domain.crt"
    local domains_to_renew=("$domain")
    
    # 如果存在证书，读取SAN以获取所有域名
    if [[ -f "$cert_file" ]]; then
        local sans=$(openssl x509 -noout -ext subjectAltName -in "$cert_file" 2>/dev/null)
        if [[ -n "$sans" ]]; then
            # 解析SAN中的域名
            sans=$(echo "$sans" | sed 's/subjectAltName=//' | tr ',' '\n' | grep 'DNS:' | sed 's/DNS://g' | sed 's/^[ \t]*//')
            domains_to_renew=()
            while IFS= read -r san_domain; do
                if [[ -n "$san_domain" ]]; then
                    # 移除通配符前缀，只保留主域名
                    san_domain=${san_domain#\*.}
                    if [[ ! " ${domains_to_renew[@]} " =~ " ${san_domain} " ]]; then
                        domains_to_renew+=("$san_domain")
                    fi
                fi
            done <<< "$sans"
        fi
    fi
    
    log INFO "将续期以下域名: ${domains_to_renew[*]}"
    
    # 调用证书生成脚本
    if bash "$(dirname "${BASH_SOURCE[0]}")/gen.cert.sh" "${domains_to_renew[@]}"; then
        log INFO "域名 $domain 续期成功"
        
        # 清理旧版本
        cleanup_old_versions "$domain"
        
        return 0
    else
        log ERROR "域名 $domain 续期失败"
        return 1
    fi
}

# 清理旧版本
cleanup_old_versions() {
    local domain="$1"
    local domain_dir="out/$domain"
    
    if [[ ! -d "$domain_dir" ]]; then
        return 0
    fi
    
    log DEBUG "清理 $domain 的旧版本，保留最新 $KEEP_VERSIONS 个"
    
    # 找到所有版本目录
    local versions=($(find "$domain_dir" -maxdepth 1 -mindepth 1 -type d -name "[0-9]*" | sort -r))
    
    if [[ ${#versions[@]} -gt $KEEP_VERSIONS ]]; then
        local to_delete=("${versions[@]:$KEEP_VERSIONS}")
        for old_version in "${to_delete[@]}"; do
            log INFO "删除旧版本: $old_version"
            rm -rf "$old_version"
        done
    fi
}

# 设置定时任务
setup_schedule() {
    if [[ -z "$SCHEDULE" ]]; then
        log INFO "未设置定时任务"
        return 0
    fi
    
    local script_path="$(readlink -f "${BASH_SOURCE[0]}")"
    local cron_job="$SCHEDULE $script_path -a -v"
    local temp_cron=$(mktemp)
    
    # 导出当前crontab
    crontab -l 2>/dev/null > "$temp_cron" || touch "$temp_cron"
    
    # 检查是否已存在相同的任务
    if grep -qF "$script_path" "$temp_cron"; then
        log INFO "定时任务已存在，更新中..."
        # 删除旧的任务
        grep -vF "$script_path" "$temp_cron" > "${temp_cron}.new"
        mv "${temp_cron}.new" "$temp_cron"
    fi
    
    # 添加新的任务
    echo "$cron_job" >> "$temp_cron"
    
    # 导入crontab
    crontab "$temp_cron" || error_exit "设置定时任务失败"
    
    rm -f "$temp_cron"
    
    log INFO "定时任务设置成功: $SCHEDULE"
    log INFO "请确保系统cron服务正在运行"
}

# 发送通知（如果配置了）
send_notification() {
    local subject="$1"
    local message="$2"
    
    # 如果配置了邮件通知
    if [[ -n "$NOTIFICATION_EMAIL" ]]; then
        echo "$message" | mail -s "$subject" "$NOTIFICATION_EMAIL"
        log INFO "已发送邮件通知到: $NOTIFICATION_EMAIL"
    fi
    
    # 如果配置了Webhook
    if [[ -n "$WEBHOOK_URL" ]]; then
        curl -X POST "$WEBHOOK_URL" -H "Content-Type: application/json" \
            -d "{\"text\": \"$subject\\n$message\"}" >/dev/null 2>&1
        log INFO "已发送Webhook通知"
    fi
}

# 主函数
main() {
    # 加载配置
    load_config
    
    # 设置定时任务
    if [[ -n "$SCHEDULE" ]]; then
        setup_schedule
        exit 0
    fi
    
    # 确定要处理的域名列表
    if [[ "$AUTO_MODE" = true ]]; then
        # 自动模式：获取所有域名
        DOMAINS=($(get_all_domains))
        log INFO "自动模式：发现 ${#DOMAINS[@]} 个域名需要检查"
    elif [[ ${#DOMAINS[@]} -eq 0 ]]; then
        show_help
        error_exit "请指定域名或使用 -a 选项自动检查所有证书"
    fi
    
    # 续期统计
    local total=0
    local success=0
    local failed=0
    local renewed=()
    local failed_domains=()
    
    # 处理每个域名
    for domain in "${DOMAINS[@]}"; do
        total=$((total + 1))
        domain=$(format_domain "$domain")
        
        # 检查是否需要续期
        local cert_file="out/$domain/$domain.crt"
        if check_renew_needed "$cert_file"; then
            if renew_domain "$domain"; then
                success=$((success + 1))
                renewed+=("$domain")
            else
                failed=$((failed + 1))
                failed_domains+=("$domain")
            fi
        else
            success=$((success + 1))
        fi
    done
    
    # 输出总结
    echo
    echo -e "${GREEN}=== 续期完成 ===${NC}"
    echo "总共检查: $total 个域名"
    echo "成功: $success 个"
    if [[ $failed -gt 0 ]]; then
        echo -e "${RED}失败: $failed 个${NC}"
        echo "失败的域名: ${failed_domains[*]}"
    fi
    
    if [[ ${#renewed[@]} -gt 0 ]]; then
        echo
        echo -e "${BLUE}已续期的域名:${NC} ${renewed[*]}"
        
        # 发送通知
        if [[ -n "$NOTIFICATION_EMAIL" || -n "$WEBHOOK_URL" ]]; then
            local subject="证书续期通知 - $(date '+%Y-%m-%d')"
            local message="成功续期 ${#renewed[@]} 个域名:\\n${renewed[*]}"
            if [[ $failed -gt 0 ]]; then
                message="\\n失败的域名:\\n${failed_domains[*]}"
            fi
            send_notification "$subject" "$message"
        fi
    fi
    
    # 返回状态码
    if [[ $failed -gt 0 ]]; then
        exit 1
    fi
}

# 执行主函数
main "$@"