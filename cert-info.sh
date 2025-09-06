#!/bin/bash

# 证书信息查看和验证工具
# 用于查看证书详情、验证证书状态、检查证书过期时间等

# 加载通用函数库
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 设置日志级别
CURRENT_LOG_LEVEL=INFO

# 显示帮助信息
show_help() {
    echo
    echo "${GREEN}证书信息查看和验证工具${NC}"
    echo
    echo "${YELLOW}用法:${NC} $0 [选项] [证书文件或域名]"
    echo
    echo "${YELLOW}选项:${NC}"
    echo "    -h, --help              显示此帮助信息"
    echo "    -v, --verbose           显示详细日志"
    echo "    -i, --info <文件/域名>   显示证书详细信息"
    echo "    -c, --check <文件/域名> 验证证书有效性"
    echo "    -e, --expiry <文件/域名> 检查证书过期时间"
    echo "    -w, --warning <天数>     设置过期警告天数（默认：30天）"
    echo "    -r, --root <文件>        指定根证书文件（默认：out/root.crt）"
    echo "    -l, --list               列出所有生成的证书"
    echo "    -f, --fingerprint        显示证书指纹"
    echo
    echo "${BLUE}示例:${NC}"
    echo "  $0 -i out/example.dev/example.dev.crt          # 显示证书信息"
    echo "  $0 -i example.dev                             # 显示域名证书信息"
    echo "  $0 -c out/example.dev/example.dev.crt          # 验证证书"
    echo "  $0 -e example.dev -w 30                       # 检查证书是否在30天内过期"
    echo "  $0 -l                                         # 列出所有证书"
    echo
}

# 参数解析
ACTION=""
TARGET=""
WARNING_DAYS=30
ROOT_CERT="out/root.crt"
SHOW_FINGERPRINT=false

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
        -i|--info)
            ACTION="info"
            TARGET="$2"
            shift 2
            ;;
        -c|--check)
            ACTION="check"
            TARGET="$2"
            shift 2
            ;;
        -e|--expiry)
            ACTION="expiry"
            TARGET="$2"
            shift 2
            ;;
        -w|--warning)
            WARNING_DAYS="$2"
            shift 2
            ;;
        -r|--root)
            ROOT_CERT="$2"
            shift 2
            ;;
        -l|--list)
            ACTION="list"
            shift
            ;;
        -f|--fingerprint)
            SHOW_FINGERPRINT=true
            shift
            ;;
        -*)
            error_exit "未知选项: $1"
            ;;
        *)
            if [[ -z "$ACTION" ]]; then
                ACTION="info"
                TARGET="$1"
            else
                error_exit "参数错误: $1"
            fi
            shift
            ;;
    esac
done

# 检查依赖
check_dependencies openssl

# 查找证书文件
find_cert_file() {
    local domain="$1"
    local cert_file=""
    
    # 如果直接是文件路径
    if [[ -f "$domain" ]]; then
        echo "$domain"
        return
    fi
    
    # 尝试查找域名对应的证书文件
    domain=$(format_domain "$domain")
    cert_file="out/$domain/$domain.crt"
    
    if [[ -f "$cert_file" ]]; then
        echo "$cert_file"
    elif [[ -L "out/$domain/$domain.crt" ]]; then
        # 处理符号链接
        cert_file=$(readlink -f "out/$domain/$domain.crt")
        if [[ -f "$cert_file" ]]; then
            echo "$cert_file"
        else
            error_exit "无法找到证书文件: $domain"
        fi
    else
        error_exit "无法找到证书文件: $domain"
    fi
}

# 显示证书详细信息
show_cert_details() {
    local cert_file="$1"
    
    check_file "$cert_file" "证书"
    
    show_cert_info "$cert_file" ""
    
    if [[ "$SHOW_FINGERPRINT" = true ]]; then
        echo -e "${BLUE}证书指纹:${NC}"
        echo "  SHA-1:   $(openssl x509 -sha1 -fingerprint -noout -in "$cert_file" | cut -d= -f2- | sed 's/://g')"
        echo "  SHA-256: $(openssl x509 -sha256 -fingerprint -noout -in "$cert_file" | cut -d= -f2- | sed 's/://g')"
        echo
    fi
}

# 验证证书
cert_check() {
    local cert_file="$1"
    
    check_file "$cert_file" "证书"
    check_file "$ROOT_CERT" "根证书"
    
    echo -e "${GREEN}=== 证书验证 ===${NC}"
    echo "证书文件: $cert_file"
    echo "根证书: $ROOT_CERT"
    echo
    
    if validate_cert "$cert_file" "$ROOT_CERT"; then
        echo -e "${GREEN}✓ 证书验证通过${NC}"
    else
        echo -e "${RED}✗ 证书验证失败${NC}"
        exit 1
    fi
}

# 检查证书过期时间
check_expiry() {
    local cert_file="$1"
    
    check_file "$cert_file" "证书"
    
    echo -e "${GREEN}=== 证书过期检查 ===${NC}"
    echo "证书文件: $cert_file"
    echo "警告天数: $WARNING_DAYS 天"
    echo
    
    check_cert_expiry "$cert_file" "$WARNING_DAYS"
    local result=$?
    
    case $result in
        0)
            echo -e "${GREEN}✓ 证书在有效期内${NC}"
            ;;
        1)
            echo -e "${YELLOW}⚠ 证书即将过期${NC}"
            ;;
        2)
            echo -e "${RED}✗ 证书已过期${NC}"
            exit 2
            ;;
    esac
    
    # 显示证书有效期
    local start_date=$(openssl x509 -startdate -noout -in "$cert_file" | cut -d= -f2)
    local end_date=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    echo
    echo -e "${BLUE}有效期:${NC}"
    echo "  开始: $start_date"
    echo "  结束: $end_date"
    echo
}

# 列出所有证书
list_certs() {
    echo -e "${GREEN}=== 所有证书列表 ===${NC}"
    echo
    
    if [[ ! -d "out" ]]; then
        log WARN "out 目录不存在，没有找到任何证书"
        exit 0
    fi
    
    # 查找所有域名目录
    local domains=($(find out -maxdepth 1 -mindepth 1 -type d ! -name "newcerts" ! -name "backups" 2>/dev/null | sort))
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        log WARN "没有找到任何域名证书"
        exit 0
    fi
    
    for domain_dir in "${domains[@]}"; do
        local domain=$(basename "$domain_dir")
        local cert_file="$domain_dir/$domain.crt"
        
        if [[ -L "$cert_file" ]]; then
            cert_file=$(readlink -f "$cert_file")
        fi
        
        if [[ -f "$cert_file" ]]; then
            echo -e "${BLUE}域名:${NC} $domain"
            
            # 获取证书信息
            local subject=$(openssl x509 -subject -noout -in "$cert_file" | cut -d= -f2- | sed 's/^[ \t]*//')
            local issuer=$(openssl x509 -issuer -noout -in "$cert_file" | cut -d= -f2- | sed 's/^[ \t]*//')
            local expiry=$(get_cert_expiry "$cert_file")
            
            echo "  主题: $subject"
            echo "  颁发者: $issuer"
            echo "  过期时间: $expiry"
            
            # 检查是否即将过期
            check_cert_expiry "$cert_file" "$WARNING_DAYS" >/dev/null
            local result=$?
            case $result in
                0) echo -e "  状态: ${GREEN}正常${NC}" ;;
                1) echo -e "  状态: ${YELLOW}即将过期${NC}" ;;
                2) echo -e "  状态: ${RED}已过期${NC}" ;;
            esac
            
            echo
        fi
    done
}

# 执行对应操作
case $ACTION in
    info)
        if [[ -z "$TARGET" ]]; then
            show_help
            error_exit "请指定证书文件或域名"
        fi
        cert_file=$(find_cert_file "$TARGET")
        show_cert_details "$cert_file"
        ;;
    check)
        if [[ -z "$TARGET" ]]; then
            show_help
            error_exit "请指定证书文件或域名"
        fi
        cert_file=$(find_cert_file "$TARGET")
        cert_check "$cert_file"
        ;;
    expiry)
        if [[ -z "$TARGET" ]]; then
            show_help
            error_exit "请指定证书文件或域名"
        fi
        cert_file=$(find_cert_file "$TARGET")
        check_expiry "$cert_file"
        ;;
    list)
        list_certs
        ;;
    *)
        show_help
        error_exit "请指定操作类型"
        ;;
esac