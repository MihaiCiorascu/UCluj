from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import settings

engine = create_async_engine(settings.database_url, echo=False)

async_session = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)


async def init_db():
    from db.models import Base
    import sportradar.db_models  # noqa: F401, registers sr_* tables with Base.metadata
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
