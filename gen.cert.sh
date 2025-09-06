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
    echo "${YELLOW}用法:${NC} $0 <域名> [<域名2>] [<域名3>] [<域名4>] ..."
    echo "    ${YELLOW}<域名>${NC}           你的网站域名，如 'example.dev'"
    echo "                        将获得 *.example.dev 的证书"
    echo "                        支持多个域名"
    echo
    echo "${YELLOW}选项:${NC}"
    echo "    -h, --help          显示此帮助信息"
    echo "    -v, --verbose       显示详细日志"
    echo "    -p, --password      指定PFX文件密码（默认：123456）"
    echo "    -a, --algorithm     指定密钥算法（默认：rsa:4096）"
    echo
    echo "${BLUE}注意:${NC} 此脚本还会生成PFX文件，可用于ClickOnce清单签名"
    echo
}

# 参数解析
PFX_PASSWORD="123456"
KEY_ALGORITHM="rsa:4096"
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
        -p|--password)
            PFX_PASSWORD="$2"
            shift 2
            ;;
        -a|--algorithm)
            KEY_ALGORITHM="$2"
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

if [ ${#DOMAINS[@]} -eq 0 ]; then
    show_help
    error_exit "至少需要指定一个域名"
fi

# 格式化和验证域名
VALID_DOMAINS=()
for domain in "${DOMAINS[@]}"; do
    # 格式化域名
    formatted_domain=$(format_domain "$domain")
    VALID_DOMAINS+=("$formatted_domain")
    log DEBUG "添加域名: $formatted_domain"
done

# 构建SAN字符串
SAN=""
for domain in "${VALID_DOMAINS[@]}"; do
    SAN="$SAN""DNS:*.${domain},DNS:${domain},"
done
SAN="${SAN%?}"

log INFO "为以下域名生成证书: ${VALID_DOMAINS[*]}"

# 进入脚本所在目录
cd "$(dirname "${BASH_SOURCE[0]}")"

# 检查根证书，如果不存在则生成
if [ ! -f "out/root.crt" ]; then
    log INFO "根证书不存在，正在生成..."
    bash gen.root.sh || error_exit "生成根证书失败"
fi

# 创建域名目录
BASE_DIR="out/${VALID_DOMAINS[0]}"
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
openssl req -new -out "${DIR}/${VALID_DOMAINS[0]}.csr.pem" \
    -key out/cert.key.pem \
    -reqexts SAN \
    -config <(cat ca.cnf \
        <(printf "[SAN]\nsubjectAltName=${SAN}")) \
    -subj "/C=CN/ST=Guangdong/L=Zhuhai/O=Cutebaby/OU=${VALID_DOMAINS[0]}/CN=*.${VALID_DOMAINS[0]}" \
    || error_exit "创建CSR失败"

# 颁发证书（包含代码签名扩展和SAN）
log INFO "颁发证书..."
openssl ca -config ./ca.cnf -batch -notext \
    -in "${DIR}/${VALID_DOMAINS[0]}.csr.pem" \
    -out "${DIR}/${VALID_DOMAINS[0]}.crt" \
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
cat "${DIR}/${VALID_DOMAINS[0]}.crt" ./out/root.crt > "${DIR}/${VALID_DOMAINS[0]}.bundle.crt"

# 创建符号链接
safe_link "./${TIME}/${VALID_DOMAINS[0]}.bundle.crt" "${BASE_DIR}/${VALID_DOMAINS[0]}.bundle.crt"
safe_link "./${TIME}/${VALID_DOMAINS[0]}.crt" "${BASE_DIR}/${VALID_DOMAINS[0]}.crt"
safe_link "../cert.key.pem" "${BASE_DIR}/${VALID_DOMAINS[0]}.key.pem"
safe_link "../root.crt" "${BASE_DIR}/root.crt"

# 创建PFX文件（用于ClickOnce签名）
log INFO "创建PFX文件..."
openssl pkcs12 -export \
    -out "${DIR}/${VALID_DOMAINS[0]}.pfx" \
    -inkey out/cert.key.pem \
    -in "${DIR}/${VALID_DOMAINS[0]}.crt" \
    -certfile ./out/root.crt \
    -password pass:${PFX_PASSWORD} \
    || error_exit "创建PFX文件失败"

# 为PFX文件创建符号链接
safe_link "./${TIME}/${VALID_DOMAINS[0]}.pfx" "${BASE_DIR}/${VALID_DOMAINS[0]}.pfx"

# 验证证书
log INFO "验证生成的证书..."
validate_cert "${DIR}/${VALID_DOMAINS[0]}.crt" "./out/root.crt"

# 输出证书信息
echo
echo -e "${GREEN}=== 证书生成完成 ===${NC}"
echo
echo -e "${BLUE}证书文件位置:${NC}"
echo "  证书:         ${BASE_DIR}/${VALID_DOMAINS[0]}.crt"
echo "  证书链:       ${BASE_DIR}/${VALID_DOMAINS[0]}.bundle.crt"
echo "  私钥:         ${BASE_DIR}/${VALID_DOMAINS[0]}.key.pem"
echo "  PFX文件:      ${BASE_DIR}/${VALID_DOMAINS[0]}.pfx"
echo
echo -e "${BLUE}PFX文件信息:${NC}"
echo "  路径:         ${BASE_DIR}/${VALID_DOMAINS[0]}.pfx"
echo "  密码:         ${PFX_PASSWORD}"
echo

# 显示证书详细信息
show_cert_info "${DIR}/${VALID_DOMAINS[0]}.crt" "${VALID_DOMAINS[0]}"

# 显示文件列表
echo -e "${BLUE}生成文件列表:${NC}"
LS=$([[ $(ls --help 2>/dev/null | grep '\-\-color') ]] && echo "ls --color=auto" || echo "ls -G")
${LS} -la "${BASE_DIR}/"*.*
echo

log INFO "证书生成成功完成"
