"""Server settings, read from environment variables or a .env file."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

VERSION = "2.0.0"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Shown in the app when someone enters this server's address.
    server_name: str = "CodeNote server"
    # postgresql+asyncpg://user:pass@host/db, or SQLite for a quick try.
    database_url: str = "sqlite+aiosqlite:///./codenote.db"
    # Signs sign-in tokens. Set a long random value in production.
    secret_key: str = "change-me"
    access_minutes: int = 30
    refresh_days: int = 60

    # Where uploaded pictures are kept, and the address the app uses to load
    # them (leave empty to use the address of each request).
    upload_dir: str = "./uploads"
    public_url: str = ""
    max_upload_mb: int = 15

    # Google sign-in: the OAuth client ids allowed (comma separated).
    google_client_ids: str = ""

    # Push: a Firebase service account JSON file (Firebase console >
    # Project settings > Service accounts > Generate new private key).
    fcm_service_account_file: str = ""

    # Email for verification and password reset codes. Without SMTP the
    # codes are written to the server log.
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    require_email_verification: bool = False

    # Extra admins by email (comma separated). The first account is always
    # an admin.
    admin_emails: str = ""
    cors_origins: str = "*"
    # Slows down password guessing. Only turned off for tests.
    rate_limit: bool = True

    @property
    def google_ids(self) -> list[str]:
        return [s.strip() for s in self.google_client_ids.split(",") if s.strip()]

    @property
    def admin_list(self) -> set[str]:
        return {s.strip().lower() for s in self.admin_emails.split(",") if s.strip()}

    @property
    def smtp_enabled(self) -> bool:
        return bool(self.smtp_host and self.smtp_from)


@lru_cache
def get_settings() -> Settings:
    return Settings()
