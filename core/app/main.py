"""StarLight Core HTTP entrypoint.

Run with::

    uvicorn app.main:app --host 127.0.0.1 --port 8765

The lifespan owns the BLE manager: it connects on startup when a device is
configured and always closes cleanly, so ``stop``/``restart`` from systemd
leaves no half-open link. It deliberately does *not* fail startup when the
controller is missing - the service must come up so clients get a clear error
and the reconnect path can take over later.

Every failure leaves as JSON of the same shape::

    {"success": false, "error": "<code>", "message": "...", "details": {...}}
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from typing import AsyncIterator

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app import __version__
from app.api import devices, lights, scenes
from app.api.schemas import ErrorOut, LightStateOut
from app.ble.manager import BleManager
from app.config.settings import Settings
from app.errors import (
    BleError,
    CharacteristicNotFoundError,
    DeviceNotFoundError,
    FeatureNotAvailableError,
    NotConnectedError,
    ServiceNotFoundError,
    StarLightError,
    UnsupportedEffectError,
    WriteTimeoutError,
)
from app.services.light_service import LightService

logger = logging.getLogger(__name__)

# Exception -> (status, error code). Ordered most specific first.
ERROR_MAP: list[tuple[type[Exception], int, str]] = [
    (DeviceNotFoundError, status.HTTP_404_NOT_FOUND, "device_not_found"),
    (NotConnectedError, status.HTTP_503_SERVICE_UNAVAILABLE, "not_connected"),
    (WriteTimeoutError, status.HTTP_504_GATEWAY_TIMEOUT, "write_timeout"),
    (ServiceNotFoundError, status.HTTP_502_BAD_GATEWAY, "service_not_found"),
    (
        CharacteristicNotFoundError,
        status.HTTP_502_BAD_GATEWAY,
        "characteristic_not_found",
    ),
    (UnsupportedEffectError, status.HTTP_501_NOT_IMPLEMENTED, "unsupported_effect"),
    (FeatureNotAvailableError, status.HTTP_501_NOT_IMPLEMENTED, "not_implemented"),
    (BleError, status.HTTP_503_SERVICE_UNAVAILABLE, "ble_error"),
    (StarLightError, status.HTTP_500_INTERNAL_SERVER_ERROR, "starlight_error"),
]


def _details(exc: Exception) -> dict[str, object] | None:
    """Extra context a caller can act on, when the error carries any."""
    if isinstance(exc, (ServiceNotFoundError, CharacteristicNotFoundError)):
        return {"wanted": exc.wanted, "available": exc.available}
    if isinstance(exc, FeatureNotAvailableError):
        return {"feature": exc.feature, "reason": exc.reason}
    if isinstance(exc, UnsupportedEffectError):
        return {"effect": exc.name}
    return None


def install_error_handlers(app: FastAPI) -> None:
    """Maps the domain exceptions onto status codes and one JSON shape."""

    for exception_type, code, error_code in ERROR_MAP:

        async def handler(
            _request: Request,
            exc: Exception,
            _code: int = code,
            _error_code: str = error_code,
        ) -> JSONResponse:
            return JSONResponse(
                status_code=_code,
                content=ErrorOut(
                    error=_error_code,
                    message=str(exc),
                    details=_details(exc),
                ).model_dump(),
            )

        app.add_exception_handler(exception_type, handler)

    @app.exception_handler(RequestValidationError)
    async def validation_handler(
        _request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        # FastAPI's default is {"detail": [...]}. Clients should not have to
        # handle two error shapes, so validation is folded into the same one.
        problems = [
            {
                "field": ".".join(str(part) for part in error.get("loc", ())[1:]),
                "message": error.get("msg", "invalid value"),
            }
            for error in exc.errors()
        ]
        return JSONResponse(
            # Literal 422: the starlette constant for it was renamed across
            # versions (UNPROCESSABLE_ENTITY -> UNPROCESSABLE_CONTENT).
            status_code=422,
            content=ErrorOut(
                error="validation_error",
                message="request body failed validation",
                details={"problems": problems},
            ).model_dump(),
        )

    @app.exception_handler(ValueError)
    async def value_error_handler(_request: Request, exc: ValueError) -> JSONResponse:
        # e.g. a malformed hex color that slipped past validation.
        return JSONResponse(
            status_code=status.HTTP_400_BAD_REQUEST,
            content=ErrorOut(error="invalid_value", message=str(exc)).model_dump(),
        )


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Connects on startup when configured, and always cleans up."""
    settings: Settings = app.state.settings
    manager: BleManager = app.state.manager
    service: LightService = app.state.service

    # A pre-bound service (tests, or an embedding host) means someone else owns
    # the transport; leave it alone.
    if settings.auto_connect and service.transport is None:
        try:
            device = await manager.connect()
            service.bind(device.transport, device.id)
            manager.watch(device.id)
            logger.info("bound to %s", device.id)
        except Exception as exc:
            logger.warning("startup connect failed: %s", exc)

    try:
        yield
    finally:
        await manager.close()


def create_app(
    settings: Settings | None = None,
    manager: BleManager | None = None,
    service: LightService | None = None,
) -> FastAPI:
    """Application factory.

    ``manager`` and ``service`` are injectable so the API can be exercised
    against a fake transport, with no BLE stack or hardware involved.
    """
    settings = settings or Settings.from_env()

    app = FastAPI(title="StarLight Core", version=__version__, lifespan=lifespan)
    app.state.settings = settings
    app.state.manager = manager or BleManager(settings)
    app.state.service = service or LightService()

    install_error_handlers(app)
    app.include_router(lights.router)
    app.include_router(devices.router)
    app.include_router(scenes.router)

    @app.get("/health", tags=["health"])
    async def health(request: Request) -> dict[str, object]:
        """Liveness plus a compact view of the link and light state.

        The light block uses the same shape as ``/light/state`` so a client can
        reuse one parser.
        """
        service: LightService = request.app.state.service
        manager: BleManager = request.app.state.manager
        return {
            "status": "ok",
            "version": __version__,
            "devices": [device.model_dump() for device in manager.devices],
            "light": LightStateOut.from_state(service.state).model_dump(),
        }

    return app


app = create_app()
