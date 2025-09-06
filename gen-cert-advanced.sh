#!/bin/bash

# 高级证书生成工具
# 支持多种算法和格式

# 加载通用函数库
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# 设置日志级别
CURRENT_LOG_LEVEL=INFO

# 显示帮助信息
show_help() {
    echo
    echo "${GREEN}高级证书生成工具${NC}"
    echo
    echo "${YELLOW}用法:${NC} $0 [选项] <域名> [<域名2>] ..."
    echo
    echo "${YELLOW}算法选项:${NC}"
    echo "    --rsa <bits>         RSA算法（默认：4096位）"
    echo "    --ecc <curve>        ECC算法（如：prime256v1, secp384r1, secp521r1）"
    echo "    --ed25519            Ed25519算法（需要OpenSSL 1.1.1+）"
    echo
    echo "${YELLOW}格式选项:${NC}"
    echo "    --pem                PEM格式（默认）"
    echo "    --der                DER格式"
    echo "    --pkcs8              PKCS#8格式私钥"
    echo "    --p12                PKCS#12格式（PFX）"
    echo "    --jks                Java Keystore格式（需要keytool）"
    echo
    echo "${YELLOW}哈希算法:${NC}"
    echo "    --sha256             SHA-256（默认）"
    echo "    --sha384             SHA-384"
    echo "    --sha512             SHA-512"
    echo
    echo "${YELLOW}证书类型:${NC}"
    echo "    --server             服务器证书（默认）"
    echo "    --client             客户端证书"
    echo "    --code_sign           代码签名证书"
    echo "    --email              邮件证书"
    echo "    --all                所有类型"
    echo
    echo "${YELLOW}其他选项:${NC}"
    echo "    -h, --help           显示帮助信息"
    echo "    -v, --verbose        详细日志"
    echo "    -p, --password <密码> 指定密码（默认：123456）"
    echo "    -o, --output <目录>  指定输出目录"
    echo "    --san                包含额外的备用名称"
    echo "    --ip                 包含IP地址"
    echo "    --no-wildcard        不包含通配符"
    echo
    echo "${BLUE}示例:${NC}"
    echo "  $0 --ecc prime256v1 example.dev            # ECC证书"
    echo "  $0 --ed25519 example.dev                     # Ed25519证书"
    echo "  $0 --rsa 2048 example.dev                   # 2048位RSA"
    echo "  $0 --jks example.dev                        # 生成JKS"
    echo "  $0 --code_sign --sha512 example.dev          # 代码签名证书"
    echo
}

# 参数解析
ALGORITHM="rsa"
KEY_SIZE="4096"
ECC_CURVE=""
ED25519=false
HASH_ALGO="sha256"
CERT_TYPES=("server")
FORMATS=("pem")
PASSWORD="123456"
OUTPUT_DIR=""
EXTRA_SANS=()
EXTRA_IPS=()
NO_WILDCARD=false

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
            PASSWORD="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --rsa)
            ALGORITHM="rsa"
            KEY_SIZE="$2"
            shift 2
            ;;
        --ecc)
            ALGORITHM="ecc"
            ECC_CURVE="$2"
            shift 2
            ;;
        --ed25519)
            ALGORITHM="ed25519"
            ED25519=true
            shift
            ;;
        --sha256|--sha384|--sha512)
            HASH_ALGO="${1#--}"
            shift
            ;;
        --server)
            CERT_TYPES=("server")
            shift
            ;;
        --client)
            CERT_TYPES=("client")
            shift
            ;;
        --code_sign)
            CERT_TYPES=("code_sign")
            shift
            ;;
        --email)
            CERT_TYPES=("email")
            shift
            ;;
        --all)
            CERT_TYPES=("server" "client" "code_sign" "email")
            shift
            ;;
        --pem)
            FORMATS=("pem")
            shift
            ;;
        --der)
            FORMATS=("der")
            shift
            ;;
        --pkcs8)
            FORMATS=("pkcs8")
            shift
            ;;
        --p12)
            FORMATS=("pem" "p12")
            shift
            ;;
        --jks)
            FORMATS=("pem" "jks")
            shift
            ;;
        --san)
            EXTRA_SANS+=("$2")
            shift 2
            ;;
        --ip)
            EXTRA_IPS+=("$2")
            shift 2
            ;;
        --no-wildcard)
            NO_WILDCARD=true
            shift
            ;;
        -*)
            error_exit "未知选项: $1"
            ;;
        *)
            if [[ -z "$1" ]]; then
                show_help
                error_exit "至少需要指定一个域名"
            fi
            DOMAIN_ARG+=("$1")
            shift
            ;;
    esac
done

if [[ ${#DOMAIN_ARG[@]} -eq 0 ]]; then
    show_help
    error_exit "至少需要指定一个域名"
fi

# 检查依赖
check_dependencies openssl

# 如果使用JKS格式，检查keytool
if [[ " ${FORMATS[@]} " =~ " jks " ]]; then
    if ! command -v keytool >/dev/null 2>&1; then
        error_exit "keytool未找到，请安装Java JDK"
    fi
fi

# 格式化域名
DOMAINS=()
for domain in "${DOMAIN_ARG[@]}"; do
    formatted_domain=$(format_domain "$domain")
    DOMAINS+=("$formatted_domain")
done

# 生成私钥
generate_private_key() {
    local output_file="$1"
    log INFO "生成私钥: $output_file"
    
    case $ALGORITHM in
        rsa)
            log DEBUG "使用RSA算法，密钥大小: $KEY_SIZE"
            openssl genrsa -out "$output_file" "$KEY_SIZE" || error_exit "生成RSA私钥失败"
            ;;
        ecc)
            log DEBUG "使用ECC算法，曲线: $ECC_CURVE"
            openssl ecparam -name "$ECC_CURVE" -genkey -noout -out "$output_file" || error_exit "生成ECC私钥失败"
            ;;
        ed25519)
            log DEBUG "使用Ed25519算法"
            if openssl genpkey -algorithm Ed25519 -out "$output_file" 2>/dev/null; then
                # OpenSSL 1.1.1+ 支持Ed25519
                :
            else
                # 降级到使用ecdsa
                log WARN "Ed25519不支持，使用secp521r1替代"
                openssl ecparam -name secp521r1 -genkey -noout -out "$output_file" || error_exit "生成ECDSA私钥失败"
            fi
            ;;
        *)
            error_exit "未知算法: $ALGORITHM"
            ;;
    esac
    
    # 设置私钥权限
    chmod 600 "$output_file"
}

# 转换格式
convert_format() {
    local input_file="$1"
    local output_file="$2"
    local format="$3"
    
    case $format in
        der)
            log DEBUG "转换为DER格式"
            if [[ "$input_file" == *.key ]]; then
                openssl rsa -in "$input_file" -outform DER -out "$output_file"
            else
                openssl x509 -in "$input_file" -outform DER -out "$output_file"
            fi
            ;;
        pkcs8)
            log DEBUG "转换为PKCS#8格式"
            openssl pkcs8 -topk8 -in "$input_file" -out "$output_file" -nocrypt
            ;;
        p12)
            log DEBUG "转换为PKCS#12格式"
            local cert_file="${input_file%.*}.crt"
            openssl pkcs12 -export -in "$cert_file" -inkey "$input_file" \
                -out "$output_file" -password pass:"$PASSWORD"
            ;;
        jks)
            log DEBUG "转换为JKS格式"
            local cert_file="${input_file%.*}.crt"
            local p12_file="${cert_file%.crt}.p12"
            
            # 先创建P12文件
            openssl pkcs12 -export -in "$cert_file" -inkey "$input_file" \
                -out "$p12_file" -password pass:"$PASSWORD"
            
            # 转换为JKS
            keytool -importkeystore -srckeystore "$p12_file" -destkeystore "${cert_file%.crt}.jks" \
                -srcstoretype PKCS12 -deststoretype JKS \
                -srcstorepass "$PASSWORD" -deststorepass "$PASSWORD" \
                -srcalias 1 -destalias 1 -noprompt
            ;;
    esac
}

# 构建SAN字符串
build_san() {
    local san=""
    
    # 添加域名
    for domain in "${DOMAINS[@]}"; do
        if [[ "$NO_WILDCARD" != true ]]; then
            san="$san""DNS:*.${domain},"
        fi
        san="$san""DNS:${domain},"
    done
    
    # 添加额外的SAN
    for extra_san in "${EXTRA_SANS[@]}"; do
        san="$san""DNS:${extra_san},"
    done
    
    # 添加IP地址
    for ip in "${EXTRA_IPS[@]}"; do
        san="$san""IP:${ip},"
    done
    
    echo "${san%,}"
}

# 生成证书扩展配置
generate_extensions() {
    local cert_type="$1"
    local san="$2"
    
    case $cert_type in
        server)
            cat <<EOF
[ server_cert ]
basicConstraints = CA:FALSE
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = ${san}
EOF
            ;;
        client)
            cat <<EOF
[ client_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection
subjectAltName = ${san}
EOF
            ;;
        code_sign)
            cat <<EOF
[ code_sign_cert ]
basicConstraints = CA:FALSE
nsComment = "OpenSSL Generated Code Signing Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = codeSigning
subjectAltName = ${san}
EOF
            ;;
        email)
            cat <<EOF
[ email_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Email Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = emailProtection, clientAuth
subjectAltName = ${san}
EOF
            ;;
    esac
}

# 主函数
main() {
    # 检查根证书
    if [[ ! -f "out/root.crt" ]]; then
        log INFO "根证书不存在，正在生成..."
        bash gen.root.sh || error_exit "生成根证书失败"
    fi
    
    # 设置输出目录
    local base_domain="${DOMAINS[0]}"
    if [[ -n "$OUTPUT_DIR" ]]; then
        BASE_DIR="$OUTPUT_DIR/$base_domain"
    else
        BASE_DIR="out/$base_domain"
    fi
    
    local time=$(date +%Y%m%d-%H%M)
    local output_subdir="${BASE_DIR}/${time}"
    ensure_dir "$output_subdir"
    
    log INFO "输出目录: $output_subdir"
    
    # 构建SAN
    local san=$(build_san)
    log DEBUG "SAN: $san"
    
    # 生成私钥
    local key_file="${output_subdir}/${base_domain}.key"
    generate_private_key "$key_file"
    
    # 为每种证书类型生成证书
    for cert_type in "${CERT_TYPES[@]}"; do
        log INFO "生成 $cert_type 证书..."
        
        # 创建CSR
        local csr_file="${output_subdir}/${base_domain}.${cert_type}.csr.pem"
        openssl req -new -out "$csr_file" \
            -key "$key_file" \
            -reqexts SAN \
            -config <(cat ca.cnf \
                <(printf "[SAN]\nsubjectAltName=${san}")) \
            -subj "/C=CN/ST=Guangdong/L=Zhuhai/O=Cutebaby/OU=${base_domain}/CN=*.${base_domain}" \
            || error_exit "创建CSR失败"
        
        # 签发证书
        local cert_file="${output_subdir}/${base_domain}.${cert_type}.crt"
        openssl ca -config ./ca.cnf -batch -notext \
            -in "$csr_file" \
            -out "$cert_file" \
            -cert ./out/root.crt \
            -keyfile ./out/root.key.pem \
            -extfile <(generate_extensions "$cert_type" "$san") \
            -extensions "${cert_type}_cert" \
            || error_exit "签发证书失败"
        
        # 转换格式
        for format in "${FORMATS[@]}"; do
            case $format in
                pem)
                    # PEM是默认格式，不需要转换
                    ;;
                der)
                    openssl rsa -in "$key_file" -outform DER -out "${key_file}.der"
                    openssl x509 -in "$cert_file" -outform DER -out "${cert_file}.der"
                    ;;
                pkcs8)
                    openssl pkcs8 -topk8 -in "$key_file" -out "${key_file}.pk8" -nocrypt
                    ;;
                p12)
                    openssl pkcs12 -export -in "$cert_file" -inkey "$key_file" \
                        -out "${cert_file%.crt}.p12" -password pass:"$PASSWORD"
                    ;;
                jks)
                    # 先创建P12
                    openssl pkcs12 -export -in "$cert_file" -inkey "$key_file" \
                        -out "${cert_file%.crt}.p12" -password pass:"$PASSWORD"
                    # 转换为JKS
                    keytool -importkeystore -srckeystore "${cert_file%.crt}.p12" \
                        -destkeystore "${cert_file%.crt}.jks" \
                        -srcstoretype PKCS12 -deststoretype JKS \
                        -srcstorepass "$PASSWORD" -deststorepass "$PASSWORD" \
                        -srcalias 1 -destalias 1 -noprompt
                    ;;
            esac
        done
    done
    
    # 创建符号链接
    safe_link "./${time}/${base_domain}.key" "${BASE_DIR}/${base_domain}.key"
    
    # 输出信息
    echo
    echo -e "${GREEN}=== 证书生成完成 ===${NC}"
    echo
    echo -e "${BLUE}算法:${NC} $ALGORITHM ${KEY_SIZE:-$ECC_CURVE}"
    echo -e "${BLUE}哈希:${NC} $HASH_ALGO"
    echo -e "${BLUE}证书类型:${NC} ${CERT_TYPES[*]}"
    echo -e "${BLUE}输出格式:${NC} ${FORMATS[*]}"
    echo
    echo -e "${BLUE}输出目录:${NC} $output_subdir"
    
    # 显示文件列表
    echo
    echo -e "${BLUE}生成文件:${NC}"
    LS=$([[ $(ls --help 2>/dev/null | grep '\-\-color') ]] && echo "ls --color=auto" || echo "ls -G")
    ${LS} -la "$output_subdir/"
    echo
    
    log INFO "高级证书生成成功"
}

# 执行主函数
main "$@"