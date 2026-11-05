import logging
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.api.routes import router as api_router
from app.services.scanner_service import scanner_service

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("room-sweep-sentinel")

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Gestione del ciclo di vita dell'applicazione (avvio e arresto pulito)."""
    logger.info(f"Avvio di {settings.APP_NAME} v{settings.VERSION}...")
    yield
    logger.info("Arresto in corso: terminazione scansioni attive...")
    if scanner_service.is_scanning:
        await scanner_service.stop_scan()
    logger.info("Chiusura completata con successo.")

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.VERSION,
    description="Sistema di bonifica ambientale e rilevamento microspie Wi-Fi / BLE (Room Sweep Sentinel)",
    lifespan=lifespan
)

# Configurazione Middleware CORS per integrazione con app mobile/desktop
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Endpoint di diagnostica e salute
@app.get("/health", tags=["System"])
async def health_check():
    """Verifica lo stato operativo del servizio backend."""
    return {
        "status": "OK",
        "app": settings.APP_NAME,
        "version": settings.VERSION,
        "scanning": scanner_service.is_scanning
    }

@app.get("/", tags=["System"])
async def root():
    """Punto di ingresso radice con metadati essenziali dell'API."""
    return {
        "service": settings.APP_NAME,
        "version": settings.VERSION,
        "status": "ONLINE",
        "docs_url": "/docs"
    }

# Inclusione delle rotte operative sia sulla radice sia con prefisso /api per massima interoperabilità
app.include_router(api_router)
app.include_router(api_router, prefix="/api")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)
