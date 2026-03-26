-- Admin-managed OpenClaw instances and user assignments.
-- Used by gateway-orchestrator for multi-tenant pod lifecycle management.

create table if not exists rbac.openclaws (
    id              uuid primary key default gen_random_uuid(),
    name            text not null unique,
    description     text,
    gateway_token   text not null,
    pod_name        text,
    service_name    text,
    pvc_name        text,
    namespace       text not null default 'trinity',
    status          text not null default 'pending'
                    check (status in ('pending', 'provisioning', 'running', 'error', 'deleting')),
    error_message   text,
    port            integer not null default 18789,
    created_by      uuid,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz default now()
);

create table if not exists rbac.openclaw_assignments (
    id              uuid primary key default gen_random_uuid(),
    user_id         uuid not null,
    openclaw_id     uuid not null references rbac.openclaws(id) on delete cascade,
    assigned_by     uuid,
    assigned_at     timestamptz not null default now(),
    unique(user_id, openclaw_id)
);

create index if not exists idx_openclaws_status on rbac.openclaws(status);
create index if not exists idx_openclaws_name on rbac.openclaws(name);
create index if not exists idx_openclaw_assignments_user on rbac.openclaw_assignments(user_id);
create index if not exists idx_openclaw_assignments_claw on rbac.openclaw_assignments(openclaw_id);

create or replace function rbac.update_openclaw_timestamp()
returns trigger as $$
begin
    new.updated_at = now();
    return new;
end;
$$ language plpgsql;

drop trigger if exists trg_openclaws_updated_at on rbac.openclaws;
create trigger trg_openclaws_updated_at
    before update on rbac.openclaws
    for each row
    execute function rbac.update_openclaw_timestamp();
