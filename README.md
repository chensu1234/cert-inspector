# cert-inspector 🔒

> SSL/TLS 证书检查工具 — 快速检查证书链、过期时间、加密套件和潜在安全问题

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Go Version](https://img.shields.io/badge/Go-1.21+-00ADD8.svg)](https://golang.org/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-blue.svg)](https://golang.org/)

`cert-inspector` 是一个轻量、高效的 SSL/TLS 证书检查工具，无需外部依赖即可运行。可批量检查多个主机的证书状态，识别过期、弱签名算法、废弃 TLS 版本等问题。

## ✨ 特性

- 🔒 **完整证书链分析** — 显示从 Leaf 到 Root CA 的完整链
- ⏱️ **过期预警** — 可配置警告 / 严重阈值，智能分级
- 🔍 **加密质量检测** — TLS 版本、加密套件、签名算法检查
- ⚠️ **安全问题识别** — 检测弱签名 (MD5/SHA1)、废弃 TLS 版本 (1.0/1.1)
- 📊 **批量检查** — 一行命令检查任意数量主机
- 🎨 **彩色输出** — 终端友好的彩色状态报告
- ⚡ **零依赖** — 纯 Go 编写，仅依赖标准库
- 🔔 **Webhook 支持** — 可选通知到 Slack 等 Webhook

## 🏃 快速开始

### 安装

**方式一：下载预编译二进制（推荐）**

```bash
# macOS (Apple Silicon)
curl -sL https://github.com/chensu1234/cert-inspector/releases/latest/download/cert-inspector-darwin-arm64 -o cert-inspector
chmod +x cert-inspector

# macOS (Intel)
curl -sL https://github.com/chensu1234/cert-inspector/releases/latest/download/cert-inspector-darwin-amd64 -o cert-inspector
chmod +x cert-inspector

# Linux
curl -sL https://github.com/chensu1234/cert-inspector/releases/latest/download/cert-inspector-linux-amd64 -o cert-inspector
chmod +x cert-inspector
```

**方式二：从源码构建**

```bash
git clone https://github.com/chensu1234/cert-inspector.git
cd cert-inspector
go build -o bin/cert-inspector ./cmd/cert-inspector/
```

### 使用

```bash
# 检查单个主机
./bin/cert-inspector github.com:443

# 检查多个主机
./bin/cert-inspector github.com:443 google.com:443 cloudflare.com:443

# 使用配置文件批量检查
./bin/cert-inspector -c config/hosts.conf

# 自定义警告阈值
./bin/cert-inspector -w 60 -crt 14 -c config/hosts.conf

# 设置连接超时
./bin/cert-inspector -t 5 github.com:443

# 启用 Webhook 通知
./bin/cert-inspector -W "https://hooks.slack.com/services/xxx" -c config/hosts.conf
```

## ⚙️ 配置

编辑 `config/hosts.conf`，每行一个 `host:port`，`#` 开头的行为注释：

```bash
# 格式: host:port

# 主要网站
github.com:443
google.com:443
cloudflare.com:443

# API 服务
api.github.com:443
api.stripe.com:443

# CDN
cdn.jsdelivr.net:443
unpkg.com:443

# 测试域名
# expired.badssl.com:443
# self-signed.badssl.com:443
```

## 📋 命令行选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| `-c`, `--config FILE` | 主机列表配置文件 | `./config/hosts.conf` |
| `-w`, `--warn DAYS` | 警告阈值（天） | `30` |
| `-crt`, `--critical DAYS` | 严重阈值（天） | `7` |
| `-t`, `--timeout SECS` | 连接超时（秒） | `10` |
| `-j`, `--json` | 输出 JSON 格式 | `false` |
| `-W`, `--webhook URL` | Webhook 通知地址 | `-` |
| `-h`, `--help` | 显示帮助 | - |

## 📊 输出示例

```
╔═══════════════════════════════════════════════════════╗
║      🔒  cert-inspector v1.0.0                         ║
║      SSL/TLS Certificate Inspector                     ║
╚═══════════════════════════════════════════════════════╝

  Warn threshold:     30 days
  Critical threshold: 7 days
  Timeout:           10 seconds
  Hosts:             1

🔍 Inspecting github.com:443 ... ✓

═══════════════════════════════════════════════════════
  github.com:443         [OK]
═══════════════════════════════════════════════════════
  ✓ Reachable        (252.00ms)
  TLS Version:   TLS 1.3
  Cipher Suite:  TLS_AES_128_GCM_SHA256

  ── Leaf Certificate ──
    Subject:       github.com
    Issuer:        Sectigo Public Server Authentication CA DV E36
    Valid From:    2026-03-06
    Valid Until:   2026-06-03 23:59 (62 days)
    Algorithm:     ECDSA-SHA256
    Serial:        39557711522153605937503944820825465427
    DNS Names:     github.com, www.github.com
    Fingerprint:   97:16:D3:94:41:CA:65:1C:51:BE:78:E9:...

  ── Root CA ──
    Subject:       Sectigo Public Server Authentication Root E46
    Issuer:        USERTrust ECC Certification Authority
    Valid Until:   2038-01-18 23:59 (4309 days)
    Algorithm:     ECDSA-SHA384

────────────────────────────────────────────────────────────
  📊  1 hosts    ✓ OK: 1  ⚠ WARN: 0  ✗ CRIT: 0  ✗ ERR: 0
────────────────────────────────────────────────────────────
```

## ⚠️ 告警状态说明

| 状态 | 颜色 | 含义 |
|------|------|------|
| `OK` | 🟢 绿 | 证书状态正常，距离过期天数 > 警告阈值 |
| `WARN` | 🟡 黄 | 证书在警告阈值内（30天）需关注 |
| `CRIT` | 🔴 红 | 证书在严重阈值内（7天）或已过期 |
| `ERROR` | 🔴 红 | 无法连接或证书解析失败 |

## 📁 项目结构

```
cert-inspector/
├── cmd/
│   └── cert-inspector/          # 主程序入口
│       └── main.go
├── config/
│   └── hosts.conf               # 主机列表配置
├── log/                         # 日志目录
│   └── .gitkeep
├── bin/                         # 编译输出目录
├── README.md
├── LICENSE
├── go.mod
└── .gitignore
```

## 🔧 技术细节

- **语言**: Go 1.21+
- **依赖**: 仅 Go 标准库（无外部依赖）
- **连接方式**: `crypto/tls.DialWithDialer` 底层 TCP 连接
- **指纹算法**: SHA-256 over DER-encoded certificate
- **TLS 版本**: 支持 TLS 1.0 / 1.1 / 1.2 / 1.3
- **超时控制**: `net.Dialer` 主动超时管理

## 📝 CHANGELOG

### v1.0.0 (2026-04-02)

- ✨ 初始版本发布
- 🔒 完整证书链分析（Leaf / Intermediate / Root CA）
- ⏱️ 可配置过期预警（Warn / Critical）
- 🔍 TLS 版本、加密套件、签名算法检查
- ⚠️ 弱签名 / 废弃 TLS 版本警告
- 🎨 彩色终端输出
- 🔔 Webhook 通知支持
- 📄 JSON 输出模式

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 👤 作者

Chen Su

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！
