# 自签泛域名证书（增强版）

此工具用于颁发泛域名证书，方便开发环境调试。现已升级为功能全面的SSL证书管理工具。

请勿用于生产环境，生产环境还是购买正式的证书。  
或者到 [Let's Encrypt](https://letsencrypt.org/) 可以申请到免费证书  
（支持多域名和泛域名）。

## 新增功能亮点

### 🔥 全新功能
- **多算法支持**：RSA、ECC/ECDSA、Ed25519
- **多格式输出**：PEM、DER、PKCS#8、PKCS#12、JKS
- **证书管理工具**：查看、验证、检查过期时间
- **自动续期功能**：配置定时任务，自动检查和续期
- **多平台安装**：自动在Linux、macOS、Windows安装证书
- **增强日志系统**：彩色输出、多级别日志、错误处理
- **灵活的参数传递**：支持 `--domain`、`--domains`、`--ip`、`--ips` 等多种方式

### 🚀 使用示例
```bash
# 基础用法（已增强）
./gen.cert.sh -v example.dev cdn.example.dev

# 使用新的参数格式
./gen.cert.sh --domain example.dev --domain cdn.example.dev

# 使用 --domains 和 --ips 参数
./gen.cert.sh --domains example.com,test.com --ips 192.168.1.100,127.0.0.1

# 纯IP地址证书
./gen.cert.sh --ip 127.0.0.1 --ips 192.168.1.1,10.0.0.1

# 使用ECC算法
./gen-cert-advanced.sh --ecc prime256v1 --jks example.dev

# 查看证书信息
./cert-info.sh -i example.dev -f

# 自动续期
./cert-renew.sh -a

# 自动安装根证书
sudo ./install-cert.sh --system
```

## 原有优点
1. 你可以创建任意网站证书，只需导入一次根证书，无需多次导入；
1. 减少重复又无谓的组织信息输入，创建证书时只需要输入域名；
1. 泛域名证书可以减少 `nginx` 配置，例如你要模拟 CDN：  
假设你的项目网站是 `example.dev`，CDN 网站设置为 `cdn.example.dev`，  
你只需在 `nginx` 里面配置一个网站，`server_name` 同时填写  `example.dev`  
和 `cdn.example.dev`，它们可以使用同一个 `*.example.dev` 的证书。
1. 现在你只需要一个证书，就可以搞定所有项目网站！

使用 `SAN` 来支持多域名和泛域名：
```ini
subjectAltName=DNS:*.one.dev,DNS:one.dev,DNS:*.two.dev,DNS:two.dev,DNS:*.three.dev,DNS:three.dev
```

## 系统要求
1. Linux、macOS 或 Windows (WSL/Git Bash)，openssl
1. 事先用 `hosts` 或者 `dnsmasq` 解析你本地开发的域名，  
例如把 `example.dev` 指向 `127.0.0.1`

## 快速开始

### 基础用法
```bash
# 生成证书（已增强，支持彩色输出和错误处理）
./gen.cert.sh example.dev

# 使用 --domain 参数（推荐）
./gen.cert.sh --domain example.dev --domain cdn.example.dev

# 使用 --domains 和 --ips 参数（逗号分隔）
./gen.cert.sh --domains example.com,test.com --ips 192.168.1.100,127.0.0.1

# 多域名（旧格式仍支持）
./gen.cert.sh example.dev cdn.example.dev api.example.dev

# 使用自定义密码
./gen.cert.sh -p mypassword example.dev
```

### 高级用法
```bash
# 使用ECC算法（性能更好）
./gen-cert-advanced.sh --ecc prime256v1 example.dev

# 生成Java KeyStore
./gen-cert-advanced.sh --jks example.dev

# 包含IP地址（使用高级脚本）
./gen-cert-advanced.sh --ip 127.0.0.1 example.dev

# 纯IP地址证书（无域名）
./gen.cert.sh --ip 127.0.0.1 --ips 192.168.1.1,10.0.0.1

# 混合域名和IP
./gen.cert.sh --domain example.com --ip 127.0.0.1 --ips 192.168.1.100
```

### 证书管理
```bash
# 查看证书信息
./cert-info.sh -i example.dev

# 检查过期时间
./cert-info.sh -e example.dev -w 30

# 自动安装根证书
sudo ./install-cert.sh --system

# 设置自动续期
./cert-renew.sh -a
./cert-renew.sh -s '0 2 * * *'  # 每天2点检查
```

## 详细说明

### 生成证书
```bash
# 新的推荐用法（更清晰明确）
./gen.cert.sh --domain <domain> [--domain <domain2>] ...
./gen.cert.sh --domains <domain1>,<domain2> [--ips <ip1>,<ip2>]
./gen.cert.sh --ip <ip> [--ip <ip2>] ...
./gen.cert.sh --ips <ip1>,<ip2> [--domains <domain1>,<domain2>]

# 旧格式（仍然支持）
./gen.cert.sh <domain> [<domain2>] [<domain3>] ...
```

#### 参数说明
- `--domain <域名>` - 添加单个域名，支持泛域名
- `--domains <域名>` - 多个域名，逗号分隔，如 `example.com,test.com`
- `--ip <IP地址>` - 添加单个IP地址到证书
- `--ips <IP地址>` - 多个IP地址，逗号分隔，如 `192.168.1.100,127.0.0.1`
- `-v, --verbose` - 显示详细日志
- `-p, --password <密码>` - 指定PFX文件密码（默认：123456）
- `-a, --algorithm <算法>` - 指定密钥算法（默认：rsa:4096）

#### 使用示例
```bash
# 单域名
./gen.cert.sh --domain example.dev

# 多域名（逗号分隔）
./gen.cert.sh --domains example.com,test.com,api.com

# 混合域名和IP
./gen.cert.sh --domain example.com --ip 127.0.0.1 --ips 192.168.1.100

# 纯IP地址证书
./gen.cert.sh --ip 192.168.1.100 --ips 10.0.0.1,172.16.0.1
```

把 `<domain>` 替换成你的域名，例如 `example.dev`。证书将自动包含泛域名（如 `*.example.dev`）和主域名。

如果同时需要域名和IP地址，可以使用上述所有参数的任意组合。

生成的证书位于：
```text
out/<domain>/<domain>.crt              # 证书文件
out/<domain>/<domain>.bundle.crt       # 证书链（包含根证书）
out/<domain>/<domain>.key.pem          # 私钥文件
out/<domain>/<domain>.pfx              # PKCS#12格式（含密码）
```

**注意**：
- 如果只有IP地址没有域名，目录名将使用IP地址（点替换为下划线），如 `out/127_0_0_1/`
- 每次生成都会创建时间戳目录，如 `20250906-2138/`，保留历史版本
- 符号链接会自动创建，指向最新版本的文件

证书有效期是 2 年，你可以修改 `ca.cnf` 来修改这个年限。

根证书位于：  
`out/root.crt`  
成功之后，使用 `install-cert.sh` 自动安装到操作系统信任这个证书。

根证书的有效期是 20 年，你可以修改 `gen.root.sh` 来修改这个年限。

证书私钥位于：  
`out/cert.key.pem`

其中 `<domain>.bundle.crt` 是已经拼接好 CA 的证书，可以添加到 `nginx` 配置里面。  
然后你就可以愉快地用 `https` 来访问你本地的开发网站了。

### 清空
你可以运行 `flush.sh` 来清空所有历史，包括根证书和网站证书。

### 配置
你可以修改 `ca.cnf` 来修改你的证书年限。
```ini
default_days    = 7300
```

可以修改 `gen.root.sh` 来自定义你的根证书名称和组织。

也可以修改 `gen.cert.sh` 来自定义你的网站证书组织。

## 更多文档
- [使用示例](USAGE_EXAMPLES.md) - 详细的用法示例和场景
- [Chrome 信任证书问题](docs/chrome-trust.md) - Chrome浏览器信任证书指南

## 参考 / 致谢
[Vault and self signed SSL certificates](http://dunne.io/vault-and-self-signed-ssl-certificates)

[利用OpenSSL创建自签名的SSL证书备忘](http://wangye.org/blog/archives/732/)

[Provide subjectAltName to openssl directly on command line](http://security.stackexchange.com/questions/74345/provide-subjectaltname-to-openssl-directly-on-command-line)

## 关于 Let's Encrypt 客户端
官方客户端 `certbot` [太复杂了](https://github.com/Neilpang/acme.sh/issues/386)，推荐使用 [acme.sh](https://github.com/Neilpang/acme.sh/wiki/%E8%AF%B4%E6%98%8E)。

## 关于 .dev 域名
[Chrome to force .dev domains to HTTPS via preloaded HSTS](https://ma.ttias.be/chrome-force-dev-domains-https-via-preloaded-hSTS/) ([2017-9-16](https://chromium-review.googlesource.com/c/chromium/src/+/669923))

## 关于 Chrome 信任证书问题
看到有人反映 Chrome 下无法信任证书，可参考 [这个文档](docs/chrome-trust.md)