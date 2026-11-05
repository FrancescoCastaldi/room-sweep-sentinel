from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    APP_NAME: str = "Room Sweep Sentinel API"
    VERSION: str = "1.0.0"
    DEBUG: bool = False
    RSSI_PROXIMITY_THRESHOLD: int = -50  # dBm: values higher than this mean very close
    RSSI_CRITICAL_THRESHOLD: int = -40   # dBm: immediate proximity (within 1 meter)
    DEFAULT_SCAN_DURATION_SEC: int = 15

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

settings = Settings()
