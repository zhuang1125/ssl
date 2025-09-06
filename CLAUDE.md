# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a self-signed wildcard SSL certificate generation tool designed for development environment debugging. The tool allows developers to create their own SSL certificates for local development HTTPS testing without purchasing official certificates or dealing with Let's Encrypt complexity.

## Key Commands

### Generate Certificates
```bash
./gen.cert.sh <domain> [<domain2>] [<domain3>] ...
```
- Generates wildcard SSL certificates for one or more domains
- Supports SAN (Subject Alternative Name) for multiple domains and wildcards
- Automatically creates PFX file with password "123456" for ClickOnce manifest signing
- Example: `./gen.cert.sh example.dev cdn.example.dev`

### Generate Root Certificate
```bash
./gen.root.sh
```
- Creates the self-signed root CA certificate (Cutebaby ROOT CA)
- Required before generating domain certificates
- 4096-bit RSA key, 20-year validity period

### Generate Code Signing Certificate
```bash
./gen.codesign.sh
```
- Creates code signing certificates for ClickOnce applications
- Generates PFX file for code signing operations

### Clean All Generated Files
```bash
./flush.sh
```
- Removes all generated certificates and keys
- Rebuilds OpenSSL directory structure

## Architecture

### Certificate Generation Flow
1. **Root Certificate Setup**: The `gen.root.sh` script creates a root CA that signs all domain certificates
2. **Domain Certificate Creation**: `gen.cert.sh` generates certificates with the following properties:
   - Supports wildcards (*.example.dev) and multiple domains via SAN
   - Includes server authentication, client authentication, and code signing extensions
   - Links certificate chain with CA root
   - Creates PFX file for Windows compatibility
3. **Version Management**: Each certificate generation creates timestamped directories while maintaining symlinks to the latest version

### Configuration System
- `ca.cnf`: OpenSSL configuration file defining:
  - Certificate authority settings
  - Multiple certificate extensions (server, client, code signing)
  - Default key size (4096-bit) and algorithm (SHA-256)
  - Loose policy allowing optional fields
  - 2-year default validity for domain certificates

### Output Structure
```
out/
├── root.crt           # Root CA certificate
├── root.key.pem       # Root CA private key
├── cert.key.pem       # Domain certificate private key
├── newcerts/          # Certificate database
├── index.txt          # Certificate index file
├── serial             # Serial number file
└── <domain>/          # Domain-specific directory
    ├── <domain>.crt           # Certificate
    ├── <domain>.bundle.crt    # Certificate + CA chain
    ├── <domain>.pfx           # PKCS#12 format (password: 123456)
    ├── <domain>.key.pem       # Private key
    ├── root.crt               # Symlink to root certificate
    └── <timestamp>/           # Versioned directory
        ├── <domain>.crt
        ├── <domain>.bundle.crt
        └── <domain>.pfx
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