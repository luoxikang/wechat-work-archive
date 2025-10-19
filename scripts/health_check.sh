#!/bin/bash

# 企业微信群聊天记录存档系统健康检查脚本
# Usage: ./scripts/health_check.sh [options]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示使用帮助
show_help() {
    cat << EOF
企业微信群聊天记录存档系统健康检查脚本

Usage: $0 [OPTIONS]

Options:
    -h, --help              显示帮助信息
    -v, --verbose           详细输出
    -q, --quiet             静默模式
    -u, --url URL           指定API基础URL (默认: http://localhost:8000)
    -t, --timeout SECONDS   请求超时时间 (默认: 10秒)
    --nagios               Nagios监控格式输出
    --json                 JSON格式输出
    --check-all            检查所有组件
    --check-api            仅检查API服务
    --check-db             仅检查数据库
    --check-redis          仅检查Redis
    --check-workers        仅检查后台任务
    --check-external       检查外部依赖

Examples:
    $0                          # 基本健康检查
    $0 --check-all             # 完整健康检查
    $0 --url http://prod:8000  # 检查生产环境
    $0 --nagios                # Nagios监控输出
EOF
}

# 默认配置
API_URL="http://localhost:8000"
TIMEOUT=10
VERBOSE=false
QUIET=false
NAGIOS_MODE=false
JSON_MODE=false
CHECK_ALL=false
CHECK_API=true
CHECK_DB=false
CHECK_REDIS=false
CHECK_WORKERS=false
CHECK_EXTERNAL=false

# 健康状态
OVERALL_STATUS="OK"
HEALTH_ISSUES=()
HEALTH_DETAILS=()

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -u|--url)
            API_URL="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --nagios)
            NAGIOS_MODE=true
            QUIET=true
            shift
            ;;
        --json)
            JSON_MODE=true
            QUIET=true
            shift
            ;;
        --check-all)
            CHECK_ALL=true
            CHECK_API=true
            CHECK_DB=true
            CHECK_REDIS=true
            CHECK_WORKERS=true
            CHECK_EXTERNAL=true
            shift
            ;;
        --check-api)
            CHECK_API=true
            shift
            ;;
        --check-db)
            CHECK_DB=true
            shift
            ;;
        --check-redis)
            CHECK_REDIS=true
            shift
            ;;
        --check-workers)
            CHECK_WORKERS=true
            shift
            ;;
        --check-external)
            CHECK_EXTERNAL=true
            shift
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 切换到项目根目录
cd "$(dirname "$0")/.."

# 记录健康问题
add_health_issue() {
    local component="$1"
    local message="$2"
    local severity="$3"  # OK, WARNING, CRITICAL

    HEALTH_ISSUES+=("$component: $message")
    HEALTH_DETAILS+=("{\"component\": \"$component\", \"message\": \"$message\", \"severity\": \"$severity\"}")

    if [ "$severity" = "CRITICAL" ]; then
        OVERALL_STATUS="CRITICAL"
    elif [ "$severity" = "WARNING" ] && [ "$OVERALL_STATUS" = "OK" ]; then
        OVERALL_STATUS="WARNING"
    fi
}

# 记录健康成功
add_health_success() {
    local component="$1"
    local message="$2"

    HEALTH_DETAILS+=("{\"component\": \"$component\", \"message\": \"$message\", \"severity\": \"OK\"}")
}

# 日志输出（根据模式）
health_log() {
    local level="$1"
    local message="$2"

    if [ "$QUIET" = false ]; then
        case $level in
            info) log_info "$message" ;;
            success) log_success "$message" ;;
            warning) log_warning "$message" ;;
            error) log_error "$message" ;;
        esac
    fi
}

# 检查命令是否存在
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        add_health_issue "system" "$cmd 命令不存在" "CRITICAL"
        return 1
    fi
    return 0
}

# API健康检查
check_api_health() {
    health_log "info" "检查API服务..."

    # 检查基本连通性
    if ! curl -f -s --max-time "$TIMEOUT" "$API_URL/health" > /dev/null 2>&1; then
        add_health_issue "api" "API服务无响应" "CRITICAL"
        return 1
    fi

    # 获取详细健康信息
    local health_response
    health_response=$(curl -s --max-time "$TIMEOUT" "$API_URL/health" 2>/dev/null)

    if [ $? -eq 0 ]; then
        # 检查响应内容
        if echo "$health_response" | grep -q '"status".*"healthy"'; then
            add_health_success "api" "API服务运行正常"
            health_log "success" "API服务健康"

            # 检查API响应时间
            local response_time
            response_time=$(curl -o /dev/null -s -w "%{time_total}" --max-time "$TIMEOUT" "$API_URL/health")
            if (( $(echo "$response_time > 2.0" | bc -l) )); then
                add_health_issue "api" "API响应时间过长: ${response_time}s" "WARNING"
            fi

        else
            add_health_issue "api" "API服务状态异常" "WARNING"
        fi
    else
        add_health_issue "api" "无法获取API健康状态" "CRITICAL"
        return 1
    fi

    # 检查API端点
    local endpoints=("/api/v1/groups" "/metrics")
    for endpoint in "${endpoints[@]}"; do
        if curl -f -s --max-time "$TIMEOUT" "$API_URL$endpoint" > /dev/null 2>&1; then
            health_log "info" "端点 $endpoint 正常"
        else
            add_health_issue "api" "端点 $endpoint 无响应" "WARNING"
        fi
    done

    return 0
}

# 数据库健康检查
check_database_health() {
    health_log "info" "检查数据库连接..."

    if ! check_command "docker-compose"; then
        return 1
    fi

    # 检查PostgreSQL容器状态
    if ! docker-compose ps postgres | grep -q "Up"; then
        add_health_issue "database" "PostgreSQL容器未运行" "CRITICAL"
        return 1
    fi

    # 检查数据库连接
    if docker-compose exec -T postgres pg_isready > /dev/null 2>&1; then
        add_health_success "database" "数据库连接正常"
        health_log "success" "数据库连接正常"
    else
        add_health_issue "database" "数据库连接失败" "CRITICAL"
        return 1
    fi

    # 检查数据库性能
    local db_user="${DB_USER:-wechat_admin}"
    local db_name="${DB_NAME:-wechat_archive}"

    # 检查连接数
    local connections
    connections=$(docker-compose exec -T postgres psql -U "$db_user" -d "$db_name" -t -c "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | xargs)

    if [ -n "$connections" ]; then
        if [ "$connections" -gt 80 ]; then
            add_health_issue "database" "数据库连接数过高: $connections" "WARNING"
        else
            health_log "info" "数据库连接数: $connections"
        fi
    fi

    # 检查数据库大小
    local db_size
    db_size=$(docker-compose exec -T postgres psql -U "$db_user" -d "$db_name" -t -c "SELECT pg_size_pretty(pg_database_size('$db_name'));" 2>/dev/null | xargs)

    if [ -n "$db_size" ]; then
        health_log "info" "数据库大小: $db_size"
    fi

    return 0
}

# Redis健康检查
check_redis_health() {
    health_log "info" "检查Redis服务..."

    if ! check_command "docker-compose"; then
        return 1
    fi

    # 检查Redis容器状态
    if ! docker-compose ps redis | grep -q "Up"; then
        add_health_issue "redis" "Redis容器未运行" "CRITICAL"
        return 1
    fi

    # 检查Redis连接
    if docker-compose exec -T redis redis-cli ping | grep -q "PONG"; then
        add_health_success "redis" "Redis服务正常"
        health_log "success" "Redis连接正常"
    else
        add_health_issue "redis" "Redis连接失败" "CRITICAL"
        return 1
    fi

    # 检查Redis内存使用
    local memory_info
    memory_info=$(docker-compose exec -T redis redis-cli info memory 2>/dev/null | grep "used_memory_human" | cut -d: -f2 | tr -d '\r')

    if [ -n "$memory_info" ]; then
        health_log "info" "Redis内存使用: $memory_info"
    fi

    # 检查连接的客户端数量
    local connected_clients
    connected_clients=$(docker-compose exec -T redis redis-cli info clients 2>/dev/null | grep "connected_clients" | cut -d: -f2 | tr -d '\r')

    if [ -n "$connected_clients" ] && [ "$connected_clients" -gt 100 ]; then
        add_health_issue "redis" "Redis客户端连接数过高: $connected_clients" "WARNING"
    fi

    return 0
}

# 检查后台任务
check_workers_health() {
    health_log "info" "检查后台任务..."

    if ! check_command "docker-compose"; then
        return 1
    fi

    # 检查Celery Worker
    if docker-compose ps worker | grep -q "Up"; then
        add_health_success "workers" "Worker服务运行正常"
        health_log "success" "Worker服务正常"

        # 检查Worker状态
        local worker_status
        worker_status=$(docker-compose exec -T worker celery -A src.tasks inspect active 2>/dev/null || echo "error")

        if [ "$worker_status" = "error" ]; then
            add_health_issue "workers" "无法获取Worker状态" "WARNING"
        fi
    else
        add_health_issue "workers" "Worker服务未运行" "CRITICAL"
    fi

    # 检查Celery Beat (调度器)
    if docker-compose ps scheduler | grep -q "Up"; then
        add_health_success "scheduler" "调度器服务运行正常"
        health_log "success" "调度器服务正常"
    else
        add_health_issue "scheduler" "调度器服务未运行" "CRITICAL"
    fi

    return 0
}

# 检查外部依赖
check_external_dependencies() {
    health_log "info" "检查外部依赖..."

    # 检查企业微信API连通性
    local wechat_api_url="https://qyapi.weixin.qq.com"
    if curl -f -s --max-time "$TIMEOUT" "$wechat_api_url" > /dev/null 2>&1; then
        add_health_success "wechat_api" "企业微信API可访问"
        health_log "success" "企业微信API连通正常"
    else
        add_health_issue "wechat_api" "企业微信API无法访问" "WARNING"
    fi

    # 检查DNS解析
    if nslookup qyapi.weixin.qq.com > /dev/null 2>&1; then
        health_log "info" "DNS解析正常"
    else
        add_health_issue "dns" "DNS解析异常" "WARNING"
    fi

    return 0
}

# 检查系统资源
check_system_resources() {
    health_log "info" "检查系统资源..."

    # 检查磁盘空间
    local disk_usage
    disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')

    if [ "$disk_usage" -gt 90 ]; then
        add_health_issue "system" "磁盘空间不足: ${disk_usage}%" "CRITICAL"
    elif [ "$disk_usage" -gt 80 ]; then
        add_health_issue "system" "磁盘空间紧张: ${disk_usage}%" "WARNING"
    else
        health_log "info" "磁盘使用率: ${disk_usage}%"
    fi

    # 检查内存使用
    if command -v free &> /dev/null; then
        local memory_usage
        memory_usage=$(free | awk '/^Mem/ {printf "%.1f", $3/$2 * 100}')

        if (( $(echo "$memory_usage > 90" | bc -l) )); then
            add_health_issue "system" "内存使用率过高: ${memory_usage}%" "WARNING"
        else
            health_log "info" "内存使用率: ${memory_usage}%"
        fi
    fi

    # 检查负载
    if command -v uptime &> /dev/null; then
        local load_avg
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')

        if (( $(echo "$load_avg > 4.0" | bc -l) )); then
            add_health_issue "system" "系统负载过高: $load_avg" "WARNING"
        else
            health_log "info" "系统负载: $load_avg"
        fi
    fi

    return 0
}

# 生成Nagios输出
generate_nagios_output() {
    local exit_code=0

    case $OVERALL_STATUS in
        "OK")
            echo "OK - 所有服务运行正常"
            exit_code=0
            ;;
        "WARNING")
            echo "WARNING - 检测到警告: ${HEALTH_ISSUES[*]}"
            exit_code=1
            ;;
        "CRITICAL")
            echo "CRITICAL - 检测到严重问题: ${HEALTH_ISSUES[*]}"
            exit_code=2
            ;;
    esac

    exit $exit_code
}

# 生成JSON输出
generate_json_output() {
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

    cat << EOF
{
    "timestamp": "$timestamp",
    "overall_status": "$OVERALL_STATUS",
    "api_url": "$API_URL",
    "checks": [
        $(IFS=,; echo "${HEALTH_DETAILS[*]}")
    ],
    "issues": [
        $(printf '"%s",' "${HEALTH_ISSUES[@]}" | sed 's/,$//')
    ]
}
EOF
}

# 显示健康报告
show_health_report() {
    if [ "$NAGIOS_MODE" = true ]; then
        generate_nagios_output
        return
    fi

    if [ "$JSON_MODE" = true ]; then
        generate_json_output
        return
    fi

    echo
    echo "=== 健康检查报告 ==="
    echo "检查时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "API地址: $API_URL"
    echo "总体状态: $OVERALL_STATUS"
    echo

    if [ ${#HEALTH_ISSUES[@]} -eq 0 ]; then
        log_success "所有检查项目都正常！"
    else
        log_warning "发现以下问题:"
        for issue in "${HEALTH_ISSUES[@]}"; do
            echo "  - $issue"
        done
    fi

    echo
}

# 主要检查函数
main() {
    health_log "info" "开始系统健康检查..."

    # 检查系统资源
    check_system_resources

    # 根据参数执行对应检查
    if [ "$CHECK_API" = true ]; then
        check_api_health
    fi

    if [ "$CHECK_DB" = true ]; then
        check_database_health
    fi

    if [ "$CHECK_REDIS" = true ]; then
        check_redis_health
    fi

    if [ "$CHECK_WORKERS" = true ]; then
        check_workers_health
    fi

    if [ "$CHECK_EXTERNAL" = true ]; then
        check_external_dependencies
    fi

    # 显示健康报告
    show_health_report

    # 根据整体状态设置退出码
    case $OVERALL_STATUS in
        "OK") exit 0 ;;
        "WARNING") exit 1 ;;
        "CRITICAL") exit 2 ;;
    esac
}

# 检查bc命令（用于浮点数比较）
if ! command -v bc &> /dev/null; then
    # 如果没有bc，定义简单的浮点数比较函数
    bc() {
        awk "BEGIN {print ($1)}"
    }
fi

# 执行主函数
main "$@"