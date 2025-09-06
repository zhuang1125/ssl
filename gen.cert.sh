#!/bin/bash

# 加载通用函数库
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 设置日志级别
CURRENT_LOG_LEVEL=INFO

# 检查依赖
check_dependencies openssl

# 显示帮助信息
show_help() {
    echo
    echo "${GREEN}使用 Cutebaby ROOT CA 颁发泛域名SSL证书${NC}"
    echo
    echo "${YELLOW}用法:${NC} $0 --domain <域名> [--domain <域名2>] ..."
    echo "    ${YELLOW}--domain <域名>${NC}   你的网站域名，如 'example.dev'"
    echo "                        将获得 *.example.dev 的证书"
    echo "                        支持多个域名"
    echo "    ${YELLOW}--domains <域名>${NC}   多个域名，逗号分隔，如 'a.com,b.com'"
    echo "    ${YELLOW}--ip <IP地址>${NC}      添加单个IP地址到证书"
    echo "    ${YELLOW}--ips <IP地址>${NC}      多个IP地址，逗号分隔，如 '1.1.1.1,2.2.2.2'"
    echo
    echo "${YELLOW}选项:${NC}"
    echo "    -h, --help          显示此帮助信息"
    echo "    -v, --verbose       显示详细日志"
    echo "    -p, --password      指定PFX文件密码（默认：123456）"
    echo "    -a, --algorithm     指定密钥算法（默认：rsa:4096）"
    echo "    --domain <域名>     添加要生成证书的域名"
    echo "    --domains <域名>    多个域名，逗号分隔"
    echo "    --ip <IP地址>       添加单个IP地址"
    echo "    --ips <IP地址>      多个IP地址，逗号分隔"
    echo
    echo "${BLUE}注意:${NC} 此脚本还会生成PFX文件，可用于ClickOnce清单签名"
    echo
}

# 参数解析
PFX_PASSWORD="123456"
KEY_ALGORITHM="rsa:4096"
DOMAINS=()
IPS=()

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
        -p|--password)
            PFX_PASSWORD="$2"
            shift 2
            ;;
        -a|--algorithm)
            KEY_ALGORITHM="$2"
            shift 2
            ;;
        --domain)
            DOMAINS+=("$2")
            shift 2
            ;;
        --domains)
            # 分割逗号分隔的域名
            IFS=',' read -ra DOMAIN_ARRAY <<< "$2"
            for d in "${DOMAIN_ARRAY[@]}"; do
                DOMAINS+=("$d")
            done
            shift 2
            ;;
        --ip)
            IPS+=("$2")
            shift 2
            ;;
        --ips)
            # 分割逗号分隔的IP地址
            IFS=',' read -ra IP_ARRAY <<< "$2"
            for ip in "${IP_ARRAY[@]}"; do
                IPS+=("$ip")
            done
            shift 2
            ;;
        -*)
            error_exit "未知选项: $1"
            ;;
        *)
            error_exit "未知选项: $1"
            ;;
    esac
done

if [ ${#DOMAINS[@]} -eq 0 ] && [ ${#IPS[@]} -eq 0 ]; then
    show_help
    error_exit "至少需要指定一个域名或IP地址"
fi

# 格式化和验证域名
VALID_DOMAINS=()
for domain in "${DOMAINS[@]}"; do
    # 格式化域名
    formatted_domain=$(format_domain "$domain")
    VALID_DOMAINS+=("$formatted_domain")
    log DEBUG "添加域名: $formatted_domain"
done

# 验证IP地址
VALID_IPS=()
for ip in "${IPS[@]}"; do
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        # 验证每个八位组
        valid=true
        IFS='.' read -ra OCTETS <<< "$ip"
        for octet in "${OCTETS[@]}"; do
            if [ "$octet" -gt 255 ]; then
                valid=false
                break
            fi
        done
        if $valid; then
            VALID_IPS+=("$ip")
            log DEBUG "添加IP地址: $ip"
        else
            error_exit "无效的IP地址: $ip"
        fi
    else
        error_exit "无效的IP地址格式: $ip"
    fi
done

# 构建SAN字符串
SAN=""
for domain in "${VALID_DOMAINS[@]}"; do
    SAN="$SAN""DNS:*.${domain},DNS:${domain},"
done
for ip in "${VALID_IPS[@]}"; do
    SAN="$SAN""IP:${ip},"
done
# 移除最后的逗号（如果有）
if [ -n "$SAN" ]; then
    SAN="${SAN%?}"
fi

if [ ${#VALID_DOMAINS[@]} -gt 0 ] && [ ${#VALID_IPS[@]} -gt 0 ]; then
    log INFO "为以下域名和IP地址生成证书: ${VALID_DOMAINS[*]} 和 ${VALID_IPS[*]}"
elif [ ${#VALID_DOMAINS[@]} -gt 0 ]; then
    log INFO "为以下域名生成证书: ${VALID_DOMAINS[*]}"
else
    log INFO "为以下IP地址生成证书: ${VALID_IPS[*]}"
fi

# 进入脚本所在目录
cd "$(dirname "${BASH_SOURCE[0]}")"

# 检查根证书，如果不存在则生成
if [ ! -f "out/root.crt" ]; then
    log INFO "根证书不存在，正在生成..."
    bash gen.root.sh || error_exit "生成根证书失败"
fi

# 创建域名目录
if [ ${#VALID_DOMAINS[@]} -gt 0 ]; then
    BASE_DIR="out/${VALID_DOMAINS[0]}"
else
    # 如果只有IP，使用第一个IP作为目录名
    BASE_DIR="out/$(echo ${VALID_IPS[0]} | tr '.' '_')"
fi
TIME=$(date +%Y%m%d-%H%M)
DIR="${BASE_DIR}/${TIME}"
ensure_dir "$DIR"

log INFO "证书将生成到: $DIR"

# 检查证书密钥是否存在
if [ ! -f "out/cert.key.pem" ]; then
    log INFO "生成证书私钥..."
    openssl genrsa -out "out/cert.key.pem" 4096 || error_exit "生成私钥失败"
fi

# 创建CSR
log INFO "创建证书签名请求..."
# 确定证书名称和CN
if [ ${#VALID_DOMAINS[@]} -gt 0 ]; then
    CERT_NAME="${VALID_DOMAINS[0]}"
    CN="*.${VALID_DOMAINS[0]}"
    OU="${VALID_DOMAINS[0]}"
else
    # 如果只有IP，使用IP作为CN
    CERT_NAME="$(echo ${VALID_IPS[0]} | tr '.' '_')"
    CN="${VALID_IPS[0]}"
    OU="${CERT_NAME}"
fi

openssl req -new -out "${DIR}/${CERT_NAME}.csr.pem" \
    -key out/cert.key.pem \
    -reqexts SAN \
    -config <(cat ca.cnf \
        <(printf "[SAN]\nsubjectAltName=${SAN}")) \
    -subj "/C=CN/ST=Guangdong/L=Zhuhai/O=Cutebaby/OU=${OU}/CN=${CN}" \
    || error_exit "创建CSR失败"

# 颁发证书（包含代码签名扩展和SAN）
log INFO "颁发证书..."
openssl ca -config ./ca.cnf -batch -notext \
    -in "${DIR}/${CERT_NAME}.csr.pem" \
    -out "${DIR}/${CERT_NAME}.crt" \
    -cert ./out/root.crt \
    -keyfile ./out/root.key.pem \
    -extfile <(cat <<EOF
[code_sign_cert]
basicConstraints = CA:FALSE
nsComment = "OpenSSL Generated Code Signing Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth,clientAuth,codeSigning
subjectAltName = ${SAN}
EOF
) \
    -extensions code_sign_cert \
    || error_exit "颁发证书失败"

# 将证书与CA链合并
log INFO "创建证书链..."
cat "${DIR}/${CERT_NAME}.crt" ./out/root.crt > "${DIR}/${CERT_NAME}.bundle.crt"

# 创建符号链接
safe_link "./${TIME}/${CERT_NAME}.bundle.crt" "${BASE_DIR}/${CERT_NAME}.bundle.crt"
safe_link "./${TIME}/${CERT_NAME}.crt" "${BASE_DIR}/${CERT_NAME}.crt"
safe_link "../cert.key.pem" "${BASE_DIR}/${CERT_NAME}.key.pem"
safe_link "../root.crt" "${BASE_DIR}/root.crt"

# 创建PFX文件（用于ClickOnce签名）
log INFO "创建PFX文件..."
openssl pkcs12 -export \
    -out "${DIR}/${CERT_NAME}.pfx" \
    -inkey out/cert.key.pem \
    -in "${DIR}/${CERT_NAME}.crt" \
    -certfile ./out/root.crt \
    -password pass:${PFX_PASSWORD} \
    || error_exit "创建PFX文件失败"

# 为PFX文件创建符号链接
safe_link "./${TIME}/${CERT_NAME}.pfx" "${BASE_DIR}/${CERT_NAME}.pfx"

# 验证证书
log INFO "验证生成的证书..."
validate_cert "${DIR}/${CERT_NAME}.crt" "./out/root.crt"

# 输出证书信息
echo
echo -e "${GREEN}=== 证书生成完成 ===${NC}"
echo
echo -e "${BLUE}证书文件位置:${NC}"
echo "  证书:         ${BASE_DIR}/${CERT_NAME}.crt"
echo "  证书链:       ${BASE_DIR}/${CERT_NAME}.bundle.crt"
echo "  私钥:         ${BASE_DIR}/${CERT_NAME}.key.pem"
echo "  PFX文件:      ${BASE_DIR}/${CERT_NAME}.pfx"
echo
echo -e "${BLUE}PFX文件信息:${NC}"
echo "  路径:         ${BASE_DIR}/${CERT_NAME}.pfx"
echo "  密码:         ${PFX_PASSWORD}"
echo

# 显示证书详细信息
show_cert_info "${DIR}/${CERT_NAME}.crt" "${CERT_NAME}"

# 显示文件列表
echo -e "${BLUE}生成文件列表:${NC}"
LS=$([[ $(ls --help 2>/dev/null | grep '\-\-color') ]] && echo "ls --color=auto" || echo "ls -G")
${LS} -la "${BASE_DIR}/"*.*
echo

log INFO "证书生成成功完成"
