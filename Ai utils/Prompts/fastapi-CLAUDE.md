# FastAPI Backend CLAUDE.md — Local Rules

> Works together with the global CLAUDE.md. Place this file in the root of any FastAPI project. It mirrors the Django rulebook's structure so both stacks share one mental model. **This is a rulebook, not a description of one running app.** `authentication/` and `payments/` below are worked examples of file shape, not a fixed app list every project must have.

## Django → FastAPI Naming Map

| Django                              | FastAPI                                             | Purpose                                |
|---------------------------------------|--------------------------------------------------------|-------------------------------------------|
| `app/v1/urls.py`                       | `app/v1/routers.py`                                      | Version-specific endpoints                |
| `<project_name>/urls_v1.py`             | `project_config/api_v1.py`                                | Aggregates all apps' v1 routers           |
| `app/v1/views.py`                        | `app/v1/routers.py` (endpoint functions)                    | Receives request, calls service           |
| `app/v1/serializers.py`                   | `app/v1/schemas.py`                                           | Request/response models (Pydantic)        |
| `models.py` (Django ORM)                   | `models.py` (SQLAlchemy)                                        | Database tables                            |
| `managers/` (custom model manager)          | No direct equivalent — put creation/query helpers in `services/` or a small `repository.py` | SQLAlchemy has no manager concept |
| `permission_classes`                         | `dependencies.py` (`Depends(...)`)                                | Auth/permission checks                     |
| `throttles.py` (DRF throttle classes)         | No built-in equivalent — needs a library (e.g. `slowapi`) or a custom Redis-backed `Depends()` | FastAPI has no built-in throttling |
| `management/commands/`                         | No built-in equivalent — use a small script, or a CLI toolkit if the project has one | No Django-style management framework |
| `settings.py` + `env_config.py`                 | `settings.py` (pydantic-settings `BaseSettings`)                    | One step does both: reads AND validates env vars |
| Django health-report template                    | `Jinja2Templates` response in FastAPI (`fastapi.templating`)     | Human-readable health page                 |
| Bruno collection                                 | Swagger UI (`/docs`) + ReDoc (`/redoc`), auto-generated               | Interactive API reference (see §15)        |
| `signals.py` (post_save/pre_delete hooks)          | No signal system — call the side-effect function directly from the service that triggers it | SQLAlchemy has `sqlalchemy.event` listeners, but they carry the same hidden-control-flow risk; prefer an explicit call |
| `apps.py` (AppConfig, signal registration)          | No equivalent — a domain folder is just a plain Python package        | No app-registry concept in FastAPI          |
| Root `admin.py` (Django admin site registration)     | No default equivalent — optional: SQLAdmin, registered once in `project_config/main.py` | No built-in admin UI                        |
| `migrations/` (one folder per Django app)             | One centralized `alembic/versions/` folder at the project root, not per-domain | Alembic tracks one shared metadata object across all models by default |

**Real gaps, not just naming differences:** Django gives you throttling, permission classes, custom managers, and a management-command framework for free. FastAPI gives you none of these out of the box — `Depends()` is powerful but manual, and rate limiting needs a third-party library. Don't assume parity just because a folder has the same name.

## Reference Project Structure

Two domains are expanded in full purely to make the file-level shape unambiguous: `authentication/`, because nearly every backend needs one, and `payments/`, as a worked example of a webhook-driven domain. Neither is mandatory.

```
├── authentication/            # Custom user model, JWT auth, password flows, admin user management
│   ├── docs/                    # Module reference
│   ├── services/
│   │   ├── __init__.py
│   │   ├── admin.py                 # admin-triggered business logic (creation/query helpers replace managers/)
│   │   ├── password.py
│   │   └── permissions.py
│   ├── v1/
│   │   ├── __init__.py
│   │   ├── schemas.py
│   │   └── routers.py
│   ├── __init__.py
│   ├── models.py
│   ├── dependencies.py                # get_current_user, require_role, etc.
│   ├── tests.py                        # or a tests/ package once it outgrows one file
│   └── throttles.py                     # custom rate-limit dependency for this domain
├── payments/                    # Example: a payment-provider webhook domain (see §10A for the pattern)
│   ├── docs/
│   ├── services/                    # e.g. checkout.py, webhook.py
│   ├── v1/                           # schemas.py, routers.py
│   ├── __init__.py
│   ├── models.py
│   └── tests.py                        # no throttles.py here — only add files a domain actually needs
├── <domain>/, <domain>/, ...       # every other domain YOUR project needs — otp, emails, notifications,
│                                      # a billing/ledger domain, an external-dispatch domain, a read-only
│                                      # reporting domain, dev-only debug routes — whatever applies (see §10)
│   # Every other domain follows the identical shape shown above:
│   # docs/, services/ (split by concern), v1/ (__init__.py, schemas.py, routers.py),
│   # plus root __init__.py, models.py, tests.py — with dependencies.py / throttles.py / tasks.py
│   # added only where that specific domain needs them.
├── alembic/                        # Centralized migrations — NOT per-domain, unlike Django (see naming map)
│   └── versions/                      # one file per schema change, in order
├── core/                           # Shared foundation, no domain logic
│   ├── health/                       # Per-service health checks (database, email, celery, etc.)
│   ├── services/                      # health_check aggregator
│   ├── middleware/                     # admin_throttle
│   ├── cache/                           # redis_client
│   ├── utils/                            # response, exception_handlers, pagination, permissions,
│   │                                       # filtering, validators, generators, decorators, query, image
│   ├── templates/                         # health_report.html (Jinja2)
│   ├── models.py                           # BaseModel (SQLAlchemy declarative base, soft delete)
│   └── docs/
├── project_config/                  # FastAPI project config
│   ├── configs/                        # celery_schedules.py
│   ├── settings.py                       # pydantic-settings (replaces settings.py + env_config.py)
│   ├── main.py                            # FastAPI() creation, health dashboard, /v1/
│   ├── api_v1.py                           # v1 route aggregator
│   └── celery.py
├── developer_guide/                  # Response, Services, Utilities reference docs
├── docs/                              # Full project documentation
├── developers_files/                  # Test results, evaluations, security audits
├── project_script/                    # cross-platform CLI automation toolkit, if you have one
├── docker/                             # Dockerfile, entrypoint.sh, CI env
├── .github/workflows/                  # CI and CD pipelines
├── local-db.docker-compose.yml
├── local-api.docker-compose.yml
├── production-db.docker-compose.yml
├── production-api.docker-compose.yml
└── requirements.txt (or pyproject.toml)
```

---

## 1. App Organization

- One folder per business domain. Each domain keeps the same internal shape: `models.py`, `services/` (split into focused files), a version folder (`v1/`, later `v2/`), and a `docs/` folder.
- `services/` splits into focused files once a domain has more than one clear concern — same rule as Django, just without a `managers/` folder, since SQLAlchemy has no manager concept.
- `services/admin.py` is business logic triggered by an admin action — not a Django-style admin site registration, since FastAPI has no default admin UI (see the naming map for the SQLAdmin option, if one is ever needed).
- `dependencies.py` per domain (when needed) holds that domain's own `Depends()` functions — kept next to the domain that owns the auth logic, not centralized into one giant file.
- No `signals.py` equivalent, and that's a deliberate simplification, not a missing feature: call the side-effect function directly from the service that triggers it. A developer reading `services/checkout.py` sees every consequence of a checkout right there, instead of needing to find a signal handler elsewhere.
- No `apps.py` equivalent needed — a domain folder is just a plain Python package.
- `tests.py` is fine for a small domain. Convert it to a `tests/` package once a single file gets hard to navigate.
- `throttles.py` per domain holds a custom rate-limit dependency for that domain specifically — built with `slowapi` or a custom Redis-backed `Depends()`, since FastAPI has nothing built in. Only add this file to domains that actually need a custom scope.
- `docs/` per domain is a short module reference — distinct from `developer_guide/` (shared conventions) and root `docs/` (full project documentation).

## 2. API Versioning — Per-Domain `v1/` Folders

- Each domain owns its own version folder — containing that version's `routers.py` and `schemas.py`.
- `models.py` and `services/` live **outside** the version folder, shared across versions.
- `project_config/api_v1.py` is only an aggregator: it includes each domain's `v1/routers.py` under the right prefix. It never defines a route directly.
- `project_config/main.py` includes the health dashboard, and `api_v1.py` — nothing else.
- **Versioning is per-domain, not global.** When one domain needs a breaking change, add `domain_name/v2/` next to its `v1/` and register it through a new `api_v2.py`.
- Never remove a `v1/` router while any client still depends on it. Deprecate first, remove once usage hits zero.

## 3. Models (SQLAlchemy)

- Every model inherits from `core.models.BaseModel` — a declarative base mixin with `created_at`, `updated_at`, and a soft-delete flag.
- Default queries exclude soft-deleted rows unless a query explicitly asks for deleted records.
- Keep models focused on table structure. Business logic belongs in `services/`, not model methods.
- Index every foreign key and any column used often in filters or ordering.
- Use Alembic for every schema change — but unlike Django, migrations live in one centralized `alembic/versions/` folder at the project root, not inside each domain. Review the auto-generated migration before applying it.

## 4. Schemas (Pydantic)

- One schema per use case, scoped to its version folder — never one schema reused for both input and output.
- Validate with Pydantic field validators for single-field rules, model validators for rules spanning multiple fields.
- Never include sensitive fields (password hashes, internal flags, raw webhook payloads) in a response schema.
- Use `ConfigDict(from_attributes=True)` on response schemas so they map cleanly from SQLAlchemy instances.

## 5. Routers (Endpoints)

- Keep router functions thin: receive the already-validated request, call a service function, return the result through `core/utils/response`. No business logic inside a router function.
- Use `dependencies.py` for auth/permission checks (`Depends(get_current_user)`, `Depends(require_admin)`) — never a manual check inside the endpoint body.
- Group related endpoints under one `APIRouter` per domain, with a matching `tags=[...]` for Swagger grouping (see §15).

## 6. Rate Limiting & Throttling

- FastAPI has no built-in throttling. Configure a default rate at the app level — via `slowapi`'s global limiter, or a shared Redis-backed `Depends()` applied to every router — so every endpoint has a baseline limit even before any domain-specific override exists.
- **The rate-limit counter must live in Redis (`core/cache/redis_client`), never in-process memory.** An in-memory counter is per-worker — with more than one Uvicorn/Gunicorn worker or server instance, each process counts independently, and the real effective limit silently becomes (configured rate × number of processes). This is the most common reason rate limiting "works locally" and does nothing in production.
- Layer limits at two levels: per-IP (protects endpoints before a user is authenticated — login, signup, verification-code requests) and per-user (fair use once authenticated, via a dependency keyed on the user ID from the JWT).
- Give tighter, purpose-specific limits to abuse-prone endpoints: login, verification codes, password reset, signup — and any webhook or callback endpoint (see §10A/§10C). Those skip normal auth, but they still need a limit; a flood of fake calls is still a resource-exhaustion risk even if each one fails verification.
- Give admin routes (`core/middleware/admin_throttle`, implemented as a dependency) their own limit, separate from the public API's — admin traffic is low-volume but high-privilege.
- On a throttled request, return `429` with a `Retry-After` header — never substitute a "friendly" 200; the client needs the real status code to back off correctly.

## 7. Database & Query Practices

- Avoid N+1 queries anywhere a query is looped over to reach a related object — use `joinedload`/`selectinload` in SQLAlchemy.
- Every list endpoint is paginated — never return an unbounded query result. Use the shared `core/utils/pagination.py` helper.
- Wrap any multi-step write in a database transaction so a partial failure can't leave the database inconsistent. Mandatory for any ledger domain (§10B) or external-dispatch domain (§10C), where a request touches more than one table that must succeed or fail together.
- Use `with_for_update()` inside a transaction for any read-then-write on a row that can be hit concurrently.
- Configure connection pooling explicitly (SQLAlchemy's `pool_size`/`max_overflow`) — the defaults are rarely right for production load.

## 8. Error Handling

- Every error response goes through `core/utils/exception_handlers.py`, registered via `add_exception_handler()`, and comes out in one consistent shape: `{ "error": { "code": "...", "message": "..." } }`. A router or service never constructs its own ad-hoc error JSON.
- Map exception types to HTTP status codes consistently across the whole API: validation → 400/422, missing auth → 401, permission denied → 403, not found → 404, conflict → 409, unhandled → 500.
- Never let a raw exception message, stack trace, or database error reach the client. Log the full detail internally; return only the generic, mapped message externally.
- Log every 401, 403, and 429 specifically, not just 500s.
- The `code` field (not just `message`) is what the frontend maps to a friendly, localized string — keep it stable.

## 9. Authentication, OTP, Emails, Notifications

These four are close to universal — almost every real backend needs some form of each.

- The auth domain owns the `User` model, JWT issuing/verification, password flows, and admin user management. No other domain duplicates this logic.
- JWT rules: access token short-lived (5–15 min), refresh token rotated on every use, both verified server-side through a shared dependency on every request. Always confirm the requesting user owns the resource being accessed.
- If the project uses one-time verification codes, define per-purpose rules — a signup code and a password-reset code can have different expiry and retry limits.
- Rate-limit verification-code generation and checking per user/phone/email, with a cooldown or lockout after repeated failures.
- Send all email through Celery tasks, never synchronously inside a router function. Email content lives in Jinja2 templates, never hardcoded strings.
- Log every email attempt for delivery debugging.
- In-app notifications stay decoupled from the domains that trigger them.

## 10. Common Domain Patterns (Worked Examples, Not Mandatory Apps)

Real backends keep running into the same handful of domain *shapes*, whatever the domain is actually called. Apply whichever pattern matches something your project actually has.

**A. Payment / billing domains (Stripe or similar)**
- All payment-provider interaction lives in `services/` — never call the provider's SDK directly from a router.
- **Webhook signature verification is mandatory on every webhook request.** Verify the provider's signature with the signing secret before trusting the payload.
- The webhook route skips normal user/admin auth but never skips signature verification.
- Handle every webhook idempotently — check the provider's event ID against what's already processed.
- Never trust a client-supplied payment amount. Compute it server-side from the actual stored price.
- Never store raw card data.
- Log every payment state transition for audit and dispute handling.

**B. Ledger-backed domains (credits, wallets, points)**
- Treat it as a **ledger, not a balance column** — every change is an append-only entry; the balance is derived or cached-and-reconciled from it.
- Wrap balance-changing operations in a transaction with row-level locking (`with_for_update()`).
- A refund is a new ledger entry, never a retroactive edit to an old one.

**C. External dispatch & callback domains**
- Treat the callback endpoint with the same suspicion as any public-facing endpoint.
- The callback must be authenticated with a per-dispatch token, verified against the original dispatch.
- Callbacks must be idempotent — a retried callback must not double-refund, double-charge, or double-dispatch.
- Failed or timed-out dispatches follow a defined retry policy with a maximum attempt count.
- A dispatch that ultimately fails after retries triggers a compensating action (typically a refund, pattern B).

**D. Read-only aggregation / dashboard domains**
- Never let one modify data.
- Cache expensive aggregation results in Redis with a TTL matched to how fresh the data needs to be.
- Watch for N+1 queries in aggregation code specifically.
- Require admin-level permission via `Depends(require_admin)`.

**E. Third-party usage / metering domains**
- The provider's API key comes from `project_config/settings.py`, never hardcoded.
- The sync task is idempotent — re-running it for an already-synced period must not double-count usage.
- A backfill script shares the same underlying sync function as the scheduled task.
- Handle the provider's own rate limits gracefully.

**F. Dev-only / debug routes**
- Routed only when the environment is explicitly non-production (`settings.ENV == "dev"` or equivalent), enforced with a conditional include in `main.py`.
- Validate the running environment at startup and fail loudly if production config looks wrong.
- Anything here that touches a real external service is sensitive even though it's dev-only.
- A debug route that quietly ships to production is one of the most common real-world security leaks. The code-level guard is the actual protection, not the folder name.

## 11. Logs — Structured Logging

- Use a non-blocking `QueueHandler` — the same Python `logging` pattern as Django, framework-independent. Log writes go to a queue processed by a separate listener so they never block the request-response cycle.
- Separate normal application logs from error-level logs.
- FastAPI middleware attaches request context (request ID, user, path) to every log line automatically.
- Any API exposing raw logs is admin-only.

## 12. Core Utilities & Shared Foundation

- `core/utils/response.py` — every response, success or error, goes through this one formatter.
- `core/utils/exception_handlers.py` — registered in `main.py`, implementing the policy in §8.
- `core/utils/pagination.py` — one shared pagination helper for every list endpoint.
- `core/utils/permissions.py` and `filtering.py` — shared dependency functions for permission checks and query filtering.
- `core/utils/validators.py`, `generators.py`, `decorators.py`, `query.py`, `image.py` — shared helpers, checked before writing something new.
- `core/middleware/admin_throttle` — a separate rate-limit dependency for admin routes (see §6).
- `core/cache/redis_client` — the single shared Redis client for caching and rate-limit state. Don't create a second one elsewhere.
- `core/health/` holds one health-check function per dependency. `core/services/health_check` aggregates them, exposed as JSON and as a `Jinja2Templates`-rendered dashboard.

## 13. Background Jobs (Celery)

- `project_config/celery.py` is the single Celery app entry point. `project_config/configs/celery_schedules.py` holds all periodic (beat) schedules in one place.
- Task functions live inside the domain that owns them.
- Every task is idempotent.
- Tasks calling external services need explicit timeout and retry settings.

## 14. Docker & Environments

- `project_config/settings.py` (pydantic-settings `BaseSettings`) reads and validates every environment variable in one step. Fail loudly at startup if a required variable is missing or malformed.
- Keep `db`/`api` compose files separate, and `local`/`production` compose files separate.
- CI must run lint and tests on every pull request before merge is allowed.
- Keep the CI environment's Docker setup close to production's actual setup.

## 15. Swagger / OpenAPI Documentation Rules

FastAPI generates interactive API docs (Swagger UI at `/docs`, ReDoc at `/redoc`) directly from your route decorators and Pydantic schemas — there's no separate collection to maintain by hand like Bruno. That only helps if the metadata is actually filled in.

**Organization**
- Group endpoints with `tags=[...]` on each `APIRouter`, audience-first: `"Admin - Payments"`, `"User - Leads"`, `"Public - Auth"`.
- Reuse the same short domain names as your Bruno collection, if one exists, so switching between the two feels consistent.

**Per-endpoint documentation**
Every route decorator sets:
- `summary=` — a short title.
- `description=` (or a clear docstring) — what the endpoint does, permission requirements, and any non-obvious behavior.
- `response_model=` — the exact schema returned.
- `responses={...}` — every non-200 status code the endpoint can actually return, each with an example body.
- `Field(..., max_length=..., ge=...)` constraints on every schema field, so parameter types and limits show up automatically.
- Source of truth is the router function and its schemas — Swagger can't show an endpoint that doesn't exist in code, so the risk shifts from "invented endpoints" to "under-documented endpoints."

**Auth**
- Public routes: no security dependency.
- User routes: `dependencies=[Depends(get_current_user)]` at the router level.
- Admin routes: `dependencies=[Depends(require_admin)]` at the router level.
- Configure two distinct OpenAPI security schemes (`UserAuth`, `AdminAuth`) so Swagger's "Authorize" button shows them separately.
- Never put a real token as a Swagger example value.

**Keeping docs accurate**
- `summary`, `description`, `response_model`, and `responses` are updated in the *same commit* as any behavior change. A stale description is worse than no documentation.

**Production exposure**
- Disable or protect `/docs`, `/redoc`, and `/openapi.json` in production.

## 16. Developer Guide & Project Docs

- `developer_guide/` — shared response/service/utility conventions.
- `docs/` — full project documentation.
- `developers_files/` — test results, evaluations, and security audit records, if you keep them.
- A cross-platform CLI toolkit, if the project has one — reuse it for seeding, backfilling, and setup scripts instead of building a separate tool per stack.

## 17. Testing

- Each domain tests itself in its own `tests.py` or `tests/` package using FastAPI's `TestClient` / `httpx.AsyncClient`.
- Confirm the shared response format is used correctly in each new endpoint's tests.
- Explicitly test authorization boundaries.
- Explicitly test rate-limit enforcement, and, for any domain following the ledger (§10B) or external-callback (§10C) patterns, webhook/callback idempotency and balance correctness under concurrent requests.

## 18. Security (FastAPI-Specific)

- Disable or protect `/docs`, `/redoc`, `/openapi.json` in production.
- Keep all secrets (`SECRET_KEY`, any third-party API keys, DB credentials) in environment variables only, validated by `project_config/settings.py` at startup.
- Because FastAPI has no built-in admin panel, session/CSRF system, or throttle framework like Django, double-check that every state-changing endpoint requires a valid dependency-enforced auth check.
- Verify webhook/callback signatures on every external request (§10A/§10C).
- Confirm dev-only routes (§10F) are unreachable outside the dev environment before every release.
- Give admin routes their own throttle dependency instead of sharing the public rate limit.

## 19. Implementation Discipline — Precautions Before Writing Code

Before generating or modifying any endpoint, model, or service in this project, work through this checklist. It exists so the rules in §1–§18 actually get applied while code is being written, not discovered missing afterward in review.

**Modularity & coupling**
- Does this change belong in `services/`, not directly in a router? If the same logic is needed in two places, is it one function called twice, not copy-pasted?
- Does this new code reach into another domain's internals (importing another domain's models directly instead of calling its service function)? That's tight coupling — go through the owning domain's `services/` layer instead.
- Is a new shared helper being written that already exists in `core/utils/`? Check there first (§12) before adding a duplicate.

**Security**
- Does this endpoint touch another user's data? If yes, is there an explicit object-level ownership check inside the service, not just a `Depends(get_current_user)` auth check (§1, §9)?
- Does this endpoint accept external input (body, query params, headers, webhook payload)? Is every field validated through a Pydantic schema, not just the ones that "look important"?
- Is anything here a secret (API key, signing secret, DB credential)? It comes from `project_config/settings.py` (pydantic-settings) — never a literal string in the code, even temporarily "to test."
- Is this a webhook or callback endpoint? Signature/token verification (§10A/§10C) must be in place before the handler trusts any part of the payload — not added as a follow-up task.

**Throttling & rate limits**
- Does this endpoint fall outside the default rate limit — login, verification codes, password reset, signup, or any webhook/callback? If so, apply the tighter dependency from §6 explicitly instead of leaving it on the default.
- If throttling is being set up for the first time on a fresh project, is the counter backend actually Redis, not in-process memory? (§6 — this is the single most common silent failure.)

**Database & scalability**
- Does this code loop over a query result and touch a related object inside the loop? That's N+1 — use `joinedload`/`selectinload` (§7) before it ships, not after a slow-query report.
- Does this write touch more than one table, or read-then-write a value that can be hit concurrently (a balance, a count, a status flag)? Wrap it in a transaction, and add `with_for_update()` if concurrency is possible (§7).
- Is this a new list endpoint? Paginate it before it ships — don't plan to add pagination later.

**Error handling & reliability**
- Does every failure path return through the shared response/exception-handler formatter (§8), or does this code build its own error JSON?
- If this operation can be retried (a webhook, a background job, a callback), is it actually idempotent, or will a retry double-apply it (§10B/§10C)?

**When something doesn't fit cleanly**
If a change doesn't obviously map to one of these checks — a genuinely new kind of endpoint, an ambiguous ownership case, a performance tradeoff with no clear right answer — say so explicitly instead of silently picking an approach. Flag the tradeoff and the reasoning, same as the global CLAUDE.md's agent-behavior rules already require.

---

*Status: v4 — added §19, a pre-implementation checklist tying security, modularity/coupling, throttling, database, and error-handling rules together at the moment code is actually written.*
