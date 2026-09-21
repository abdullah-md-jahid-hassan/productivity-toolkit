# Django 14-Day Guideline for FastAPI Developers
### From FastAPI Background → Basic-to-Intermediate Django in 2 Weeks

---

## Before You Start: The Mental Shift

You already know REST, Python, async concepts, and Pydantic validation. Django is **batteries-included** — it ships things you had to wire manually in FastAPI. The key mindset changes:

| FastAPI | Django Equivalent |
|---|---|
| Pydantic models (validation + schema) | **Serializers** (DRF) — brand new concept for you |
| Path decorators (`@app.get`) | `urls.py` routing files |
| `app = FastAPI()` + routers | Project + apps structure |
| You wire your own admin UI | **Free pass** — Django admin is built-in, zero effort |
| Dependency injection | Middleware + signals |
| Manual DB session (SQLAlchemy) | Django ORM — built-in, no setup needed |
| Pydantic `BaseModel` | `models.Model` for DB, `Serializer` for I/O |

---

## The File System — Read This First

Before writing logic, understand what every file does.

```
myproject/
├── manage.py                   ← CLI tool (runserver, migrate, createsuperuser)
├── myproject/
│   ├── settings.py             ← Global config (DB, apps, middleware, keys)
│   ├── urls.py                 ← Root URL router — entry point for all routes
│   ├── asgi.py / wsgi.py       ← Server entry points
└── myapp/
    ├── models.py               ← DB schema (ORM models)
    ├── views.py                ← Business logic + HTTP response
    ├── urls.py                 ← App-level URL routes
    ├── serializers.py          ← Input validation + output formatting (DRF)
    ├── admin.py                ← Register models to the free admin panel
    ├── apps.py                 ← App config
    └── migrations/             ← Auto-generated DB migration scripts
```

---

## Week 1 — Days 1 to 7: Foundation

---

### Day 1 — Setup + Project Structure

**Install:**
```bash
pip install django djangorestframework psycopg2-binary python-decouple
django-admin startproject core .
python manage.py startapp users
```

**`settings.py` — Key sections to understand:**
```python
INSTALLED_APPS = [
    'django.contrib.admin',       # The free pass — gives you /admin UI for free
    'django.contrib.auth',        # Built-in user model + auth system
    'rest_framework',             # DRF — adds serializers and API views
    'users',                      # Your custom app
]

DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': 'mydb',
        'USER': 'postgres',
        'PASSWORD': 'yourpassword',
        'HOST': 'localhost',
    }
}

REST_FRAMEWORK = {
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
}
```

**Tasks for Day 1:**
- Create project and one app
- Register the app in `INSTALLED_APPS`
- Run `python manage.py runserver` — confirm it works
- Open `http://127.0.0.1:8000/admin` — you will see the free admin login

---

### Day 2 — URLs and Views

**Comparison with FastAPI:**
```python
# FastAPI
@app.get("/users/{id}")
def get_user(id: int): ...

# Django urls.py
path("users/<int:id>/", views.get_user, name="get-user")
```

**Root `urls.py` (project level):**
```python
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path("admin/", admin.site.urls),              # Free admin panel route
    path("api/users/", include("users.urls")),    # Delegate to app-level urls
]
```

**App-level `users/urls.py`:**
```python
from django.urls import path
from . import views

urlpatterns = [
    path("", views.user_list, name="user-list"),
    path("<int:id>/", views.user_detail, name="user-detail"),
]
```

**Function-Based View (FBV):**
```python
from django.http import JsonResponse

def user_list(request):
    if request.method == "GET":
        return JsonResponse({"users": []})
```

**Tasks for Day 2:**
- Create 3 URL routes across root and app `urls.py`
- Write matching function-based views
- Use `include()` to connect app URLs to root URLs
- Test all routes in browser or Postman

---

### Day 3 — Models + Migrations (ORM Basics)

**Define models:**
```python
# users/models.py
from django.db import models

class Category(models.Model):
    name = models.CharField(max_length=100)

    def __str__(self):
        return self.name

class Post(models.Model):
    title = models.CharField(max_length=200)
    content = models.TextField()
    category = models.ForeignKey(Category, on_delete=models.CASCADE, related_name="posts")
    created_at = models.DateTimeField(auto_now_add=True)
    is_published = models.BooleanField(default=False)

    class Meta:
        ordering = ["-created_at"]    # newest first by default

    def __str__(self):
        return self.title
```

**Migrations workflow:**
```bash
python manage.py makemigrations    # generates migration file from model changes
python manage.py migrate           # applies migrations to the database
```

**Tasks for Day 3:**
- Define at least 2 models with a ForeignKey relationship
- Run makemigrations and migrate
- Open the `migrations/` folder and read the generated file to understand what it does

---

### Day 4 — ORM Queries (The Core Power)

This is Django's biggest advantage. Invest time here.

**Basic CRUD:**
```python
# Create
post = Post.objects.create(title="Hello", content="World", category=cat)

# Read
Post.objects.all()                          # all records
Post.objects.filter(is_published=True)      # WHERE clause
Post.objects.get(id=1)                      # single record, raises error if not found
Post.objects.first()                        # first record
Post.objects.order_by("title")             # ORDER BY
Post.objects.count()                        # COUNT(*)

# Update
Post.objects.filter(id=1).update(title="Updated")

# Delete
Post.objects.filter(id=1).delete()
```

**Filtering:**
```python
Post.objects.filter(title__icontains="django")   # LIKE '%django%' (case-insensitive)
Post.objects.filter(created_at__year=2024)
Post.objects.exclude(is_published=False)
```

**`select_related` — for ForeignKey (one JOIN query):**
```python
# BAD — hits DB once per post to get category (N+1 problem)
posts = Post.objects.all()
for post in posts:
    print(post.category.name)    # separate query each time

# GOOD — one SQL JOIN fetches everything
posts = Post.objects.select_related("category").all()
for post in posts:
    print(post.category.name)    # no extra query
```

**`prefetch_related` — for ManyToMany or reverse FK (two queries, Python-side join):**
```python
# Fetching categories with all their posts efficiently
categories = Category.objects.prefetch_related("posts").all()
for cat in categories:
    print(cat.posts.all())       # no extra queries
```

**Rule of thumb:**
- `select_related` → ForeignKey / OneToOne (forward relation) → uses SQL JOIN
- `prefetch_related` → ManyToMany / reverse FK → uses 2 queries + Python join

**Tasks for Day 4:**
- Write 10 different ORM queries in Django shell: `python manage.py shell`
- Demonstrate the N+1 problem and fix it with `select_related`
- Use `filter` with at least 3 different lookups (`__icontains`, `__gte`, `__in`)

---

### Day 5 — The Admin Panel (Your Free Pass)

Django's admin is a fully functional CRUD interface generated for free from your models. No frontend code needed.

**Register models:**
```python
# users/admin.py
from django.contrib import admin
from .models import Category, Post

@admin.register(Post)
class PostAdmin(admin.ModelAdmin):
    list_display = ["title", "category", "is_published", "created_at"]
    list_filter = ["is_published", "category"]
    search_fields = ["title", "content"]
    list_editable = ["is_published"]
    ordering = ["-created_at"]
    readonly_fields = ["created_at"]

@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ["name"]
    search_fields = ["name"]
```

**Create a superuser to log in:**
```bash
python manage.py createsuperuser
```

**Visit `http://127.0.0.1:8000/admin`** — you now have a full admin dashboard.

**Why this is your free pass:**
- No client work needed during development
- Manage all data visually
- Test models and relationships instantly
- Can be used as an internal tool in production with zero extra code

**Tasks for Day 5:**
- Register all your models with `@admin.register`
- Configure `list_display`, `search_fields`, and `list_filter` on each
- Create, update, and delete records through the admin UI
- Add `list_editable` to toggle `is_published` directly from the list view

---

### Day 6 — Serializers (Completely New to FastAPI Devs)

In FastAPI you used Pydantic `BaseModel` for request/response schemas. Django REST Framework uses **Serializers** — they do the same job but with more power: validation, transformation, nested objects, and write operations all in one class.

**The FastAPI way (for comparison):**
```python
class PostSchema(BaseModel):
    title: str
    content: str
    category_id: int
```

**The Django/DRF way:**
```python
# users/serializers.py
from rest_framework import serializers
from .models import Post, Category

class CategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = ["id", "name"]

class PostSerializer(serializers.ModelSerializer):
    category = CategorySerializer(read_only=True)       # nested object on output
    category_id = serializers.PrimaryKeyRelatedField(   # accepts ID on input
        queryset=Category.objects.all(),
        source="category",
        write_only=True
    )

    class Meta:
        model = Post
        fields = ["id", "title", "content", "category", "category_id", "is_published", "created_at"]
        read_only_fields = ["created_at"]

    def validate_title(self, value):
        if len(value) < 3:
            raise serializers.ValidationError("Title must be at least 3 characters.")
        return value

    def validate(self, data):
        # Cross-field validation
        return data
```

**Using a serializer in a view:**
```python
# Deserialize (input) — like FastAPI request body parsing
serializer = PostSerializer(data=request.data)
if serializer.is_valid(raise_exception=True):
    serializer.save()

# Serialize (output) — like FastAPI response_model
post = Post.objects.get(id=1)
serializer = PostSerializer(post)
return Response(serializer.data)

# Many objects
posts = Post.objects.all()
serializer = PostSerializer(posts, many=True)
return Response(serializer.data)
```

**Key serializer types:**
| Type | Use Case |
|---|---|
| `ModelSerializer` | Tied to a model — auto-generates fields |
| `Serializer` | Manual fields — full control |
| `HyperlinkedModelSerializer` | Uses URLs instead of IDs for relations |

**Tasks for Day 6:**
- Write a `ModelSerializer` for each of your models
- Add custom `validate_<field>` method for at least one field
- Handle a nested serializer (read) + `PrimaryKeyRelatedField` (write)
- Test input validation by sending bad data and reading the error response

---

### Day 7 — API Views with DRF

Now combine URLs, views, and serializers into real API endpoints.

**Function-based API view:**
```python
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from .models import Post
from .serializers import PostSerializer

@api_view(["GET", "POST"])
def post_list(request):
    if request.method == "GET":
        posts = Post.objects.select_related("category").all()
        serializer = PostSerializer(posts, many=True)
        return Response(serializer.data)

    if request.method == "POST":
        serializer = PostSerializer(data=request.data)
        if serializer.is_valid(raise_exception=True):
            serializer.save()
            return Response(serializer.data, status=status.HTTP_201_CREATED)

@api_view(["GET", "PUT", "DELETE"])
def post_detail(request, id):
    try:
        post = Post.objects.select_related("category").get(id=id)
    except Post.DoesNotExist:
        return Response({"error": "Not found"}, status=status.HTTP_404_NOT_FOUND)

    if request.method == "GET":
        return Response(PostSerializer(post).data)

    if request.method == "PUT":
        serializer = PostSerializer(post, data=request.data)
        if serializer.is_valid(raise_exception=True):
            serializer.save()
            return Response(serializer.data)

    if request.method == "DELETE":
        post.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
```

**Tasks for Day 7:**
- Build full CRUD API for your Post model using `@api_view`
- Always use `select_related` when fetching related objects
- Test all endpoints in Postman or DRF's built-in browsable API (`http://localhost:8000/api/`)
- Confirm serializer validation errors are returned properly

---

## Week 2 — Days 8 to 14: Intermediate

---

### Day 8 — All DRF View Types (The Full Picture)

DRF has a layered view system. Each layer adds more built-in behaviour. Understand all of them — you will choose between them daily.

---

#### The DRF View Hierarchy (top to bottom = more abstraction)

```
@api_view                         ← function-based, manual everything
APIView                           ← class-based, manual everything
  └── GenericAPIView              ← adds queryset, serializer_class, get_object()
        └── Mixins                ← add list, create, retrieve, update, destroy
              └── Generic Views   ← pre-combined mixin classes (ListAPIView, etc.)
                    └── ViewSet   ← groups related views under one class
                          └── ModelViewSet / ReadOnlyModelViewSet
```

---

#### Layer 1 — `@api_view` (already covered Day 7, recap only)

```python
from rest_framework.decorators import api_view
from rest_framework.response import Response

@api_view(["GET", "POST"])
def post_list(request):
    if request.method == "GET":
        return Response(PostSerializer(Post.objects.all(), many=True).data)
    serializer = PostSerializer(data=request.data)
    serializer.is_valid(raise_exception=True)
    serializer.save()
    return Response(serializer.data, status=201)
```

**When to use:** Quick one-off endpoints, simple non-CRUD logic.

---

#### Layer 2 — `APIView`

The base class for all DRF class-based views. You define `get()`, `post()`, `put()`, `patch()`, `delete()` methods manually.

```python
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status

class PostListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        posts = Post.objects.select_related("category").all()
        return Response(PostSerializer(posts, many=True).data)

    def post(self, request):
        serializer = PostSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(author=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

class PostDetailView(APIView):
    def get_object(self, pk):
        try:
            return Post.objects.select_related("category").get(pk=pk)
        except Post.DoesNotExist:
            raise Http404

    def get(self, request, pk):
        return Response(PostSerializer(self.get_object(pk)).data)

    def put(self, request, pk):
        serializer = PostSerializer(self.get_object(pk), data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data)

    def delete(self, request, pk):
        self.get_object(pk).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)
```

**When to use:** Non-standard logic, endpoints that do not map cleanly to a single model, full manual control.

---

#### Layer 3 — `GenericAPIView`

Adds `queryset`, `serializer_class`, `get_object()`, `get_queryset()`, and pagination support. Does NOT add any HTTP method handlers on its own — you still define `get()`, `post()`, etc. yourself, but you get helper methods for free.

```python
from rest_framework.generics import GenericAPIView

class PostListView(GenericAPIView):
    queryset = Post.objects.select_related("category").all()
    serializer_class = PostSerializer
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = self.get_queryset()           # uses self.queryset, applies filters
        serializer = self.get_serializer(qs, many=True)
        return Response(serializer.data)

    def post(self, request):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(serializer.data, status=201)
```

**When to use:** Base for building custom views that need queryset/serializer wiring but non-standard HTTP logic.

---

#### Layer 4 — Mixins

Mixins add individual HTTP actions to `GenericAPIView`. You combine them yourself.

```python
from rest_framework import mixins, generics

# Available mixins
# mixins.ListModelMixin       → adds list()     → handles GET (many)
# mixins.CreateModelMixin     → adds create()   → handles POST
# mixins.RetrieveModelMixin   → adds retrieve() → handles GET (single)
# mixins.UpdateModelMixin     → adds update()   → handles PUT + PATCH
# mixins.DestroyModelMixin    → adds destroy()  → handles DELETE

class PostListView(mixins.ListModelMixin, mixins.CreateModelMixin, generics.GenericAPIView):
    queryset = Post.objects.select_related("category").all()
    serializer_class = PostSerializer

    def get(self, request):
        return self.list(request)       # from ListModelMixin

    def post(self, request):
        return self.create(request)     # from CreateModelMixin
```

**When to use:** Rare — only when you need to mix actions in non-standard combinations.

---

#### Layer 5 — Concrete Generic Views (use these most often)

DRF pre-combines the mixins for the most common patterns. These are your daily workhorses.

```python
from rest_framework import generics

# Single-action views
generics.ListAPIView            # GET    → returns a list
generics.CreateAPIView          # POST   → creates one object
generics.RetrieveAPIView        # GET    → returns one object by pk
generics.UpdateAPIView          # PUT/PATCH → updates one object
generics.DestroyAPIView         # DELETE → deletes one object

# Combined views (most commonly used)
generics.ListCreateAPIView              # GET list + POST create
generics.RetrieveUpdateAPIView          # GET detail + PUT/PATCH
generics.RetrieveDestroyAPIView         # GET detail + DELETE
generics.RetrieveUpdateDestroyAPIView   # GET detail + PUT/PATCH + DELETE
```

**Real usage:**
```python
from rest_framework import generics
from rest_framework.permissions import IsAuthenticatedOrReadOnly

class PostListCreateView(generics.ListCreateAPIView):
    queryset = Post.objects.select_related("category").all()
    serializer_class = PostSerializer
    permission_classes = [IsAuthenticatedOrReadOnly]

    def perform_create(self, serializer):
        serializer.save(author=self.request.user)   # inject extra field on save

class PostDetailView(generics.RetrieveUpdateDestroyAPIView):
    queryset = Post.objects.select_related("category").all()
    serializer_class = PostSerializer
    permission_classes = [IsAuthenticatedOrReadOnly]
```

```python
# urls.py
urlpatterns = [
    path("posts/", PostListCreateView.as_view(), name="post-list"),
    path("posts/<int:pk>/", PostDetailView.as_view(), name="post-detail"),
]
```

**Hooks you can override without rewriting the whole view:**
```python
def get_queryset(self):
    # filter by current user or query params
    return Post.objects.filter(author=self.request.user)

def get_serializer_class(self):
    if self.request.method in ["POST", "PUT", "PATCH"]:
        return PostWriteSerializer
    return PostReadSerializer

def perform_create(self, serializer):
    serializer.save(author=self.request.user)

def perform_update(self, serializer):
    serializer.save()

def perform_destroy(self, instance):
    instance.delete()
```

**When to use:** Standard CRUD endpoints on a single model. This covers ~80% of all API endpoints you will write.

---

#### Layer 6 — `ViewSet` and `ModelViewSet`

A ViewSet groups all related views into one class. Combined with a Router, it auto-generates all URLs.

**`ModelViewSet` — full CRUD, auto-routed:**
```python
from rest_framework.viewsets import ModelViewSet
from rest_framework.permissions import IsAuthenticatedOrReadOnly

class PostViewSet(ModelViewSet):
    queryset = Post.objects.select_related("category").all()
    serializer_class = PostSerializer
    permission_classes = [IsAuthenticatedOrReadOnly]

    def perform_create(self, serializer):
        serializer.save(author=self.request.user)

    def get_queryset(self):
        qs = super().get_queryset()
        category = self.request.query_params.get("category")
        if category:
            qs = qs.filter(category__id=category)
        return qs
```

**Actions that `ModelViewSet` auto-provides:**

| Router Action | HTTP Method | URL Pattern | ViewSet Method |
|---|---|---|---|
| `list` | GET | `/posts/` | `list()` |
| `create` | POST | `/posts/` | `create()` |
| `retrieve` | GET | `/posts/{id}/` | `retrieve()` |
| `update` | PUT | `/posts/{id}/` | `update()` |
| `partial_update` | PATCH | `/posts/{id}/` | `partial_update()` |
| `destroy` | DELETE | `/posts/{id}/` | `destroy()` |

```python
# urls.py — Router auto-generates all 6 URL patterns above
from rest_framework.routers import DefaultRouter

router = DefaultRouter()
router.register("posts", PostViewSet, basename="post")

urlpatterns = router.urls
```

---

#### `ReadOnlyModelViewSet` — read-only endpoints only

```python
from rest_framework.viewsets import ReadOnlyModelViewSet

class CategoryViewSet(ReadOnlyModelViewSet):
    queryset = Category.objects.all()
    serializer_class = CategorySerializer
    # Only generates: GET /categories/ and GET /categories/{id}/
```

**When to use:** Public reference data (categories, tags, countries) that users can read but not modify.

---

#### `@action` — custom endpoints on a ViewSet

Add non-standard endpoints that do not fit list/create/retrieve/update/destroy.

```python
from rest_framework.decorators import action
from rest_framework.response import Response

class PostViewSet(ModelViewSet):
    queryset = Post.objects.all()
    serializer_class = PostSerializer

    # GET /posts/{id}/publish/
    @action(detail=True, methods=["post"], permission_classes=[IsAuthenticated])
    def publish(self, request, pk=None):
        post = self.get_object()
        post.is_published = True
        post.save()
        return Response({"status": "published"})

    # GET /posts/my_posts/
    @action(detail=False, methods=["get"], permission_classes=[IsAuthenticated])
    def my_posts(self, request):
        posts = Post.objects.filter(author=request.user)
        return Response(PostSerializer(posts, many=True).data)
```

- `detail=True` → operates on one object, URL includes `{id}`: `/posts/{id}/publish/`
- `detail=False` → operates on the collection, no `{id}`: `/posts/my_posts/`

---

#### Choosing the Right View — Decision Guide

```
Does the endpoint map to a single model with standard CRUD?
  └── YES → Is it a group of related endpoints (list + detail)?
              └── YES → ModelViewSet + Router
              └── NO  → Concrete generic view (ListCreateAPIView, etc.)
  └── NO  → Does it need queryset + serializer wiring?
              └── YES → GenericAPIView (override get/post manually)
              └── NO  → APIView or @api_view
```

**Quick rule:**
- `ModelViewSet` for standard resource APIs (posts, users, products)
- `ListCreateAPIView` / `RetrieveUpdateDestroyAPIView` for simpler two-file URL layouts
- `APIView` for auth endpoints, dashboards, aggregations, non-model logic
- `@action` for extra behaviour on an existing ViewSet (publish, archive, export)

---

**Tasks for Day 8:**
- Build the same Post CRUD four ways: `@api_view` → `APIView` → `ListCreateAPIView + RetrieveUpdateDestroyAPIView` → `ModelViewSet`
- Observe how much code shrinks at each layer
- Add a `ReadOnlyModelViewSet` for Categories
- Add a custom `@action` called `publish` that sets `is_published=True`
- Confirm the router generates all URLs with `python manage.py show_urls` (install `django-extensions` first)

---

### Day 9 — Authentication + Permissions

**Built-in token auth setup:**
```python
# settings.py
INSTALLED_APPS += ['rest_framework.authtoken']

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework.authentication.TokenAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': [
        'rest_framework.permissions.IsAuthenticated',
    ],
}
```

```bash
python manage.py migrate    # creates the token table
```

**Login view to get a token:**
```python
from rest_framework.authtoken.models import Token
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from django.contrib.auth import authenticate

@api_view(["POST"])
@permission_classes([AllowAny])
def login(request):
    username = request.data.get("username")
    password = request.data.get("password")
    user = authenticate(username=username, password=password)
    if user:
        token, _ = Token.objects.get_or_create(user=user)
        return Response({"token": token.key})
    return Response({"error": "Invalid credentials"}, status=400)
```

**Custom permission:**
```python
from rest_framework.permissions import BasePermission

class IsOwner(BasePermission):
    def has_object_permission(self, request, view, obj):
        return obj.author == request.user
```

**Tasks for Day 9:**
- Set up token authentication in settings
- Build a login endpoint that returns a token
- Protect your Post endpoints with `IsAuthenticated`
- Write a custom `IsOwner` permission and apply it to the delete endpoint

---

### Day 10 — Advanced ORM + QuerySet Optimization

**Annotations — add computed fields to querysets:**
```python
from django.db.models import Count, Avg, Q

# Count posts per category
categories = Category.objects.annotate(post_count=Count("posts"))
for cat in categories:
    print(cat.name, cat.post_count)    # no extra query

# Filter with complex conditions
Post.objects.filter(
    Q(title__icontains="django") | Q(content__icontains="django")
)
```

**`values()` and `values_list()` — lighter queries:**
```python
# Only fetch specific columns (like SELECT title, id FROM post)
Post.objects.values("id", "title")
Post.objects.values_list("id", "title", flat=False)
Post.objects.values_list("id", flat=True)    # flat list of IDs
```

**`only()` and `defer()` — partial model loading:**
```python
Post.objects.only("id", "title")      # load only these fields
Post.objects.defer("content")         # load everything except content
```

**Chaining and slicing:**
```python
Post.objects.filter(is_published=True).select_related("category").order_by("-created_at")[:10]
```

**Tasks for Day 10:**
- Use `annotate(Count(...))` to add computed fields to a queryset
- Combine `Q` objects for OR/AND filtering
- Compare query counts: a naive loop vs. `select_related` using Django Debug Toolbar or print statements
- Use `values_list("id", flat=True)` to get a flat list of IDs

---

### Day 11 — Serializer Depth: Nested + Custom Fields

**Read vs. write serializer pattern:**
```python
class PostWriteSerializer(serializers.ModelSerializer):
    class Meta:
        model = Post
        fields = ["title", "content", "category", "is_published"]

class PostReadSerializer(serializers.ModelSerializer):
    category = CategorySerializer(read_only=True)
    author_name = serializers.SerializerMethodField()

    class Meta:
        model = Post
        fields = ["id", "title", "content", "category", "author_name", "created_at"]

    def get_author_name(self, obj):
        return obj.author.get_full_name() if obj.author else None
```

**Use different serializers per action in a ViewSet:**
```python
class PostViewSet(ModelViewSet):
    def get_serializer_class(self):
        if self.action in ["create", "update", "partial_update"]:
            return PostWriteSerializer
        return PostReadSerializer
```

**`SerializerMethodField` — add any computed value:**
```python
word_count = serializers.SerializerMethodField()

def get_word_count(self, obj):
    return len(obj.content.split())
```

**Tasks for Day 11:**
- Create separate read and write serializers for a model
- Add 2 `SerializerMethodField` fields with real computed logic
- Switch serializers per action in a ViewSet using `get_serializer_class`

---

### Day 12 — Filtering, Pagination, and Search

**Pagination in settings:**
```python
REST_FRAMEWORK = {
    'DEFAULT_PAGINATION_CLASS': 'rest_framework.pagination.PageNumberPagination',
    'PAGE_SIZE': 10,
}
```

**Custom pagination:**
```python
from rest_framework.pagination import PageNumberPagination

class StandardPagination(PageNumberPagination):
    page_size = 20
    page_size_query_param = "page_size"
    max_page_size = 100
```

**Filtering with `django-filter`:**
```bash
pip install django-filter
```

```python
# settings.py
INSTALLED_APPS += ['django_filters']
REST_FRAMEWORK = {
    'DEFAULT_FILTER_BACKENDS': ['django_filters.rest_framework.DjangoFilterBackend'],
}

# views.py
import django_filters

class PostFilter(django_filters.FilterSet):
    is_published = django_filters.BooleanFilter()
    category = django_filters.NumberFilter(field_name="category__id")
    title = django_filters.CharFilter(lookup_expr="icontains")

    class Meta:
        model = Post
        fields = ["is_published", "category", "title"]

class PostViewSet(ModelViewSet):
    filterset_class = PostFilter
    search_fields = ["title", "content"]    # ?search=django
    ordering_fields = ["created_at", "title"]
```

**Tasks for Day 12:**
- Add `PageNumberPagination` to your ViewSet
- Install `django-filter` and write a `FilterSet` with 3 filter fields
- Test `?search=`, `?ordering=`, and `?page=` query params in Postman

---

### Day 13 — Signals + Custom Model Methods + Manager

**Signals — run code when model events happen:**
```python
# users/signals.py
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.contrib.auth.models import User
from rest_framework.authtoken.models import Token

@receiver(post_save, sender=User)
def create_token_on_user_create(sender, instance, created, **kwargs):
    if created:
        Token.objects.create(user=instance)
```

```python
# users/apps.py
class UsersConfig(AppConfig):
    def ready(self):
        import users.signals    # wire the signals on app startup
```

**Custom Manager:**
```python
class PublishedManager(models.Manager):
    def get_queryset(self):
        return super().get_queryset().filter(is_published=True)

class Post(models.Model):
    objects = models.Manager()          # default manager (keep this first)
    published = PublishedManager()      # custom manager

# Usage
Post.published.all()                    # only published posts
Post.published.select_related("category").filter(category__name="Tech")
```

**Custom model method:**
```python
class Post(models.Model):
    def is_recent(self):
        from django.utils import timezone
        return (timezone.now() - self.created_at).days < 7
```

**Tasks for Day 13:**
- Write a signal that auto-creates an auth token when a new user is created
- Write a custom Manager that filters by a status field
- Add a model method and expose it via a `SerializerMethodField`

---

### Day 14 — Mini Project Day (Tie Everything Together)

Build a small but complete API from scratch using every concept from the past 13 days.

**Project: Blog API**

**Models:**
- `User` (use Django's built-in)
- `Category` (name)
- `Post` (title, content, author FK, category FK, is_published, created_at)
- `Comment` (post FK, author FK, body, created_at)

**Endpoints to build:**

| Method | URL | Description |
|---|---|---|
| POST | `/api/auth/login/` | Return auth token |
| GET | `/api/posts/` | List published posts (paginated, filterable) |
| POST | `/api/posts/` | Create post (auth required) |
| GET | `/api/posts/{id}/` | Post detail with nested category + author |
| PUT | `/api/posts/{id}/` | Update (owner only) |
| DELETE | `/api/posts/{id}/` | Delete (owner only) |
| GET | `/api/posts/{id}/comments/` | List comments for a post |
| POST | `/api/posts/{id}/comments/` | Add comment (auth required) |

**Requirements checklist:**
- [ ] `select_related("author", "category")` on all Post querysets
- [ ] `prefetch_related("comments")` when listing posts with comment count
- [ ] Separate read/write serializers for Post
- [ ] `annotate(comment_count=Count("comments"))` on post list
- [ ] Custom `IsOwner` permission on update/delete
- [ ] All models registered in admin with `list_display` and `search_fields`
- [ ] Token authentication on protected endpoints
- [ ] Pagination on list endpoints
- [ ] Signal that auto-creates token on user creation
- [ ] At least one custom Manager (e.g., `Post.published`)

---

## Quick Reference: FastAPI vs Django Comparison

| Concept | FastAPI | Django/DRF |
|---|---|---|
| Request body | `Pydantic BaseModel` | `Serializer` with `is_valid()` |
| Response schema | `response_model=MyModel` | `Serializer(obj).data` |
| Route definition | `@app.get("/path")` | `path("path/", view)` in `urls.py` |
| Dependency injection | `Depends(...)` | Middleware / `get_object_or_404` |
| DB session | SQLAlchemy session | Django ORM (no session needed) |
| Auto docs | `/docs` (Swagger) | DRF Browsable API at each endpoint |
| Admin UI | None | Free at `/admin` |
| Auth | Manual / FastAPI Users | `rest_framework.authtoken` |
| Validation error | 422 Unprocessable Entity | 400 Bad Request (DRF) |

---

## ORM Cheat Sheet

```python
# Basic queries
Model.objects.all()
Model.objects.filter(field=value)
Model.objects.exclude(field=value)
Model.objects.get(pk=1)                    # raises DoesNotExist if not found
Model.objects.first() / .last()
Model.objects.count()
Model.objects.exists()

# ForeignKey optimization (always use these — avoid N+1)
Model.objects.select_related("fk_field")           # one JOIN — forward FK
Model.objects.prefetch_related("reverse_set")      # two queries — reverse FK / M2M

# Aggregation
from django.db.models import Count, Sum, Avg, Max, Min
Model.objects.aggregate(total=Count("id"))
Model.objects.annotate(item_count=Count("items"))

# Complex filters
from django.db.models import Q
Model.objects.filter(Q(a=1) | Q(b=2))             # OR
Model.objects.filter(Q(a=1) & Q(b=2))             # AND
Model.objects.filter(~Q(a=1))                      # NOT

# Field lookups
__exact, __iexact        # exact match, case-insensitive
__contains, __icontains  # LIKE, case-insensitive LIKE
__startswith, __endswith
__gt, __gte, __lt, __lte
__in                     # WHERE field IN (...)
__isnull                 # IS NULL / IS NOT NULL
__year, __month, __day   # date parts

# Performance
Model.objects.only("id", "name")      # load only these columns
Model.objects.defer("large_field")    # load all except these
Model.objects.values("id", "name")    # return dicts instead of model instances
Model.objects.values_list("id", flat=True)  # flat list
```

---

## Serializer Cheat Sheet

```python
# Read-only field
field = serializers.ReadOnlyField(source="user.email")

# Computed field
field = serializers.SerializerMethodField()
def get_field(self, obj): return obj.something

# Nested serializer (read)
category = CategorySerializer(read_only=True)

# Accept ID on write, return object on read
category_id = serializers.PrimaryKeyRelatedField(
    queryset=Category.objects.all(), source="category", write_only=True
)

# Validation
def validate_title(self, value):
    if len(value) < 3:
        raise serializers.ValidationError("Too short.")
    return value

def validate(self, data):
    # Cross-field validation
    return data

# Create / Update override
def create(self, validated_data):
    return Post.objects.create(**validated_data)

def update(self, instance, validated_data):
    instance.title = validated_data.get("title", instance.title)
    instance.save()
    return instance
```

---

## Common `manage.py` Commands

```bash
python manage.py runserver              # start dev server
python manage.py makemigrations         # generate migration from model changes
python manage.py migrate                # apply migrations to DB
python manage.py createsuperuser        # create admin user
python manage.py shell                  # interactive Python shell with Django loaded
python manage.py startapp appname       # create a new app
python manage.py collectstatic          # gather static files for production
python manage.py check                  # validate project for errors
```

---

*After 14 days following this plan, you will have covered Django's full request cycle, the ORM with real optimization patterns, DRF serializers from basic to advanced, the free admin panel, authentication, and a complete mini-project. The foundation is production-ready — scale it with experience.*
