"""Scenes and presets.

These routes exist because the API contract lists them, but their behaviour is
defined by later phases (scenes in Phase 14, presets alongside the existing
Flutter preset storage). Every one answers 501 with a machine-readable code and
a reason, so a client gets a clear "not yet" instead of a misleading 404 that
looks like a broken path.
"""

from __future__ import annotations

from fastapi import APIRouter

from app.api.schemas import ErrorOut, SceneIn
from app.errors import FeatureNotAvailableError

ERROR_RESPONSES = {
    501: {"model": ErrorOut, "description": "Not implemented yet."},
}

router = APIRouter(tags=["scenes"])

_SCENES_REASON = "scene storage and activation arrive in Phase 14"
_PRESETS_REASON = "preset persistence is not exposed over the API yet"


@router.get("/scenes", responses=ERROR_RESPONSES)
async def list_scenes() -> None:
    raise FeatureNotAvailableError("scenes", _SCENES_REASON)


@router.post("/scenes", responses=ERROR_RESPONSES)
async def create_scene(payload: SceneIn) -> None:
    raise FeatureNotAvailableError("scenes", _SCENES_REASON)


@router.delete("/scenes/{name}", responses=ERROR_RESPONSES)
async def delete_scene(name: str) -> None:
    raise FeatureNotAvailableError("scenes", _SCENES_REASON)


@router.get("/presets", responses=ERROR_RESPONSES)
async def list_presets() -> None:
    raise FeatureNotAvailableError("presets", _PRESETS_REASON)


@router.post("/presets", responses=ERROR_RESPONSES)
async def create_preset(payload: SceneIn) -> None:
    raise FeatureNotAvailableError("presets", _PRESETS_REASON)
