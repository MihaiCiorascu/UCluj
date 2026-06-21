import os
import json
import uuid
import shutil
from typing import List
from datetime import datetime
from pydantic import BaseModel

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc

from db.engine import async_session as session_factory
from db.models import Message, User, ChatGroup
from core.security import get_current_user
from services.ws_fanout_service import push_to_channel, push_to_users
from services import avatar_service

router = APIRouter(prefix="/chat", tags=["chat"])


async def _get_db():
    async with session_factory() as session:
        yield session


async def enforce_message_limit(session: AsyncSession, channel_id: str, limit: int = 50):
    # Fetch all message IDs ordered by newest first
    stmt = select(Message).where(Message.channel_id == channel_id).order_by(desc(Message.created_at))
    result = await session.execute(stmt)
    all_msgs = result.scalars().all()

    # If we have more than limit, delete the older ones
    if len(all_msgs) > limit:
        msgs_to_delete = all_msgs[limit:]
        for msg in msgs_to_delete:
            await session.delete(msg)
        await session.commit()


async def _assert_channel_access(session: AsyncSession, user: User, channel_id: str) -> None:
    """Authorize the user for a chat channel.

    The user must belong to a team. Group channels (``group_<uuid>``) require the
    user to be a member of that group. Mirrors the membership check the retired
    WebSocket handler used to perform on $connect.
    """
    if not user.team_name:
        raise HTTPException(status_code=403, detail="User must belong to a team")

    if channel_id.startswith("group_"):
        group_uuid = channel_id.replace("group_", "")
        res = await session.execute(select(ChatGroup).where(ChatGroup.id == group_uuid))
        group = res.scalar_one_or_none()
        if not group:
            raise HTTPException(status_code=404, detail="Group not found")
        try:
            members = json.loads(group.member_ids)
        except Exception:
            members = []
        if user.id not in members:
            raise HTTPException(status_code=403, detail="Not a member of this group")


class SendMessageRequest(BaseModel):
    content: str | None = None
    file_url: str | None = None
    file_type: str | None = None


@router.post("/{channel_id}/send")
async def send_message(
    channel_id: str,
    body: SendMessageRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(_get_db),
):
    """Persist a chat message and fan it out to live WebSocket connections.

    Replaces the App-Runner-incompatible FastAPI WebSocket send path. The message
    is written to RDS (reusing the Message model + 50-message cap), then pushed to
    every connection on the channel via the API Gateway Management API, including
    the author's avatar so it renders beside the bubble.
    """
    await _assert_channel_access(session, current_user, channel_id)

    if not (body.content and body.content.strip()) and not body.file_url:
        raise HTTPException(status_code=400, detail="Message must have content or a file")

    author_name = (
        (current_user.full_name.strip() if current_user.full_name and current_user.full_name.strip() else None)
        or current_user.email.split("@")[0]
    )

    new_msg = Message(
        team_name=current_user.team_name,
        channel_id=channel_id,
        author_id=current_user.id,
        author_name=author_name,
        content=body.content,
        file_url=body.file_url,
        file_type=body.file_type,
    )
    session.add(new_msg)
    await session.commit()
    await session.refresh(new_msg)

    # Trim history to the most recent 50 messages on this channel.
    await enforce_message_limit(session, channel_id, 50)

    payload = {
        "id": new_msg.id,
        "channel_id": new_msg.channel_id,
        "author_id": new_msg.author_id,
        "author_name": new_msg.author_name,
        "author_avatar_url": current_user.avatar_url,
        "content": new_msg.content,
        "file_url": new_msg.file_url,
        "file_type": new_msg.file_type,
        "created_at": new_msg.created_at.isoformat() if new_msg.created_at else None,
    }

    # Instant delivery to everyone currently on the channel. Fan-out failures are
    # swallowed inside the service; the message is persisted and will be picked up
    # by the history endpoint on the next load/reconnect regardless.
    await push_to_channel(channel_id, payload)

    return payload


@router.post("/{channel_id}/typing")
async def signal_typing(
    channel_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(_get_db),
):
    """Broadcast an ephemeral "typing" signal to the rest of the channel.

    Unlike ``/send``, this persists nothing: it only fans a transient marker out
    over the same API Gateway WebSocket path so other participants can show a
    "<name> is typing" hint. The ``type: "typing"`` field distinguishes it from
    real messages (which carry no ``type``); the receiving client drops typing
    frames from the message list and ignores its own. Author derivation mirrors
    ``/send`` (full name when present, else the email local-part).
    """
    await _assert_channel_access(session, current_user, channel_id)

    author_name = (
        (current_user.full_name.strip() if current_user.full_name and current_user.full_name.strip() else None)
        or current_user.email.split("@")[0]
    )

    await push_to_channel(
        channel_id,
        {
            "type": "typing",
            "author_id": current_user.id,
            "author_name": author_name,
            "channel_id": channel_id,
        },
    )

    return {"ok": True}


@router.get("/{channel_id}/messages")
async def get_channel_messages(
    channel_id: str,
    since: str | None = None,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(_get_db),
):
    """Return channel history (oldest -> newest) including the author's avatar.

    Used for initial load and reconnect gap-fill. ``since`` is an optional ISO-8601
    timestamp; when provided, only messages strictly newer than it are returned.
    Each message's ``author_avatar_url`` is joined from the author's user row.
    """
    await _assert_channel_access(session, current_user, channel_id)

    stmt = (
        select(Message, User.avatar_url)
        .outerjoin(User, User.id == Message.author_id)
        .where(Message.channel_id == channel_id)
    )
    if since:
        try:
            since_dt = datetime.fromisoformat(since)
        except ValueError:
            raise HTTPException(status_code=400, detail="`since` must be an ISO-8601 timestamp")
        stmt = stmt.where(Message.created_at > since_dt)
    stmt = stmt.order_by(Message.created_at)

    result = await session.execute(stmt)
    rows = result.all()

    return [
        {
            "id": msg.id,
            "channel_id": msg.channel_id,
            "author_id": msg.author_id,
            "author_name": msg.author_name,
            "author_avatar_url": avatar_url,
            "content": msg.content,
            "file_url": msg.file_url,
            "file_type": msg.file_type,
            "created_at": msg.created_at.isoformat() if msg.created_at else None,
        }
        for msg, avatar_url in rows
    ]


@router.get("/users")
async def get_team_users(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(_get_db)
):
    if not current_user.team_name:
        return []

    stmt = select(User).where(
        User.team_name == current_user.team_name,
        User.id != current_user.id
    )
    result = await session.execute(stmt)
    users = result.scalars().all()

    return [
        {
            "id": u.id,
            "email": u.email,
            "full_name": u.full_name,
            "role": u.role,
            "avatar_url": u.avatar_url,
        } for u in users
    ]


class CreateGroupRequest(BaseModel):
    name: str
    member_ids: List[str]


@router.post("/groups")
async def create_chat_group(
    req: CreateGroupRequest,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(_get_db)
):
    if not current_user.team_name:
        raise HTTPException(status_code=400, detail="User must belong to a team")

    members = set(req.member_ids)
    members.add(current_user.id)

    member_ids_str = json.dumps(list(members))

    new_group = ChatGroup(
        team_name=current_user.team_name,
        name=req.name,
        member_ids=member_ids_str
    )
    session.add(new_group)
    await session.commit()
    await session.refresh(new_group)

    member_list = list(members)
    # Push the new group to every member's live connection so it appears for them
    # immediately, whatever channel they are currently viewing, instead of only
    # after their next reload. Best effort: a transport hiccup never fails create,
    # and GET /chat/groups still back-fills it on the next load.
    await push_to_users(member_list, {
        "type": "group_created",
        "group": {
            "id": new_group.id,
            "name": new_group.name,
            "member_ids": member_list,
        },
    })
    return {"id": new_group.id, "name": new_group.name, "member_ids": member_list}


@router.get("/groups")
async def get_chat_groups(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(_get_db)
):
    if not current_user.team_name:
        return []

    stmt = select(ChatGroup).where(ChatGroup.team_name == current_user.team_name)
    result = await session.execute(stmt)
    all_groups = result.scalars().all()

    user_groups = []
    for g in all_groups:
        try:
            members = json.loads(g.member_ids)
            if current_user.id in members:
                user_groups.append({
                    "id": g.id,
                    "name": g.name,
                    "member_ids": members
                })
        except Exception:
            pass
    return user_groups


# Ephemeral chat file sharing (unchanged): small attachments still land on the
# App Runner local disk and are served from /uploads. This is unrelated to the
# retired WebSocket transport and the durable S3 avatar storage; the frontend
# chat composer still POSTs here.
UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)


@router.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    ext = os.path.splitext(file.filename or "")[1]
    data = await file.read()

    # Durable S3 storage (reuses the avatars bucket under avatars/chat/) so chat
    # images survive App Runner redeploys. Fall back to the ephemeral local disk
    # only when S3 is unconfigured or the upload fails, preserving old behaviour.
    if avatar_service.chat_files_enabled():
        try:
            url = avatar_service.upload_chat_file(data, file.content_type or "", ext)
            return {"url": url, "type": file.content_type}
        except Exception:
            pass

    file_id = str(uuid.uuid4())
    filename = f"{file_id}{ext}"
    file_path = os.path.join(UPLOAD_DIR, filename)
    with open(file_path, "wb") as buffer:
        buffer.write(data)

    return {"url": f"/uploads/{filename}", "type": file.content_type}
