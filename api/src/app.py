"""
企业微信群聊天记录存档系统主应用

FastAPI 应用的主入口点，包含API路由、中间件配置和应用初始化。
"""

import logging
import os
import time
from contextlib import asynccontextmanager
from typing import AsyncGenerator

import structlog
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from prometheus_client import Counter, Histogram, generate_latest
from starlette.middleware.base import BaseHTTPMiddleware

from .config import get_settings
from .database import engine, init_db
from .routes import api_router, health_router
from .utils.logging import setup_logging

# 配置结构化日志
setup_logging()
logger = structlog.get_logger()

# Prometheus 指标
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_DURATION = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration in seconds',
    ['method', 'endpoint']
)


class PrometheusMiddleware(BaseHTTPMiddleware):
    """Prometheus 监控中间件"""

    async def dispatch(self, request: Request, call_next):
        start_time = time.time()

        response = await call_next(request)

        # 记录指标
        method = request.method
        endpoint = request.url.path
        status = response.status_code

        REQUEST_COUNT.labels(method=method, endpoint=endpoint, status=status).inc()
        REQUEST_DURATION.labels(method=method, endpoint=endpoint).observe(
            time.time() - start_time
        )

        return response


class LoggingMiddleware(BaseHTTPMiddleware):
    """请求日志中间件"""

    async def dispatch(self, request: Request, call_next):
        start_time = time.time()

        # 记录请求开始
        logger.info(
            "Request started",
            method=request.method,
            url=str(request.url),
            client_ip=request.client.host if request.client else None
        )

        response = await call_next(request)

        # 记录请求完成
        duration = time.time() - start_time
        logger.info(
            "Request completed",
            method=request.method,
            url=str(request.url),
            status_code=response.status_code,
            duration=duration
        )

        return response


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """应用生命周期管理"""
    # 启动时执行
    logger.info("Starting WeChat Work Archive System API")

    # 初始化数据库
    try:
        await init_db()
        logger.info("Database initialized successfully")
    except Exception as e:
        logger.error("Failed to initialize database", error=str(e))
        raise

    yield

    # 关闭时执行
    logger.info("Shutting down WeChat Work Archive System API")

    # 关闭数据库连接
    if engine:
        await engine.dispose()
        logger.info("Database connections closed")


def create_app() -> FastAPI:
    """创建 FastAPI 应用实例"""
    settings = get_settings()

    app = FastAPI(
        title="企业微信群聊天记录存档系统 API",
        description="WeChat Work Chat Archive System API",
        version="1.0.0",
        docs_url="/docs" if settings.debug else None,
        redoc_url="/redoc" if settings.debug else None,
        lifespan=lifespan
    )

    # 添加中间件
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.add_middleware(GZipMiddleware, minimum_size=1000)
    app.add_middleware(PrometheusMiddleware)

    if settings.debug:
        app.add_middleware(LoggingMiddleware)

    # 注册路由
    app.include_router(health_router, tags=["Health"])
    app.include_router(api_router, prefix="/api/v1", tags=["API"])

    # Prometheus 指标端点
    @app.get("/metrics")
    async def metrics():
        """Prometheus 指标端点"""
        return Response(
            content=generate_latest(),
            media_type="text/plain"
        )

    # 根路径
    @app.get("/")
    async def root():
        """根路径"""
        return {
            "message": "企业微信群聊天记录存档系统 API",
            "version": "1.0.0",
            "docs": "/docs",
            "health": "/health"
        }

    return app


# 创建应用实例
app = create_app()


if __name__ == "__main__":
    import uvicorn

    settings = get_settings()

    uvicorn.run(
        "src.app:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug,
        workers=1 if settings.debug else settings.api_workers,
        log_level=settings.log_level.lower(),
        access_log=settings.debug
    )