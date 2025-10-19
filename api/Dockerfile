# 多阶段构建 Dockerfile for 企业微信群聊天记录存档系统

# ================================================================================
# Base stage - 基础镜像
# ================================================================================
FROM python:3.10-slim as base

# 设置环境变量
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONHASHSEED=random \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# 设置工作目录
WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    curl \
    gcc \
    g++ \
    libpq-dev \
    libffi-dev \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# 创建非root用户
RUN groupadd -r appuser && useradd -r -g appuser appuser

# ================================================================================
# Dependencies stage - 依赖安装
# ================================================================================
FROM base as dependencies

# 复制依赖文件
COPY requirements.txt .

# 安装Python依赖
RUN pip install --upgrade pip && \
    pip install -r requirements.txt

# ================================================================================
# Development stage - 开发环境
# ================================================================================
FROM dependencies as development

# 安装开发依赖
COPY requirements-dev.txt .
RUN pip install -r requirements-dev.txt

# 复制应用代码
COPY . .

# 设置权限
RUN chown -R appuser:appuser /app

# 切换到非root用户
USER appuser

# 暴露端口
EXPOSE 8000

# 启动命令
CMD ["uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]

# ================================================================================
# Test stage - 测试环境
# ================================================================================
FROM dependencies as test

# 安装测试依赖
COPY requirements-dev.txt .
RUN pip install -r requirements-dev.txt

# 复制应用代码
COPY . .

# 设置权限
RUN chown -R appuser:appuser /app

# 切换到非root用户
USER appuser

# 运行测试
CMD ["pytest", "tests/", "-v", "--cov=src", "--cov-report=term-missing"]

# ================================================================================
# Production stage - 生产环境
# ================================================================================
FROM dependencies as production

# 复制应用代码
COPY src/ ./src/
COPY alembic/ ./alembic/
COPY alembic.ini .

# 创建必要的目录
RUN mkdir -p /app/logs /app/media /app/uploads

# 设置权限
RUN chown -R appuser:appuser /app

# 切换到非root用户
USER appuser

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# 暴露端口
EXPOSE 8000

# 启动命令
CMD ["uvicorn", "src.app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "4"]