"""
API 数据模式定义

使用 Pydantic 定义请求和响应的数据模式。
"""

from datetime import datetime
from typing import Any, Dict, List, Optional, Union
from pydantic import BaseModel, Field, validator
from enum import Enum


# 枚举类型
class MessageTypeEnum(str, Enum):
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


class MemberTypeEnum(str, Enum):
    OWNER = "owner"
    ADMIN = "admin"
    MEMBER = "member"


class TaskStatusEnum(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class DownloadStatusEnum(str, Enum):
    PENDING = "pending"
    DOWNLOADING = "downloading"
    COMPLETED = "completed"
    FAILED = "failed"


# 基础响应模式
class BaseResponse(BaseModel):
    """基础响应模式"""
    success: bool = True
    message: str = "操作成功"
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class PaginationMeta(BaseModel):
    """分页元数据"""
    page: int = Field(..., description="当前页码")
    size: int = Field(..., description="每页数量")
    total: int = Field(..., description="总数量")
    pages: int = Field(..., description="总页数")
    has_next: bool = Field(..., description="是否有下一页")
    has_prev: bool = Field(..., description="是否有上一页")


class PaginatedResponse(BaseResponse):
    """分页响应基类"""
    meta: PaginationMeta


# 群组相关模式
class GroupBase(BaseModel):
    """群组基础模式"""
    roomid: str = Field(..., description="群组ID")
    room_name: str = Field(..., description="群组名称")
    creator: Optional[str] = Field(None, description="创建者")
    notice: Optional[str] = Field(None, description="群公告")
    owner_corpid: str = Field(..., description="企业ID")


class GroupCreate(GroupBase):
    """创建群组请求模式"""
    create_time: Optional[datetime] = Field(None, description="创建时间")
    metadata: Optional[Dict[str, Any]] = Field(default_factory=dict, description="元数据")


class GroupUpdate(BaseModel):
    """更新群组请求模式"""
    room_name: Optional[str] = Field(None, description="群组名称")
    notice: Optional[str] = Field(None, description="群公告")
    is_active: Optional[bool] = Field(None, description="是否活跃")
    metadata: Optional[Dict[str, Any]] = Field(None, description="元数据")


class GroupResponse(GroupBase):
    """群组响应模式"""
    create_time: Optional[datetime] = Field(None, description="创建时间")
    member_count: int = Field(0, description="成员数量")
    is_active: bool = Field(True, description="是否活跃")
    last_sync_time: Optional[datetime] = Field(None, description="最后同步时间")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="元数据")
    created_at: datetime = Field(..., description="记录创建时间")
    updated_at: datetime = Field(..., description="记录更新时间")

    class Config:
        from_attributes = True


class GroupListResponse(PaginatedResponse):
    """群组列表响应模式"""
    data: List[GroupResponse] = Field(..., description="群组列表")


# 消息相关模式
class MediaFileResponse(BaseModel):
    """媒体文件响应模式"""
    id: int = Field(..., description="文件ID")
    file_type: str = Field(..., description="文件类型")
    file_name: Optional[str] = Field(None, description="文件名")
    original_filename: Optional[str] = Field(None, description="原始文件名")
    file_size: Optional[int] = Field(None, description="文件大小")
    file_extension: Optional[str] = Field(None, description="文件扩展名")
    mime_type: Optional[str] = Field(None, description="MIME类型")
    local_path: Optional[str] = Field(None, description="本地路径")
    download_status: DownloadStatusEnum = Field(..., description="下载状态")
    downloaded_at: Optional[datetime] = Field(None, description="下载时间")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="元数据")

    class Config:
        from_attributes = True


class MessageBase(BaseModel):
    """消息基础模式"""
    msgid: str = Field(..., description="消息ID")
    roomid: str = Field(..., description="群组ID")
    msgtype: MessageTypeEnum = Field(..., description="消息类型")
    msgtime: datetime = Field(..., description="消息时间")
    from_user: Optional[str] = Field(None, description="发送者")
    content: Optional[str] = Field(None, description="消息内容")


class MessageCreate(MessageBase):
    """创建消息请求模式"""
    seq: int = Field(..., description="消息序号")
    to_users: Optional[List[str]] = Field(None, description="接收者列表")
    media_data: Optional[Dict[str, Any]] = Field(default_factory=dict, description="媒体数据")
    raw_data: Optional[Dict[str, Any]] = Field(default_factory=dict, description="原始数据")
    reply_to_msgid: Optional[str] = Field(None, description="回复的消息ID")


class MessageResponse(MessageBase):
    """消息响应模式"""
    id: int = Field(..., description="消息主键ID")
    seq: int = Field(..., description="消息序号")
    to_users: Optional[List[str]] = Field(None, description="接收者列表")
    media_data: Dict[str, Any] = Field(default_factory=dict, description="媒体数据")
    is_revoked: bool = Field(False, description="是否已撤回")
    revoke_time: Optional[datetime] = Field(None, description="撤回时间")
    forward_count: int = Field(0, description="转发次数")
    reply_to_msgid: Optional[str] = Field(None, description="回复的消息ID")
    media_files: List[MediaFileResponse] = Field(default_factory=list, description="媒体文件列表")
    created_at: datetime = Field(..., description="记录创建时间")
    updated_at: datetime = Field(..., description="记录更新时间")

    class Config:
        from_attributes = True


class MessageListResponse(PaginatedResponse):
    """消息列表响应模式"""
    data: List[MessageResponse] = Field(..., description="消息列表")


# 群成员相关模式
class MemberBase(BaseModel):
    """群成员基础模式"""
    roomid: str = Field(..., description="群组ID")
    userid: str = Field(..., description="用户ID")
    user_name: Optional[str] = Field(None, description="用户名")
    member_type: MemberTypeEnum = Field(MemberTypeEnum.MEMBER, description="成员类型")


class MemberResponse(MemberBase):
    """群成员响应模式"""
    id: int = Field(..., description="成员主键ID")
    join_time: datetime = Field(..., description="加入时间")
    quit_time: Optional[datetime] = Field(None, description="退出时间")
    inviter: Optional[str] = Field(None, description="邀请人")
    is_active: bool = Field(True, description="是否活跃")
    last_seen: Optional[datetime] = Field(None, description="最后活跃时间")
    message_count: int = Field(0, description="消息数量")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="元数据")
    created_at: datetime = Field(..., description="记录创建时间")

    class Config:
        from_attributes = True


# 同步任务相关模式
class SyncTaskRequest(BaseModel):
    """同步任务请求模式"""
    roomid: Optional[str] = Field(None, description="群组ID，为空则同步所有群组")
    start_time: Optional[datetime] = Field(None, description="开始时间")
    end_time: Optional[datetime] = Field(None, description="结束时间")
    task_type: str = Field("sync_messages", description="任务类型")

    @validator('end_time')
    def end_time_must_be_after_start_time(cls, v, values):
        if v and values.get('start_time') and v <= values['start_time']:
            raise ValueError('结束时间必须晚于开始时间')
        return v


class SyncTaskResponse(BaseModel):
    """同步任务响应模式"""
    id: int = Field(..., description="任务主键ID")
    task_id: str = Field(..., description="任务ID")
    roomid: Optional[str] = Field(None, description="群组ID")
    task_type: str = Field(..., description="任务类型")
    status: str = Field(..., description="任务状态")
    start_time: Optional[datetime] = Field(None, description="开始时间")
    end_time: Optional[datetime] = Field(None, description="结束时间")
    progress: int = Field(0, description="进度")
    total_count: int = Field(0, description="总数量")
    success_count: int = Field(0, description="成功数量")
    error_count: int = Field(0, description="错误数量")
    error_message: Optional[str] = Field(None, description="错误信息")
    metadata: Dict[str, Any] = Field(default_factory=dict, description="元数据")
    created_at: datetime = Field(..., description="创建时间")
    updated_at: datetime = Field(..., description="更新时间")

    class Config:
        from_attributes = True


class SyncTaskListResponse(PaginatedResponse):
    """同步任务列表响应模式"""
    data: List[SyncTaskResponse] = Field(..., description="任务列表")


# 统计相关模式
class GroupStats(BaseModel):
    """群组统计模式"""
    total_groups: int = Field(..., description="总群组数")
    active_groups: int = Field(..., description="活跃群组数")
    total_members: int = Field(..., description="总成员数")
    avg_members_per_group: float = Field(..., description="平均每群成员数")


class MessageStats(BaseModel):
    """消息统计模式"""
    total_messages: int = Field(..., description="总消息数")
    messages_by_type: Dict[str, int] = Field(..., description="按类型统计的消息数")
    messages_by_day: List[Dict[str, Union[str, int]]] = Field(..., description="按天统计的消息数")
    top_active_users: List[Dict[str, Union[str, int]]] = Field(..., description="最活跃用户")


class MediaStats(BaseModel):
    """媒体统计模式"""
    total_files: int = Field(..., description="总文件数")
    total_size: int = Field(..., description="总文件大小")
    files_by_type: Dict[str, int] = Field(..., description="按类型统计的文件数")
    download_status: Dict[str, int] = Field(..., description="下载状态统计")


# 搜索相关模式
class SearchRequest(BaseModel):
    """搜索请求模式"""
    keyword: str = Field(..., min_length=1, description="搜索关键词")
    roomid: Optional[str] = Field(None, description="群组ID")
    msgtype: Optional[MessageTypeEnum] = Field(None, description="消息类型")
    start_time: Optional[datetime] = Field(None, description="开始时间")
    end_time: Optional[datetime] = Field(None, description="结束时间")
    from_user: Optional[str] = Field(None, description="发送者")


class SearchResponse(PaginatedResponse):
    """搜索响应模式"""
    data: List[MessageResponse] = Field(..., description="搜索结果")
    keyword: str = Field(..., description="搜索关键词")


# 健康检查模式
class HealthResponse(BaseModel):
    """健康检查响应模式"""
    status: str = Field(..., description="健康状态")
    timestamp: datetime = Field(default_factory=datetime.utcnow, description="检查时间")
    services: Dict[str, str] = Field(..., description="服务状态")
    version: str = Field("1.0.0", description="API版本")


# 错误响应模式
class ErrorResponse(BaseModel):
    """错误响应模式"""
    success: bool = Field(False, description="操作是否成功")
    error_code: str = Field(..., description="错误代码")
    message: str = Field(..., description="错误信息")
    details: Optional[Dict[str, Any]] = Field(None, description="错误详情")
    timestamp: datetime = Field(default_factory=datetime.utcnow, description="错误时间")


# 批量操作模式
class BulkOperationRequest(BaseModel):
    """批量操作请求模式"""
    action: str = Field(..., description="操作类型")
    ids: List[Union[str, int]] = Field(..., min_items=1, description="操作对象ID列表")
    params: Optional[Dict[str, Any]] = Field(None, description="操作参数")


class BulkOperationResponse(BaseModel):
    """批量操作响应模式"""
    total: int = Field(..., description="总操作数")
    success: int = Field(..., description="成功数")
    failed: int = Field(..., description="失败数")
    errors: List[Dict[str, Any]] = Field(default_factory=list, description="错误详情")


# 配置相关模式
class SystemConfigResponse(BaseModel):
    """系统配置响应模式"""
    key: str = Field(..., description="配置键")
    value: str = Field(..., description="配置值")
    description: Optional[str] = Field(None, description="配置描述")
    config_type: str = Field(..., description="配置类型")
    updated_at: datetime = Field(..., description="更新时间")

    class Config:
        from_attributes = True