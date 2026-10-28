from functools import lru_cache
from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "RescuPath API"
    environment: str = "development"
    debug: bool = False
    database_url: str
    redis_url: str = "redis://localhost:6379/0"
    secret_key: str
    access_token_expire_minutes: int = 30
    cors_origins: str = "http://localhost:3000,http://127.0.0.1:3000,http://localhost:8080,http://127.0.0.1:8080,http://localhost:8694,http://127.0.0.1:8694"
    cors_origin_regex: str | None = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"
    google_routes_api_key: str | None = None
    google_routes_base_url: str = "https://routes.googleapis.com"
    google_web_client_id: str | None = None
    apple_service_id: str | None = None
    apple_issuer: str = "https://appleid.apple.com"
    apple_jwks_url: str = "https://appleid.apple.com/auth/keys"
    smtp_host: str | None = None
    smtp_port: int = 587
    smtp_username: str | None = None
    smtp_password: str | None = None
    smtp_from: str | None = None
    reset_base_url: str = "http://localhost:8080"
    allow_public_operations_registration: bool | None = None

    model_config = SettingsConfigDict(env_file=str(Path(__file__).resolve().parents[2] / ".env"), env_file_encoding="utf-8", case_sensitive=False)

    @property
    def public_operations_registration_enabled(self) -> bool:
        if self.allow_public_operations_registration is not None:
            return self.allow_public_operations_registration
        return self.environment.strip().lower() in {"development", "dev", "local"}

    @property
    def cors_origin_list(self) -> list[str]:
        return [x.strip() for x in self.cors_origins.split(",") if x.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
