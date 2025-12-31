# luci-app-mydomain

luci-app-mydomain 是一个用于 OpenWrt LuCI 的域名管理应用，提供动态 DNS 管理、反向代理配置和 SSL/TLS 证书管理等功能。

## 功能特性

### 1. 动态域名管理 (Dynamic DNS)
- 支持多种 DNS 服务商 (DNSPod, Aliyun, Cloudflare, 以及其他支持 API 的 DNS 服务)
- 支持自动检测和更新公网 IP 地址
- 同时支持 IPv4 和 IPv6
- 支持自定义更新间隔和脚本
- 支持域名状态监控和通知
- 支持多域名和子域名管理

### 2. 反向代理管理 (Reverse Proxy)
- 基于 HAProxy 实现高性能反向代理
- 支持 HTTP/HTTPS 代理和负载均衡
- 支持 SSL/TLS 证书自动绑定
- 支持 WebSocket 代理
- 支持自定义访问规则和 ACL
- 支持实时状态监控

### 3. 证书管理 (Certificate Management)
- 支持 ACME 协议自动申请 Let's Encrypt 证书
- 支持 HTTP-01 和 DNS-01 验证方式
- 支持证书自动续期
- 支持多域名证书和通配符证书
- 支持证书状态监控和通知
- 支持证书手动上传和管理

## 系统要求

- OpenWrt 19.07 及以上版本
- LuCI 19.07 及以上版本
- 依赖软件包：
  - haproxy
  - acme
  - curl
  - openssl-util
  - luci-lib-jsonc

## 安装方法

### 从源码编译安装
1. 将项目克隆到 OpenWrt SDK 的 package 目录
2. 运行 `make menuconfig`
3. 在 `LuCI -> Applications` 中选择 `luci-app-mydomain`
4. 编译固件或单独编译包

### 直接安装 IPK 包
1. 下载适合您设备的 IPK 包
2. 运行 `opkg install luci-app-mydomain_1.0.0_all.ipk`
3. 安装完成后在 LuCI 界面中配置

## 使用说明

### 配置动态域名
1. 登录 LuCI 界面，进入 `服务 -> Dynamic Domain -> 动态域名设置`
2. 点击 "添加" 按钮创建新的动态域名配置
3. 填写域名信息、DNS 服务商和 API 密钥
4. 选择更新间隔和验证方式
5. 保存配置并启用

### 配置反向代理
1. 进入 `服务 -> Dynamic Domain -> 反向代理设置`
2. 点击 "添加" 按钮创建新的代理规则
3. 填写域名、目标服务器和端口
4. 选择是否启用 SSL 和证书
5. 保存配置并应用

### 配置证书管理
1. 进入 `服务 -> Dynamic Domain -> 证书管理`
2. 点击 "添加" 按钮创建新的证书申请
3. 填写域名信息和验证方式
4. 选择证书存储位置和续期设置
5. 保存配置并申请证书

## 配置示例

### 动态域名配置示例
```uci
config domain 'my_domain'
    option enabled '1'
    option domain 'example.com'
    list subdomains '@'
    list subdomains 'www'
    option service 'cloudflare'
    option dns_api_key 'your_api_key'
    option ipv4_enabled '1'
    option ipv6_enabled '1'
```    


## **反代配置**
用于将 `https://mv.movie.top` 代理至内网 `192.168.10.3:7023`

### 核心配置
| 模块          | 配置项               | 参数示例/说明                                                                 | 必要性 |
|---------------|----------------------|-----------------------------------------------------------------------------|--------|
| **前端配置**  |                      |                                                                             |        |
|               | 监听地址             | `0.0.0.0:80` (HTTP) 或 `0.0.0.0:443` (HTTPS)                      | 必选   |
|               | ACL规则              | `acl is_mv hdr(host) -i mv.movie.top`                                       | 必选   |
|               | 证书绑定             | `bind *:443 ssl crt /etc/acme/movie.top/fullchain.cer`                      | 必选   |
| **后端配置**  |                      |                                                                             |        |
|               | 后端名称             | `backend_mv`                                                               | 必选   |
|               | 服务器地址           | `server server1 192.168.10.3:7023 check`                                    | 必选   |
|               | 负载均衡算法         | `roundrobin` (单服务器时可忽略)                                             | 可选   |

### 完整配置示例
```bash
frontend https_in
    bind *:443 ssl crt /etc/acme/movie.top/fullchain.cer
    acl is_mv hdr(host) -i mv.movie.top
    use_backend backend_mv if is_mv

backend backend_mv
    server server1 192.168.10.3:7023 check
```
## **证书配置**
用于申请 *.movie.top 的 Let's Encrypt 证书（DNS-01 验证）

| 配置项               | 参数值/操作说明                                                                 | 必要性 |
|----------------------|-------------------------------------------------------------------------------|--------|
| **基本设置**         |                                                                               |        |
| `启用`               | ✅ 勾选                                                                       | 必选   |
| `验证方法`           | `DNS-01 DNS验证`                                                              | 必选   |
| `域名`               | 添加两行：<br>1. `movie.top`（主域名）<br>2. `*.movie.top`（泛域名）          | 必选   |
| **高级设置**         |                                                                               |        |
| `ACME服务器URL`      | Let's Encrypt 生产环境：<br>`https://acme-v02.api.letsencrypt.org/directory`  | 必选   |
| `密钥类型`           | `RSA 2048位`                                                                  | 可选   |
| `更新前天数`         | `60`（默认值）                                                                | 可选   |
| **DNS验证**          |                                                                               |        |
| `DNS API`            | 选择您的 DNS 服务商（如 `dns_cf`、`dns_ali`、`dns_dp`）                       | 必选   |
| `DNS API凭据`        | **Cloudflare**:<br>`CF_Key="your_api_key"`<br>`CF_Email="your_email"`<br>**阿里云**:<br>`Ali_Key="your_id"`<br>`Ali_Secret="your_secret"` | 必选   |
| **证书路径**         | `/etc/acme/movie.top/fullchain.cer`（证书）<br>`/etc/acme/movie.top/movie.top.key`（私钥） | 自动生成 |
