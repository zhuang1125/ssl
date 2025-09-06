#!/bin/bash

if [ -z "$1" ]
then
    echo
    echo '生成代码签名证书（适用于ClickOnce清单签名）'
    echo
    echo 'Usage: ./gen.codesign.sh <company-name>'
    echo '    <company-name>    公司名称，例如 "MyCompany"'
    exit;
fi

COMPANY_NAME="$1"
BASE_DIR="out/${COMPANY_NAME}.codesign"
TIME=`date +%Y%m%d-%H%M`
DIR="${BASE_DIR}/${TIME}"
mkdir -p ${DIR}

# 移动到根目录
cd "$(dirname "${BASH_SOURCE[0]}")"

# 生成根证书（如果不存在）
if [ ! -f "out/root.crt" ]; then
    bash gen.root.sh
fi

# 创建私钥
openssl genrsa -out "${DIR}/${COMPANY_NAME}.key" 4096

# 创建证书签名请求(CSR)
openssl req -new -key "${DIR}/${COMPANY_NAME}.key" \
    -out "${DIR}/${COMPANY_NAME}.csr" \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=${COMPANY_NAME}/OU=IT/CN=${COMPANY_NAME} Code Signing Certificate"

# 使用根证书签名（创建代码签名证书）
openssl x509 -req -in "${DIR}/${COMPANY_NAME}.csr" \
    -CA ./out/root.crt \
    -CAkey ./out/root.key.pem \
    -CAcreateserial \
    -out "${DIR}/${COMPANY_NAME}.crt" \
    -days 7300 \
    -sha256 \
    -extfile <(cat <<EOF
[cert_ext]
basicConstraints=CA:FALSE
keyUsage=digitalSignature
extendedKeyUsage=codeSigning
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EOF
) \
    -extensions cert_ext

# 创建.pfx文件（需要设置密码）
PFX_PASSWORD="123456"  # 默认密码，可以修改
openssl pkcs12 -export \
    -out "${DIR}/${COMPANY_NAME}.pfx" \
    -inkey "${DIR}/${COMPANY_NAME}.key" \
    -in "${DIR}/${COMPANY_NAME}.crt" \
    -certfile ./out/root.crt \
    -password pass:${PFX_PASSWORD}

# 创建符号链接到最新版本
ln -snf "./${TIME}/${COMPANY_NAME}.pfx" "${BASE_DIR}/${COMPANY_NAME}.pfx"
ln -snf "./${TIME}/${COMPANY_NAME}.crt" "${BASE_DIR}/${COMPANY_NAME}.crt"
ln -snf "./${TIME}/${COMPANY_NAME}.key" "${BASE_DIR}/${COMPANY_NAME}.key"

# 输出证书信息
echo
echo "代码签名证书已创建："
echo "PFX文件位置: $(pwd)/${BASE_DIR}/${COMPANY_NAME}.pfx"
echo "PFX密码: ${PFX_PASSWORD}"
echo
echo "证书信息："
openssl pkcs12 -in "${DIR}/${COMPANY_NAME}.pfx" -nokeys -info -passin pass:${PFX_PASSWORD}