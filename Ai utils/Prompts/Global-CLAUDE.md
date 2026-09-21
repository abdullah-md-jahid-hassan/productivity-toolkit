# Global CLAUDE.md — Universal Rules

> These rules apply to **every** session, in every project, no matter the stack (frontend, backend, AI/ML, or DevOps). Stack-specific rules live in separate local CLAUDE.md files.

---

## 1. Code Architecture & Design

- **Modular coding** — Each function or module does ONE job. If a function does multiple unrelated things, split it.
- **Loose coupling** — Modules should not depend on the internal details of other modules. Communicate through clear interfaces (function signatures, APIs), not shared internal state.
- **High cohesion** — Keep related logic together in the same file/module.
- **Separation of concerns** — Business logic, data access (DB queries), and presentation (UI/API response formatting) should live in separate layers.
- **YAGNI (You Aren't Gonna Need It)** — Don't add abstraction, config options, or design patterns for a future need that doesn't exist yet. Build for today's actual requirement.
- **DRY, but readability first** — Don't repeat the same logic in multiple places, but don't force a shared abstraction if it makes the code harder to follow.
- **Consistent naming** — Use the same naming style (camelCase, snake_case, etc.) already used in the project. Follow the language's standard convention if starting fresh.
- **Consistent folder structure** — Follow the pattern already used in the project (feature-based or layer-based). Don't mix styles.

## 2. Code Quality & Comments

- Names describe purpose, not implementation. Use `getUserById`, not `getData`.
- Comments explain **why**, not what. Example: `# Retry 3 times — payment gateway has flaky uptime`, not `# loop 3 times`.
- Keep functions short — aim for under ~40 lines. If longer, find a natural place to split it.
- Avoid deep nesting — more than 3 levels of if/for is a sign to refactor (use early returns / guard clauses).
- Follow the project's existing linter/formatter config (ESLint, Prettier, Black, Ruff, etc.) — don't fight the existing style.
- Add docstrings/type hints for public functions, especially in backend code and shared libraries.

## 3. Security

- Never hardcode secrets, API keys, DB passwords, or tokens in code — always load from environment variables or a secret manager (AWS Secrets Manager, Vault, etc.).
- Validate and sanitize every input — from users, from APIs, from files. Never assume input is safe.
- Use parameterized queries or ORM methods — never build SQL with raw string concatenation (prevents SQL injection).
- Escape/encode output properly to prevent XSS in any HTML/JS response.
- **Least privilege** — DB users, IAM roles, and API keys get only the exact permissions needed, never broader "just in case."
- **Token handling:**
  - Access tokens: short-lived (e.g. 15 min – 1 hour)
  - Refresh tokens: longer-lived, stored securely (httpOnly cookie, not localStorage), rotated on use
  - Always verify token signature and expiry on the server side
- **Rate limiting & throttling** — every public-facing endpoint needs a limit, to stop abuse and brute-force attacks.
- **CORS** — allow only specific, known origins. Never use `*` in production, especially with credentials enabled.
- **Logging** — never log passwords, tokens, card numbers, or personal data. Mask/redact if it must appear.
- **Package & dependency supply-chain verification (mandatory, no exceptions)** — before installing any package, in any language or package manager (npm/yarn/pnpm, pip/poetry/uv, RubyGems, Cargo, Composer, Go modules, etc.):
  - Search for that package's recent security history before installing it — recent advisories, malware reports, compromised-maintainer incidents, or unusual publishing activity for the *specific version* being installed. Don't rely on memory or assume a well-known package name is automatically safe; check the version.
  - Don't default to "always install the latest version." Latest is preferred only if it checks out clean. A freshly published version is often the least-verified by the community and is exactly the version real supply-chain attacks target — a compromised maintainer account publishing a malicious patch release is a known, recurring attack pattern.
  - If the latest version has any credible report of malicious code, a security incident, or suspicious activity, fall back to the previous version and run the same check on it. If that version is also flagged, keep falling back one version at a time until a version with a clean, verified history is found — never skip the check on a fallback version just because it's older; a backdoor is sometimes discovered well after a version was published.
  - **Check the full dependency tree, not only the package being installed directly.** A package can look clean while pulling in a compromised transitive dependency — this is how several real supply-chain attacks have actually spread, through a small, deeply-nested utility package that many other packages depend on. Apply the same version-history check to the significant packages in the dependency tree, not only the top-level one being added.
  - Once a verified-safe version is chosen, pin it exactly in the lock file (`package-lock.json`, `poetry.lock`, `Cargo.lock`, etc.) — don't leave it on an open version range that could silently resolve to a different, unverified version on a future install.

## 4. Error Handling & Resilience

- Every error must be handled or explicitly raised — no empty catch blocks, no silently swallowed exceptions.
- Set a timeout on every external call (HTTP request, DB query, third-party API) — never let a call hang forever.
- Use retry with exponential backoff for calls that can fail temporarily (network blips, rate limits).
- Design write operations to be idempotent when retries are possible (e.g. idempotency keys for payment APIs).
- Never expose internal error details or stack traces to the end user — log them internally, return a clean, generic message externally.

## 5. Performance & Scalability

- Watch for N+1 queries — when a loop makes one DB call per item instead of one batched call.
- Always paginate large lists — never return an entire table in one response.
- Use caching (Redis, in-memory, CDN) where data doesn't change often, and always have a clear invalidation plan.
- Prefer async/non-blocking I/O for operations that wait on network or disk.
- Don't optimize before there's a real, measured bottleneck — premature optimization wastes time and adds complexity.

## 6. Testing

- Write unit tests for core business logic, especially anything involving money, auth, or data integrity.
- Test edge cases — empty input, null values, very large input, wrong types — not just the expected happy path.
- Don't skip writing tests to "save time." Untested code is technical debt.

## 7. Configuration & Environments

- All configurable values (URLs, keys, feature flags, limits) come from environment variables, never hardcoded.
- Keep separate config values for dev, staging, and production — never point dev code at a production database by mistake.
- If a required config value is missing at startup, fail immediately with a clear error. Don't let the app start in a broken state.

## 8. DevOps & Infrastructure

- Prefer infrastructure as code (Terraform, CloudFormation, etc.) over manual console changes, so infra changes are tracked and repeatable.
- Store secrets in a proper secret manager or vault — never commit `.env` files or credentials to the repo (add them to `.gitignore`).
- CI/CD pipeline should run lint + tests automatically before allowing a merge to the main branch.
- Add monitoring, logging, and alerting from the start of a project — don't wait until something breaks in production.
- Always have a rollback plan (or automated rollback) before deploying a change to production.
- For AWS EC2 / cloud infra specifically: use security groups with least-privilege rules, avoid public access to databases, and snapshot/back up before major changes like resizing or cloning an instance.

## 9. Version Control & Workflow

- Make small, atomic commits — each commit represents one logical change.
- Write clear commit messages that explain what changed and why, not just "fix" or "update."
- Never commit secrets, `.env` files, credentials, or private keys — check before every commit.
- Follow a consistent branch naming convention (e.g. `feature/`, `fix/`, `hotfix/`).

## 10. Rules for the AI Agent (Claude) Itself

- If a requirement is unclear or ambiguous, ask a clarifying question instead of guessing.
- Do not silently change, remove, or "improve" working code outside of what was actually asked.
- Proactively flag security, scaling, or architecture concerns — even if not asked directly.
- When more than one valid approach exists, briefly explain the trade-offs instead of picking one silently.
- Never invent library, API, or framework behavior — verify it's real and check correct usage before using it.
- Follow the existing patterns and style already used in the project, instead of introducing a new style without a clear reason.
- Don't over-engineer — match the solution's complexity to the actual size and need of the feature.

## 11. Persona & Communication Style (for Hassan)

This section controls **how the AI talks**, separate from how it writes code.

- English is not my first language, and I'm at an intermediate level, especially with reading.
- When explaining anything in the chat — after finishing a feature, after running a prompt, or answering a question — use **easy, plain English**.
- Avoid rare or complex words when a simple word means the same thing (say "use" instead of "utilize," say "fix" instead of "remediate").
- Keep explanations short and direct. Prefer bullet points or short paragraphs over long blocks of text.
- This rule applies **only to chat explanations and summaries** — not to the actual code, code comments, or technical names, which should stay professional and production-grade as normal.

---

*Status: v2 — added a strict, recursive package supply-chain verification policy under Security, covering direct packages and their transitive dependency tree across every package manager.*