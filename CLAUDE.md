# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive self-signed wildcard SSL certificate generation tool designed for development environment debugging. The tool allows developers to create their own SSL certificates for local development HTTPS testing without purchasing official certificates or dealing with Let's Encrypt complexity. The project has been enhanced with advanced features including multiple algorithms, automatic renewal, certificate information viewing, and multi-platform certificate installation.

## Key Commands

### Generate Certificates (Enhanced)
```bash
./gen.cert.sh [options] <domain> [<domain2>] ...
```
- Generates wildcard SSL certificates for one or more domains
- Enhanced with error handling, colored output, and detailed logging
- New options:
  - `-v, --verbose`: Show detailed logs
  - `-p, --password <password>`: Set PFX password (default: 123456)
  - `-a, --algorithm <algorithm>`: Set key algorithm (default: rsa:4096)

### Advanced Certificate Generation
```bash
./gen-cert-advanced.sh [options] <domain> [<domain2>] ...
```
- Supports multiple algorithms: RSA, ECC/ECDSA, Ed25519
- Multiple output formats: PEM, DER, PKCS#8, PKCS#12, JKS
- Multiple hash algorithms: SHA-256, SHA-384, SHA-512
- Multiple certificate types: Server, Client, Code Signing, Email
- Example: `./gen-cert-advanced.sh --ecc prime256v1 --jks example.dev`

### Generate Root Certificate
```bash
./gen.root.sh
```
- Creates the self-signed root CA certificate (Cutebaby ROOT CA)
- Required before generating domain certificates
- 4096-bit RSA key, 20-year validity period

### Certificate Information and Verification
```bash
./cert-info.sh [options] [certificate file or domain]
```
- View detailed certificate information
- Verify certificate validity
- Check expiration status
- List all generated certificates
- Examples:
  - `./cert-info.sh -i example.dev`: Show certificate info
  - `./cert-info.sh -c out/example.dev/example.dev.crt`: Verify certificate
  - `./cert-info.sh -e example.dev -w 30`: Check if expires in 30 days
  - `./cert-info.sh -l`: List all certificates

### Automatic Certificate Renewal
```bash
./cert-renew.sh [options] [domain...]
```
- Automatically check and renew certificates
- Schedule automatic renewal with cron
- Configuration file support
- Clean old versions
- Examples:
  - `./cert-renew.sh -a`: Check all certificates
  - `./cert-renew.sh -s '0 2 * * *'`: Schedule daily at 2 AM

### Certificate Installation
```bash
./install-cert.sh [options]
```
- Automatically install root certificate on multiple platforms
- Support for Linux (Debian, Ubuntu, CentOS, RHEL, Fedora, Arch), macOS, Windows
- System-wide or user-level installation
- Example: `./install-cert.sh --system`: Install system-wide

### Clean All Generated Files
```bash
./flush.sh
```
- Removes all generated certificates and keys
- Rebuilds OpenSSL directory structure

## Architecture

### Certificate Generation Flow
1. **Root Certificate Setup**: The `gen.root.sh` script creates a root CA that signs all domain certificates
2. **Domain Certificate Creation**: Multiple certificate generation tools:
   - `gen.cert.sh`: Enhanced basic generator with error handling and logging
   - `gen-cert-advanced.sh`: Advanced generator supporting multiple algorithms, formats, and types
3. **Certificate Management**: 
   - `cert-info.sh`: View, verify, and check certificate expiration
   - `cert-renew.sh`: Automatic renewal with configuration and scheduling
4. **Certificate Installation**: `install-cert.sh` automatically installs root certificates on multiple platforms

### Common Functions Library
- `common.sh`: Central library containing:
  - Logging system with multiple levels (DEBUG, INFO, WARN, ERROR)
  - Error handling and validation functions
  - Certificate utility functions (validation, info display, expiry check)
  - File management helpers (safe removal, symlinks, backups)

### Configuration System
- `ca.cnf`: OpenSSL configuration file defining:
  - Certificate authority settings
  - Multiple certificate extensions (server, client, code signing)
  - Default key size (4096-bit) and algorithm (SHA-256)
  - Loose policy allowing optional fields
  - 2-year default validity for domain certificates
- `cert-renew.conf.example`: Template for automatic renewal configuration

### Supported Algorithms and Formats

#### Cryptographic Algorithms:
- **RSA**: 2048, 3072, 4096, 8192 bits
- **ECC/ECDSA**: prime256v1, secp384r1, secp521r1
- **Ed25519**: Modern elliptic curve signature algorithm (requires OpenSSL 1.1.1+)

#### Output Formats:
- **PEM**: Base64 encoded format (default)
- **DER**: Binary ASN.1 format
- **PKCS#8**: Standard private key format
- **PKCS#12**: PFX format with password protection
- **JKS**: Java KeyStore format

#### Certificate Types:
- **Server**: For HTTPS/TLS servers
- **Client**: For client authentication
- **Code Signing**: For signing applications and code
- **Email**: For S/MIME email encryption

### Output Structure
```
out/
├── root.crt           # Root CA certificate
├── root.key.pem       # Root CA private key
├── cert.key.pem       # Domain certificate private key
├── newcerts/          # Certificate database
├── index.txt          # Certificate index file
├── serial             # Serial number file
├── backups/           # Backup directory
└── <domain>/          # Domain-specific directory
    ├── <domain>.crt           # Certificate
    ├── <domain>.bundle.crt    # Certificate + CA chain
    ├── <domain>.pfx           # PKCS#12 format
    ├── <domain>.jks           # Java KeyStore (if generated)
    ├── <domain>.key.pem       # Private key
    ├── <domain>.key.der       # DER format (if generated)
    ├── <domain>.key.pk8       # PKCS#8 format (if generated)
    ├── root.crt               # Symlink to root certificate
    └── <timestamp>/           # Versioned directory
        ├── <domain>.crt
        ├── <domain>.bundle.crt
        ├── <domain>.pfx
        └── ...
```

## Important Implementation Details

### Certificate Properties
- **Algorithm**: RSA 4096-bit with SHA-256
- **Extensions**: Includes serverAuth, clientAuth, and codeSigning
- **Wildcard Support**: Automatic SAN generation for *.domain.com and domain.com
- **PFX Password**: Always "123456" for ClickOnce compatibility

### SAN Format
The tool generates Subject Alternative Names dynamically:
```
subjectAltName=DNS:*.one.dev,DNS:one.dev,DNS:*.two.dev,DNS:two.dev
```

### Certificate Trust Model
- Root certificate must be manually imported into operating system trust store
- Once root is trusted, all generated certificates are automatically trusted
- Documentation available in `docs/chrome-trust.md` for Chrome-specific trust issues

## Development Notes

- Certificate validity periods: 2 years for domains (configurable in `ca.cnf`), 20 years for root (configurable in `gen.root.sh`)
- All scripts use relative paths, ensuring portability
- The tool maintains certificate history through timestamped directories
- Symlinks ensure stable paths for configuration files (nginx, IIS, etc.)
- Default organization information: China, Guangdong Province, Zhuhai, Cutebaby