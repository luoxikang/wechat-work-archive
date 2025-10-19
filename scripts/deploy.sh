#!/bin/bash

# 企业微信群聊天记录存档系统部署脚本
# Usage: ./scripts/deploy.sh [environment] [strategy]
# Examples:
#   ./scripts/deploy.sh staging rolling
#   ./scripts/deploy.sh production blue-green

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
企业微信群聊天记录存档系统部署脚本

Usage: $0 [ENVIRONMENT] [STRATEGY]

ENVIRONMENT:
    staging     部署到测试环境
    production  部署到生产环境 (默认)

STRATEGY:
    rolling     滚动更新 (默认)
    blue-green  蓝绿部署
    recreate    重新创建

Options:
    -h, --help          显示帮助信息
    -v, --verbose       详细输出
    -f, --force         强制部署（跳过检查）
    --skip-backup       跳过备份
    --skip-tests        跳过健康检查
    --dry-run           模拟运行

Examples:
    $0 staging rolling
    $0 production blue-green
    $0 --dry-run production
EOF
}

# 默认配置
ENVIRONMENT="production"
STRATEGY="rolling"
VERBOSE=false
FORCE=false
SKIP_BACKUP=false
SKIP_TESTS=false
DRY_RUN=false

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
        -f|--force)
            FORCE=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        staging|production)
            ENVIRONMENT=$1
            shift
            ;;
        rolling|blue-green|recreate)
            STRATEGY=$1
            shift
            ;;
        *)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
    esac
done

# 设置详细输出
if [ "$VERBOSE" = true ]; then
    set -x
fi

# 检查必要的命令
check_commands() {
    local commands=("docker" "docker-compose" "curl" "git")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd 命令未找到，请先安装"
            exit 1
        fi
    done
}

# 检查环境文件
check_environment() {
    local env_file=".env"
    if [ "$ENVIRONMENT" = "staging" ]; then
        env_file=".env.staging"
    fi

    if [ ! -f "$env_file" ]; then
        log_error "环境文件 $env_file 不存在"
        exit 1
    fi

    # 检查必要的环境变量
    local required_vars=("CORP_ID" "SECRET" "DB_PASSWORD")
    for var in "${required_vars[@]}"; do
        if ! grep -q "^$var=" "$env_file"; then
            log_error "环境变量 $var 未在 $env_file 中定义"
            exit 1
        fi
    done
}

# 健康检查
health_check() {
    local url="http://localhost:8000"
    if [ "$ENVIRONMENT" = "staging" ]; then
        url="http://localhost:8001"
    fi

    log_info "正在进行健康检查..."
    for i in {1..30}; do
        if curl -f "$url/health" > /dev/null 2>&1; then
            log_success "健康检查通过"
            return 0
        fi
        log_info "等待服务启动... ($i/30)"
        sleep 2
    done

    log_error "健康检查失败"
    return 1
}

# 备份数据库
backup_database() {
    if [ "$SKIP_BACKUP" = true ]; then
        log_warning "跳过数据库备份"
        return 0
    fi

    local backup_dir="./backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"

    log_info "正在备份数据库到 $backup_dir"

    if docker-compose ps | grep -q postgres; then
        docker-compose exec -T postgres pg_dump -U "${DB_USER:-wechat_admin}" "${DB_NAME:-wechat_archive}" > "$backup_dir/database.sql"
        log_success "数据库备份完成: $backup_dir/database.sql"
    else
        log_warning "PostgreSQL 容器未运行，跳过数据库备份"
    fi

    # 备份配置文件
    if [ -f "docker-compose.yml" ]; then
        cp "docker-compose.yml" "$backup_dir/"
    fi
    if [ -f ".env" ]; then
        cp ".env" "$backup_dir/"
    fi

    echo "$backup_dir" > .last_backup
    log_success "配置文件备份完成"
}

# 滚动更新部署
deploy_rolling() {
    log_info "开始滚动更新部署..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将执行滚动更新"
        return 0
    fi

    # 拉取最新镜像
    docker-compose pull

    # 滚动更新
    docker-compose up -d --no-deps --remove-orphans api worker

    # 等待服务就绪
    sleep 10

    # 更新其他服务
    docker-compose up -d

    log_success "滚动更新完成"
}

# 蓝绿部署
deploy_blue_green() {
    log_info "开始蓝绿部署..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将执行蓝绿部署"
        return 0
    fi

    # 拉取最新镜像
    docker-compose pull

    # 启动绿色环境（扩容）
    log_info "启动绿色环境..."
    docker-compose up -d --scale api=2 --scale worker=2 --no-recreate

    # 等待绿色环境就绪
    sleep 30

    # 检查绿色环境健康状态
    if ! health_check; then
        log_error "绿色环境健康检查失败，停止部署"
        return 1
    fi

    # 切换到绿色环境
    log_info "切换到绿色环境..."
    docker-compose up -d --remove-orphans

    log_success "蓝绿部署完成"
}

# 重新创建部署
deploy_recreate() {
    log_info "开始重新创建部署..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将执行重新创建部署"
        return 0
    fi

    # 停止所有服务
    docker-compose down --timeout 30

    # 拉取最新镜像
    docker-compose pull

    # 重新启动服务
    docker-compose up -d

    log_success "重新创建部署完成"
}

# 运行数据库迁移
run_migrations() {
    log_info "运行数据库迁移..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将运行数据库迁移"
        return 0
    fi

    # 等待数据库就绪
    sleep 5

    if docker-compose exec -T api alembic upgrade head; then
        log_success "数据库迁移完成"
    else
        log_error "数据库迁移失败"
        return 1
    fi
}

# 清理资源
cleanup() {
    log_info "清理未使用的资源..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将清理未使用的资源"
        return 0
    fi

    # 清理未使用的镜像
    docker image prune -f

    # 清理未使用的容器
    docker container prune -f

    # 清理未使用的网络
    docker network prune -f

    # 保持最近5个备份
    if [ -d "./backups" ]; then
        find ./backups -type d -name "20*" | sort -r | tail -n +6 | xargs rm -rf 2>/dev/null || true
    fi

    log_success "资源清理完成"
}

# 显示部署状态
show_status() {
    log_info "=== 部署状态 ==="
    docker-compose ps

    if [ "$SKIP_TESTS" = false ]; then
        health_check
    fi

    log_info "=== 日志预览 ==="
    docker-compose logs --tail=20 api

    log_success "部署状态检查完成"
}

# 主要部署函数
main() {
    log_info "开始部署 - 环境: $ENVIRONMENT, 策略: $STRATEGY"

    # 前置检查
    check_commands
    check_environment

    # 如果不是强制部署，进行额外检查
    if [ "$FORCE" = false ]; then
        # 检查是否有未提交的更改
        if [ -d ".git" ] && ! git diff --quiet; then
            log_warning "存在未提交的更改，建议先提交或使用 --force 参数"
            if [ "$DRY_RUN" = false ]; then
                read -p "是否继续部署? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_info "部署已取消"
                    exit 0
                fi
            fi
        fi
    fi

    # 切换到项目根目录
    cd "$(dirname "$0")/.."

    # 设置环境变量
    if [ "$ENVIRONMENT" = "staging" ]; then
        export COMPOSE_FILE="docker/docker-compose.dev.yml"
    else
        export COMPOSE_FILE="docker/docker-compose.yml"
    fi

    # 创建备份
    backup_database

    # 根据策略执行部署
    case $STRATEGY in
        rolling)
            deploy_rolling
            ;;
        blue-green)
            deploy_blue_green
            ;;
        recreate)
            deploy_recreate
            ;;
        *)
            log_error "未知的部署策略: $STRATEGY"
            exit 1
            ;;
    esac

    # 运行数据库迁移
    if ! run_migrations; then
        log_error "数据库迁移失败，开始回滚..."
        if [ -f ".last_backup" ]; then
            ./scripts/rollback.sh "$(cat .last_backup)"
        fi
        exit 1
    fi

    # 健康检查
    if [ "$SKIP_TESTS" = false ]; then
        if ! health_check; then
            log_error "健康检查失败，开始回滚..."
            if [ -f ".last_backup" ]; then
                ./scripts/rollback.sh "$(cat .last_backup)"
            fi
            exit 1
        fi
    fi

    # 清理资源
    cleanup

    # 显示状态
    show_status

    log_success "部署完成!"
    log_info "环境: $ENVIRONMENT"
    log_info "策略: $STRATEGY"

    if [ -f ".last_backup" ]; then
        log_info "备份位置: $(cat .last_backup)"
    fi
}

# 信号处理
trap 'log_error "部署被中断"; exit 130' INT TERM

# 执行主函数
main "$@"