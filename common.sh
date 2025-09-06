#!/bin/bash

# 通用函数库
# 包含日志、错误处理和通用功能

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志级别
LOG_LEVELS=("DEBUG" "INFO" "WARN" "ERROR")
CURRENT_LOG_LEVEL=${LOG_LEVEL:-INFO}

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 检查日志级别
    local level_index=-1
    local current_level_index=-1
    for i in "${!LOG_LEVELS[@]}"; do
        if [[ "${LOG_LEVELS[$i]}" == "$level" ]]; then
            level_index=$i
        fi
        if [[ "${LOG_LEVELS[$i]}" == "$CURRENT_LOG_LEVEL" ]]; then
            current_level_index=$i
        fi
    done
    
    if [[ $level_index -ge $current_level_index ]]; then
        case $level in
            DEBUG) color=$BLUE ;;
            INFO) color=$GREEN ;;
            WARN) color=$YELLOW ;;
            ERROR) color=$RED ;;
        esac
        
        echo -e "${color}[$timestamp] [$level] $message${NC}" >&2
    fi
}

# 错误处理函数
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    log ERROR "$message"
    exit $exit_code
}

# 检查依赖命令
check_dependencies() {
    local deps=("$@")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error_exit "缺少依赖命令: ${missing[*]}"
    fi
}

# 确保目录存在
ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log INFO "创建目录: $dir"
        mkdir -p "$dir" || error_exit "无法创建目录: $dir"
    fi
}

# 检查文件是否存在
check_file() {
    local file="$1"
    local description="$2"
    
    if [[ ! -f "$file" ]]; then
        error_exit "$description 文件不存在: $file"
    fi
}

# 安全删除文件
safe_remove() {
    local target="$1"
    if [[ -e "$target" ]]; then
        log DEBUG "删除: $target"
        rm -rf "$target" || error_exit "删除失败: $target"
    fi
}

# 创建符号链接
safe_link() {
    local source="$1"
    local target="$2"
    
    if [[ -L "$target" ]]; then
        safe_remove "$target"
    fi
    
    log DEBUG "创建符号链接: $target -> $source"
    ln -s "$source" "$target" || error_exit "创建符号链接失败: $target -> $source"
}

# 获取证书过期时间
get_cert_expiry() {
    local cert_file="$1"
    if [[ -f "$cert_file" ]]; then
        openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2
    else
        echo "unknown"
    fi
}

# 验证证书
validate_cert() {
    local cert_file="$1"
    local ca_file="${2:-out/root.crt}"
    
    if [[ ! -f "$cert_file" ]]; then
        log ERROR "证书文件不存在: $cert_file"
        return 1
    fi
    
    if [[ ! -f "$ca_file" ]]; then
        log ERROR "CA证书文件不存在: $ca_file"
        return 1
    fi
    
    openssl verify -CAfile "$ca_file" "$cert_file" >/dev/null 2>&1
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        log INFO "证书验证通过: $cert_file"
    else
        log ERROR "证书验证失败: $cert_file"
    fi
    
    return $result
}

# 格式化域名
format_domain() {
    local domain="$1"
    # 移除协议前缀
    domain="${domain#https://}"
    domain="${domain#http://}"
    # 移除路径和端口
    domain="${domain%%/*}"
    domain="${domain%%:*}"
    echo "$domain"
}

# 显示证书信息
show_cert_info() {
    local cert_file="$1"
    local domain="$2"
    
    if [[ ! -f "$cert_file" ]]; then
        log ERROR "证书文件不存在: $cert_file"
        return 1
    fi
    
    echo -e "${GREEN}=== 证书信息 ===${NC}"
    echo -e "${BLUE}域名:${NC} $domain"
    echo -e "${BLUE}证书文件:${NC} $cert_file"
    echo -e "${BLUE}颁发者:${NC} $(openssl x509 -issuer -noout -in "$cert_file" | cut -d= -f2- | sed 's/^[ \t]*//')"
    echo -e "${BLUE}主题:${NC} $(openssl x509 -subject -noout -in "$cert_file" | cut -d= -f2- | sed 's/^[ \t]*//')"
    echo -e "${BLUE}有效期:${NC} $(openssl x509 -startdate -noout -in "$cert_file" | cut -d= -f2) 至 $(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)"
    echo -e "${BLUE}序列号:${NC} $(openssl x509 -serial -noout -in "$cert_file" | cut -d= -f2)"
    echo -e "${BLUE}SHA-1指纹:${NC} $(openssl x509 -sha1 -fingerprint -noout -in "$cert_file" | cut -d= -f2- | sed 's/://g')"
    echo -e "${BLUE}SHA-256指纹:${NC} $(openssl x509 -sha256 -fingerprint -noout -in "$cert_file" | cut -d= -f2- | sed 's/://g')"
    
    # 显示SAN
    local sans=$(openssl x509 -noout -ext subjectAltName -in "$cert_file" 2>/dev/null)
    if [[ -n "$sans" ]]; then
        echo -e "${BLUE}备用名称:${NC}"
        echo "$sans" | sed 's/subjectAltName=//' | tr ',' '\n' | sed 's/DNS:/- /g' | sed 's/^[ \t]*//'
    fi
    echo
}

# 生成随机密码
generate_password() {
    local length="${1:-16}"
    openssl rand -base64 "$length" | tr -d '=+/' | cut -c1-"$length"
}

# 备份文件
backup_file() {
    local source_file="$1"
    local backup_dir="${2:-out/backups}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    if [[ ! -f "$source_file" ]]; then
        log WARN "文件不存在，无需备份: $source_file"
        return 1
    fi
    
    ensure_dir "$backup_dir"
    local backup_file="$backup_dir/$(basename "$source_file").$timestamp"
    
    log INFO "备份文件: $source_file -> $backup_file"
    cp "$source_file" "$backup_file" || error_exit "备份失败: $source_file"
    
    echo "$backup_file"
}

# 检查证书是否即将过期
check_cert_expiry() {
    local cert_file="$1"
    local days_warning="${2:-30}"
    
    if [[ ! -f "$cert_file" ]]; then
        log ERROR "证书文件不存在: $cert_file"
        return 1
    fi
    
    local expiry_epoch=$(openssl x509 -enddate -noout -in "$cert_file" | cut -d= -f2)
    local current_epoch=$(date -u +%s)
    local expiry_seconds=$(date -d "$expiry_epoch" -u +%s)
    local days_left=$(( (expiry_seconds - current_epoch) / 86400 ))
    
    if [[ $days_left -lt 0 ]]; then
        log ERROR "证书已过期 $(( -days_left )) 天"
        return 2
    elif [[ $days_left -lt $days_warning ]]; then
        log WARN "证书将在 $days_left 天后过期"
        return 1
    else
        log INFO "证书有效，还有 $days_left 天"
        return 0
    fi
}