# 企业微信群聊天记录存档系统

## 项目概述

企业微信群聊天记录存档系统是一个基于Docker的微服务架构应用，用于自动收集、存储和管理企业微信群聊天记录。系统支持多种消息类型，提供安全可靠的数据存储和便捷的查询接口。

## 核心功能

- ✅ 自动拉取企业微信群聊天记录
- ✅ 解密并安全存储消息内容
- ✅ 支持文本、图片、文件、语音等多种消息类型
- ✅ 增量同步机制，避免重复拉取
- ✅ RESTful API接口和实时WebSocket推送
- ✅ 完整的CI/CD流程和自动化部署
- ✅ 监控告警和性能优化

## 技术栈

- **后端**: Python 3.10+ / FastAPI
- **数据库**: PostgreSQL 15
- **缓存**: Redis 7
- **任务队列**: Celery
- **容器化**: Docker & Docker Compose
- **反向代理**: Nginx
- **监控**: Prometheus + Grafana
- **CI/CD**: GitHub Actions

## 快速开始

### 前置要求

1. **系统要求**
   - Ubuntu 20.04+ 或 CentOS 7+
   - Docker 20.10+
   - Docker Compose 2.0+
   - 2核4G内存以上服务器

2. **企业微信配置**
   - 开启会话内容存档功能
   - 配置服务器IP到白名单
   - 获取CorpID和Secret
   - 购买存档席位

### 安装部署

1. **克隆项目**
```bash
git clone https://github.com/your-org/wechat-work-archive.git
cd wechat-work-archive
```

2. **配置环境变量**
```bash
cp .env.example .env
# 编辑.env文件，填入实际配置
```

3. **启动服务**
```bash
# 生产环境
docker-compose -f docker/docker-compose.yml up -d

# 开发环境
docker-compose -f docker/docker-compose.dev.yml up -d
```

4. **初始化数据库**
```bash
docker-compose exec api alembic upgrade head
```

5. **验证服务**
```bash
curl http://localhost:8000/health
```

## 项目结构

```
wechat-work-archive/
├── .github/                      # GitHub CI/CD配置
│   └── workflows/               # 工作流文件
├── docker/                      # Docker配置
│   ├── docker-compose.yml       # 生产环境
│   ├── docker-compose.dev.yml   # 开发环境
│   └── docker-compose.test.yml  # 测试环境
├── api/                         # API服务
│   ├── src/                     # 源代码
│   ├── tests/                   # 测试文件
│   ├── Dockerfile
│   └── requirements.txt
├── database/                    # 数据库
│   ├── init.sql                 # 初始化脚本
│   └── migrations/              # 数据库迁移
├── nginx/                       # Nginx配置
├── scripts/                     # 运维脚本
├── monitoring/                  # 监控配置
└── docs/                        # 文档
```

## API接口

### 健康检查
```bash
GET /health
```

### 手动同步消息
```bash
POST /api/v1/sync
Content-Type: application/json
{
    "roomid": "room_001",
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-01-31T23:59:59Z"
}
```

### 查询群组列表
```bash
GET /api/v1/groups?page=1&size=20&keyword=关键词
```

### 获取群消息
```bash
GET /api/v1/groups/{roomid}/messages?start_time=2024-01-01T00:00:00Z&end_time=2024-01-31T23:59:59Z
```

## 开发指南

### 本地开发环境

1. **安装Python虚拟环境**
```bash
python -m venv venv
source venv/bin/activate  # Linux/Mac
# 或
venv\Scripts\activate     # Windows
```

2. **安装依赖**
```bash
pip install -r api/requirements-dev.txt
```

3. **启动开发数据库**
```bash
docker-compose -f docker/docker-compose.dev.yml up -d postgres redis
```

4. **运行开发服务器**
```bash
uvicorn api.app:app --reload --port 8000
```

### 运行测试

```bash
# 运行所有测试
make test

# 运行单元测试
make test-unit

# 运行集成测试
make test-integration

# 生成覆盖率报告
pytest --cov=api/src --cov-report=html
```

### 代码规范

- 使用black进行代码格式化
- 使用flake8进行代码检查
- 使用mypy进行类型检查
- 测试覆盖率要求>80%

## 部署运维

### 常用命令

```bash
# 查看服务状态
docker-compose ps

# 查看日志
docker-compose logs -f api

# 重启服务
docker-compose restart api

# 数据备份
./scripts/backup.sh

# 部署到生产环境
./scripts/deploy.sh production blue-green
```

### 监控访问

- **Prometheus**: http://server:9090
- **Grafana**: http://server:3000 (admin/password)
- **API文档**: http://server:8000/docs

### 故障排查

1. **检查服务状态**
```bash
docker-compose ps
docker-compose logs api
```

2. **检查数据库连接**
```bash
docker-compose exec postgres pg_isready
```

3. **检查Redis连接**
```bash
docker-compose exec redis redis-cli ping
```

## 安全说明

- 所有敏感配置通过环境变量管理
- 支持HTTPS/TLS加密传输
- 数据库连接使用内部网络
- 定期安全扫描和依赖更新
- 完整的访问日志和审计跟踪

## 贡献指南

1. Fork项目
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建Pull Request

## 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 联系我们

- 问题反馈: [GitHub Issues](https://github.com/your-org/wechat-work-archive/issues)
- 技术文档: [docs/](docs/)
- 更新日志: [CHANGELOG.md](CHANGELOG.md)

---

**注意**: 使用本系统前请确保已获得相关人员的授权同意，并遵守企业微信的使用条款和相关法律法规。