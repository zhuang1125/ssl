#!/bin/bash

if [ -z "$1" ]
then
    echo
    echo 'Issue a wildcard SSL certificate with Cutebaby ROOT CA'
    echo
    echo 'Usage: ./gen.cert.sh <domain> [<domain2>] [<domain3>] [<domain4>] ...'
    echo '    <domain>          The domain name of your site, like "example.dev",'
    echo '                      you will get a certificate for *.example.dev'
    echo '                      Multiple domains are acceptable'
    echo
    echo 'Note: This script also generates a .pfx file (password: 123456)'
    echo '      that can be used for ClickOnce manifest signing'
    exit;
fi

SAN=""
for var in "$@"
do
    SAN="$SAN""DNS:*.${var},DNS:${var},"
done
SAN="${SAN%?}"

# Move to root directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Generate root certificate if not exists
if [ ! -f "out/root.crt" ]; then
    bash gen.root.sh
fi

# Create domain directory
BASE_DIR="out/$1"
TIME=`date +%Y%m%d-%H%M`
DIR="${BASE_DIR}/${TIME}"
mkdir -p ${DIR}

# Create CSR
openssl req -new -out "${DIR}/$1.csr.pem" \
    -key out/cert.key.pem \
    -reqexts SAN \
    -config <(cat ca.cnf \
        <(printf "[SAN]\nsubjectAltName=${SAN}")) \
    -subj "/C=CN/ST=Guangdong/L=Zhuhai/O=Cutebaby/OU=$1/CN=*.$1"

# Issue certificate with code signing extensions and subjectAltName
openssl ca -config ./ca.cnf -batch -notext \
    -in "${DIR}/$1.csr.pem" \
    -out "${DIR}/$1.crt" \
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
    -extensions code_sign_cert

# Chain certificate with CA
cat "${DIR}/$1.crt" ./out/root.crt > "${DIR}/$1.bundle.crt"
ln -snf "./${TIME}/$1.bundle.crt" "${BASE_DIR}/$1.bundle.crt"
ln -snf "./${TIME}/$1.crt" "${BASE_DIR}/$1.crt"
ln -snf "../cert.key.pem" "${BASE_DIR}/$1.key.pem"
ln -snf "../root.crt" "${BASE_DIR}/root.crt"

# Create PFX file for ClickOnce signing
PFX_PASSWORD="123456"  # Default password for PFX
openssl pkcs12 -export \
    -out "${DIR}/$1.pfx" \
    -inkey out/cert.key.pem \
    -in "${DIR}/$1.crt" \
    -certfile ./out/root.crt \
    -password pass:${PFX_PASSWORD}

# Create symlink for PFX file
ln -snf "./${TIME}/$1.pfx" "${BASE_DIR}/$1.pfx"

# Output certificates
echo
echo "Certificates are located in:"
echo
echo "PFX file for ClickOnce signing: ${BASE_DIR}/$1.pfx (password: 123456)"

LS=$([[ `ls --help | grep '\-\-color'` ]] && echo "ls --color" || echo "ls -G")

${LS} -la `pwd`/${BASE_DIR}/*.*
