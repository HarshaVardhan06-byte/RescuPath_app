from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.api import auth, hospitals, emergencies, ws, ambulances, coordination
from app.api.dashboard import router as dashboard_router


app = FastAPI(
    title=settings.app_name,
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_origin_regex=settings.cors_origin_regex if settings.environment == "development" else None,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


app.include_router(auth.router)
app.include_router(hospitals.router)
app.include_router(emergencies.router)
app.include_router(ws.router)
app.include_router(ambulances.router)
app.include_router(dashboard_router)
app.include_router(coordination.router)


@app.get("/health", tags=["System"])
def health():
    return {
        "status": "ok",
        "service": settings.app_name,
        "environment": settings.environment,
    }