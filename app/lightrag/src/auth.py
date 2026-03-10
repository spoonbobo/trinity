import logging

from fastapi import Header, HTTPException, status

from .config import get_settings
from .schemas import RequestScope
from .workspace import build_claw_workspace_id, normalize_workspace_part

logger = logging.getLogger(__name__)
_workspace_variant_warnings: set[str] = set()


def _warn_workspace_variants(tenant_id: str, openclaw_id: str) -> None:
    settings = get_settings()
    workspaces_dir = settings.data_dir / "workspaces"
    if not workspaces_dir.exists():
        return

    claw_suffix = f"__claw_{normalize_workspace_part(openclaw_id)}"
    candidates = sorted(
        path.name
        for path in workspaces_dir.iterdir()
        if path.is_dir() and path.name.endswith(claw_suffix)
    )

    if len(candidates) <= 1:
        return

    canonical = build_claw_workspace_id(tenant_id, openclaw_id)
    warning_key = f"{canonical}|{'|'.join(candidates)}"
    if warning_key in _workspace_variant_warnings:
        return

    _workspace_variant_warnings.add(warning_key)
    logger.warning(
        "Multiple workspace variants detected for openclaw=%s canonical=%s variants=%s",
        openclaw_id,
        canonical,
        candidates,
    )


def require_scope(
    authorization: str | None = Header(default=None),
    x_trinity_tenant: str | None = Header(default=None),
    x_trinity_workspace: str | None = Header(default=None),
    x_trinity_user: str | None = Header(default=None),
    x_trinity_openclaw: str | None = Header(default=None),
) -> RequestScope:
    settings = get_settings()
    expected = settings.internal_token.strip()
    if not expected:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="LIGHTRAG_INTERNAL_TOKEN is not configured",
        )

    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )

    token = authorization.removeprefix("Bearer ").strip()
    if token != expected:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid internal token",
        )

    if not x_trinity_tenant or not x_trinity_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Trinity tenant or user headers",
        )

    derived_workspace = None
    if x_trinity_openclaw:
        derived_workspace = build_claw_workspace_id(x_trinity_tenant, x_trinity_openclaw)
        _warn_workspace_variants(x_trinity_tenant, x_trinity_openclaw)

    if derived_workspace and x_trinity_workspace and x_trinity_workspace != derived_workspace:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Workspace does not match derived claw workspace",
        )

    effective_workspace = derived_workspace or x_trinity_workspace
    if not effective_workspace:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing Trinity workspace or openclaw headers",
        )

    return RequestScope(
        tenant_id=x_trinity_tenant,
        workspace_id=effective_workspace,
        user_id=x_trinity_user,
        openclaw_id=x_trinity_openclaw,
    )
