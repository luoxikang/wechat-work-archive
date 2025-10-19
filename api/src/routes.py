"""
API 路由定义

定义所有的API端点和路由。
"""

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List, Optional
import structlog

from .database import get_db, check_database_health
from .schemas import (
    GroupResponse, GroupListResponse, MessageResponse, MessageListResponse,
    SyncTaskRequest, SyncTaskResponse, HealthResponse
)
from .services.group_service import GroupService
from .services.message_service import MessageService
from .services.sync_service import SyncService

logger = structlog.get_logger()

# 健康检查路由
health_router = APIRouter()

# API路由
api_router = APIRouter()


@health_router.get("/health", response_model=HealthResponse)
async def health_check():
    """健康检查端点"""
    try:
        # 检查数据库连接
        db_healthy = await check_database_health()

        # 检查Redis连接（如果需要）
        # redis_healthy = await check_redis_health()

        # TODO: 添加其他服务健康检查

        if db_healthy:
            return HealthResponse(
                status="healthy",
                services={
                    "database": "connected",
                    "api": "running"
                }
            )
        else:
            return JSONResponse(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                content={
                    "status": "unhealthy",
                    "services": {
                        "database": "disconnected",
                        "api": "running"
                    }
                }
            )
    except Exception as e:
        logger.error("Health check failed", error=str(e))
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "status": "error",
                "error": str(e)
            }
        )


@api_router.get("/groups", response_model=GroupListResponse)
async def get_groups(
    page: int = Query(1, ge=1, description="页码"),
    size: int = Query(20, ge=1, le=100, description="每页数量"),
    keyword: Optional[str] = Query(None, description="搜索关键词"),
    is_active: Optional[bool] = Query(None, description="是否活跃"),
    db: AsyncSession = Depends(get_db)
):
    """获取群组列表"""
    try:
        group_service = GroupService(db)
        result = await group_service.get_groups(
            page=page,
            size=size,
            keyword=keyword,
            is_active=is_active
        )
        return result
    except Exception as e:
        logger.error("Failed to get groups", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="获取群组列表失败"
        )


@api_router.get("/groups/{roomid}", response_model=GroupResponse)
async def get_group(
    roomid: str,
    db: AsyncSession = Depends(get_db)
):
    """获取群组详情"""
    try:
        group_service = GroupService(db)
        group = await group_service.get_group_by_id(roomid)
        if not group:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="群组不存在"
            )
        return group
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get group", roomid=roomid, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="获取群组详情失败"
        )


@api_router.get("/groups/{roomid}/messages", response_model=MessageListResponse)
async def get_group_messages(
    roomid: str,
    page: int = Query(1, ge=1, description="页码"),
    size: int = Query(50, ge=1, le=200, description="每页数量"),
    start_time: Optional[str] = Query(None, description="开始时间 (ISO格式)"),
    end_time: Optional[str] = Query(None, description="结束时间 (ISO格式)"),
    msgtype: Optional[str] = Query(None, description="消息类型"),
    from_user: Optional[str] = Query(None, description="发送者"),
    keyword: Optional[str] = Query(None, description="搜索关键词"),
    db: AsyncSession = Depends(get_db)
):
    """获取群组消息"""
    try:
        message_service = MessageService(db)
        result = await message_service.get_messages_by_room(
            roomid=roomid,
            page=page,
            size=size,
            start_time=start_time,
            end_time=end_time,
            msgtype=msgtype,
            from_user=from_user,
            keyword=keyword
        )
        return result
    except Exception as e:
        logger.error("Failed to get messages", roomid=roomid, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="获取群组消息失败"
        )


@api_router.get("/messages/{msgid}", response_model=MessageResponse)
async def get_message(
    msgid: str,
    db: AsyncSession = Depends(get_db)
):
    """获取消息详情"""
    try:
        message_service = MessageService(db)
        message = await message_service.get_message_by_id(msgid)
        if not message:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="消息不存在"
            )
        return message
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get message", msgid=msgid, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="获取消息详情失败"
        )


@api_router.post("/sync", response_model=SyncTaskResponse)
async def sync_messages(
    request: SyncTaskRequest,
    db: AsyncSession = Depends(get_db)
):
    """手动同步消息"""
    try:
        sync_service = SyncService(db)
        task = await sync_service.create_sync_task(
            roomid=request.roomid,
            start_time=request.start_time,
            end_time=request.end_time
        )
        return task
    except Exception as e:
        logger.error("Failed to create sync task", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="创建同步任务失败"
        )


@api_router.get("/sync/tasks/{task_id}", response_model=SyncTaskResponse)
async def get_sync_task(
    task_id: str,
    db: AsyncSession = Depends(get_db)
):
    """获取同步任务状态"""
    try:
        sync_service = SyncService(db)
        task = await sync_service.get_task_by_id(task_id)
        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="同步任务不存在"
            )
        return task
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to get sync task", task_id=task_id, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="获取同步任务失败"
        )


@api_router.get("/sync/tasks")
async def get_sync_tasks(
    page: int = Query(1, ge=1, description="页码"),
    size: int = Query(20, ge=1, le=100, description="每页数量"),
    status: Optional[str] = Query(None, description="任务状态"),
    roomid: Optional[str] = Query(None, description="群组ID"),
    db: AsyncSession = Depends(get_db)
):
    """获取同步任务列表"""
    try:
        sync_service = SyncService(db)
        result = await sync_service.get_tasks(
            page=page,
            size=size,
            status=status,
            roomid=roomid
        )
        return result
    except Exception as e:
        logger.error("Failed to get sync tasks", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="获取同步任务列表失败"
        )


@api_router.delete("/sync/tasks/{task_id}")
async def cancel_sync_task(
    task_id: str,
    db: AsyncSession = Depends(get_db)
):
    """取消同步任务"""
    try:
        sync_service = SyncService(db)
        success = await sync_service.cancel_task(task_id)
        if not success:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="同步任务不存在或无法取消"
            )
        return {"message": "同步任务已取消"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error("Failed to cancel sync task", task_id=task_id, error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="取消同步任务失败"
        )


@api_router.get("/stats/groups")
async def get_group_stats(
    db: AsyncSession = Depends(get_db)
):
    """获取群组统计信息"""
    try:
        group_service = GroupService(db)
        stats = await group_service.get_group_stats()
        return stats
    except Exception as e:
        logger.error("Failed to get group stats", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="获取群组统计失败"
        )


@api_router.get("/stats/messages")
async def get_message_stats(
    roomid: Optional[str] = Query(None, description="群组ID"),
    days: int = Query(7, ge=1, le=365, description="统计天数"),
    db: AsyncSession = Depends(get_db)
):
    """获取消息统计信息"""
    try:
        message_service = MessageService(db)
        stats = await message_service.get_message_stats(
            roomid=roomid,
            days=days
        )
        return stats
    except Exception as e:
        logger.error("Failed to get message stats", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="获取消息统计失败"
        )


@api_router.get("/search/messages")
async def search_messages(
    q: str = Query(..., description="搜索关键词"),
    page: int = Query(1, ge=1, description="页码"),
    size: int = Query(20, ge=1, le=100, description="每页数量"),
    roomid: Optional[str] = Query(None, description="群组ID"),
    msgtype: Optional[str] = Query(None, description="消息类型"),
    start_time: Optional[str] = Query(None, description="开始时间"),
    end_time: Optional[str] = Query(None, description="结束时间"),
    db: AsyncSession = Depends(get_db)
):
    """搜索消息"""
    try:
        message_service = MessageService(db)
        result = await message_service.search_messages(
            keyword=q,
            page=page,
            size=size,
            roomid=roomid,
            msgtype=msgtype,
            start_time=start_time,
            end_time=end_time
        )
        return result
    except Exception as e:
        logger.error("Failed to search messages", error=str(e))
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="搜索消息失败"
        )