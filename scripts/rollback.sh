#!/bin/bash

# 企业微信群聊天记录存档系统回滚脚本
# Usage: ./scripts/rollback.sh [backup_directory]

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
企业微信群聊天记录存档系统回滚脚本

Usage: $0 [BACKUP_DIRECTORY]

BACKUP_DIRECTORY:
    指定要回滚到的备份目录路径
    如果不提供，将自动选择最新的备份

Options:
    -h, --help          显示帮助信息
    -v, --verbose       详细输出
    -f, --force         强制回滚（跳过确认）
    --list-backups      列出所有可用备份
    --dry-run           模拟运行

Examples:
    $0                                    # 回滚到最新备份
    $0 ./backups/20240101_120000         # 回滚到指定备份
    $0 --list-backups                    # 列出所有备份
EOF
}

# 默认配置
BACKUP_DIR=""
VERBOSE=false
FORCE=false
DRY_RUN=false
LIST_BACKUPS=false

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
        --list-backups)
            LIST_BACKUPS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -*)
            log_error "未知参数: $1"
            show_help
            exit 1
            ;;
        *)
            BACKUP_DIR="$1"
            shift
            ;;
    esac
done

# 设置详细输出
if [ "$VERBOSE" = true ]; then
    set -x
fi

# 切换到项目根目录
cd "$(dirname "$0")/.."

# 列出所有备份
list_backups() {
    log_info "可用的备份:"

    if [ ! -d "./backups" ]; then
        log_warning "备份目录不存在"
        return 1
    fi

    local count=0
    for backup in ./backups/*/; do
        if [ -d "$backup" ]; then
            local backup_name=$(basename "$backup")
            local backup_date=$(echo "$backup_name" | sed 's/_/ /')
            local size=$(du -sh "$backup" 2>/dev/null | cut -f1)

            echo "  $backup_name (大小: $size)"

            # 显示备份内容
            if [ -f "$backup/docker-compose.yml" ]; then
                echo "    ✓ Docker Compose 配置"
            fi
            if [ -f "$backup/.env" ]; then
                echo "    ✓ 环境变量配置"
            fi
            if [ -f "$backup/database.sql" ]; then
                echo "    ✓ 数据库备份"
            fi

            count=$((count + 1))
        fi
    done

    if [ $count -eq 0 ]; then
        log_warning "没有找到可用的备份"
        return 1
    fi

    log_info "总共找到 $count 个备份"
}

# 如果只是列出备份，执行后退出
if [ "$LIST_BACKUPS" = true ]; then
    list_backups
    exit 0
fi

# 查找最新备份
find_latest_backup() {
    if [ ! -d "./backups" ]; then
        log_error "备份目录不存在"
        return 1
    fi

    local latest=""
    for backup in ./backups/*/; do
        if [ -d "$backup" ]; then
            latest="$backup"
        fi
    done

    if [ -z "$latest" ]; then
        log_error "没有找到可用的备份"
        return 1
    fi

    echo "${latest%/}"  # 移除末尾的斜杠
}

# 验证备份目录
validate_backup() {
    local backup_path="$1"

    if [ ! -d "$backup_path" ]; then
        log_error "备份目录不存在: $backup_path"
        return 1
    fi

    log_info "验证备份目录: $backup_path"

    # 检查必要的文件
    local required_files=("docker-compose.yml")
    local optional_files=(".env" "database.sql")

    for file in "${required_files[@]}"; do
        if [ ! -f "$backup_path/$file" ]; then
            log_error "必需文件不存在: $backup_path/$file"
            return 1
        fi
    done

    for file in "${optional_files[@]}"; do
        if [ -f "$backup_path/$file" ]; then
            log_info "找到可选文件: $file"
        else
            log_warning "可选文件不存在: $file"
        fi
    done

    log_success "备份验证通过"
    return 0
}

# 停止当前服务
stop_services() {
    log_info "停止当前服务..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将停止所有服务"
        return 0
    fi

    if docker-compose ps -q | grep -q .; then
        docker-compose down --timeout 30
        log_success "服务已停止"
    else
        log_info "没有运行中的服务"
    fi
}

# 恢复配置文件
restore_configs() {
    local backup_path="$1"

    log_info "恢复配置文件..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将恢复配置文件从 $backup_path"
        return 0
    fi

    # 备份当前配置（以防回滚失败）
    local current_backup="./rollback_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$current_backup"

    if [ -f "docker-compose.yml" ]; then
        cp "docker-compose.yml" "$current_backup/"
        log_info "已备份当前 docker-compose.yml"
    fi

    if [ -f ".env" ]; then
        cp ".env" "$current_backup/"
        log_info "已备份当前 .env"
    fi

    # 恢复配置文件
    if [ -f "$backup_path/docker-compose.yml" ]; then
        cp "$backup_path/docker-compose.yml" ./
        log_success "恢复 docker-compose.yml"
    fi

    if [ -f "$backup_path/.env" ]; then
        cp "$backup_path/.env" ./
        log_success "恢复 .env"
    fi

    echo "$current_backup" > .rollback_backup
}

# 恢复数据库
restore_database() {
    local backup_path="$1"

    if [ ! -f "$backup_path/database.sql" ]; then
        log_warning "数据库备份文件不存在，跳过数据库恢复"
        return 0
    fi

    log_info "恢复数据库..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将恢复数据库从 $backup_path/database.sql"
        return 0
    fi

    # 启动 PostgreSQL 服务
    docker-compose up -d postgres
    log_info "等待 PostgreSQL 启动..."
    sleep 30

    # 检查 PostgreSQL 是否就绪
    for i in {1..30}; do
        if docker-compose exec -T postgres pg_isready; then
            log_success "PostgreSQL 已就绪"
            break
        fi
        if [ $i -eq 30 ]; then
            log_error "PostgreSQL 启动超时"
            return 1
        fi
        sleep 2
    done

    # 恢复数据库
    log_info "正在恢复数据库..."
    if docker-compose exec -T postgres psql -U "${DB_USER:-wechat_admin}" "${DB_NAME:-wechat_archive}" < "$backup_path/database.sql"; then
        log_success "数据库恢复完成"
    else
        log_error "数据库恢复失败"
        return 1
    fi
}

# 启动服务
start_services() {
    log_info "启动服务..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将启动所有服务"
        return 0
    fi

    docker-compose up -d

    log_info "等待服务启动..."
    sleep 30

    # 健康检查
    for i in {1..30}; do
        if curl -f http://localhost:8000/health > /dev/null 2>&1; then
            log_success "服务健康检查通过"
            return 0
        fi
        log_info "等待服务就绪... ($i/30)"
        sleep 5
    done

    log_warning "服务健康检查超时，但服务可能仍在启动中"
    return 0
}

# 清理临时文件
cleanup() {
    log_info "清理临时文件..."

    # 移除回滚备份标记（如果回滚成功）
    if [ -f ".rollback_backup" ]; then
        rm .rollback_backup
    fi

    # 清理未使用的Docker资源
    if [ "$DRY_RUN" = false ]; then
        docker system prune -f > /dev/null 2>&1 || true
    fi

    log_success "清理完成"
}

# 显示回滚状态
show_status() {
    log_info "=== 回滚状态 ==="

    if [ "$DRY_RUN" = false ]; then
        docker-compose ps

        log_info "=== 服务日志 ==="
        docker-compose logs --tail=10 api
    fi

    log_success "回滚状态检查完成"
}

# 主要回滚函数
main() {
    log_info "开始系统回滚..."

    # 确定备份目录
    if [ -z "$BACKUP_DIR" ]; then
        log_info "未指定备份目录，查找最新备份..."
        BACKUP_DIR=$(find_latest_backup)
        if [ $? -ne 0 ]; then
            exit 1
        fi
        log_info "使用最新备份: $BACKUP_DIR"
    fi

    # 验证备份
    if ! validate_backup "$BACKUP_DIR"; then
        exit 1
    fi

    # 显示即将回滚的信息
    log_info "准备回滚到: $BACKUP_DIR"

    if [ -f "$BACKUP_DIR/database.sql" ]; then
        log_warning "将恢复数据库，这将覆盖当前所有数据!"
    fi

    # 确认回滚（除非使用 force 参数）
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        echo
        read -p "确认要继续回滚吗? (yes/no): " -r
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "回滚已取消"
            exit 0
        fi
    fi

    # 执行回滚步骤
    log_info "开始执行回滚..."

    # 1. 停止当前服务
    if ! stop_services; then
        log_error "停止服务失败"
        exit 1
    fi

    # 2. 恢复配置文件
    if ! restore_configs "$BACKUP_DIR"; then
        log_error "恢复配置失败"
        exit 1
    fi

    # 3. 恢复数据库
    if ! restore_database "$BACKUP_DIR"; then
        log_error "恢复数据库失败"
        exit 1
    fi

    # 4. 启动服务
    if ! start_services; then
        log_error "启动服务失败"
        exit 1
    fi

    # 5. 清理
    cleanup

    # 6. 显示状态
    show_status

    log_success "回滚完成!"
    log_info "已回滚到: $BACKUP_DIR"

    if [ -f ".rollback_backup" ]; then
        log_info "当前配置已备份到: $(cat .rollback_backup)"
    fi
}

# 信号处理
trap 'log_error "回滚被中断"; exit 130' INT TERM

# 执行主函数
main "$@"