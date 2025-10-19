#!/bin/bash

# 企业微信群聊天记录存档系统备份脚本
# Usage: ./scripts/backup.sh [options]

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
企业微信群聊天记录存档系统备份脚本

Usage: $0 [OPTIONS]

Options:
    -h, --help              显示帮助信息
    -v, --verbose           详细输出
    -o, --output DIR        指定备份输出目录 (默认: ./backups)
    -c, --compress          压缩备份文件
    -r, --retention DAYS    备份保留天数 (默认: 30天)
    --db-only               仅备份数据库
    --config-only           仅备份配置文件
    --media-only            仅备份媒体文件
    --exclude-media         排除媒体文件
    --dry-run               模拟运行
    --cron                  cron模式（静默运行）

Examples:
    $0                          # 完整备份
    $0 --db-only               # 仅备份数据库
    $0 --compress              # 压缩备份
    $0 -o /backup/path         # 指定备份目录
    $0 --retention 7           # 保留7天的备份
EOF
}

# 默认配置
OUTPUT_DIR="./backups"
COMPRESS=false
RETENTION_DAYS=30
VERBOSE=false
DRY_RUN=false
CRON_MODE=false
DB_ONLY=false
CONFIG_ONLY=false
MEDIA_ONLY=false
EXCLUDE_MEDIA=false

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
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -c|--compress)
            COMPRESS=true
            shift
            ;;
        -r|--retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --db-only)
            DB_ONLY=true
            shift
            ;;
        --config-only)
            CONFIG_ONLY=true
            shift
            ;;
        --media-only)
            MEDIA_ONLY=true
            shift
            ;;
        --exclude-media)
            EXCLUDE_MEDIA=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --cron)
            CRON_MODE=true
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
if [ "$VERBOSE" = true ] && [ "$CRON_MODE" = false ]; then
    set -x
fi

# cron模式下重定向输出
if [ "$CRON_MODE" = true ]; then
    # 重定向到日志文件
    LOG_FILE="/var/log/wechat-archive-backup.log"
    exec 1> >(while IFS= read -r line; do echo "$(date '+%Y-%m-%d %H:%M:%S') $line"; done >> "$LOG_FILE")
    exec 2>&1
fi

# 切换到项目根目录
cd "$(dirname "$0")/.."

# 检查Docker环境
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装"
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose 未安装"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker 服务未运行"
        exit 1
    fi
}

# 创建备份目录
create_backup_dir() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$OUTPUT_DIR/$timestamp"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将创建备份目录: $backup_dir"
        echo "$backup_dir"
        return 0
    fi

    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# 备份数据库
backup_database() {
    local backup_dir="$1"

    if [ "$CONFIG_ONLY" = true ] || [ "$MEDIA_ONLY" = true ]; then
        return 0
    fi

    log_info "备份数据库..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将备份数据库到 $backup_dir/database.sql"
        return 0
    fi

    # 检查PostgreSQL容器是否运行
    if ! docker-compose ps postgres | grep -q "Up"; then
        log_warning "PostgreSQL 容器未运行，跳过数据库备份"
        return 0
    fi

    # 获取数据库配置
    local db_user="${DB_USER:-wechat_admin}"
    local db_name="${DB_NAME:-wechat_archive}"

    # 执行数据库备份
    if docker-compose exec -T postgres pg_dump -U "$db_user" "$db_name" > "$backup_dir/database.sql"; then
        local size=$(du -sh "$backup_dir/database.sql" | cut -f1)
        log_success "数据库备份完成 (大小: $size)"

        # 创建数据库元信息
        cat > "$backup_dir/database.info" << EOF
backup_time=$(date '+%Y-%m-%d %H:%M:%S')
database_name=$db_name
database_user=$db_user
backup_size=$size
postgres_version=$(docker-compose exec -T postgres psql -U "$db_user" -d "$db_name" -t -c "SELECT version();" | head -1 | xargs)
EOF
    else
        log_error "数据库备份失败"
        return 1
    fi
}

# 备份配置文件
backup_configs() {
    local backup_dir="$1"

    if [ "$DB_ONLY" = true ] || [ "$MEDIA_ONLY" = true ]; then
        return 0
    fi

    log_info "备份配置文件..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将备份配置文件到 $backup_dir"
        return 0
    fi

    # 备份主要配置文件
    local config_files=(
        "docker-compose.yml"
        "docker/docker-compose.yml"
        "docker/docker-compose.dev.yml"
        ".env"
        ".env.example"
        "nginx/nginx.conf"
        "alembic.ini"
    )

    local config_dirs=(
        "nginx/"
        "monitoring/"
        "scripts/"
    )

    # 备份文件
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            local dest_dir="$backup_dir/$(dirname "$file")"
            mkdir -p "$dest_dir"
            cp "$file" "$dest_dir/"
            log_info "已备份: $file"
        fi
    done

    # 备份目录
    for dir in "${config_dirs[@]}"; do
        if [ -d "$dir" ]; then
            cp -r "$dir" "$backup_dir/"
            log_info "已备份目录: $dir"
        fi
    done

    # 创建配置备份元信息
    cat > "$backup_dir/config.info" << EOF
backup_time=$(date '+%Y-%m-%d %H:%M:%S')
git_commit=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
docker_version=$(docker --version)
docker_compose_version=$(docker-compose --version)
EOF

    log_success "配置文件备份完成"
}

# 备份媒体文件
backup_media() {
    local backup_dir="$1"

    if [ "$DB_ONLY" = true ] || [ "$CONFIG_ONLY" = true ] || [ "$EXCLUDE_MEDIA" = true ]; then
        return 0
    fi

    log_info "备份媒体文件..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将备份媒体文件到 $backup_dir/media"
        return 0
    fi

    # 检查媒体目录
    local media_dirs=("./media" "./uploads")

    for media_dir in "${media_dirs[@]}"; do
        if [ -d "$media_dir" ] && [ "$(ls -A "$media_dir" 2>/dev/null)" ]; then
            log_info "备份媒体目录: $media_dir"
            cp -r "$media_dir" "$backup_dir/"

            # 计算媒体文件统计
            local file_count=$(find "$media_dir" -type f | wc -l)
            local total_size=$(du -sh "$media_dir" | cut -f1)

            log_info "媒体文件数量: $file_count, 总大小: $total_size"

            # 创建媒体备份元信息
            cat > "$backup_dir/$(basename "$media_dir").info" << EOF
backup_time=$(date '+%Y-%m-%d %H:%M:%S')
source_path=$media_dir
file_count=$file_count
total_size=$total_size
EOF
        else
            log_info "媒体目录为空或不存在: $media_dir"
        fi
    done

    log_success "媒体文件备份完成"
}

# 备份应用日志
backup_logs() {
    local backup_dir="$1"

    if [ "$DB_ONLY" = true ] || [ "$CONFIG_ONLY" = true ] || [ "$MEDIA_ONLY" = true ]; then
        return 0
    fi

    log_info "备份应用日志..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将备份应用日志到 $backup_dir/logs"
        return 0
    fi

    # 备份日志目录
    if [ -d "./logs" ] && [ "$(ls -A ./logs 2>/dev/null)" ]; then
        # 只备份最近7天的日志
        mkdir -p "$backup_dir/logs"
        find ./logs -name "*.log" -mtime -7 -exec cp {} "$backup_dir/logs/" \;
        log_success "应用日志备份完成"
    fi

    # 导出Docker容器日志
    if docker-compose ps -q | grep -q .; then
        mkdir -p "$backup_dir/container_logs"

        # 获取所有运行中的容器
        local containers=$(docker-compose ps --services)

        for container in $containers; do
            if docker-compose ps "$container" | grep -q "Up"; then
                docker-compose logs --tail=1000 "$container" > "$backup_dir/container_logs/${container}.log" 2>/dev/null || true
                log_info "已导出 $container 容器日志"
            fi
        done

        log_success "容器日志导出完成"
    fi
}

# 压缩备份
compress_backup() {
    local backup_dir="$1"

    if [ "$COMPRESS" = false ]; then
        return 0
    fi

    log_info "压缩备份文件..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将压缩备份到 ${backup_dir}.tar.gz"
        return 0
    fi

    local backup_name=$(basename "$backup_dir")
    local parent_dir=$(dirname "$backup_dir")

    # 创建压缩包
    if tar -czf "${backup_dir}.tar.gz" -C "$parent_dir" "$backup_name"; then
        local compressed_size=$(du -sh "${backup_dir}.tar.gz" | cut -f1)
        local original_size=$(du -sh "$backup_dir" | cut -f1)

        log_success "压缩完成: ${backup_dir}.tar.gz (原始: $original_size, 压缩后: $compressed_size)"

        # 删除原始目录
        rm -rf "$backup_dir"
        log_info "已删除原始备份目录"
    else
        log_error "压缩备份失败"
        return 1
    fi
}

# 清理旧备份
cleanup_old_backups() {
    if [ "$RETENTION_DAYS" -le 0 ]; then
        return 0
    fi

    log_info "清理 $RETENTION_DAYS 天前的备份..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将删除超过 $RETENTION_DAYS 天的备份"
        if [ -d "$OUTPUT_DIR" ]; then
            find "$OUTPUT_DIR" -type d -name "20*" -mtime +$RETENTION_DAYS | while read -r old_backup; do
                log_info "[DRY RUN] 将删除: $old_backup"
            done
            find "$OUTPUT_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS | while read -r old_backup; do
                log_info "[DRY RUN] 将删除: $old_backup"
            done
        fi
        return 0
    fi

    if [ ! -d "$OUTPUT_DIR" ]; then
        return 0
    fi

    local deleted_count=0

    # 删除旧的备份目录
    find "$OUTPUT_DIR" -type d -name "20*" -mtime +$RETENTION_DAYS | while read -r old_backup; do
        if [ -d "$old_backup" ]; then
            rm -rf "$old_backup"
            log_info "已删除旧备份: $old_backup"
            deleted_count=$((deleted_count + 1))
        fi
    done

    # 删除旧的压缩包
    find "$OUTPUT_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS | while read -r old_backup; do
        if [ -f "$old_backup" ]; then
            rm -f "$old_backup"
            log_info "已删除旧备份: $old_backup"
            deleted_count=$((deleted_count + 1))
        fi
    done

    if [ $deleted_count -gt 0 ]; then
        log_success "已清理 $deleted_count 个旧备份"
    else
        log_info "没有需要清理的旧备份"
    fi
}

# 验证备份
verify_backup() {
    local backup_dir="$1"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] 将验证备份完整性"
        return 0
    fi

    log_info "验证备份完整性..."

    local success=true

    # 如果是压缩包，先解压验证
    if [ "$COMPRESS" = true ] && [ -f "${backup_dir}.tar.gz" ]; then
        if ! tar -tzf "${backup_dir}.tar.gz" > /dev/null 2>&1; then
            log_error "压缩包损坏: ${backup_dir}.tar.gz"
            success=false
        fi
    else
        # 验证目录结构
        if [ ! -d "$backup_dir" ]; then
            log_error "备份目录不存在: $backup_dir"
            success=false
        fi

        # 验证数据库备份
        if [ "$DB_ONLY" = true ] || ([ "$CONFIG_ONLY" = false ] && [ "$MEDIA_ONLY" = false ]); then
            if [ -f "$backup_dir/database.sql" ]; then
                # 检查SQL文件是否有效
                if ! head -10 "$backup_dir/database.sql" | grep -q "PostgreSQL database dump"; then
                    log_warning "数据库备份文件可能无效"
                fi
            else
                log_warning "数据库备份文件不存在"
            fi
        fi
    fi

    if [ "$success" = true ]; then
        log_success "备份验证通过"
    else
        log_error "备份验证失败"
        return 1
    fi
}

# 发送通知
send_notification() {
    local status="$1"
    local backup_path="$2"

    # 只在cron模式或有邮件配置时发送通知
    if [ "$CRON_MODE" = false ]; then
        return 0
    fi

    # 这里可以添加邮件、Slack等通知逻辑
    # 示例：发送到日志
    if [ "$status" = "success" ]; then
        log_info "备份成功完成: $backup_path"
    else
        log_error "备份失败"
    fi
}

# 显示备份统计
show_stats() {
    local backup_dir="$1"

    if [ "$CRON_MODE" = true ] || [ "$DRY_RUN" = true ]; then
        return 0
    fi

    log_info "=== 备份统计 ==="

    if [ "$COMPRESS" = true ] && [ -f "${backup_dir}.tar.gz" ]; then
        local size=$(du -sh "${backup_dir}.tar.gz" | cut -f1)
        echo "备份文件: ${backup_dir}.tar.gz"
        echo "备份大小: $size"
    elif [ -d "$backup_dir" ]; then
        local size=$(du -sh "$backup_dir" | cut -f1)
        echo "备份目录: $backup_dir"
        echo "备份大小: $size"

        if [ -f "$backup_dir/database.sql" ]; then
            local db_size=$(du -sh "$backup_dir/database.sql" | cut -f1)
            echo "数据库备份: $db_size"
        fi

        local file_count=$(find "$backup_dir" -type f | wc -l)
        echo "文件数量: $file_count"
    fi

    echo "备份时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "保留期限: $RETENTION_DAYS 天"
}

# 主要备份函数
main() {
    log_info "开始系统备份..."

    # 检查环境
    check_docker

    # 创建备份目录
    local backup_dir
    backup_dir=$(create_backup_dir)

    if [ "$DRY_RUN" = false ]; then
        log_info "备份目录: $backup_dir"
    fi

    # 执行备份任务
    local backup_success=true

    if ! backup_database "$backup_dir"; then
        backup_success=false
    fi

    if ! backup_configs "$backup_dir"; then
        backup_success=false
    fi

    if ! backup_media "$backup_dir"; then
        backup_success=false
    fi

    if ! backup_logs "$backup_dir"; then
        backup_success=false
    fi

    # 压缩备份
    if [ "$backup_success" = true ]; then
        if ! compress_backup "$backup_dir"; then
            backup_success=false
        fi
    fi

    # 验证备份
    if [ "$backup_success" = true ]; then
        if ! verify_backup "$backup_dir"; then
            backup_success=false
        fi
    fi

    # 清理旧备份
    cleanup_old_backups

    # 显示统计信息
    if [ "$backup_success" = true ]; then
        show_stats "$backup_dir"
        log_success "备份完成!"
        send_notification "success" "$backup_dir"
    else
        log_error "备份过程中出现错误"
        send_notification "failure" "$backup_dir"
        exit 1
    fi
}

# 信号处理
trap 'log_error "备份被中断"; exit 130' INT TERM

# 执行主函数
main "$@"