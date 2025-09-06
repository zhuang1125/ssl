# 使用示例

本文档提供了各种使用场景的示例，帮助您快速上手这个增强版的SSL证书生成工具。

## 基本用法

### 1. 生成单个域名的证书

```bash
# 生成 example.dev 的证书
./gen.cert.sh example.dev

# 使用自定义密码
./gen.cert.sh -p mypassword example.dev

# 查看详细日志
./gen.cert.sh -v example.dev
```

### 2. 生成多个域名的证书

```bash
# 同时生成多个域名的证书
./gen.cert.sh example.dev cdn.example.dev api.example.dev

# 证书将支持所有列出的域名和它们的通配符
```

## 高级用法

### 1. 使用ECC算法生成证书

```bash
# 使用prime256v1曲线生成证书
./gen-cert-advanced.sh --ecc prime256v1 example.dev

# 使用secp384r1曲线并生成JKS文件
./gen-cert-advanced.sh --ecc secp384r1 --jks example.dev
```

### 2. 生成Ed25519证书（现代算法）

```bash
# 生成Ed25519证书
./gen-cert-advanced.sh --ed25519 example.dev

# 同时生成多种格式
./gen-cert-advanced.sh --ed25519 --p12 --jks example.dev
```

### 3. 生成不同类型的证书

```bash
# 生成服务器证书（默认）
./gen-cert-advanced.sh --server example.dev

# 生成客户端认证证书
./gen-cert-advanced.sh --client example.dev

# 生成代码签名证书
./gen-cert-advanced.sh --codesign example.dev

# 生成邮件证书
./gen-cert-advanced.sh --email example.dev

# 生成所有类型的证书
./gen-cert-advanced.sh --all example.dev
```

### 4. 包含额外的IP地址和域名

```bash
# 添加IP地址到SAN
./gen-cert-advanced.sh --ip 192.168.1.100 --ip 10.0.0.1 example.dev

# 添加额外的域名
./gen-cert-advanced.sh --san test.example.net --san example.org example.dev

# 组合使用
./gen-cert-advanced.sh --ip 127.0.0.1 --san localhost example.dev
```

## 证书管理

### 1. 查看证书信息

```bash
# 查看证书详细信息
./cert-info.sh -i out/example.dev/example.dev.crt

# 使用域名直接查看
./cert-info.sh -i example.dev

# 包含指纹信息
./cert-info.sh -i example.dev -f
```

### 2. 验证证书

```bash
# 验证证书有效性
./cert-info.sh -c example.dev

# 指定根证书文件验证
./cert-info.sh -c example.dev -r /path/to/ca.crt
```

### 3. 检查证书过期时间

```bash
# 检查证书是否即将过期（默认30天）
./cert-info.sh -e example.dev

# 设置60天警告期
./cert-info.sh -e example.dev -w 60

# 列出所有证书及其状态
./cert-info.sh -l
```

## 自动续期

### 1. 手动续期

```bash
# 检查所有证书并自动续期
./cert-renew.sh -a

# 续期指定域名
./cert-renew.sh example.dev cdn.example.dev

# 强制续期（忽略过期时间）
./cert-renew.sh -f example.dev
```

### 2. 配置自动续期

1. 创建配置文件：

```bash
cp cert-renew.conf.example cert-renew.conf
```

2. 编辑配置文件：

```bash
# cert-renew.conf 内容示例
WARNING_DAYS=30
KEEP_VERSIONS=10
NOTIFICATION_EMAIL=admin@example.com
PFX_PASSWORD=securepassword
```

3. 设置定时任务：

```bash
# 每天凌晨2点检查证书
./cert-renew.sh -s '0 2 * * *'

# 每周日午夜检查
./cert-renew.sh -s '0 0 * * 0'
```

## 证书安装

### 1. Linux系统

```bash
# 安装到当前用户
./install-cert.sh

# 安装到系统（需要root权限）
sudo ./install-cert.sh --system

# 使用自定义证书文件
./install-cert.sh -f /path/to/ca.crt -n 'My Custom CA'
```

### 2. macOS系统

```bash
# 安装到用户钥匙串
./install-cert.sh

# 安装到系统钥匙串（需要管理员密码）
sudo ./install-cert.sh --system
```

### 3. Windows系统

```bash
# 通过WSL或Git Bash运行
./install-cert.sh

# 或者手动运行（需要管理员权限）
./install-cert.sh --system
```

## 实际应用场景

### 1. 本地开发环境

```bash
# 为本地开发环境生成证书
./gen.cert.sh localhost 127.0.0.1

# 安装根证书信任
./install-cert.sh
```

### 2. 微服务架构

```bash
# 为多个服务生成证书
./gen.cert.sh api.service.com web.service.com db.service.com

# 使用ECC算法提高性能
./gen-cert-advanced.sh --ecc prime256v1 api.service.com web.service.com
```

### 3. CI/CD流水线

```bash
#!/bin/bash
# 在CI/CD中自动生成和部署证书

# 生成证书
./gen.cert.sh -v staging.example.com

# 输出PFX文件用于部署
echo "PFX_FILE=out/staging.example.com/staging.example.com.pfx" >> $GITHUB_ENV
echo "PFX_PASSWORD=123456" >> $GITHUB_ENV

# 设置自动续期检查
./cert-renew.sh -s '0 3 * * *'
```

### 4. Docker环境

```dockerfile
# Dockerfile示例
FROM alpine:latest
COPY ssl/ /opt/ssl/
RUN chmod +x /opt/ssl/*.sh

# 运行容器时生成证书
CMD ["/opt/ssl/gen.cert.sh", "docker.example.com"]
```

## 故障排除

### 1. 证书不被浏览器信任

```bash
# 检查证书是否正确安装
./cert-info.sh -c out/root.crt

# 重新安装根证书
sudo ./install-cert.sh --system --remove  # 先删除
sudo ./install-cert.sh --system        # 再安装

# 重启浏览器
```

### 2. OpenSSL版本问题

```bash
# 检查OpenSSL版本
openssl version

# 如果不支持Ed25519，降级使用ECC
./gen-cert-advanced.sh --ecc prime256v1 example.dev
```

### 3. 权限问题

```bash
# 确保脚本有执行权限
chmod +x *.sh

# 确保输出目录有正确的权限
sudo chown -R $USER:$USER out/
chmod 700 out/cert.key.pem
```

## 性能优化建议

1. **使用ECC证书**：比RSA更小的密钥大小，更好的性能
2. **定期清理旧版本**：使用 `cert-renew.sh -k 5` 只保留5个版本
3. **监控证书过期**：设置定期检查并配置邮件通知
4. **使用自动化工具**：集成到CI/CD流程中自动管理和更新证书