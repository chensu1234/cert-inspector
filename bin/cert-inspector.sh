#!/bin/bash
#
# cert-inspector - SSL/TLS 证书检查与过期监控工具
# 检查证书链、过期时间、常见配置问题
# 作者: Chen Su
# 许可证: MIT
#

set -euo pipefail

# ========================
# OS 检测 (date 命令兼容性)
# ========================
IS_DARWIN=$([[ "$(uname -s)" == "Darwin" ]] && echo 1 || echo 0)

# ========================
# 颜色定义
# ========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ========================
# 默认配置
# ========================
CONFIG_FILE="${CONFIG_FILE:-./config/hosts.conf}"
LOG_FILE="${LOG_FILE:-./log/cert-inspector.log}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
ALERT_DAYS="${ALERT_DAYS:-30}"    # 提前多少天告警
CHECK_INTERVAL="${CHECK_INTERVAL:-1440}"  # 默认每天检查一次（分钟）
MODE="${MODE:-check}"   # check | monitor
TIMEOUT="${TIMEOUT:-10}"

# ========================
# 全局状态
# ========================
total_checks=0
expired_count=0
expiring_count=0
ok_count=0

# ========================
# 帮助信息
# ========================
show_help() {
    cat << EOF
${BOLD}cert-inspector${NC} - SSL/TLS 证书检查与过期监控工具

${BOLD}用法:${NC}  $(basename "$0") [选项]

${BOLD}选项:${NC}
    -c, --config FILE     配置文件路径 (默认: ./config/hosts.conf)
    -o, --output FILE     日志输出文件 (默认: ./log/cert-inspector.log)
    -d, --days DAYS       提前告警天数 (默认: 30)
    -w, --webhook URL     Slack/飞书 Webhook URL
    -i, --interval MIN    监控模式检测间隔(分钟，默认1440)
    -m, --mode MODE       运行模式: check(单次) | monitor(持续监控，默认check)
    -t, --timeout SEC     连接超时秒数 (默认: 10)
    -h, --help            显示帮助信息
    -v, --version         显示版本信息

${BOLD}示例:${NC}
    $(basename "$0") -c /etc/cert-inspector.conf
    $(basename "$0") -w "https://hooks.slack.com/services/xxx" -d 14
    $(basename "$0") -m monitor -i 60 -w "https://open.feishu.cn/..."

${BOLD}配置文件格式:${NC} (config/hosts.conf)
    # 每行一个主机，格式: host:port 或 host (默认443)
    example.com
    api.example.com:8443
    # 注释以 # 开头

EOF
}

show_version() {
    echo "cert-inspector v1.0.0"
}

# ========================
# 日志函数
# ========================
log() {
    local level="$1"
    shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo -e "$msg" >> "$LOG_FILE"
    echo -e "$msg"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "${YELLOW}WARN${NC}" "$@"; }
log_error() { log "${RED}ERROR${NC}" "$@"; }
log_ok()    { log "${GREEN} OK ${NC}" "$@"; }

# ========================
# 解析配置文件
# ========================
parse_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi

    local hosts=()
    while IFS= read -r line; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        # 跳过纯空白行
        local stripped
        stripped=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$stripped" ]] && continue
        # 去除首尾空白
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        hosts+=("$line")
    done < "$CONFIG_FILE"

    printf '%s\n' "${hosts[@]}"
}

# ========================
# 解析 host:port
# ========================
parse_host_port() {
    local entry="$1"
    local host port

    if [[ "$entry" =~ ^([^:]+):([0-9]+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        port="${BASH_REMATCH[2]}"
    else
        host="$entry"
        port="443"
    fi

    echo "$host:$port"
}

# ========================
# 获取证书信息 (使用 openssl)
# ========================
get_cert_info() {
    local host="$1"
    local port="$2"
    local info

    # -servername 用于 SNI
    # -showcert   显示证书信息
    # openssl s_client 输出去 stderr，需要重定向
    info=$(echo | openssl s_client -connect "${host}:${port}" \
        -servername "$host" \
        -timeout "$TIMEOUT" \
        2>/dev/null | openssl x509 -noout -subject -issuer -dates -serial 2>/dev/null) || return 1

    echo "$info"
}

# ========================
# 解析证书日期
# ========================
parse_cert_dates() {
    local cert_info="$1"
    local not_before not_after

    not_before=$(echo "$cert_info" | grep 'Not Before:' | sed 's/.*Not Before://')
    not_after=$(echo "$cert_info" | grep 'Not After:' | sed 's/.*Not After://')

    echo "$not_before|$not_after"
}

# ========================
# 计算天数差异
# ========================
days_until() {
    local date_str="$1"
    # 转换日期格式: "Mar 25 12:00:00 2026 GMT"
    local target_ts
    if [[ "$IS_DARWIN" == "1" ]]; then
        # macOS
        target_ts=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$date_str" +%s 2>/dev/null) || return 1
    else
        # Linux (GNU date)
        target_ts=$(date -d "$date_str" +%s 2>/dev/null) || return 1
    fi
    local now_ts
    now_ts=$(date +%s)
    echo $(( (target_ts - now_ts) / 86400 ))
}

# ========================
# 格式化日期
# ========================
format_date() {
    local date_str="$1"
    if [[ "$IS_DARWIN" == "1" ]]; then
        # macOS
        date -j -f "%b %d %H:%M:%S %Y %Z" "$date_str" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || echo "$date_str"
    else
        # Linux (GNU date)
        date -d "$date_str" "+%Y-%m-%d %H:%M:%S %Z" 2>/dev/null || echo "$date_str"
    fi
}

# ========================
# 获取证书主体
# ========================
get_cert_subject() {
    local cert_info="$1"
    echo "$cert_info" | grep 'subject=' | sed 's/.*subject=//'
}

# ========================
# 获取证书颁发者
# ========================
get_cert_issuer() {
    local cert_info="$1"
    echo "$cert_info" | grep 'issuer=' | sed 's/.*issuer=//'
}

# ========================
# 发送通知
# ========================
send_notification() {
    local message="$1"
    local color="${2:-good}"  # good | warning | danger

    if [[ -z "$WEBHOOK_URL" ]]; then
        return
    fi

    # Slack 格式
    if [[ "$WEBHOOK_URL" == *"slack.com"* ]]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"attachments\":[{\"color\":\"$color\",\"text\":\"$message\"}]}" \
            > /dev/null 2>&1 || true
    # 飞书格式
    elif [[ "$WEBHOOK_URL" == *"feishu"* ]]; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H 'Content-Type: application/json' \
            -d "{\"msg_type\":\"text\",\"content\":{\"text\":\"$message\"}}" \
            > /dev/null 2>&1 || true
    fi
}

# ========================
# 检查单个主机
# ========================
check_host() {
    local entry="$1"
    local host port cert_info subject issuer dates not_before not_after
    local days_left color status_icon

    host_port=$(parse_host_port "$entry")
    host="${host_port%:*}"
    port="${host_port#*:}"

    ((total_checks++))

    printf "  ${CYAN}%-40s${NC} " "$entry"

    # 获取证书信息
    cert_info=$(get_cert_info "$host" "$port" 2>/dev/null) || {
        echo -e "${RED}✗ 连接失败${NC}"
        log_error "无法连接 $entry"
        send_notification "❌ cert-inspector: 无法连接 $entry" "danger"
        return 1
    }

    if [[ -z "$cert_info" ]]; then
        echo -e "${RED}✗ 无证书${NC}"
        log_error "$entry 无有效证书"
        return 1
    fi

    subject=$(get_cert_subject "$cert_info")
    issuer=$(get_cert_issuer "$cert_info")
    dates=$(parse_cert_dates "$cert_info")
    not_before="${dates%%|*}"
    not_after="${dates##*|}"

    # 计算剩余天数
    days_left=$(days_until "$not_after") || days_left=-999

    # 判断状态
    if [[ "$days_left" -lt 0 ]]; then
        status_icon="${RED}✗ 已过期${NC}"
        color="danger"
        ((expired_count++))
        status="EXPIRED"
    elif [[ "$days_left" -le "$ALERT_DAYS" ]]; then
        status_icon="${YELLOW}⚠ 即将过期${NC}"
        color="warning"
        ((expiring_count++))
        status="EXPIRING"
    else
        status_icon="${GREEN}✓ 正常${NC}"
        color="good"
        ((ok_count++))
        status="OK"
    fi

    echo -e "$status_icon  ${days_left}天后过期  ($not_after)"

    # 记录到日志
    log_info "检查 $entry: $status, 剩余${days_left}天, 过期: $not_after"

    # 详细日志
    log_info "  Subject: $subject"
    log_info "  Issuer:  $issuer"

    # 发送告警
    if [[ "$status" != "OK" ]]; then
        local msg="🔔 cert-inspector: *$entry* 证书 $status ($(if [[ "$days_left" -lt 0 ]]; then echo "已过期 $((0 - days_left)) 天"; else echo "剩余 $days_left 天"; fi))"
        send_notification "$msg" "$color"
    fi

    return 0
}

# ========================
# 打印头部
# ========================
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "${BOLD}${BLUE}     cert-inspector v1.0.0${NC}"
    echo -e "${BOLD}${BLUE}  SSL/TLS 证书检查与过期监控工具${NC}"
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo ""
    echo -e "  ${BOLD}检查时间:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "  ${BOLD}告警阈值:${NC} ${ALERT_DAYS} 天"
    echo -e "  ${BOLD}超时时间:${NC} ${TIMEOUT} 秒"
    echo ""
}

# ========================
# 打印摘要
# ========================
print_summary() {
    echo ""
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "${BOLD}  检查摘要${NC}"
    echo -e "${BOLD}${BLUE}========================================${NC}"
    echo -e "  总计检查: ${total_checks}"
    echo -e "  ${GREEN}✓ 正常:    ${ok_count}${NC}"
    echo -e "  ${YELLOW}⚠ 即将过期: ${expiring_count}${NC}"
    echo -e "  ${RED}✗ 已过期:   ${expired_count}${NC}"
    echo ""

    if [[ "$((expired_count + expiring_count))" -gt 0 ]]; then
        echo -e "${YELLOW}⚠ 共有 $((expired_count + expiring_count)) 个证书需要关注${NC}"
    else
        echo -e "${GREEN}✓ 所有证书状态正常${NC}"
    fi
    echo ""
}

# ========================
# 清理旧日志 (保留30天)
# ========================
cleanup_logs() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ -d "$log_dir" ]]; then
        # 保留最近7天的日志
        find "$log_dir" -name "cert-inspector*.log" -mtime +7 -delete 2>/dev/null || true
    fi
}

# ========================
# 主函数
# ========================
main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -o|--output)
                LOG_FILE="$2"
                shift 2
                ;;
            -d|--days)
                ALERT_DAYS="$2"
                shift 2
                ;;
            -w|--webhook)
                WEBHOOK_URL="$2"
                shift 2
                ;;
            -i|--interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            -m|--mode)
                MODE="$2"
                shift 2
                ;;
            -t|--timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            *)
                echo -e "${RED}未知选项: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done

    # 确保目录存在
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$(dirname "$CONFIG_FILE")"

    # 单次检查模式
    if [[ "$MODE" == "check" ]]; then
        log_info "========== 开始证书检查 =========="
        log_info "配置文件: $CONFIG_FILE"
        log_info "告警阈值: ${ALERT_DAYS} 天"

        print_header

        # 读取所有主机 (bash 3.x 兼容写法)
        hosts=()
        while IFS= read -r line; do
            hosts+=("$line")
        done < <(parse_config)

        if [[ ${#hosts[@]} -eq 0 ]]; then
            log_error "配置文件中没有有效的主机"
            echo -e "${RED}错误: 配置文件中没有有效的主机${NC}"
            exit 1
        fi

        echo -e "  ${BOLD}正在检查 ${#hosts[@]} 个主机...${NC}"
        echo ""

        for entry in "${hosts[@]}"; do
            check_host "$entry" || true
        done

        print_summary
        log_info "========== 检查完成 =========="

        # 清理旧日志
        cleanup_logs

        # 非0退出码表示有问题
        [[ "$expired_count" -gt 0 ]] && exit 2
        [[ "$expiring_count" -gt 0 ]] && exit 1
        exit 0

    # 持续监控模式
    elif [[ "$MODE" == "monitor" ]]; then
        log_info "========== 启动证书监控 =========="
        log_info "检查间隔: ${CHECK_INTERVAL} 分钟"

        while true; do
            total_checks=0
            expired_count=0
            expiring_count=0
            ok_count=0

            print_header

            hosts=()
            while IFS= read -r line; do
                hosts+=("$line")
            done < <(parse_config)

            for entry in "${hosts[@]}"; do
                check_host "$entry" || true
            done

            print_summary
            log_info "下次检查: ${CHECK_INTERVAL} 分钟后"

            sleep $((CHECK_INTERVAL * 60))
        done
    fi
}

main "$@"
