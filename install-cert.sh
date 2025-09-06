#!/bin/bash

# 自动化安装脚本
# 支持多种操作系统的根证书自动安装

# 加载通用函数库
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 设置日志级别
CURRENT_LOG_LEVEL=INFO

# 显示帮助信息
show_help() {
    echo
    echo "${GREEN}根证书自动化安装工具${NC}"
    echo
    echo "${YELLOW}用法:${NC} $0 [选项] [证书文件]"
    echo
    echo "${YELLOW}选项:${NC}"
    echo "    -h, --help              显示此帮助信息"
    echo "    -v, --verbose           显示详细日志"
    echo "    -f, --file <文件>       指定证书文件（默认：out/root.crt）"
    echo "    -s, --store <存储>     指定证书存储位置"
    echo "    -n, --name <名称>       指定证书显示名称"
    echo "    -r, --remove            移除证书"
    echo "    --system               系统级别安装（需要root权限）"
    echo "    --user                 用户级别安装（默认）"
    echo
    echo "${YELLOW}支持的操作系统:${NC}"
    echo "    Linux (Debian/Ubuntu/CentOS/RHEL/Fedora/Arch)"
    echo "    macOS"
    echo "    Windows (通过WSL或Git Bash)"
    echo
    echo "${BLUE}示例:${NC}"
    echo "  $0                                           # 安装到当前用户"
    echo "  $0 --system                                 # 安装到系统"
    echo "  $0 -f my-ca.crt -n 'My CA'                 # 安装指定证书"
    echo "  $0 -r                                       # 移除证书"
    echo
}

# 检测操作系统
detect_os() {
    local os=""
    local distro=""
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        os="Linux"
        if [[ -f /etc/os-release ]]; then
            distro=$(source /etc/os-release && echo "$ID")
        elif [[ -f /etc/redhat-release ]]; then
            distro="rhel"
        elif [[ -f /etc/debian_version ]]; then
            distro="debian"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        os="macOS"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" || "$OSTYPE" == "cygwin" ]]; then
        os="Windows"
    else
        error_exit "不支持的操作系统: $OSTYPE"
    fi
    
    log DEBUG "检测到操作系统: $os $distro"
    echo "$os:$distro"
}

# 检查证书文件
check_cert_file() {
    local cert_file="$1"
    
    if [[ ! -f "$cert_file" ]]; then
        error_exit "证书文件不存在: $cert_file"
    fi
    
    # 验证是否为有效的PEM格式证书
    if ! openssl x509 -in "$cert_file" -noout -text >/dev/null 2>&1; then
        error_exit "无效的证书文件: $cert_file"
    fi
    
    log DEBUG "证书文件验证通过: $cert_file"
}

# Linux系统安装证书
install_linux() {
    local cert_file="$1"
    local cert_name="${2:-Cutebaby ROOT CA}"
    local system_install="$3"
    local distro="$4"
    
    log INFO "在Linux系统上安装证书: $distro"
    
    case $distro in
        ubuntu|debian)
            install_debian "$cert_file" "$cert_name" "$system_install"
            ;;
        centos|rhel|fedora)
            install_rhel "$cert_file" "$cert_name" "$system_install"
            ;;
        arch)
            install_arch "$cert_file" "$cert_name" "$system_install"
            ;;
        *)
            install_linux_generic "$cert_file" "$cert_name" "$system_install"
            ;;
    esac
}

# Debian/Ubuntu系统安装
install_debian() {
    local cert_file="$1"
    local cert_name="$2"
    local system_install="$3"
    
    if [[ "$system_install" == true ]]; then
        # 系统级别安装
        local cert_dir="/usr/local/share/ca-certificates"
        ensure_dir "$cert_dir"
        
        local target_file="$cert_dir/${cert_name// /_}.crt"
        cp "$cert_file" "$target_file"
        
        # 更新证书存储
        update-ca-certificates || {
            log WARN "update-ca-certificates 失败，尝试使用dpkg-reconfigure"
            dpkg-reconfigure ca-certificates
        }
        
        log INFO "证书已安装到系统证书存储"
    else
        # 用户级别安装
        local cert_dir="$HOME/.local/share/ca-certificates"
        ensure_dir "$cert_dir"
        
        local target_file="$cert_dir/${cert_name// /_}.crt"
        cp "$cert_file" "$target_file"
        
        # 更新用户证书存储
        update-ca-trust extract || log WARN "无法更新用户证书存储"
        
        log INFO "证书已安装到用户证书存储"
    fi
}

# RHEL/CentOS/Fedora系统安装
install_rhel() {
    local cert_file="$1"
    local cert_name="$2"
    local system_install="$3"
    
    if [[ "$system_install" == true ]]; then
        # 系统级别安装
        local cert_dir="/etc/pki/ca-trust/source/anchors"
        ensure_dir "$cert_dir"
        
        local target_file="$cert_dir/${cert_name// /_}.crt"
        cp "$cert_file" "$target_file"
        
        # 更新证书存储
        update-ca-trust extract || error_exit "更新证书存储失败"
        
        log INFO "证书已安装到系统证书存储"
    else
        # 用户级别安装
        local cert_dir="$HOME/.pki/ca-trust/source/anchors"
        ensure_dir "$cert_dir"
        
        local target_file="$cert_dir/${cert_name// /_}.crt"
        cp "$cert_file" "$target_file"
        
        # 更新用户证书存储
        update-ca-trust extract --user || log WARN "无法更新用户证书存储"
        
        log INFO "证书已安装到用户证书存储"
    fi
}

# Arch Linux系统安装
install_arch() {
    local cert_file="$1"
    local cert_name="$2"
    local system_install="$3"
    
    if [[ "$system_install" == true ]]; then
        # 系统级别安装
        local cert_dir="/etc/ca-certificates/trust-source/anchors"
        ensure_dir "$cert_dir"
        
        local target_file="$cert_dir/${cert_name// /_}.crt"
        cp "$cert_file" "$target_file"
        
        # 更新证书存储
        trust extract-compat || error_exit "更新证书存储失败"
        
        log INFO "证书已安装到系统证书存储"
    else
        # 用户级别安装
        local cert_dir="$HOME/.local/share/ca-certificates"
        ensure_dir "$cert_dir"
        
        local target_file="$cert_dir/${cert_name// /_}.crt"
        cp "$cert_file" "$target_file"
        
        log INFO "证书已安装到用户目录"
        log INFO "请将证书添加到应用程序的信任存储中"
    fi
}

# 通用Linux安装方法
install_linux_generic() {
    local cert_file="$1"
    local cert_name="$2"
    local system_install="$3"
    
    # 尝试使用certutil（如果有）
    if command -v certutil >/dev/null 2>&1; then
        install_with_certutil "$cert_file" "$cert_name" "$system_install"
    else
        log WARN "无法找到证书安装工具，请手动安装"
        echo "请将以下证书添加到您的信任存储："
        echo "文件: $cert_file"
        echo "名称: $cert_name"
    fi
}

# 使用certutil安装
install_with_certutil() {
    local cert_file="$1"
    local cert_name="$2"
    local system_install="$3"
    
    local db_dir=""
    if [[ "$system_install" == true ]]; then
        db_dir="/etc/pki/nssdb"
        ensure_dir "$db_dir"
    else
        db_dir="$HOME/.pki/nssdb"
        ensure_dir "$db_dir"
    fi
    
    # 初始化数据库（如果不存在）
    if [[ ! -f "$db_dir/cert9.db" ]]; then
        certutil -N -d "$db_dir" --empty-password
    fi
    
    # 添加证书
    certutil -A -n "$cert_name" -t "C,C,C" -i "$cert_file" -d "$db_dir"
    
    log INFO "证书已使用certutil安装到: $db_dir"
}

# macOS系统安装证书
install_macos() {
    local cert_file="$1"
    local cert_name="$2"
    local system_install="$3"
    
    log INFO "在macOS系统上安装证书"
    
    # 添加证书到Keychain
    if [[ "$system_install" == true ]]; then
        # 需要管理员权限
        security add-trusted-cert -d -r trustRoot -k "/Library/Keychains/System.keychain" "$cert_file"
        log INFO "证书已安装到系统Keychain"
    else
        # 安装到用户Keychain
        security add-trusted-cert -d -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$cert_file"
        log INFO "证书已安装到用户Keychain"
    fi
}

# Windows系统安装证书
install_windows() {
    local cert_file="$1"
    local cert_name="$2"
    local system_install="$3"
    
    log INFO "在Windows系统上安装证书"
    
    if command -v certmgr >/dev/null 2>&1; then
        # 使用certmgr
        if [[ "$system_install" == true ]]; then
            certmgr -add -r LocalMachine -s Root "$cert_file"
        else
            certmgr -add -r CurrentUser -s Root "$cert_file"
        fi
    elif command -v certutil >/dev/null 2>&1; then
        # 使用Windows的certutil
        local store="Root"
        if [[ "$system_install" != true ]]; then
            store="-user Root"
        fi
        
        certutil -addstore "$store" "$cert_file"
    else
        log ERROR "无法找到证书安装工具"
        echo "请在Windows中手动安装证书："
        echo "1. 双击证书文件: $cert_file"
        echo "2. 选择'安装证书'"
        echo "3. 选择'当前用户'或'本地计算机'"
        echo "4. 选择'将所有证书都放入下列存储' → '受信任的根证书颁发机构'"
        return 1
    fi
    
    log INFO "证书已安装到Windows证书存储"
}

# 移除证书
remove_certificate() {
    local cert_name="${1:-Cutebaby ROOT CA}"
    local system_install="$2"
    
    local os_info=$(detect_os)
    local os="${os_info%%:*}"
    
    log INFO "移除证书: $cert_name"
    
    case $os in
        Linux)
            remove_linux_cert "$cert_name" "$system_install"
            ;;
        macOS)
            remove_macos_cert "$cert_name" "$system_install"
            ;;
        Windows)
            remove_windows_cert "$cert_name" "$system_install"
            ;;
    esac
}

# Linux系统移除证书
remove_linux_cert() {
    local cert_name="$1"
    local system_install="$2"
    
    local os_info=$(detect_os)
    local distro="${os_info#*:}"
    
    case $distro in
        ubuntu|debian)
            if [[ "$system_install" == true ]]; then
                rm -f "/usr/local/share/ca-certificates/${cert_name// /_}.crt"
                update-ca-certificates
            else
                rm -f "$HOME/.local/share/ca-certificates/${cert_name// /_}.crt"
                update-ca-trust extract
            fi
            ;;
        centos|rhel|fedora)
            if [[ "$system_install" == true ]]; then
                rm -f "/etc/pki/ca-trust/source/anchors/${cert_name// /_}.crt"
                update-ca-trust extract
            else
                rm -f "$HOME/.pki/ca-trust/source/anchors/${cert_name// /_}.crt"
                update-ca-trust extract --user
            fi
            ;;
        arch)
            if [[ "$system_install" == true ]]; then
                rm -f "/etc/ca-certificates/trust-source/anchors/${cert_name// /_}.crt"
                trust extract-compat
            else
                rm -f "$HOME/.local/share/ca-certificates/${cert_name// /_}.crt"
            fi
            ;;
        *)
            if command -v certutil >/dev/null 2>&1; then
                local db_dir=""
                if [[ "$system_install" == true ]]; then
                    db_dir="/etc/pki/nssdb"
                else
                    db_dir="$HOME/.pki/nssdb"
                fi
                certutil -D -n "$cert_name" -d "$db_dir"
            else
                log WARN "无法自动移除证书，请手动移除"
            fi
            ;;
    esac
    
    log INFO "证书已移除"
}

# macOS系统移除证书
remove_macos_cert() {
    local cert_name="$1"
    local system_install="$2"
    
    local keychain=""
    if [[ "$system_install" == true ]]; then
        keychain="/Library/Keychains/System.keychain"
    else
        keychain="$HOME/Library/Keychains/login.keychain-db"
    fi
    
    security find-certificate -c "$cert_name" -Z "$keychain" | \
        grep "SHA-1 hash:" | \
        awk '{print $3}' | \
        while read -r hash; do
            security delete-certificate -Z "$hash" "$keychain"
        done
    
    log INFO "证书已从Keychain移除"
}

# Windows系统移除证书
remove_windows_cert() {
    local cert_name="$1"
    local system_install="$2"
    
    if command -v certmgr >/dev/null 2>&1; then
        local store="Root"
        if [[ "$system_install" != true ]]; then
            store="-user Root"
        fi
        
        certmgr -del -r "${store#- }" -n "$cert_name"
    elif command -v certutil >/dev/null 2>&1; then
        local store="Root"
        if [[ "$system_install" != true ]]; then
            store="-user Root"
        fi
        
        # 需要获取证书序列号或哈希
        log WARN "Windows证书移除需要手动操作"
        echo "请在证书管理器中手动移除证书"
    else
        log ERROR "无法找到证书管理工具"
    fi
}

# 参数解析
CERT_FILE="out/root.crt"
CERT_NAME="Cutebaby ROOT CA"
REMOVE_CERT=false
SYSTEM_INSTALL=false

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
        -f|--file)
            CERT_FILE="$2"
            shift 2
            ;;
        -s|--store)
            # 保留参数，兼容性考虑
            shift 2
            ;;
        -n|--name)
            CERT_NAME="$2"
            shift 2
            ;;
        -r|--remove)
            REMOVE_CERT=true
            shift
            ;;
        --system)
            SYSTEM_INSTALL=true
            shift
            ;;
        --user)
            SYSTEM_INSTALL=false
            shift
            ;;
        -*)
            error_exit "未知选项: $1"
            ;;
        *)
            CERT_FILE="$1"
            shift
            ;;
    esac
done

# 检查依赖
check_dependencies openssl

# 检测操作系统
OS_INFO=$(detect_os)
OS="${OS_INFO%%:*}"
DISTRO="${OS_INFO#*:}"

# 系统安装需要root权限
if [[ "$SYSTEM_INSTALL" == true && "$EUID" -ne 0 ]]; then
    log INFO "系统级别安装需要root权限，使用sudo重新运行"
    exec sudo "$0" "$@"
fi

# 执行操作
if [[ "$REMOVE_CERT" == true ]]; then
    remove_certificate "$CERT_NAME" "$SYSTEM_INSTALL"
else
    check_cert_file "$CERT_FILE"
    
    case $OS in
        Linux)
            install_linux "$CERT_FILE" "$CERT_NAME" "$SYSTEM_INSTALL" "$DISTRO"
            ;;
        macOS)
            install_macos "$CERT_FILE" "$CERT_NAME" "$SYSTEM_INSTALL"
            ;;
        Windows)
            install_windows "$CERT_FILE" "$CERT_NAME" "$SYSTEM_INSTALL"
            ;;
    esac
    
    echo
    echo -e "${GREEN}=== 安装完成 ===${NC}"
    echo -e "${BLUE}证书名称:${NC} $CERT_NAME"
    echo -e "${BLUE}证书文件:${NC} $CERT_FILE"
    echo -e "${BLUE}安装级别:${NC} $([ "$SYSTEM_INSTALL" == true ] && echo "系统" || echo "用户")"
    echo
    echo -e "${YELLOW}注意:${NC} 可能需要重启应用程序或浏览器才能使证书生效"
fi