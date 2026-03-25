# cert-inspector 🔐

> SSL/TLS 证书检查与过期监控工具

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![OpenSSL](https://img.shields.io/badge/OpenSSL-Required-blue.svg)](https://www.openssl.org/)

自动检查 SSL/TLS 证书过期时间，支持 Slack / 飞书 Webhook 告警，守护进程模式持续监控。

## ✨ 特性

- 🚀 **轻量级** — 纯 Bash 脚本，仅依赖 OpenSSL
- 📅 **过期监控** — 自动检测即将过期的证书，支持自定义告警阈值
- 🔗 **SNI 支持** — 支持多域名共享 IP 的证书检查
- 📢 **多平台通知** — 支持 Slack、飞书 Webhook 告警
- 🖥️ **守护模式** — 支持持续监控，定时检测
- 📝 **详细日志** — 完整的检查记录和状态变更日志
- 🔧 **灵活配置** — 支持配置文件和命令行参数双重配置

## 🏃 快速开始

### 安装

```bash
# 克隆项目
git clone https://github.com/chensu1234/cert-inspector.git
cd cert-inspector

# 添加执行权限
chmod +x bin/cert-inspector.sh
```

### 使用

```bash
# 使用默认配置 (config/hosts.conf) 单次检查
./bin/cert-inspector.sh

# 指定配置文件
./bin/cert-inspector.sh -c /path/to/hosts.conf

# 设置 14 天告警阈值
./bin/cert-inspector.sh -d 14

# 启用 Slack 通知
./bin/cert-inspector.sh -w "https://hooks.slack.com/services/xxx"

# 启用飞书通知
./bin/cert-inspector.sh -w "https://open.feishu.cn/..."

# 守护模式：每 60 分钟检查一次
./bin/cert-inspector.sh -m monitor -i 60 -w "https://hooks.slack.com/..."
```

### 依赖

```bash
# macOS
brew install openssl

# Ubuntu/Debian
sudo apt install openssl

# CentOS/RHEL
sudo yum install openssl
```

## ⚙️ 配置

编辑 `config/hosts.conf` 文件：

```bash
# 格式: host 或 host:port
# 注释以 # 开头

# 常用网站
google.com
github.com

# 指定端口
api.example.com:8443
internal.example.com:4433

# 支持 SNI 的虚拟主机
secure.example.com:443
```

## 📋 命令行选项

| 选项 | 说明 | 默认值 |
|------|------|--------|
| -c, --config FILE | 配置文件路径 | ./config/hosts.conf |
| -o, --output FILE | 日志输出文件 | ./log/cert-inspector.log |
| -d, --days DAYS | 提前告警天数 | 30 |
| -w, --webhook URL | Webhook 通知 URL | - |
| -i, --interval MIN | 监控模式检测间隔(分钟) | 1440 |
| -m, --mode MODE | 运行模式: check/monitor | check |
| -t, --timeout SEC | 连接超时秒数 | 10 |
| -h, --help | 显示帮助信息 | - |
| -v, --version | 显示版本信息 | - |

## 📁 项目结构

```
cert-inspector/
├── bin/
│   └── cert-inspector.sh      # 主脚本
├── config/
│   └── hosts.conf             # 主机配置
├── log/                       # 日志目录
│   └── .gitkeep
├── README.md
└── LICENSE
```

## 🔔 通知集成

### Slack

```bash
./bin/cert-inspector.sh -w "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### 飞书

```bash
./bin/cert-inspector.sh -w "https://open.feishu.cn/..."
```

## 📝 日志说明

日志默认保存在 `./log/cert-inspector.log`，包含：

- 每次检查的时间戳
- 证书主体信息 (Subject)
- 证书颁发者 (Issuer)
- 过期日期和剩余天数
- 告警通知发送记录
- 旧日志（超过 7 天）自动清理

## 🏗️ 扩展

- [ ] 添加邮件通知支持
- [ ] 添加企业微信通知
- [ ] 添加 Prometheus 指标导出
- [ ] 添加 CSV/JSON 报告导出
- [ ] 添加证书链完整性检查
- [ ] 添加 Web 界面

## 📄 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 👤 作者

Chen Su

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！
