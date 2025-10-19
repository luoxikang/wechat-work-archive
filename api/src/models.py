"""
数据库模型定义

定义所有的SQLAlchemy模型类。
"""

from datetime import datetime
from typing import Dict, List, Optional

from sqlalchemy import (
    Boolean, Column, DateTime, Enum, ForeignKey, Integer, BigInteger,
    String, Text, ARRAY, JSON, func, Index
)
from sqlalchemy.dialects.postgresql import INET, JSONB
from sqlalchemy.orm import relationship
from sqlalchemy.ext.hybrid import hybrid_property
import enum

from .database import Base


# 枚举类型定义
class MessageType(str, enum.Enum):
    """消息类型枚举"""
    TEXT = "text"
    IMAGE = "image"
    VOICE = "voice"
    VIDEO = "video"
    FILE = "file"
    LOCATION = "location"
    LINK = "link"
    MINIPROGRAM = "miniprogram"
    CARD = "card"
    SYSTEM = "system"
    REVOKE = "revoke"
    EMOTION = "emotion"


class MemberType(str, enum.Enum):
    """群成员类型枚举"""
    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"


class DownloadStatus(str, enum.Enum):
    """下载状态枚举"""
    PENDING = "pending"
    DOWNLOADING = "downloading"
    COMPLETED = "completed"
    FAILED = "failed"


class TaskStatus(str, enum.Enum):
    """任务状态枚举"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class ChatGroup(Base):
    """群组模型"""
    __tablename__ = "chat_groups"

    roomid = Column(String(100), primary_key=True, index=True)
    room_name = Column(String(255), nullable=False, index=True)
    creator = Column(String(100))
    notice = Column(Text)
    owner_corpid = Column(String(100), nullable=False, index=True)
    create_time = Column(DateTime(timezone=True))
    member_count = Column(Integer, default=0)
    metadata = Column(JSONB, default=dict)
    is_active = Column(Boolean, default=True, index=True)
    last_sync_time = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, index=True)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    # 关系
    messages = relationship("ChatMessage", back_populates="group", cascade="all, delete-orphan")
    members = relationship("ChatMember", back_populates="group", cascade="all, delete-orphan")
    sync_tasks = relationship("SyncTask", back_populates="group")

    # 索引
    __table_args__ = (
        Index('idx_groups_name_gin', 'room_name', postgresql_using='gin'),
        Index('idx_groups_metadata', 'metadata', postgresql_using='gin'),
        Index('idx_groups_composite', 'owner_corpid', 'is_active', 'created_at'),
    )

    @hybrid_property
    def active_member_count(self):
        """活跃成员数量"""
        return len([m for m in self.members if m.is_active])

    def __repr__(self):
        return f"<ChatGroup(roomid='{self.roomid}', name='{self.room_name}')>"


class ChatMessage(Base):
    """消息模型"""
    __tablename__ = "chat_messages"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    seq = Column(BigInteger, unique=True, nullable=False, index=True)
    msgid = Column(String(100), unique=True, nullable=False, index=True)
    roomid = Column(String(100), ForeignKey("chat_groups.roomid"), nullable=False, index=True)
    msgtype = Column(Enum(MessageType), nullable=False, index=True)
    msgtime = Column(DateTime(timezone=True), nullable=False, index=True)
    from_user = Column(String(100), index=True)
    to_users = Column(ARRAY(String))
    content = Column(Text)
    media_data = Column(JSONB, default=dict)
    raw_data = Column(JSONB, default=dict)
    is_revoked = Column(Boolean, default=False, index=True)
    revoke_time = Column(DateTime(timezone=True))
    forward_count = Column(Integer, default=0)
    reply_to_msgid = Column(String(100), ForeignKey("chat_messages.msgid"))
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, index=True)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    # 关系
    group = relationship("ChatGroup", back_populates="messages")
    media_files = relationship("MediaFile", back_populates="message", cascade="all, delete-orphan")
    reply_to = relationship("ChatMessage", remote_side=[msgid])

    # 索引
    __table_args__ = (
        Index('idx_messages_content_gin', 'content', postgresql_using='gin'),
        Index('idx_messages_media_data', 'media_data', postgresql_using='gin'),
        Index('idx_messages_composite', 'roomid', 'msgtime', 'msgtype'),
        Index('idx_messages_time_range', 'msgtime', 'roomid'),
    )

    @hybrid_property
    def has_media(self):
        """是否包含媒体文件"""
        return len(self.media_files) > 0

    def __repr__(self):
        return f"<ChatMessage(msgid='{self.msgid}', type='{self.msgtype}')>"


class ChatMember(Base):
    """群成员模型"""
    __tablename__ = "chat_members"

    id = Column(Integer, primary_key=True, autoincrement=True)
    roomid = Column(String(100), ForeignKey("chat_groups.roomid"), nullable=False, index=True)
    userid = Column(String(100), nullable=False, index=True)
    user_name = Column(String(255))
    join_time = Column(DateTime(timezone=True), nullable=False, index=True)
    quit_time = Column(DateTime(timezone=True))
    member_type = Column(Enum(MemberType), default=MemberType.MEMBER, index=True)
    inviter = Column(String(100))
    is_active = Column(Boolean, default=True, index=True)
    last_seen = Column(DateTime(timezone=True))
    message_count = Column(Integer, default=0)
    metadata = Column(JSONB, default=dict)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    # 关系
    group = relationship("ChatGroup", back_populates="members")

    # 索引
    __table_args__ = (
        Index('idx_members_composite', 'roomid', 'is_active', 'member_type'),
        Index('idx_members_unique', 'roomid', 'userid', 'join_time', unique=True),
    )

    @hybrid_property
    def is_admin_or_owner(self):
        """是否为管理员或群主"""
        return self.member_type in [MemberType.ADMIN, MemberType.OWNER]

    def __repr__(self):
        return f"<ChatMember(userid='{self.userid}', roomid='{self.roomid}')>"


class MediaFile(Base):
    """媒体文件模型"""
    __tablename__ = "media_files"

    id = Column(Integer, primary_key=True, autoincrement=True)
    msgid = Column(String(100), ForeignKey("chat_messages.msgid"), nullable=False, index=True)
    file_type = Column(String(20), nullable=False, index=True)
    file_name = Column(String(255))
    original_filename = Column(String(255))
    file_url = Column(Text)
    local_path = Column(Text)
    file_size = Column(BigInteger, index=True)
    file_extension = Column(String(10))
    mime_type = Column(String(100))
    md5 = Column(String(32), index=True)
    metadata = Column(JSONB, default=dict)
    download_status = Column(Enum(DownloadStatus), default=DownloadStatus.PENDING, index=True)
    download_attempts = Column(Integer, default=0)
    error_message = Column(Text)
    downloaded_at = Column(DateTime(timezone=True))
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, index=True)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    # 关系
    message = relationship("ChatMessage", back_populates="media_files")

    @hybrid_property
    def is_downloaded(self):
        """是否已下载"""
        return self.download_status == DownloadStatus.COMPLETED

    @hybrid_property
    def file_size_mb(self):
        """文件大小（MB）"""
        if self.file_size:
            return round(self.file_size / 1024 / 1024, 2)
        return 0

    def __repr__(self):
        return f"<MediaFile(id={self.id}, type='{self.file_type}', status='{self.download_status}')>"


class SyncTask(Base):
    """同步任务模型"""
    __tablename__ = "sync_tasks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    task_id = Column(String(100), unique=True, nullable=False, index=True)
    roomid = Column(String(100), ForeignKey("chat_groups.roomid"), index=True)
    task_type = Column(String(50), nullable=False, default="sync_messages", index=True)
    status = Column(String(20), nullable=False, default="pending", index=True)
    start_time = Column(DateTime(timezone=True))
    end_time = Column(DateTime(timezone=True))
    progress = Column(Integer, default=0)
    total_count = Column(Integer, default=0)
    success_count = Column(Integer, default=0)
    error_count = Column(Integer, default=0)
    error_message = Column(Text)
    metadata = Column(JSONB, default=dict)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, index=True)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    # 关系
    group = relationship("ChatGroup", back_populates="sync_tasks")

    @hybrid_property
    def progress_percentage(self):
        """进度百分比"""
        if self.total_count and self.total_count > 0:
            return round((self.progress / self.total_count) * 100, 2)
        return 0

    @hybrid_property
    def duration(self):
        """任务持续时间"""
        if self.start_time and self.end_time:
            return self.end_time - self.start_time
        return None

    def __repr__(self):
        return f"<SyncTask(task_id='{self.task_id}', status='{self.status}')>"


class AuditLog(Base):
    """审计日志模型"""
    __tablename__ = "audit_logs"

    id = Column(BigInteger, primary_key=True, autoincrement=True)
    user_id = Column(String(100), index=True)
    action = Column(String(100), nullable=False, index=True)
    resource_type = Column(String(50), index=True)
    resource_id = Column(String(100), index=True)
    details = Column(JSONB, default=dict)
    ip_address = Column(INET)
    user_agent = Column(Text)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow, index=True)

    # 索引
    __table_args__ = (
        Index('idx_audit_logs_resource', 'resource_type', 'resource_id'),
        Index('idx_audit_logs_user_action', 'user_id', 'action'),
    )

    def __repr__(self):
        return f"<AuditLog(id={self.id}, action='{self.action}')>"


class SystemConfig(Base):
    """系统配置模型"""
    __tablename__ = "system_configs"

    key = Column(String(100), primary_key=True)
    value = Column(Text)
    description = Column(Text)
    config_type = Column(String(20), default="string")
    is_encrypted = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), default=datetime.utcnow)
    updated_at = Column(DateTime(timezone=True), default=datetime.utcnow, onupdate=datetime.utcnow)

    def get_typed_value(self):
        """获取类型化的值"""
        if self.config_type == "integer":
            return int(self.value) if self.value else 0
        elif self.config_type == "float":
            return float(self.value) if self.value else 0.0
        elif self.config_type == "boolean":
            return self.value.lower() in ("true", "1", "yes") if self.value else False
        elif self.config_type == "json":
            import json
            return json.loads(self.value) if self.value else {}
        else:
            return self.value

    def __repr__(self):
        return f"<SystemConfig(key='{self.key}', type='{self.config_type}')>"