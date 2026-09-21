# Frontend CLAUDE.md — Local Rules (React / Next.js)

> Works together with the global CLAUDE.md. Place this file in the root of any React/Next.js project. **This is a rulebook, not a description of one running app.** Feature folders mirror whatever domains your backend actually has — `auth/` is the one fully expanded example below because nearly every app needs it; the rest are placeholders.

## Reference Project Structure

```
src/
├── app/                          # Next.js App Router — routes ONLY, no business logic
│   ├── (public)/                   # route group: unauthenticated pages
│   │   ├── login/page.tsx
│   │   ├── signup/page.tsx
│   │   └── page.tsx                  # landing page
│   ├── (app)/                       # route group: authenticated user shell
│   │   ├── layout.tsx                  # auth guard + shared nav (Server Component)
│   │   └── <domain>/page.tsx             # one folder per feature domain
│   ├── (admin)/                      # route group: admin-only shell, if the project has one
│   │   └── admin/<domain>/page.tsx
│   ├── api/                            # Route Handlers — thin BFF layer only
│   │   └── auth/
│   │       ├── login/route.ts
│   │       ├── refresh/route.ts
│   │       ├── logout/route.ts
│   │       └── me/route.ts
│   └── layout.tsx                        # root layout
├── features/                      # one folder per domain — mirrors the backend's app names
│   ├── auth/
│   │   ├── api/                      # raw fetch calls to the backend — returns raw DTOs only
│   │   ├── dto/                       # TypeScript types matching the backend response exactly
│   │   ├── mappers/                    # pure functions: DTO → domain model (the "serialize" step)
│   │   ├── models/                      # domain/view model types shaped for what the UI needs
│   │   ├── hooks/                        # React Query hooks — glue between api/mappers and components
│   │   ├── components/                    # presentational components — typed props only, no fetching
│   │   └── schemas/                        # zod validation schemas for auth forms
│   └── <domain>/, <domain>/, ...      # every other feature YOUR project needs — a billing domain, a
│                                          # dashboard domain, a listing/lead domain, notifications, etc.
│                                          # (see §13). Every domain follows the identical shape above.
├── components/                       # shared, reusable, domain-agnostic UI (buttons, inputs, layout)
├── lib/
│   ├── api-client.ts                    # single fetch instance — base URL, throttle handling, error normalization
│   ├── auth/                              # token/session helpers (server-only, using `jose`)
│   └── utils.ts
├── hooks/                              # global reusable hooks (not tied to one feature)
├── stores/                               # global client state (Zustand) — UI state only, never server data
├── types/                                  # shared global TypeScript types
├── styles/                                   # global CSS
├── middleware.ts                              # route protection, runs at the edge
└── .env.local
```

---

## 1. App Organization — App Router + Feature Folders

- `app/` is routing only — layouts, pages, loading/error boundaries. It never contains fetch logic, business logic, or reusable components directly.
- `features/` holds one folder per domain, matching whatever the backend's app names actually are — so moving between frontend and backend, the same boundaries are recognizable. Don't create a feature folder for a domain your project doesn't have.
- Each `page.tsx` is a thin composition layer: it imports components and hooks from the matching `features/<domain>/` folder and arranges them. It does not fetch data or format it directly.
- `components/` is strictly for UI with no domain knowledge (a `Button`, a `Modal`, a `DataTable`). The moment a component knows about a specific feature's data, it belongs in that feature's own `components/` folder instead.

## 2. The Modular Data Pipeline

This is the core pattern: fetching, transforming, and rendering stay in separate, independently debuggable modules.

- **`api/`** — the only place that calls `fetch` for that domain. Every function takes typed parameters and returns a raw response shaped exactly like the backend's response — no formatting, no renaming, no UI concerns. If the backend response changes, this is the only layer that should need an update.
- **`dto/`** — TypeScript types describing the *exact* shape the backend returns. These exist only to keep `api/` honest — nothing outside `api/` and `mappers/` should ever import a DTO type directly.
- **`mappers/`** — pure functions converting a DTO into a domain/view model: renaming fields, computing derived values, converting date strings to `Date` objects, discarding fields the UI doesn't need. No side effects, no fetching — trivially unit-testable.
- **`models/`** — the types produced by `mappers/`, shaped for exactly what the UI needs. Components only ever work with `models/` types, never `dto/` types.
- **`hooks/`** — React Query hooks that call `api/`, pass the result through the right mapper, and expose `{ data, isLoading, error }` in the `models/` shape. Caching, throttle handling, and pagination all live here (§6, §7).
- **`components/`** — receive already-mapped, typed data as props. They never call `fetch`, never import from `api/` or `dto/`.

Why this matters: if a component renders wrong data, the bug is either in `mappers/` or `hooks/` — never buried inside a component mixing rendering and fetching together.

## 3. Routing — App Router Route Groups

- `(public)/`, `(app)/`, `(admin)/` mirror the same Public/User/Admin audience split as the backend. The parentheses don't affect the URL — they only decide which layout wraps the page.
- `(app)/layout.tsx` and `(admin)/layout.tsx` are Server Components that check for a valid session before rendering children — a second layer of protection alongside middleware (§5).
- Route params and search params are `Promise`-typed in the current App Router — always `await` them.
- Track the backend's API version explicitly in each feature's `dto/` types. A backend version bump should be a visible, deliberate change in `dto/`, never a silent mismatch.

## 4. Token Handling & Login

- **Never store the access token or refresh token in `localStorage` or `sessionStorage`.** Any injected JavaScript — a vulnerable dependency, an XSS bug — can read them and take over the session instantly.
- The refresh token lives in an `httpOnly`, `Secure`, `SameSite=Lax` (or `Strict`) cookie, set only by a server-side Route Handler — never by client-side code.
- The access token lives in memory, not a cookie. It's gone on page refresh, which is fine — the app silently fetches a new one using the refresh cookie on load.
- Use the `jose` library for signing/verifying JWTs — it runs on both the Node.js runtime and the Edge Runtime that `middleware.ts` uses.
- If a Client Component needs basic user info, it calls `GET /api/me` — a Route Handler that reads the httpOnly cookie server-side and returns only the safe fields the client needs.
- **Login flow:** form submit → `POST /api/auth/login` → backend call → Route Handler sets the httpOnly refresh cookie and returns the access token in the JSON body.
- **Token refresh:** on a 401, `lib/api-client.ts`'s interceptor calls `POST /api/auth/refresh` once, gets a new access token, retries the original request. If refresh also fails, clear in-memory state and redirect to login.
- **Logout** clears the httpOnly cookie via a Route Handler and clears the in-memory access token.

## 5. Middleware & Route Protection

- `middleware.ts` checks for the presence of the refresh-token cookie before allowing access to protected route groups, redirecting to `/login` if missing.
- Middleware checks cookie *presence*, not full signature verification — that happens in the Route Handler / Server Component layer, keeping the edge check fast.
- Keep the `matcher` config explicit and reviewed whenever a new route group is added.
- Admin routes need a second check beyond "is logged in" — verify the role/claim in middleware or in `(admin)/layout.tsx`.

## 6. Data Fetching & Caching Strategy

- Initial page data comes from **Server Components** — `fetch` directly in the page/layout, on the server, before anything reaches the browser. This avoids the "flash of empty content" that `useEffect`-based fetching causes.
- **React Query** (via each feature's `hooks/`) is for data that changes after the initial load. Set an explicit `staleTime`/`gcTime` per query based on how often that data actually changes — a notification count can be near-real-time; a plans/pricing list can stay cached for hours.
- Next.js caches `fetch` by default. Anything that must always be fresh needs `cache: 'no-store'` explicitly.

**Throttle handling is not the same as error handling.** When any *data-reading* endpoint returns `429`, the UI keeps showing the last successful cached data exactly as it looked before — it must never drop into an error state that blanks the screen or shows an error message.

- Implement this in `lib/api-client.ts`: on a `429` response, don't throw a normal error. Read the `Retry-After` header and return a signal (e.g. `{ throttled: true, retryAfter }`) that the query layer treats as "keep the current cache, don't update yet, try again after this delay" — never as a hard failure.
- Schedule exactly one retry after the `Retry-After` duration — honor it exactly rather than guessing with backoff, since the server already told you how long to wait. Only fall back to a short exponential backoff with jitter, capped at a few attempts, if `Retry-After` is missing.
- Never show a "rate limited" banner or toast for a normal data read (a list, a dashboard number, a notification feed). The old data quietly staying on screen for a few extra seconds is the correct, invisible behavior — the user should never know a throttle happened.
- **The one exception: security-sensitive actions show the throttle, on purpose.** Login, registration, password reset, and verification-code requests must show an explicit, visible message when throttled ("Too many attempts — try again in 30 seconds") and must never auto-retry silently. Silently retrying a login attempt behind the user's back is both confusing and looks like the exact automated behavior a security system is watching for.
- Classify every call in `lib/api-client.ts` once: `throttleBehavior: 'silent'` (default — any GET/list/dashboard-style read) or `'visible'` (set explicitly only on login, registration, password-reset, and verification-code calls).

## 7. Pagination — Page Number & Lazy Load

Both styles are acceptable — pick whichever fits the page's design. Both live in the feature's `hooks/` layer (§2) and both follow the throttle rule in §6 identically: if a page change or a lazy-load fetch gets throttled, keep showing what's already rendered and retry silently after the cooldown.

**Page-number pagination**
- Key the query by page number and use `placeholderData: keepPreviousData` (the current TanStack Query API — the old `keepPreviousData: true` boolean was removed) so the current page's rows stay on screen while the next page loads, instead of flashing a spinner and blanking the list.
- Use the `isPlaceholderData` flag to show a subtle in-place loading indicator (e.g. slightly dim the list) instead of unmounting it.
- Clicking "next"/"previous" only changes the page value in the query key — the hook does the rest, and a page fetch that gets throttled simply keeps the current page visible until the retry succeeds.

**Lazy-load / infinite-scroll pagination**
- Use `useInfiniteQuery`, not a manually managed array with `useEffect` — it already handles per-page loading state and merges pages into one list.
- **Start fetching the next page before the user reaches the bottom, not when they hit it.** Place an `IntersectionObserver` sentinel at roughly 80% through the currently loaded content — e.g. if a page holds 50 items, position the sentinel around the 40th item. When it scrolls into view, call `fetchNextPage()` immediately.
- By the time the user actually reaches the visual bottom, the next page has usually already finished loading in the background — that's what makes lazy-load feel instant instead of showing a spinner at the end every time.
- Don't prefetch more than one page ahead — fetching further ahead wastes bandwidth on data the user may never reach.

## 8. Components — Server/Client Boundary & Reusability

- Every component is a Server Component by default. Add `"use client"` only when it genuinely needs browser APIs, interactivity, or a browser-only library — and push it as far down the tree as possible.
- A reusable component takes its content and behavior through props — it never hardcodes copy, links, or a specific feature's data shape.
- Compose through `children` or named slots rather than boolean prop explosion (`showHeader`, `variant`, `size`, `showFooter`...). A component collecting many boolean props is a sign it should be split into smaller composable pieces instead.
- Every interactive shared component (`Button`, `Modal`, `Dropdown`) is accessible by default — correct semantic HTML, full keyboard operability, and ARIA attributes where semantic HTML alone isn't enough. Retrofitting accessibility later costs far more than building it in from the first version.
- Keep presentational components pure: given props, they render UI. Side effects (fetching, subscriptions, analytics) live in `hooks/`, never in a presentational component's body.

## 9. Animations & Motion Design

Three tools, three jobs — reach for the lightest one that does what's needed.

- **CSS first** — transitions, hovers, simple fades, and loading skeletons are CSS's job (`transition`, `@starting-style`, native `scroll-timeline`). No library, no bundle cost, and it runs on the compositor thread by default when animating `transform`/`opacity`.
- **Motion — the library formerly named Framer Motion (import from `motion/react`, not the old `framer-motion` path) — for gesture, layout, and presence animations.** Drag/hover/tap interactions, elements that need to animate smoothly when they resize or reposition, and mount/unmount transitions via `AnimatePresence`. Reach for this when CSS genuinely can't express the animation.
- **The View Transitions API for page/route-level transitions** — shared-element continuity when navigating between routes. Don't reach for Motion to recreate what the browser already does natively at the navigation level.
- Animate `transform` and `opacity` only, wherever possible. Animating `width`, `height`, `top`/`left`, or `box-shadow` forces layout recalculation every frame and is the most common cause of janky animation.
- Use `whileInView`/`useInView` for scroll-triggered reveals instead of a hand-rolled scroll listener.
- **Respect `prefers-reduced-motion` everywhere.** Wrap non-essential motion behind `useReducedMotion()` (provided by Motion) or a `@media (prefers-reduced-motion: reduce)` block, and fall back to an instant state change. This isn't optional polish — unexpected motion causes real physical discomfort for some users.
- Keep animation variants and transition configs colocated with the component that uses them, not in a shared, ever-growing `animations.ts` every component imports from.

## 10. Forms & Validation

- Define a `zod` schema per form inside the feature's `schemas/` folder — used for both client-side validation feedback and as the source of truth for the submitted shape.
- Never trust client-side validation alone — the backend validates independently regardless of what the frontend already checked.
- Use `react-hook-form` (or Server Actions) to wire the schema to the form, keeping validation logic out of the component's JSX.

## 11. State Management

- **Local component state** (`useState`) — UI-only state nothing else needs.
- **React Query cache** — anything that came from or is going to the backend. This is the default for "server state" and should never be duplicated into a separate global store.
- **Global client store** (Zustand, if needed) — cross-cutting UI state that isn't server data and isn't local to one component. If it came from an API, it doesn't belong here.

## 12. Error Handling

- `lib/api-client.ts` normalizes every backend error into one shape (`{ status, message, code }`) before it reaches any hook or component — except a `429` on a silent-throttle endpoint (§6), which is handled as a throttle signal, not surfaced as an error at all.
- Use Next.js `error.tsx` boundaries per route segment for unexpected failures, and inline error states (React Query's `error`) for expected, recoverable failures.
- Never show a raw backend error message to the user — map known error codes to friendly text, with a generic fallback.

## 13. Common Domain Patterns (Worked Examples, Not Mandatory Features)

Real frontends keep running into the same handful of domain shapes. Apply whichever matches something your project actually has.

**A. Payment / billing domains**
- Use the provider's hosted checkout/Elements (Stripe or similar) — the frontend never collects or touches raw card data.
- After a successful checkout redirect, don't assume success from the redirect alone — re-fetch the actual status from the backend. The webhook is the source of truth and may not have processed yet the instant the user lands back on the page. Show a "processing" state until confirmed.

**B. Ledger-backed domains (credits, wallets, points)**
- **Never optimistically update a balance in the UI.** Since the backend treats it as a ledger, showing an optimistic new balance before the server confirms it risks displaying a number that doesn't match reality if a concurrent spend or refund happens. Show a loading state on the balance and update it only from a confirmed server response.

**C. Read-only aggregation / dashboard domains**
- Fetched through the domain's `hooks/`, using React Query's caching so the same aggregation isn't refetched on every navigation — respect whatever cache window the backend's own caching implies.
- Admin-only dashboards need the same route-level protection as any other admin page (§3, §5).

**D. Notification / activity-feed domains**
- Poll or use a lightweight real-time connection (WebSocket/SSE) via a dedicated hook. "Mark as read" is safe as an optimistic mutation — unlike pattern B, notifications aren't financial data.

## 14. Testing

- Unit test `mappers/` directly — pure functions, the cheapest and most valuable test in the pipeline.
- Mock the `api/` layer in component/hook tests — never scatter `fetch` mocks across test files.
- Explicitly test the token-refresh-on-401 flow.
- Explicitly test throttle behavior: simulate a `429` on a silent-throttle endpoint and confirm the last cached data stays visible with no error shown; simulate one on a login/registration call and confirm the visible message appears with no auto-retry.
- Explicitly test the lazy-load prefetch trigger fires at the ~80% threshold, not only at the literal bottom.

## 15. Performance

- Rely on the React Compiler for automatic memoization — reach for manual `useMemo`/`useCallback` only where profiling shows an actual problem.
- Use `next/image` for every image.
- Code-split heavy, rarely-used features with `next/dynamic`.
- Animation performance is covered in §9 — the same "don't force layout recalculation" rule applies everywhere, not just inside `motion.div`.

## 16. Environment & Config

- Any environment variable prefixed `NEXT_PUBLIC_` is shipped to the browser in plain text — never put a secret behind that prefix.
- Keep the backend API base URL in an environment variable, not hardcoded.

## 17. Security (Frontend-Specific)

- Never use `dangerouslySetInnerHTML` with unsanitized content. If user-generated HTML must be rendered, sanitize it with DOMPurify immediately before it reaches the sink — and keep DOMPurify itself updated, since sanitizer bypasses get patched regularly.
- Set a strict Content-Security-Policy with a per-request nonce and `strict-dynamic`. Avoid `unsafe-inline` and `unsafe-eval` entirely — a CSP that allows `unsafe-inline` blocks almost nothing.
- Add `require-trusted-types-for 'script'` (Trusted Types) alongside CSP where supported — it stops DOM XSS at the sink itself (`innerHTML`, `document.write`, etc.) by rejecting raw strings, even from a dependency you didn't write yourself.
- Any third-party `<script src>` not bundled by your own build (an analytics tag, an embedded widget) needs a Subresource Integrity (`integrity=`) attribute — this stops a compromised CDN from silently serving different code under the same URL.
- Set standard security headers on every response: `frame-ancestors 'none'` (or `X-Frame-Options: DENY`) against clickjacking, `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, a `Permissions-Policy` locking down camera/mic/geolocation unless actually used, and HSTS.
- Rely on `SameSite` cookie attributes as the first line of CSRF defense; for any state-changing Route Handler, double-check the request's origin matches your own domain.
- Validate `event.origin` in every `window.postMessage` listener — an unchecked listener accepts a message from any origin on the page, including a malicious iframe.
- Serve user-uploaded files from a separate origin/subdomain from the main app — never the same origin as authenticated pages, so an uploaded HTML/SVG file can't run with your app's cookies and CSP.
- Never log tokens, even in development console output.

## 18. Styling

- Pick one approach (Tailwind is the default recommendation for new projects) and keep it consistent.
- Colocate a component's styles with the component itself inside its feature or `components/` folder — never one giant global stylesheet everyone's afraid to touch.

## 19. Implementation Discipline — Precautions Before Writing Code

Before generating or modifying any page, component, or hook, work through this checklist. It exists so §1–§18 actually get applied while code is being written, not discovered missing in review.

**Modularity & reusability**
- Does this new component take its content through props, or does it hardcode a specific feature's copy or data? If hardcoded, it belongs in that feature's own `components/`, not the shared `components/` folder.
- Does this code call `fetch` directly inside a component? It shouldn't — trace it back through `api/` → `mappers/` → `hooks/` (§2).

**Security**
- Does this render HTML from user input or an external source? It must go through DOMPurify before `dangerouslySetInnerHTML` — never rendered raw.
- Is a new third-party script being added? Does it have an `integrity` attribute, and is its origin allowed in the CSP?
- Does this touch tokens? They stay in an httpOnly cookie (refresh) or in-memory (access) — never `localStorage`/`sessionStorage` (§4).

**Caching & throttling**
- Is this a new API call? Is its `throttleBehavior` classified — `'silent'` for a normal data read, `'visible'` only for login/registration/password-reset/verification-code (§6)?
- On a 429, does the UI keep showing the last cached data, or could it fall into an error state? Check this explicitly for any new endpoint.

**Pagination & performance**
- Is this a new list view? Does it use page-number or lazy-load pagination (§7), and if lazy-load, does it prefetch at ~80% instead of waiting for the literal bottom?
- Does a new animation risk animating layout-triggering properties instead of `transform`/`opacity`? Is `prefers-reduced-motion` respected (§9)?

**When something doesn't fit cleanly**
If a change doesn't map cleanly onto one of these checks, say so explicitly and flag the tradeoff instead of silently picking an approach — same principle as the global CLAUDE.md's agent-behavior rules.

---

*Status: v2 — reusable rulebook (feature folders de-hardcoded to match the backend fix), with throttle-aware caching, dual pagination strategy, modern animation guidance, and deepened security added.*
