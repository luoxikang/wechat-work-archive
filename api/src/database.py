"""
数据库模块

处理数据库连接、会话管理和初始化。
"""

import asyncio
from typing import AsyncGenerator

from sqlalchemy import create_engine, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import structlog

from .config import get_settings

logger = structlog.get_logger()

# 创建基础模型类
Base = declarative_base()

# 全局变量
engine = None
async_session_maker = None
sync_engine = None
sync_session_maker = None


def get_database_url(async_mode: bool = True) -> str:
    """获取数据库URL"""
    settings = get_settings()
    db_url = settings.database_url

    if async_mode and not db_url.startswith("postgresql+asyncpg://"):
        # 将 postgresql:// 转换为 postgresql+asyncpg://
        if db_url.startswith("postgresql://"):
            db_url = db_url.replace("postgresql://", "postgresql+asyncpg://", 1)
        else:
            raise ValueError("Unsupported database URL format")

    return db_url


async def init_db():
    """初始化数据库连接"""
    global engine, async_session_maker, sync_engine, sync_session_maker

    settings = get_settings()

    try:
        # 异步引擎
        engine = create_async_engine(
            get_database_url(async_mode=True),
            **settings.database_config,
            future=True
        )

        # 异步会话工厂
        async_session_maker = async_sessionmaker(
            engine,
            class_=AsyncSession,
            expire_on_commit=False
        )

        # 同步引擎（用于 Alembic 等工具）
        sync_engine = create_engine(
            get_database_url(async_mode=False),
            **settings.database_config,
            future=True
        )

        # 同步会话工厂
        sync_session_maker = sessionmaker(
            sync_engine,
            expire_on_commit=False
        )

        # 测试连接
        async with engine.begin() as conn:
            await conn.execute(text("SELECT 1"))

        logger.info("Database connection initialized successfully")

    except Exception as e:
        logger.error("Failed to initialize database connection", error=str(e))
        raise


async def get_async_session() -> AsyncGenerator[AsyncSession, None]:
    """获取异步数据库会话"""
    if async_session_maker is None:
        raise RuntimeError("Database not initialized. Call init_db() first.")

    async with async_session_maker() as session:
        try:
            yield session
        except Exception as e:
            await session.rollback()
            logger.error("Database session error", error=str(e))
            raise
        finally:
            await session.close()


def get_sync_session():
    """获取同步数据库会话"""
    if sync_session_maker is None:
        raise RuntimeError("Database not initialized. Call init_db() first.")

    session = sync_session_maker()
    try:
        yield session
    except Exception as e:
        session.rollback()
        logger.error("Database session error", error=str(e))
        raise
    finally:
        session.close()


async def check_database_health() -> bool:
    """检查数据库健康状态"""
    try:
        if engine is None:
            return False

        async with engine.begin() as conn:
            result = await conn.execute(text("SELECT 1"))
            return result.scalar() == 1

    except Exception as e:
        logger.error("Database health check failed", error=str(e))
        return False


async def close_db():
    """关闭数据库连接"""
    global engine, sync_engine

    if engine:
        await engine.dispose()
        logger.info("Async database engine closed")

    if sync_engine:
        sync_engine.dispose()
        logger.info("Sync database engine closed")


class DatabaseManager:
    """数据库管理器"""

    def __init__(self):
        self.engine = None
        self.session_maker = None

    async def initialize(self):
        """初始化数据库连接"""
        await init_db()
        self.engine = engine
        self.session_maker = async_session_maker

    async def get_session(self) -> AsyncGenerator[AsyncSession, None]:
        """获取数据库会话"""
        async for session in get_async_session():
            yield session

    async def health_check(self) -> bool:
        """健康检查"""
        return await check_database_health()

    async def close(self):
        """关闭连接"""
        await close_db()


# 全局数据库管理器实例
db_manager = DatabaseManager()


# 用于依赖注入的函数
async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """FastAPI 依赖注入用的数据库会话获取函数"""
    async for session in get_async_session():
        yield session


# 数据库装饰器
def with_db_session(func):
    """数据库会话装饰器"""
    async def wrapper(*args, **kwargs):
        async with async_session_maker() as session:
            try:
                result = await func(session, *args, **kwargs)
                await session.commit()
                return result
            except Exception as e:
                await session.rollback()
                logger.error("Database operation failed", error=str(e), function=func.__name__)
                raise
            finally:
                await session.close()

    return wrapper