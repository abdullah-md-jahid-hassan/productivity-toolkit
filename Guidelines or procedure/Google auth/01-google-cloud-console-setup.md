# Step 1 — Create the Google OAuth Client (Google Cloud Console)

> **Scope of this step:** everything here happens in a browser. No code is written, nothing is run.
> **Output of this step:** a Client ID, a Client Secret, and a registered redirect URI.
>
> Part of the "Login with Google" build. Reusable across projects — the
> project-specific bits are isolated at the bottom under
> [Project-specific notes](#project-specific-notes).

---

## 0. Background you need before clicking anything

### The one rule that prevents most confusion

**The frontend never verifies anything. Verification always happens on the backend.**

The browser only carries messages back and forth. It cannot be trusted, because
anything shipped to the browser can be read and modified by the user.

### Two keys, two very different jobs

| Key | Visibility | Where it lives |
|---|---|---|
| **Client ID** | Public. Fine in frontend JS, fine in a URL. | Anywhere. It just says "this request is from app X." |
| **Client Secret** | Private. Never in frontend code, never in a mobile app, never in git. | Backend server only, via environment variable. |

If the Client Secret leaks, anyone can impersonate your app. This is the real
reason the frontend "can't verify" — it does not have the secret required to
call Google's token endpoint.

### OAuth vs OIDC

What people call "OAuth login" is technically **OpenID Connect (OIDC)** — an
identity layer built on top of OAuth 2.0. Plain OAuth 2.0 was designed for
*permission sharing* ("let this app read my Drive"), not for *proving who
someone is*. The `id_token` is the OIDC part, and it is what actually proves
identity.

### The three flow variants (pick one before you register anything)

The choice determines **what you register as the redirect URI**, so decide now.

| Variant | `redirect_uri` points at | Trade-off |
|---|---|---|
| **A. Frontend gets code, POSTs to backend** ✅ recommended for SPA + JWT API | **Frontend** (`http://localhost:3000/auth/google/callback`) | Secret stays server-side, and your own access/refresh tokens are returned in a JSON body — never in a URL. Standard for DRF/Express/etc. + SPA. |
| **B. Backend gets code, redirects to frontend** | **Backend** (`http://localhost:8000/auth/google/callback/`) | Fully server-driven, classic for server-rendered apps. But your JWTs end up in a URL query string — visible in browser history, server logs, and `Referer` headers, unless you add a one-time exchange code on top. |
| **C. Google Identity Services (`id_token`)** | n/a — no redirect, popup-based | Simplest; no client secret needed at all. But you get identity only — no `access_token`, so you cannot later call Google APIs on the user's behalf without a second flow. |

**This guide assumes Variant A.** For B, swap the redirect URI for a backend
URL in [1e](#1e-create-the-oauth-client--this-is-where-the-credentials-come-from).

### The 8 steps of Variant A, end to end

```
1. User clicks "Sign in with Google"          [frontend]
2. Browser redirects to Google                [frontend]  carries client_id, redirect_uri, scope
3. User approves on Google's consent screen   [Google]
4. Google redirects back with ?code=...       [Google -> frontend]   code = a claim ticket, NOT user info
5. Frontend POSTs the code to the backend     [frontend -> backend]
6. Backend calls Google's token endpoint      [backend -> Google]    SERVER TO SERVER, sends client_secret
   Google returns access_token + id_token     [Google -> backend]    id_token = signed JWT w/ email, name, sub
7. Backend verifies id_token, then:           [backend]
      email exists?  -> log in
      email is new?  -> create user (registration)
   Backend issues its OWN session/JWT
8. Frontend is logged in                      [frontend]
```

Steps 6–7 are the whole security story. "Login with Google" and "Register with
Google" are the same code path — which is why it is one button, not two.

---

## 1. The clicking

### 1a. Create / select a project

1. Go to <https://console.cloud.google.com/>
2. Top-left project dropdown → **New Project**
3. Name it after your product → **Create**
4. **Confirm the new project is selected in the dropdown before continuing.**
   Configuring the wrong project is the single most common wasted-hour mistake here.

### 1b. Configure the consent screen

Left sidebar → **Google Auth Platform**
*(older UI: APIs & Services → OAuth consent screen)*

1. **Get started**, if prompted
2. **App name** — what users literally read on the account chooser. Use the real product name.
3. **User support email** — yours
4. **Audience** → **External**
   - *Internal* only appears if you have a Google Workspace org, and it limits
     login to your own domain. Almost never what you want.
5. **Contact information** — yours
6. Agree to policy → **Create**

### 1c. Add the scopes

**Data Access** *(older UI: OAuth consent screen → Scopes)* → **Add or remove scopes**.

Select exactly these three for a login-only integration:

| Scope | Why it is required |
|---|---|
| `openid` | Makes Google return the `id_token`. **Omit this and you get no `id_token` at all** — login cannot work. |
| `.../auth/userinfo.email` | The email address. Usually your user table's unique key. |
| `.../auth/userinfo.profile` | `given_name` / `family_name` / `picture`. |

All three are **non-sensitive** scopes, which means **no Google verification
review** is required to publish. Keep it that way if you can.

Do **not** bundle unrelated scopes (Calendar, Drive, Gmail) into the login
consent. Ask for them separately, at the moment the user actually enables that
feature. Bundling tanks signup conversion and can drag you into a verification
review.

### 1d. Add test users

While the app's publishing status is **Testing**, only explicitly listed
accounts can sign in. Everyone else hits `access_blocked`.

**Audience** → **Test users** → **Add users** → add your own account and every
teammate who will test.

> You do **not** need to publish or pass verification to build and test this.
> With only the three non-sensitive scopes above, publishing later is a
> one-click change with no review.

### 1e. Create the OAuth client — this is where the credentials come from

**Clients** *(older UI: APIs & Services → Credentials)* → **Create client**.

1. **Application type** → **Web application**
2. **Name** → e.g. `Web Login` (internal label; users never see it)
3. **Authorized JavaScript origins**
   ```
   http://localhost:3000
   ```
   Origins only — scheme + host + port. No path, no trailing slash.
4. **Authorized redirect URIs**
   ```
   http://localhost:3000/auth/google/callback
   ```
   Under Variant A this points at your **frontend**, and your frontend must
   actually have a route at that exact path.

   Add production URLs here too whenever you know them — you can return and
   edit this list at any time.
5. **Create**

A modal titled **"OAuth client created"** appears immediately, showing both
values. **This modal is the only place the credentials originate** — they do not
exist anywhere before this click.

```
Client ID       YOUR_CLIENT_ID.apps.googleusercontent.com
Client secret   GOCSPX-YOUR_CLIENT_SECRET_HERE
```

#### Sanity-check what you copied

| | Format | Notes |
|---|---|---|
| **Client ID** | `<digits>-<random>.apps.googleusercontent.com` | Always ends in `.apps.googleusercontent.com`. Public — safe in frontend code. |
| **Client secret** | `GOCSPX-<random>` | Modern secrets carry the `GOCSPX-` prefix. ~35 chars. Backend only, never in git. |

If your "client ID" does not end in `.apps.googleusercontent.com`, you copied the
wrong field — most likely the project number or an API key.

#### If you already closed the modal

Both values are recoverable; nothing is lost:

- **Clients** page → click the client's name → both are shown on the detail page
- Or the **download icon** (⬇) on the Clients row → JSON file containing both

Unlike Stripe or AWS, Google re-displays the secret in full on later visits — it
is not a one-time reveal. If a secret is ever genuinely lost or leaked,
**Add secret** on the client detail page issues a new one and lets you retire
the old one without downtime.

#### If "Create client" is greyed out

The consent screen must exist first. A disabled button — or a redirect into a
branding/audience form — means steps **1b–1c** are incomplete. Finish
**Branding → Audience → Data Access**, then return to **Clients**.

---

## 2. The redirect URI rules that break people in production

Google matches `redirect_uri` **character for character**. Every one of these is
a *different* URI as far as Google is concerned:

```
http://localhost:3000/auth/google/callback      <- registered
https://localhost:3000/auth/google/callback     <- different scheme
http://localhost:3000/auth/google/callback/     <- trailing slash
http://127.0.0.1:3000/auth/google/callback      <- 127.0.0.1 != localhost
http://localhost:3001/auth/google/callback      <- different port
```

The value sent in **step 2** (frontend → Google) and the value sent in
**step 6** (backend → Google token endpoint) must *both* be byte-identical to
the registered string. Any mismatch produces `redirect_uri_mismatch`.

This is why the backend endpoint should accept `redirect_uri` as a request
parameter — validated against a server-side allowlist, so it echoes exactly what
the frontend used without being open to abuse.

**This is the #1 cause of "it worked locally, it broke in production."** When
you deploy, the registered list, the frontend's value, and the backend's
allowlist must all be updated together.

---

## 3. Environment variables to set after this step

Add to `.env` (real values) **and** `.env.example` (fake placeholders only):

```bash
# Google OAuth
GOOGLE_CLIENT_ID=<client id from step 1e>
GOOGLE_CLIENT_SECRET=<client secret from step 1e>
GOOGLE_AUTH_REDIRECT_URIS=http://localhost:3000/auth/google/callback
```

`GOOGLE_AUTH_REDIRECT_URIS` is **plural / comma-separated** on purpose — it is
the backend allowlist, and it lets one deployment serve several environments:

```bash
GOOGLE_AUTH_REDIRECT_URIS=http://localhost:3000/auth/google/callback,https://app.example.com/auth/google/callback
```

### Secret hygiene — non-negotiable

- `GOOGLE_CLIENT_SECRET` comes from an environment variable. Never committed.
- Confirm `.env` is in `.gitignore` **before** you paste the secret into it.
- `.env.example` gets dummy values only. Its job is to publish the *variable
  names*, never the values.
- A secret committed to git history is drastically harder to remove than to
  prevent — rewriting history plus rotating the credential, versus not doing it
  in the first place. If it does happen: rotate the secret in Google Cloud
  Console immediately; scrubbing the commit alone is not enough, because the
  value is already exposed.

---

## 4. Checklist before moving to Step 2

- [ ] Correct project selected in the console
- [ ] Consent screen configured, audience = External
- [ ] Scopes: `openid`, `userinfo.email`, `userinfo.profile` — and nothing else
- [ ] Your own account added under Test users
- [ ] OAuth client created, type = Web application
- [ ] Authorized JavaScript origin matches the frontend dev server exactly
- [ ] Authorized redirect URI matches the frontend route exactly (scheme, host, port, path, trailing slash)
- [ ] Client ID + secret copied
- [ ] `.env` is gitignored
- [ ] Three variables added to `.env` with real values
- [ ] Same three variable **names** added to `.env.example` with fake values

---

## 5. Failure modes, decoded

| Error | Cause | Fix |
|---|---|---|
| `redirect_uri_mismatch` | Sent URI ≠ registered URI, byte for byte | Diff them character by character — scheme, port, trailing slash, `localhost` vs `127.0.0.1` |
| `access_blocked` / "app not verified" | App in Testing, account not on the test-user list | Add the account under Audience → Test users |
| `invalid_client` | Wrong client ID/secret, or credentials from a different project | Re-copy both from the Clients page of the *correct* project |
| `invalid_grant` on token exchange | Code already used, expired (~10 min), or `redirect_uri` differs from step 2 | Codes are strictly single-use. Check for double-submits — React StrictMode fires effects twice in dev and will burn the code. |
| No `id_token` in the token response | `openid` scope missing | Add `openid` in Data Access, then re-consent |
| No `refresh_token` in the token response | Only returned on *first* consent | Add `access_type=offline` **and** `prompt=consent`, or revoke access at <https://myaccount.google.com/permissions> and retry |

---

## Project-specific notes

> Everything above is generic. This section is specific to
> `ahmadaoosaq123_backend_per` (Django 5.2 + DRF + SimpleJWT).

- **Chosen variant:** A — frontend receives the code and POSTs it to Django.
- **Reusing existing variable names.** `GOOGLE_CLIENT_ID` and
  `GOOGLE_CLIENT_SECRET` already exist in `my_django/env_config.py` (~L93–94),
  declared for the Google Calendar integration but never populated. Login reuses
  them rather than introducing `GOOGLE_AUTH_CLIENT_ID` — one Google Cloud
  project, one OAuth client, one credential pair.
- **`GOOGLE_REDIRECT_URI` (singular) is untouched.** It belongs to the calendar
  integration in `integration/services/google_calendar.py`. Login uses the new
  plural `GOOGLE_AUTH_REDIRECT_URIS`. Two different callbacks, one OAuth client
  — which is normal and supported.
- **Register the calendar callback now too**, to avoid a second trip to the
  console later:
  ```
  http://localhost:3000/auth/google/callback              <- login (this build)
  http://localhost:8000/integrations/google-calendar/callback/   <- calendar (existing code)
  ```
- **Scope separation matters here.** The calendar integration requests
  `https://www.googleapis.com/auth/calendar` with `access_type=offline`. Login
  must *not* request it. Same client, different scopes per flow.
- **No new Python dependencies.** `requests` and `PyJWT` are already in
  `requirements.txt`, which covers the token exchange and `id_token` signature
  verification against Google's JWKS.
- **Frontend port.** Everything above assumes the dev server is on `:3000`.
  If it differs, both the JavaScript origin and the redirect URI must change.

### Next step

Step 2 — backend wiring: `env_config` entries, the `GoogleAccount` model
linking a Google `sub` to a `User`, and the migration.
