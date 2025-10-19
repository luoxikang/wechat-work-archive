"""
配置管理模块

使用 Pydantic Settings 管理应用配置，支持环境变量和配置文件。
"""

import os
from functools import lru_cache
from typing import List, Optional

from pydantic import BaseSettings, Field, validator


class Settings(BaseSettings):
    """应用配置类"""

    # ================================================================================
    # 基础配置
    # ================================================================================
    app_name: str = Field(default="WeChat Work Archive System", env="APP_NAME")
    debug: bool = Field(default=False, env="DEBUG")
    testing: bool = Field(default=False, env="TESTING")
    log_level: str = Field(default="INFO", env="LOG_LEVEL")

    # ================================================================================
    # API 服务配置
    # ================================================================================
    api_host: str = Field(default="0.0.0.0", env="API_HOST")
    api_port: int = Field(default=8000, env="API_PORT")
    api_workers: int = Field(default=4, env="API_WORKERS")
    allowed_origins: List[str] = Field(
        default=["http://localhost:3000", "http://localhost:8000"],
        env="ALLOWED_ORIGINS"
    )

    # ================================================================================
    # 企业微信配置
    # ================================================================================
    corp_id: str = Field(..., env="CORP_ID")
    secret: str = Field(..., env="SECRET")
    encoding_aes_key: str = Field(..., env="ENCODING_AES_KEY")
    api_base_url: str = Field(
        default="https://qyapi.weixin.qq.com",
        env="WECHAT_API_BASE_URL"
    )
    token_cache_ttl: int = Field(default=7000, env="TOKEN_CACHE_TTL")  # 秒
    max_retry_attempts: int = Field(default=3, env="MAX_RETRY_ATTEMPTS")
    request_timeout: int = Field(default=30, env="REQUEST_TIMEOUT")

    # ================================================================================
    # 数据库配置
    # ================================================================================
    database_url: str = Field(..., env="DATABASE_URL")
    db_pool_size: int = Field(default=20, env="DB_POOL_SIZE")
    db_max_overflow: int = Field(default=30, env="DB_MAX_OVERFLOW")
    db_pool_timeout: int = Field(default=30, env="DB_POOL_TIMEOUT")
    db_pool_recycle: int = Field(default=3600, env="DB_POOL_RECYCLE")
    db_echo: bool = Field(default=False, env="DB_ECHO")

    # ================================================================================
    # Redis 配置
    # ================================================================================
    redis_url: str = Field(default="redis://localhost:6379/0", env="REDIS_URL")
    redis_max_connections: int = Field(default=20, env="REDIS_MAX_CONNECTIONS")
    redis_timeout: int = Field(default=5, env="REDIS_TIMEOUT")

    # ================================================================================
    # Celery 配置
    # ================================================================================
    celery_broker_url: str = Field(default="redis://localhost:6379/1", env="CELERY_BROKER_URL")
    celery_result_backend: str = Field(default="redis://localhost:6379/2", env="CELERY_RESULT_BACKEND")
    celery_timezone: str = Field(default="Asia/Shanghai", env="CELERY_TIMEZONE")
    celery_task_serializer: str = Field(default="json", env="CELERY_TASK_SERIALIZER")
    celery_result_serializer: str = Field(default="json", env="CELERY_RESULT_SERIALIZER")
    celery_accept_content: List[str] = Field(default=["json"], env="CELERY_ACCEPT_CONTENT")

    # ================================================================================
    # 同步配置
    # ================================================================================
    sync_interval: int = Field(default=300, env="SYNC_INTERVAL")  # 秒
    max_sync_days: int = Field(default=90, env="MAX_SYNC_DAYS")
    batch_size: int = Field(default=100, env="BATCH_SIZE")
    enable_auto_sync: bool = Field(default=True, env="ENABLE_AUTO_SYNC")

    # ================================================================================
    # 媒体文件配置
    # ================================================================================
    enable_media_download: bool = Field(default=True, env="ENABLE_MEDIA_DOWNLOAD")
    media_storage_path: str = Field(default="/app/media", env="MEDIA_STORAGE_PATH")
    max_file_size: int = Field(default=104857600, env="MAX_FILE_SIZE")  # 100MB
    allowed_file_types: List[str] = Field(
        default=["jpg", "jpeg", "png", "gif", "mp4", "avi", "mp3", "wav", "doc", "docx", "pdf", "txt"],
        env="ALLOWED_FILE_TYPES"
    )
    media_url_prefix: str = Field(default="/media", env="MEDIA_URL_PREFIX")

    # ================================================================================
    # 安全配置
    # ================================================================================
    secret_key: str = Field(default="your-secret-key-here", env="SECRET_KEY")
    access_token_expire_minutes: int = Field(default=30, env="ACCESS_TOKEN_EXPIRE_MINUTES")
    algorithm: str = Field(default="HS256", env="ALGORITHM")
    enable_security: bool = Field(default=True, env="ENABLE_SECURITY")

    # ================================================================================
    # 监控和日志配置
    # ================================================================================
    enable_metrics: bool = Field(default=True, env="ENABLE_METRICS")
    log_file_path: str = Field(default="/app/logs/app.log", env="LOG_FILE_PATH")
    log_rotation: str = Field(default="1 week", env="LOG_ROTATION")
    log_retention: str = Field(default="1 month", env="LOG_RETENTION")
    sentry_dsn: Optional[str] = Field(default=None, env="SENTRY_DSN")

    # ================================================================================
    # 性能配置
    # ================================================================================
    enable_cache: bool = Field(default=True, env="ENABLE_CACHE")
    cache_ttl: int = Field(default=300, env="CACHE_TTL")  # 秒
    enable_compression: bool = Field(default=True, env="ENABLE_COMPRESSION")
    max_request_size: int = Field(default=16777216, env="MAX_REQUEST_SIZE")  # 16MB

    # ================================================================================
    # 开发和测试配置
    # ================================================================================
    reload: bool = Field(default=False, env="RELOAD")
    test_database_url: Optional[str] = Field(default=None, env="TEST_DATABASE_URL")

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False

    @validator("allowed_origins", pre=True)
    def parse_allowed_origins(cls, v):
        """解析允许的源地址"""
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",")]
        return v

    @validator("allowed_file_types", pre=True)
    def parse_allowed_file_types(cls, v):
        """解析允许的文件类型"""
        if isinstance(v, str):
            return [file_type.strip().lower() for file_type in v.split(",")]
        return v

    @validator("celery_accept_content", pre=True)
    def parse_celery_accept_content(cls, v):
        """解析 Celery 接受的内容类型"""
        if isinstance(v, str):
            return [content.strip() for content in v.split(",")]
        return v

    @validator("log_level")
    def validate_log_level(cls, v):
        """验证日志级别"""
        valid_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]
        if v.upper() not in valid_levels:
            raise ValueError(f"Log level must be one of: {valid_levels}")
        return v.upper()

    @validator("media_storage_path")
    def create_media_directory(cls, v):
        """创建媒体存储目录"""
        os.makedirs(v, exist_ok=True)
        return v

    @property
    def database_config(self) -> dict:
        """数据库配置字典"""
        return {
            "pool_size": self.db_pool_size,
            "max_overflow": self.db_max_overflow,
            "pool_timeout": self.db_pool_timeout,
            "pool_recycle": self.db_pool_recycle,
            "echo": self.db_echo,
        }

    @property
    def redis_config(self) -> dict:
        """Redis 配置字典"""
        return {
            "max_connections": self.redis_max_connections,
            "socket_timeout": self.redis_timeout,
            "socket_connect_timeout": self.redis_timeout,
        }

    @property
    def celery_config(self) -> dict:
        """Celery 配置字典"""
        return {
            "broker_url": self.celery_broker_url,
            "result_backend": self.celery_result_backend,
            "timezone": self.celery_timezone,
            "task_serializer": self.celery_task_serializer,
            "result_serializer": self.celery_result_serializer,
            "accept_content": self.celery_accept_content,
            "task_routes": {
                "src.tasks.sync_messages": {"queue": "sync"},
                "src.tasks.download_media": {"queue": "media"},
                "src.tasks.cleanup_old_data": {"queue": "maintenance"},
            },
            "beat_schedule": {
                "sync-messages": {
                    "task": "src.tasks.sync_all_groups_messages",
                    "schedule": self.sync_interval,
                },
                "cleanup-old-data": {
                    "task": "src.tasks.cleanup_old_data",
                    "schedule": 86400,  # 每天执行一次
                },
            },
        }

    def get_wechat_api_config(self) -> dict:
        """企业微信 API 配置"""
        return {
            "corp_id": self.corp_id,
            "secret": self.secret,
            "encoding_aes_key": self.encoding_aes_key,
            "api_base_url": self.api_base_url,
            "token_cache_ttl": self.token_cache_ttl,
            "max_retry_attempts": self.max_retry_attempts,
            "request_timeout": self.request_timeout,
        }


@lru_cache()
def get_settings() -> Settings:
    """获取应用配置实例（缓存）"""
    return Settings()


# 导出配置实例
settings = get_settings()