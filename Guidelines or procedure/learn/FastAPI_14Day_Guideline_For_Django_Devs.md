# FastAPI 14-Day Guideline for Django Developers
### From Intermediate Django → Confident FastAPI in 2 Weeks

---

## Before You Start: The Mental Shift

You know Django deeply. FastAPI will feel liberating in some ways and naked in others. Django gave you everything — admin, ORM, migrations, auth — out of the box. FastAPI gives you speed, type safety, and auto docs, but you assemble the pieces yourself.

The hardest unlearning: **there is no `urls.py`, no `views.py`, no `models.py` convention, no `manage.py`, and no free admin panel.** Everything is explicit.

| Django | FastAPI Equivalent |
|---|---|
| `urls.py` + `views.py` | Path decorators on functions directly |
| DRF `Serializer` | Pydantic `BaseModel` — validation + schema in one |
| `ModelSerializer` | No direct equivalent — you write schemas manually |
| Django ORM | SQLAlchemy or SQLModel (you choose) |
| `makemigrations` / `migrate` | Alembic (separate tool) |
| `settings.py` | `config.py` + `.env` with `pydantic-settings` |
| `manage.py runserver` | `uvicorn main:app --reload` |
| `request.data` | Pydantic model as function parameter |
| `request.user` | `Depends(get_current_user)` — dependency injection |
| DRF permissions | Functions injected via `Depends()` |
| `ModelViewSet` | `APIRouter` with individual path functions |
| Django admin (free pass) | No built-in equivalent — you build it or use FastAPI-admin |
| `python manage.py shell` | Plain Python REPL + manual imports |
| `@receiver(post_save)` | Background tasks or startup events |
| `python manage.py test` | `pytest` + `TestClient` |

---

## The File System — No Convention Enforced

FastAPI does not enforce a project structure. This is a production-ready convention you should follow:

```
myproject/
├── main.py                     ← App entry point (creates FastAPI instance)
├── requirements.txt
├── .env                        ← Environment variables (DB URL, secret key, etc.)
├── alembic/                    ← Migration files (replaces Django's migrations/)
│   ├── env.py
│   └── versions/
├── alembic.ini
└── app/
    ├── __init__.py
    ├── config.py               ← Settings (replaces settings.py)
    ├── database.py             ← DB engine + session (replaces Django ORM setup)
    ├── dependencies.py         ← Shared Depends() functions (auth, DB session, etc.)
    ├── models/                 ← SQLAlchemy ORM models (replaces models.py)
    │   └── post.py
    ├── schemas/                ← Pydantic schemas (replaces serializers.py)
    │   └── post.py
    └── routers/                ← Path operations grouped by resource (replaces urls.py + views.py)
        └── posts.py
```

---

## Week 1 — Days 1 to 7: Foundation

---

### Day 1 — Setup + First App + Auto Docs

**Install:**
```bash
pip install fastapi uvicorn[standard] python-dotenv pydantic-settings
```

**`main.py` — the entry point:**
```python
from fastapi import FastAPI

app = FastAPI(
    title="My Blog API",
    description="A blog API built with FastAPI",
    version="1.0.0",
)

@app.get("/")
def root():
    return {"message": "Hello FastAPI"}
```

**Run the server:**
```bash
uvicorn main:app --reload
```

**Your free pass in FastAPI — Auto Documentation:**

Unlike Django where the admin was your free pass, FastAPI's free pass is **automatic interactive API docs** generated from your code with zero extra work.

- `http://127.0.0.1:8000/docs` → Swagger UI (interactive, send real requests)
- `http://127.0.0.1:8000/redoc` → ReDoc (clean readable docs)
- `http://127.0.0.1:8000/openapi.json` → Raw OpenAPI schema

Every endpoint, request body, query param, and response you define automatically appears here. No config needed.

**`config.py` — replaces `settings.py`:**
```python
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    app_name: str = "My API"
    database_url: str
    secret_key: str
    debug: bool = False

    class Config:
        env_file = ".env"

settings = Settings()
```

**`.env`:**
```
DATABASE_URL=postgresql+asyncpg://user:password@localhost/mydb
SECRET_KEY=your-secret-key-here
DEBUG=True
```

**Tasks for Day 1:**
- Set up project structure as shown above
- Write 3 simple GET endpoints
- Open `/docs` and test all 3 from the browser — no Postman needed
- Read `config.py` and understand why it replaces `settings.py`

---

### Day 2 — Path Operations, Routing, and Parameters

This replaces `urls.py` + function-based views combined into one.

**Path parameters (replaces `<int:pk>` in urls.py):**
```python
from fastapi import FastAPI

@app.get("/posts/{post_id}")
def get_post(post_id: int):       # type hint = automatic validation + docs
    return {"post_id": post_id}

@app.get("/users/{username}/posts/{post_id}")
def get_user_post(username: str, post_id: int):
    return {"username": username, "post_id": post_id}
```

**Query parameters (replaces `request.GET.get()`):**
```python
@app.get("/posts/")
def list_posts(
    page: int = 1,
    page_size: int = 10,
    search: str | None = None,
    is_published: bool = True,
):
    return {"page": page, "search": search}
```

**`APIRouter` — replaces `urls.py` + `include()`:**
```python
# app/routers/posts.py
from fastapi import APIRouter

router = APIRouter(prefix="/posts", tags=["Posts"])

@router.get("/")
def list_posts():
    return []

@router.get("/{post_id}")
def get_post(post_id: int):
    return {"id": post_id}

@router.post("/")
def create_post():
    return {}
```

```python
# main.py — wire routers in
from app.routers import posts, users, auth

app.include_router(posts.router)
app.include_router(users.router)
app.include_router(auth.router, prefix="/auth", tags=["Auth"])
```

**HTTP methods — one decorator per method:**
```python
@router.get("/")          # list
@router.post("/")         # create
@router.get("/{id}")      # retrieve
@router.put("/{id}")      # full update
@router.patch("/{id}")    # partial update
@router.delete("/{id}")   # delete
```

**Tasks for Day 2:**
- Create 3 routers: `posts`, `categories`, `auth`
- Register all with `app.include_router()`
- Add path + query params to the posts router
- Observe all routes appear automatically in `/docs`

---

### Day 3 — Pydantic Models (Replaces DRF Serializers)

This is the **biggest concept to master**. In Django you had `ModelSerializer` auto-generating fields from your ORM model. In FastAPI, Pydantic `BaseModel` is your schema — you define it manually and it handles validation, parsing, and docs.

**Basic schema:**
```python
# app/schemas/post.py
from pydantic import BaseModel, Field, field_validator
from datetime import datetime

class PostBase(BaseModel):
    title: str = Field(..., min_length=3, max_length=200)
    content: str = Field(..., min_length=10)
    is_published: bool = False

class PostCreate(PostBase):         # input schema for POST
    category_id: int

class PostUpdate(BaseModel):        # input schema for PUT — all fields optional
    title: str | None = Field(None, min_length=3, max_length=200)
    content: str | None = None
    is_published: bool | None = None

class PostRead(PostBase):           # output schema — what the API returns
    id: int
    category_id: int
    created_at: datetime

    model_config = {"from_attributes": True}   # allows reading from ORM objects
```

**Comparison with DRF:**
```python
# Django DRF (what you know)
class PostSerializer(serializers.ModelSerializer):
    class Meta:
        model = Post
        fields = ["id", "title", "content", "is_published"]

# FastAPI Pydantic (what you're learning)
class PostRead(BaseModel):
    id: int
    title: str
    content: str
    is_published: bool
    model_config = {"from_attributes": True}
```

**Custom validation (replaces `validate_<field>` in DRF):**
```python
from pydantic import field_validator, model_validator

class PostCreate(BaseModel):
    title: str
    content: str

    @field_validator("title")
    @classmethod
    def title_must_not_be_empty(cls, v):
        if v.strip() == "":
            raise ValueError("Title cannot be blank")
        return v.strip()

    @model_validator(mode="after")           # cross-field validation
    def content_longer_than_title(self):
        if len(self.content) < len(self.title):
            raise ValueError("Content must be longer than title")
        return self
```

**Nested schemas (replaces nested serializers):**
```python
class CategoryRead(BaseModel):
    id: int
    name: str
    model_config = {"from_attributes": True}

class PostRead(BaseModel):
    id: int
    title: str
    category: CategoryRead          # nested — equivalent to DRF nested serializer
    model_config = {"from_attributes": True}
```

**Tasks for Day 3:**
- Write `Create`, `Update`, and `Read` schemas for Post and Category
- Add `field_validator` for at least one field
- Add a nested `CategoryRead` inside `PostRead`
- Test validation errors by sending bad data in `/docs`

---

### Day 4 — Request Body + Response Models + Status Codes

**Using schemas in endpoints:**
```python
from fastapi import APIRouter, status
from app.schemas.post import PostCreate, PostRead, PostUpdate

router = APIRouter(prefix="/posts", tags=["Posts"])

@router.post("/", response_model=PostRead, status_code=status.HTTP_201_CREATED)
def create_post(post: PostCreate):      # post is parsed + validated automatically
    # post.title, post.content, post.category_id are all available
    return post                         # FastAPI serializes using PostRead

@router.get("/{post_id}", response_model=PostRead)
def get_post(post_id: int):
    return {"id": post_id, "title": "Test", ...}

@router.put("/{post_id}", response_model=PostRead)
def update_post(post_id: int, post: PostUpdate):
    return {}

@router.delete("/{post_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_post(post_id: int):
    return None
```

**`response_model` — replaces DRF `serializer.data`:**
- Filters out fields not in the schema (like `password` from a user response)
- Validates that your response matches the schema
- Generates accurate response docs

**Returning different status codes:**
```python
from fastapi import HTTPException

@router.get("/{post_id}", response_model=PostRead)
def get_post(post_id: int):
    post = fake_db.get(post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found")
    return post
```

**Multiple response types:**
```python
from fastapi.responses import JSONResponse, Response

@router.get("/{id}")
def get_post(id: int):
    if id == 0:
        return Response(status_code=204)       # no content
    return JSONResponse({"id": id})
```

**Tasks for Day 4:**
- Add `response_model` to every endpoint in your posts router
- Add `status_code=201` to create endpoint
- Raise `HTTPException(404)` when a record is not found
- Confirm `/docs` shows the response schema correctly

---

### Day 5 — Dependency Injection (Replaces Django Middleware + Permissions)

Dependency Injection (`Depends()`) is FastAPI's most powerful feature. It replaces:
- `request.user` → inject current user
- DRF permission classes → inject a guard function
- DB session management → inject a DB session
- Shared query logic → inject reusable query builders

**Simple dependency:**
```python
from fastapi import Depends

def get_pagination(page: int = 1, page_size: int = 10):
    return {"skip": (page - 1) * page_size, "limit": page_size}

@router.get("/")
def list_posts(pagination: dict = Depends(get_pagination)):
    # pagination["skip"] and pagination["limit"] are ready to use
    return pagination
```

**DB session dependency (replaces Django's auto session management):**
```python
# app/dependencies.py
from app.database import SessionLocal

def get_db():
    db = SessionLocal()
    try:
        yield db          # yield = request gets the session
    finally:
        db.close()        # cleanup after request ends — like Django's auto session close
```

```python
from sqlalchemy.orm import Session

@router.get("/")
def list_posts(db: Session = Depends(get_db)):
    return db.query(Post).all()
```

**Auth dependency (replaces `permission_classes = [IsAuthenticated]`):**
```python
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    user = verify_token_and_get_user(token, db)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return user

def require_active_user(current_user = Depends(get_current_user)):
    if not current_user.is_active:
        raise HTTPException(status_code=403, detail="Inactive user")
    return current_user
```

```python
# Protect an endpoint — equivalent to permission_classes = [IsAuthenticated]
@router.post("/", status_code=201)
def create_post(post: PostCreate, current_user = Depends(get_current_user)):
    # current_user is the authenticated user object
    return {}

# Apply to whole router — equivalent to applying permission to entire ViewSet
router = APIRouter(
    prefix="/posts",
    tags=["Posts"],
    dependencies=[Depends(get_current_user)],   # all routes in this router require auth
)
```

**Chained dependencies:**
```python
def get_admin_user(current_user = Depends(get_current_user)):
    if not current_user.is_admin:
        raise HTTPException(403, "Admin access required")
    return current_user

@router.delete("/{id}")
def delete_post(id: int, admin = Depends(get_admin_user)):
    pass
```

**Tasks for Day 5:**
- Write a `get_pagination` dependency and use it on the list endpoint
- Write a `get_db` dependency (even without real DB yet — return a mock)
- Write a `get_current_user` dependency that reads a header
- Apply auth protection to an entire router using `dependencies=[...]`

---

### Day 6 — Database with SQLAlchemy + SQLModel

Django ORM is built in. FastAPI uses SQLAlchemy (the industry standard). SQLModel is a wrapper by FastAPI's creator that unifies SQLAlchemy models and Pydantic schemas.

**Option A — Pure SQLAlchemy (recommended to learn first):**

```bash
pip install sqlalchemy psycopg2-binary alembic
```

```python
# app/database.py
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase
from app.config import settings

engine = create_engine(settings.database_url)
SessionLocal = sessionmaker(bind=engine, autocommit=False, autoflush=False)

class Base(DeclarativeBase):
    pass
```

```python
# app/models/post.py
from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship
from app.database import Base

class Category(Base):
    __tablename__ = "categories"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False, unique=True)

    posts = relationship("Post", back_populates="category")   # replaces related_name

class Post(Base):
    __tablename__ = "posts"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String(200), nullable=False)
    content = Column(String, nullable=False)
    is_published = Column(Boolean, default=False)
    category_id = Column(Integer, ForeignKey("categories.id"))
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    category = relationship("Category", back_populates="posts")
```

**SQLAlchemy queries vs Django ORM:**
```python
from sqlalchemy.orm import Session, joinedload

# Django: Post.objects.all()
db.query(Post).all()

# Django: Post.objects.filter(is_published=True)
db.query(Post).filter(Post.is_published == True).all()

# Django: Post.objects.get(id=1)
db.query(Post).filter(Post.id == id).first()

# Django: Post.objects.select_related("category")
db.query(Post).options(joinedload(Post.category)).all()

# Django: Post.objects.filter(title__icontains="django")
db.query(Post).filter(Post.title.ilike("%django%")).all()

# Django: Post.objects.order_by("-created_at")[:10]
db.query(Post).order_by(Post.created_at.desc()).limit(10).all()

# Django: Post.objects.filter(id=1).update(title="x")
db.query(Post).filter(Post.id == id).update({"title": "x"})
db.commit()

# Django: post.save() after changes
db.add(post)
db.commit()
db.refresh(post)    # reload from DB (like Django's refresh_from_db())

# Django: post.delete()
db.delete(post)
db.commit()
```

**Option B — SQLModel (cleaner, less boilerplate):**
```bash
pip install sqlmodel
```

```python
from sqlmodel import SQLModel, Field, Relationship
from datetime import datetime

class Post(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str = Field(max_length=200)
    content: str
    is_published: bool = False
    category_id: int = Field(foreign_key="category.id")
    created_at: datetime | None = Field(default=None)
    # This model works as BOTH an ORM model AND a Pydantic schema
```

**Tasks for Day 6:**
- Set up `database.py` with SQLAlchemy engine and `SessionLocal`
- Define `Post` and `Category` models with a ForeignKey
- Wire `get_db` dependency into your post endpoints
- Implement full CRUD in the posts router using real DB queries
- Use `joinedload` on the category relationship

---

### Day 7 — Alembic Migrations (Replaces `makemigrations` / `migrate`)

Django generated migration files automatically. Alembic requires more manual steps but gives you full control.

```bash
pip install alembic
alembic init alembic              # creates alembic/ folder and alembic.ini
```

**Configure `alembic/env.py`:**
```python
from app.database import Base
from app.models import post      # import all models so Alembic can detect them

target_metadata = Base.metadata  # tell Alembic about your models
```

**Configure `alembic.ini`:**
```ini
sqlalchemy.url = postgresql://user:password@localhost/mydb
```

**Migration commands — Django comparison:**
```bash
# Django: python manage.py makemigrations
alembic revision --autogenerate -m "create posts table"

# Django: python manage.py migrate
alembic upgrade head

# Rollback last migration (no direct Django equivalent)
alembic downgrade -1

# View migration history
alembic history

# Current migration state
alembic current
```

**Generated migration file (inside `alembic/versions/`):**
```python
def upgrade() -> None:
    op.create_table(
        "posts",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("title", sa.String(length=200), nullable=False),
        sa.Column("content", sa.String(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )

def downgrade() -> None:
    op.drop_table("posts")
```

**Key difference from Django:** Alembic does NOT auto-detect every change perfectly. Always review the generated migration file before applying it. Django migrations are safer defaults — Alembic gives more control but requires more attention.

**Tasks for Day 7:**
- Initialize Alembic and configure `env.py`
- Generate a migration for your Post and Category models
- Apply with `alembic upgrade head`
- Add a new column to Post, generate a new migration, and apply it
- Roll back with `alembic downgrade -1` and confirm the column is gone

---

## Week 2 — Days 8 to 14: Intermediate

---

### Day 8 — Authentication with OAuth2 + JWT

Django had built-in token auth via DRF. FastAPI uses OAuth2 + JWT which is the modern standard.

```bash
pip install python-jose[cryptography] passlib[bcrypt]
```

**Password hashing (replaces Django's `make_password`):**
```python
# app/auth/security.py
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)
```

**JWT token creation + verification:**
```python
from jose import JWTError, jwt
from datetime import datetime, timedelta
from app.config import settings

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30

def create_access_token(data: dict) -> str:
    payload = data.copy()
    payload["exp"] = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    return jwt.encode(payload, settings.secret_key, algorithm=ALGORITHM)

def decode_token(token: str) -> dict:
    try:
        return jwt.decode(token, settings.secret_key, algorithms=[ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid token")
```

**Auth router — login endpoint:**
```python
# app/routers/auth.py
from fastapi import APIRouter, Depends
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from app.dependencies import get_db

router = APIRouter(tags=["Auth"])

@router.post("/token")
def login(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Incorrect username or password")
    token = create_access_token({"sub": str(user.id)})
    return {"access_token": token, "token_type": "bearer"}
```

**`get_current_user` dependency — replaces `request.user`:**
```python
# app/dependencies.py
from fastapi.security import OAuth2PasswordBearer

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    payload = decode_token(token)
    user_id = payload.get("sub")
    user = db.query(User).filter(User.id == int(user_id)).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user
```

**Tasks for Day 8:**
- Create a `User` model with `hashed_password` column
- Implement `register` and `login` endpoints
- Generate JWT tokens on login
- Protect the post creation endpoint with `Depends(get_current_user)`
- Test the full flow in `/docs`: register → login → copy token → use on protected endpoint

---

### Day 9 — Async / Await + Background Tasks

FastAPI is async-first. Django is sync-first (async support was added later). This is a real shift.

**Sync vs async endpoint:**
```python
# Sync — blocks the server while waiting
@router.get("/sync")
def sync_endpoint():
    import time
    time.sleep(1)           # blocks entire thread
    return {"ok": True}

# Async — other requests handled during await
@router.get("/async")
async def async_endpoint():
    await asyncio.sleep(1)  # yields control, server handles other requests
    return {"ok": True}
```

**Rule of thumb:**
- If your function calls `await something` → use `async def`
- If it uses standard sync libraries (like psycopg2, requests) → use `def` (FastAPI runs it in a thread pool automatically)
- Never call blocking code (`time.sleep`, sync DB calls) inside `async def`

**Async SQLAlchemy:**
```bash
pip install asyncpg sqlalchemy[asyncio]
```

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession

engine = create_async_engine("postgresql+asyncpg://user:pass@localhost/db")

async def get_db():
    async with AsyncSession(engine) as session:
        yield session

@router.get("/")
async def list_posts(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Post))
    return result.scalars().all()
```

**Background tasks — replaces Django signals for fire-and-forget work:**
```python
from fastapi import BackgroundTasks

def send_welcome_email(email: str):
    # runs after response is sent — client does not wait
    print(f"Sending email to {email}")

@router.post("/register")
def register_user(user: UserCreate, background_tasks: BackgroundTasks, db: Session = Depends(get_db)):
    new_user = create_user(db, user)
    background_tasks.add_task(send_welcome_email, new_user.email)
    return new_user       # response is sent immediately, email sends after
```

**Startup / shutdown events — replaces Django `AppConfig.ready()`:**
```python
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    print("App starting — run setup here")   # replaces AppConfig.ready()
    yield
    print("App shutting down — run cleanup here")

app = FastAPI(lifespan=lifespan)
```

**Tasks for Day 9:**
- Convert at least one endpoint to `async def` with an async DB call
- Add a `BackgroundTask` that logs something after a POST request
- Add a `lifespan` event that prints a startup message

---

### Day 10 — Middleware + CORS + Exception Handling

**CORS — allowing frontend requests:**
```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000", "https://myapp.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Custom middleware (replaces Django middleware class):**
```python
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware
import time

class RequestTimingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start = time.time()
        response = await call_next(request)             # process the request
        duration = time.time() - start
        response.headers["X-Process-Time"] = str(duration)
        return response

app.add_middleware(RequestTimingMiddleware)
```

**Global exception handlers (replaces Django's `handler404`, custom DRF exception handlers):**
```python
from fastapi import Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError

@app.exception_handler(404)
async def not_found_handler(request: Request, exc):
    return JSONResponse(status_code=404, content={"error": "Resource not found"})

@app.exception_handler(IntegrityError)
async def integrity_error_handler(request: Request, exc: IntegrityError):
    return JSONResponse(status_code=409, content={"error": "Duplicate entry"})
```

**Custom exception class:**
```python
class PermissionDenied(Exception):
    def __init__(self, message: str):
        self.message = message

@app.exception_handler(PermissionDenied)
async def permission_denied_handler(request: Request, exc: PermissionDenied):
    return JSONResponse(status_code=403, content={"error": exc.message})

# Raise anywhere
raise PermissionDenied("You do not own this post")
```

**Tasks for Day 10:**
- Add CORS middleware with `allow_origins=["*"]` for development
- Write a middleware that adds a request ID header to every response
- Write a global exception handler for 404 and a custom exception class

---

### Day 11 — Project Structure + Dependency Organization

At this scale, the project needs clean separation. This is the production-ready layout.

**`app/dependencies.py` — all shared Depends() in one place:**
```python
from fastapi import Depends, HTTPException
from sqlalchemy.orm import Session
from app.database import SessionLocal
from app.models.user import User

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)) -> User:
    ...

def get_admin_user(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_admin:
        raise HTTPException(403, "Admin only")
    return current_user

def get_pagination(skip: int = 0, limit: int = 20):
    return {"skip": skip, "limit": min(limit, 100)}
```

**Separate schemas per operation:**
```python
# app/schemas/post.py
class PostCreate(BaseModel): ...    # input
class PostUpdate(BaseModel): ...    # partial input
class PostRead(BaseModel): ...      # output (single)
class PostListRead(BaseModel): ...  # output (list item — may have fewer fields)
class PostWithComments(PostRead):   # extended output
    comments: list[CommentRead] = []
```

**Service layer — thin views, logic elsewhere:**
```python
# app/services/post_service.py
from sqlalchemy.orm import Session, joinedload
from app.models.post import Post

def get_post_or_404(post_id: int, db: Session) -> Post:
    post = db.query(Post).options(joinedload(Post.category)).filter(Post.id == post_id).first()
    if not post:
        raise HTTPException(404, "Post not found")
    return post

def create_post(data: PostCreate, author_id: int, db: Session) -> Post:
    post = Post(**data.model_dump(), author_id=author_id)
    db.add(post)
    db.commit()
    db.refresh(post)
    return post
```

```python
# app/routers/posts.py — views stay thin
from app.services import post_service

@router.get("/{post_id}", response_model=PostRead)
def get_post(post_id: int, db: Session = Depends(get_db)):
    return post_service.get_post_or_404(post_id, db)

@router.post("/", response_model=PostRead, status_code=201)
def create_post(post: PostCreate, db: Session = Depends(get_db), user = Depends(get_current_user)):
    return post_service.create_post(post, user.id, db)
```

**Tasks for Day 11:**
- Move all DB logic out of routers into a `services/` layer
- Consolidate all `Depends()` functions into `dependencies.py`
- Ensure no router imports directly from `models/` — only from `services/`

---

### Day 12 — Testing with Pytest + TestClient

Django had `TestCase` and the test runner. FastAPI uses `pytest` + `TestClient` (which runs your app in memory, no server needed).

```bash
pip install pytest httpx pytest-asyncio
```

**Basic test setup:**
```python
# tests/conftest.py
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from app.database import Base
from app.dependencies import get_db
from main import app

SQLALCHEMY_TEST_URL = "sqlite:///./test.db"
engine = create_engine(SQLALCHEMY_TEST_URL, connect_args={"check_same_thread": False})
TestSessionLocal = sessionmaker(bind=engine)

@pytest.fixture
def db():
    Base.metadata.create_all(bind=engine)
    session = TestSessionLocal()
    try:
        yield session
    finally:
        session.close()
        Base.metadata.drop_all(bind=engine)

@pytest.fixture
def client(db):
    def override_get_db():
        yield db
    app.dependency_overrides[get_db] = override_get_db    # swap real DB for test DB
    yield TestClient(app)
    app.dependency_overrides.clear()
```

**Writing tests:**
```python
# tests/test_posts.py
def test_list_posts_empty(client):
    response = client.get("/posts/")
    assert response.status_code == 200
    assert response.json() == []

def test_create_post(client, auth_headers):
    payload = {"title": "Test Post", "content": "Some content here", "category_id": 1}
    response = client.post("/posts/", json=payload, headers=auth_headers)
    assert response.status_code == 201
    assert response.json()["title"] == "Test Post"

def test_create_post_validation_error(client, auth_headers):
    payload = {"title": "Hi", "content": "x"}    # title too short
    response = client.post("/posts/", json=payload, headers=auth_headers)
    assert response.status_code == 422

def test_get_post_not_found(client):
    response = client.get("/posts/99999")
    assert response.status_code == 404
```

**`dependency_overrides` — the most important testing concept:**

This is how you swap real dependencies (DB, auth) for test versions. Equivalent to Django's test database but far more flexible.

```python
# Override auth for tests — skip real JWT verification
@pytest.fixture
def auth_headers(client, db):
    # create a real test user in the test DB
    user = User(username="testuser", hashed_password=hash_password("pass"))
    db.add(user)
    db.commit()
    token = create_access_token({"sub": str(user.id)})
    return {"Authorization": f"Bearer {token}"}
```

**Tasks for Day 12:**
- Write `conftest.py` with `client` and `db` fixtures
- Write tests for: list (empty), create (success), create (validation error), get (404)
- Use `dependency_overrides` to replace `get_db` with the test session
- Run with `pytest -v`

---

### Day 13 — File Uploads + Query Filtering + Pagination

**File upload:**
```python
from fastapi import File, UploadFile
import shutil

@router.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    with open(f"uploads/{file.filename}", "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"filename": file.filename, "content_type": file.content_type}

# Multiple files
@router.post("/upload-many")
async def upload_files(files: list[UploadFile] = File(...)):
    return [{"filename": f.filename} for f in files]
```

**Manual pagination (replaces DRF's `PageNumberPagination`):**
```python
from pydantic import BaseModel
from typing import Generic, TypeVar

T = TypeVar("T")

class PaginatedResponse(BaseModel, Generic[T]):
    total: int
    page: int
    page_size: int
    results: list[T]

@router.get("/", response_model=PaginatedResponse[PostRead])
def list_posts(page: int = 1, page_size: int = 10, db: Session = Depends(get_db)):
    skip = (page - 1) * page_size
    total = db.query(Post).count()
    posts = db.query(Post).offset(skip).limit(page_size).all()
    return {"total": total, "page": page, "page_size": page_size, "results": posts}
```

**Filtering via query params:**
```python
@router.get("/")
def list_posts(
    search: str | None = None,
    category_id: int | None = None,
    is_published: bool | None = None,
    db: Session = Depends(get_db),
):
    query = db.query(Post).options(joinedload(Post.category))
    if search:
        query = query.filter(Post.title.ilike(f"%{search}%"))
    if category_id:
        query = query.filter(Post.category_id == category_id)
    if is_published is not None:
        query = query.filter(Post.is_published == is_published)
    return query.all()
```

**Tasks for Day 13:**
- Add paginated response to your list endpoint
- Add at least 3 query param filters
- Add a file upload endpoint
- Confirm filters appear in `/docs` with correct types

---

### Day 14 — Mini Project Day (Tie Everything Together)

Build a complete Blog API from scratch using every concept from the past 13 days.

**Models to create:**
- `User` (id, username, email, hashed_password, is_active, is_admin)
- `Category` (id, name)
- `Post` (id, title, content, author FK, category FK, is_published, created_at)
- `Comment` (id, post FK, author FK, body, created_at)

**Endpoints to implement:**

| Method | URL | Auth | Description |
|---|---|---|---|
| POST | `/auth/register` | Public | Register new user |
| POST | `/auth/token` | Public | Login, return JWT |
| GET | `/posts/` | Public | List published posts (paginated + filtered) |
| POST | `/posts/` | Required | Create post |
| GET | `/posts/{id}` | Public | Post detail with nested category + comment count |
| PUT | `/posts/{id}` | Owner | Update post |
| DELETE | `/posts/{id}` | Owner | Delete post |
| GET | `/posts/{id}/comments/` | Public | List comments for a post |
| POST | `/posts/{id}/comments/` | Required | Add comment |
| GET | `/categories/` | Public | List all categories (read-only) |

**Completion checklist:**
- [ ] `joinedload(Post.category)` on all post queries — no N+1
- [ ] Separate `PostCreate`, `PostUpdate`, `PostRead` schemas
- [ ] `response_model` on every endpoint
- [ ] `get_current_user` dependency protecting create/update/delete
- [ ] Owner check before update/delete (raise 403 if not owner)
- [ ] `PaginatedResponse` on list endpoints
- [ ] Query param filtering: `?search=`, `?category_id=`, `?is_published=`
- [ ] Background task that logs on post creation
- [ ] CORS middleware configured
- [ ] Global exception handler for 404
- [ ] Alembic migrations for all tables
- [ ] At least 5 pytest tests using `TestClient` + `dependency_overrides`
- [ ] All endpoints visible and testable in `/docs`

---

## Quick Reference: Django vs FastAPI Side by Side

| Task | Django | FastAPI |
|---|---|---|
| Start project | `django-admin startproject` | `pip install fastapi` + create `main.py` |
| Run server | `python manage.py runserver` | `uvicorn main:app --reload` |
| Create tables | `makemigrations` + `migrate` | `alembic revision --autogenerate` + `alembic upgrade head` |
| Define route | `path()` in `urls.py` | `@router.get()` on function |
| Request body | `serializer = PostSerializer(data=request.data)` | `def create(post: PostCreate)` — automatic |
| Current user | `request.user` | `user = Depends(get_current_user)` |
| Protect endpoint | `permission_classes = [IsAuthenticated]` | `Depends(get_current_user)` |
| Validate input | `serializer.is_valid(raise_exception=True)` | Automatic — Pydantic raises 422 |
| Format output | `serializer.data` | `response_model=PostRead` |
| N+1 fix | `select_related("category")` | `options(joinedload(Post.category))` |
| Pagination | `PageNumberPagination` | Manual with `offset()` / `limit()` or `fastapi-pagination` |
| Admin panel | Free at `/admin` | No built-in — use `fastapi-admin` or `sqladmin` |
| Env config | `settings.py` | `pydantic-settings` + `.env` |
| Auto docs | None built-in | Free at `/docs` and `/redoc` |
| Async | Add-on (Django 4.1+) | First-class — `async def` everywhere |

---

## SQLAlchemy ORM Cheat Sheet (Your Django ORM Replacement)

```python
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import select, or_, and_, func

# All records
db.query(Post).all()

# Filter
db.query(Post).filter(Post.is_published == True).all()
db.query(Post).filter(Post.title.ilike("%django%")).all()       # icontains
db.query(Post).filter(Post.id.in_([1, 2, 3])).all()            # __in
db.query(Post).filter(Post.created_at.isnot(None)).all()        # isnull=False

# OR / AND
db.query(Post).filter(or_(Post.title.ilike("%x%"), Post.content.ilike("%x%"))).all()

# Single record
db.query(Post).filter(Post.id == id).first()                    # returns None if missing

# Order + limit
db.query(Post).order_by(Post.created_at.desc()).limit(10).all()

# Count
db.query(Post).filter(Post.is_published == True).count()

# JOIN (select_related equivalent)
db.query(Post).options(joinedload(Post.category)).all()

# Create
post = Post(title="x", content="y")
db.add(post)
db.commit()
db.refresh(post)

# Update
db.query(Post).filter(Post.id == id).update({"title": "new"})
db.commit()

# Delete
db.query(Post).filter(Post.id == id).delete()
db.commit()

# Aggregation
from sqlalchemy import func
db.query(func.count(Post.id)).scalar()
```

---

*After 14 days you will have covered FastAPI's full request cycle, Pydantic schemas, dependency injection, SQLAlchemy ORM, Alembic migrations, JWT authentication, async concepts, middleware, and a complete tested mini-project. The gap from intermediate Django to confident FastAPI is exactly this wide — and this is all of it.*
