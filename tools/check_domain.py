"""
Domain Availability Checker
============================
Uses RDAP (Registration Data Access Protocol) — the official ICANN open
standard that replaced WHOIS. Completely free, no API key needed.

Supports all popular TLDs out of the box:
  .com .net .org .io .app .dev .co .ai .cc .info .biz .me .tv .us
  .uk .ca .de .fr .au .in .shop .online .site .tech .xyz .store
  ...and any other TLD via automatic IANA bootstrap discovery.

DNS-over-HTTPS (DoH) fallback:
  If system DNS cannot resolve an RDAP server hostname (e.g. rdap.nic.io,
  rdap.nic.google, rdap.nic.app), the script automatically retries the
  DNS lookup via Cloudflare and Google DoH over HTTPS. This bypasses
  broken ISP/corporate DNS that blocks nic.* subdomains.

Retry strategy:
  - Throttle (HTTP 429/5xx) -> auto wait 10s, retry silently (no prompt)
  - DNS/conn/timeout error   -> retry up to MAX_RETRIES (5) times
  - After 5 failed attempts  -> prompt: [r]etry 5 more times | [s]kip
  - Prompt loops forever     -> user always stays in control

Summary at end:
  Three separate lists — AVAILABLE, TAKEN, ERROR — always printed.

Usage:
  pip install requests
  python3 check_domains.py

  Enter a comma-separated list of full domain names at the prompt.
  Mixed TLDs are supported in one input:
    toolnest.app, worknest.io, myapp.com, coolsite.cc, project.me
"""

import time
import sys
import socket
from urllib.parse import urlparse

try:
    import requests
except ImportError:
    print("[ERROR] 'requests' is not installed.  Run: pip install requests")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Max transient-error retries before prompting the user.
# Throttle errors (429/5xx) do NOT count toward this — they auto-retry.
MAX_RETRIES = 5

# Wait between domains (seconds) — polite to RDAP servers
REQUEST_DELAY = 0.5

# Per-request HTTP timeout (seconds)
REQUEST_TIMEOUT = 10

# Auto-wait for throttle errors (HTTP 429 / 5xx) — no user prompt needed
RETRY_DELAY_THROTTLE = 10

# Wait between non-throttle retry attempts (DNS / conn / timeout)
RETRY_DELAY_CONNECTION = 5

# ---------------------------------------------------------------------------
# RDAP server registry
#
# Each TLD maps to an ordered list of fallback RDAP base URLs.
# Tried left-to-right; moves to the next on DNS failure or connection error.
#
# Covers all popular TLDs with known servers. Any TLD not listed here
# is discovered automatically via the IANA bootstrap JSON.
# ---------------------------------------------------------------------------

RDAP_FALLBACKS: dict[str, list[str]] = {
    # ── Generic / legacy ────────────────────────────────────────────────────
    "com":   ["https://rdap.verisign.com/com/v1/domain"],
    "net":   ["https://rdap.verisign.com/net/v1/domain"],
    "org":   [
        "https://rdap.publicinterestregistry.org/rdap/domain",
        "https://rdap.afilias.net/rdap/domain",
    ],
    "info":  [
        "https://rdap.afilias.net/rdap/domain",
        "https://rdap.identitydigital.services/rdap/domain",
    ],
    "biz":   [
        "https://rdap.afilias.net/rdap/domain",
        "https://rdap.identitydigital.services/rdap/domain",
    ],
    "name":  ["https://rdap.verisign.com/name/v1/domain"],

    # ── Tech / SaaS popular ──────────────────────────────────────────────────
    "io":    [
        "https://rdap.nic.io/domain",                          # official (often fails on some ISPs)
        "https://rdap.afilias.net/rdap/domain",                # Afilias backend
        "https://rdap.identitydigital.services/rdap/domain",   # Identity Digital (was Afilias)
    ],
    "app":   [
        "https://rdap.nic.google/rdap/domain",   # Google Registry
        "https://rdap.nic.app/domain",
    ],
    "dev":   [
        "https://rdap.nic.google/rdap/domain",   # Google Registry
        "https://rdap.nic.dev/domain",
    ],
    "page":  ["https://rdap.nic.google/rdap/domain"],
    "ai":    [
        "https://rdap.nic.ai/rdap/domain",
        "https://rdap.centralnic.com/rdap/domain",
    ],
    "tech":  [
        "https://rdap.nic.tech/rdap/domain",
        "https://rdap.centralnic.com/rdap/domain",
    ],
    "xyz":   ["https://rdap.nic.xyz/rdap/domain"],
    "online":["https://rdap.centralnic.com/rdap/domain"],
    "site":  ["https://rdap.centralnic.com/rdap/domain"],
    "store": ["https://rdap.centralnic.com/rdap/domain"],
    "shop":  ["https://rdap.centralnic.com/rdap/domain"],
    "cloud": ["https://rdap.centralnic.com/rdap/domain"],
    "web":   ["https://rdap.centralnic.com/rdap/domain"],

    # ── Short / brandable ────────────────────────────────────────────────────
    "co":    [
        "https://rdap.nic.co/rdap/domain",
        "https://rdap.centralnic.com/rdap/domain",
    ],
    "me":    [
        "https://rdap.nic.me/rdap/domain",
        "https://rdap.centralnic.com/rdap/domain",
    ],
    "cc":    [
        "https://rdap.verisign.com/cc/v1/domain",   # Verisign manages .cc
        "https://rdap.nic.cc/domain",
    ],
    "tv":    [
        "https://rdap.verisign.com/tv/v1/domain",   # Verisign manages .tv
        "https://rdap.nic.tv/domain",
    ],
    "fm":    ["https://rdap.nic.fm/rdap/domain"],
    "ly":    ["https://rdap.nic.ly/rdap/domain"],
    "so":    ["https://rdap.nic.so/rdap/domain"],

    # ── Country codes (popular globally) ─────────────────────────────────────
    "us":    ["https://rdap.nic.us/rdap/domain"],
    "uk":    ["https://rdap.nominet.uk/rdap/domain"],
    "ca":    ["https://rdap.cira.ca/rdap/domain"],
    "de":    ["https://rdap.denic.de/rdap/domain"],
    "fr":    ["https://rdap.nic.fr/rdap/domain"],
    "au":    ["https://rdap.auda.org.au/rdap/domain"],
    "in":    [
        "https://rdap.registry.in/rdap/domain",
        "https://rdap.afilias.net/rdap/domain",
    ],
    "nl":    ["https://rdap.sidn.nl/rdap/domain"],
    "eu":    ["https://rdap.eu/rdap/domain"],
    "br":    ["https://rdap.registro.br/rdap/domain"],
    "jp":    ["https://rdap.jprs.jp/rdap/domain"],
    "cn":    ["https://rdap.cnnic.cn/rdap/domain"],
    "ru":    ["https://rdap.tcinet.ru/rdap/domain"],
    "sg":    ["https://rdap.sgnic.sg/rdap/domain"],
    "nz":    ["https://rdap.srs.net.nz/rdap/domain"],
    "za":    ["https://rdap.registry.net.za/rdap/domain"],

    # ── Industry / niche ─────────────────────────────────────────────────────
    "edu":   ["https://rdap.educause.edu/rdap/domain"],
    "gov":   [],   # .gov is not publicly registerable; skip
    "int":   [],   # .int is restricted; skip
    "mil":   [],   # .mil is restricted; skip
    "mobi":  ["https://rdap.afilias.net/rdap/domain"],
    "pro":   ["https://rdap.afilias.net/rdap/domain"],
    "travel":["https://rdap.nic.travel/rdap/domain"],
    "museum":["https://rdap.nic.museum/rdap/domain"],
    "design":["https://rdap.centralnic.com/rdap/domain"],
    "studio":["https://rdap.centralnic.com/rdap/domain"],
    "media": ["https://rdap.centralnic.com/rdap/domain"],
    "agency":["https://rdap.centralnic.com/rdap/domain"],
}

# IANA bootstrap — discovers RDAP servers for any TLD not in RDAP_FALLBACKS
IANA_BOOTSTRAP_URL = "https://data.iana.org/rdap/dns.json"
_bootstrap_cache: dict[str, list[str]] = {}

# DoH endpoints — bypass broken ISP DNS for nic.* hostnames
DOH_ENDPOINTS = [
    "https://cloudflare-dns.com/dns-query",
    "https://dns.google/dns-query",
]
_doh_cache: dict[str, str] = {}


# ---------------------------------------------------------------------------
# DNS-over-HTTPS resolver
# ---------------------------------------------------------------------------

def _doh_resolve(hostname: str) -> str | None:
    """
    Resolve `hostname` to an IPv4 address using DNS-over-HTTPS.

    Tries Cloudflare then Google DoH. Results are cached for the session.
    Returns an IP string or None if all DoH endpoints fail.
    """
    if hostname in _doh_cache:
        return _doh_cache[hostname]

    for doh_url in DOH_ENDPOINTS:
        try:
            resp = requests.get(
                doh_url,
                params={"name": hostname, "type": "A"},
                headers={"Accept": "application/dns-json"},
                timeout=REQUEST_TIMEOUT,
            )
            if resp.status_code == 200:
                for record in resp.json().get("Answer", []):
                    if record.get("type") == 1:          # A record
                        ip = record["data"]
                        _doh_cache[hostname] = ip
                        return ip
        except Exception:
            continue

    return None


def _make_doh_session(hostname: str, ip: str) -> requests.Session:
    """
    Build a requests.Session that connects to `ip` directly but sends
    `hostname` in the Host header and TLS SNI, so the TLS certificate
    validates correctly without DNS being involved at all.
    """
    from requests.adapters import HTTPAdapter

    class DirectIPAdapter(HTTPAdapter):
        def __init__(self, host: str, ip: str, **kw):
            self._host = host
            self._ip   = ip
            super().__init__(**kw)

        def send(self, request, **kw):
            # Swap hostname -> IP in the URL, keep hostname in Host header
            request.url = request.url.replace(f"://{self._host}", f"://{self._ip}", 1)
            request.headers["Host"] = self._host
            kw.setdefault("verify", True)
            return super().send(request, **kw)

    session = requests.Session()
    session.mount("https://", DirectIPAdapter(hostname, ip))
    return session


# ---------------------------------------------------------------------------
# Input parsing
# ---------------------------------------------------------------------------

def parse_input(raw: str) -> list[tuple[str, str]]:
    """
    Parse a comma-separated string of full domain names.

    Returns [(name, tld), ...] e.g. [("toolnest", "app"), ("worknest", "io")]

    Handles:
      - Extra whitespace           : "  foo.app , bar.io  "
      - Mixed TLDs                 : "foo.app, bar.com, baz.cc"
      - Subdomains                 : "cv.worknest.app" -> name="cv.worknest", tld="app"
      - No dot (invalid)           : skipped with warning
      - Duplicates                 : deduplicated, keeping first occurrence
      - Restricted TLDs (.gov etc) : accepted but will get "no RDAP server" error
    """
    domains = []
    seen    = set()

    for entry in raw.split(","):
        entry = entry.strip().lower()
        if not entry:
            continue

        if "." not in entry:
            print(f"  [!] Skipping '{entry}' — no TLD found (needs a dot)")
            continue

        split_at = entry.rfind(".")
        name = entry[:split_at]
        tld  = entry[split_at + 1:]

        if not name or not tld:
            print(f"  [!] Skipping malformed entry: '{entry}'")
            continue

        full = f"{name}.{tld}"
        if full in seen:
            print(f"  [!] Duplicate skipped: '{full}'")
            continue

        seen.add(full)
        domains.append((name, tld))

    return domains


# ---------------------------------------------------------------------------
# RDAP server discovery
# ---------------------------------------------------------------------------

def _get_fallback_urls(tld: str) -> list[str]:
    """
    Return ordered list of RDAP base URLs for `tld`.

    1. RDAP_FALLBACKS   — instant, no network
    2. _bootstrap_cache — already fetched this session
    3. IANA bootstrap   — one HTTP call, caches all TLDs it finds
    4. []               — unknown TLD, caller reports the error
    """
    if tld in RDAP_FALLBACKS:
        return RDAP_FALLBACKS[tld]

    if tld in _bootstrap_cache:
        return _bootstrap_cache[tld]

    # Try IANA bootstrap to discover RDAP server for this unknown TLD
    try:
        resp = requests.get(
            IANA_BOOTSTRAP_URL,
            headers={"User-Agent": "domain-availability-checker/1.0"},
            timeout=REQUEST_TIMEOUT,
        )
        if resp.status_code == 200:
            for service in resp.json().get("services", []):
                tlds, urls = service[0], service[1]
                cleaned = [u.rstrip("/") for u in urls]
                for t in tlds:
                    _bootstrap_cache[t] = cleaned
            # Now check cache again after populating
            if tld in _bootstrap_cache:
                return _bootstrap_cache[tld]
    except Exception:
        pass

    _bootstrap_cache[tld] = []   # mark as "not found" so we don't retry
    return []


def _is_dns_error(exc: Exception) -> bool:
    """Return True if the exception is a DNS resolution failure."""
    msg = str(exc).lower()
    return any(phrase in msg for phrase in [
        "nameresolerror",
        "getaddrinfo failed",
        "name or service not known",
        "failed to resolve",
        "nodename nor servname",
        "temporary failure in name resolution",
        "nameresolutionerror",
    ])


# ---------------------------------------------------------------------------
# Low-level request (with DoH fallback built in)
# ---------------------------------------------------------------------------

def _do_request(url: str, hostname: str) -> requests.Response:
    """
    GET `url`. On DNS failure, automatically retries via DoH-resolved IP.
    All other exceptions propagate normally to the caller.
    """
    headers = {
        "Accept":     "application/json",
        "User-Agent": "domain-availability-checker/1.0",
    }
    try:
        return requests.get(url, headers=headers, timeout=REQUEST_TIMEOUT)

    except requests.exceptions.ConnectionError as exc:
        if not _is_dns_error(exc):
            raise   # not a DNS problem — propagate

        # System DNS failed — try DoH
        ip = _doh_resolve(hostname)
        if not ip:
            raise   # DoH also failed — propagate original error

        # DoH succeeded — connect via IP, SNI carries the real hostname
        print(f"  [i] System DNS failed for {hostname}, "
              f"connected via DoH-resolved IP ({ip})")
        session = _make_doh_session(hostname, ip)
        return session.get(url, headers=headers, timeout=REQUEST_TIMEOUT)


# ---------------------------------------------------------------------------
# User confirmation prompt (shown after MAX_RETRIES exhausted)
# ---------------------------------------------------------------------------

def _ask_retry_or_skip(domain: str, attempt_round: int) -> str:
    """
    Ask the user what to do after MAX_RETRIES failures.

    Returns:
        "retry" — run another MAX_RETRIES attempts
        "skip"  — move on to the next domain
    """
    print()
    print(f"  {'─' * 60}")
    print(f"  [!] {domain} — failed {MAX_RETRIES * attempt_round} time(s) total.")
    print(f"  {'─' * 60}")
    while True:
        choice = input(
            f"  What do you want to do?\n"
            f"    [r] Retry {MAX_RETRIES} more times\n"
            f"    [s] Skip this domain\n"
            f"  Your choice (r/s): "
        ).strip().lower()
        if choice in ("r", "s", "retry", "skip"):
            print()
            return "retry" if choice in ("r", "retry") else "skip"
        print("  [!] Please type 'r' to retry or 's' to skip.")


# ---------------------------------------------------------------------------
# Core checker — one domain, full retry + confirmation logic
# ---------------------------------------------------------------------------

def check_domain(name: str, tld: str) -> dict:
    """
    Check if a domain is available via RDAP.

    Throttle errors (HTTP 429 / 5xx):
      Auto-wait RETRY_DELAY_THROTTLE seconds and retry silently.
      No user prompt, no retry count — keeps going until it gets through.

    Transient errors (DNS / timeout / connection):
      Retry up to MAX_RETRIES times with RETRY_DELAY_CONNECTION wait.
      After MAX_RETRIES failures, prompt the user:
        [r] retry MAX_RETRIES more  |  [s] skip
      Prompt repeats every MAX_RETRIES failures until user skips.

    Returns:
        {
            "domain":    "example.app",
            "available": True | False | None,
            "registrar": str | None,
            "created":   "YYYY-MM-DD" | None,
            "expires":   "YYYY-MM-DD" | None,
            "error":     str | None        # None means success
        }
    available=None means the user chose to skip or all servers failed.
    """
    full_domain = f"{name}.{tld}"
    fallbacks   = _get_fallback_urls(tld)

    # ── No RDAP server known for this TLD ─────────────────────────────────────
    if not fallbacks:
        return _result(
            full_domain, None,
            error=f"No RDAP server found for .{tld} — TLD may not support RDAP"
        )

    # ── Outer loop: try each fallback RDAP server in order ────────────────────
    for fb_index, base_url in enumerate(fallbacks):
        url      = f"{base_url}/{full_domain}"
        hostname = urlparse(base_url).hostname
        fb_label = f"server {fb_index + 1}/{len(fallbacks)}"

        # Track consecutive transient failures for this fallback server.
        # Throttle failures are handled separately (auto-wait, no count).
        transient_failures = 0
        prompt_round       = 0   # how many times we've already prompted

        while True:   # ── inner loop for this fallback server ─────────────────

            # ── Build retry state for this pass ───────────────────────────────
            # Each "pass" is MAX_RETRIES attempts before prompting.
            attempt_in_pass = 0
            got_result      = False    # set True when we should break out

            for attempt_in_pass in range(MAX_RETRIES):
                transient_failures += 1   # assume failure; clear below on success

                try:
                    resp = _do_request(url, hostname)

                    # ── HTTP 200 — domain TAKEN ────────────────────────────────
                    if resp.status_code == 200:
                        data = resp.json()
                        return _result(
                            full_domain,
                            available=False,
                            registrar=_extract_registrar(data),
                            created=_extract_event_date(data, "registration"),
                            expires=_extract_event_date(data, "expiration"),
                        )

                    # ── HTTP 404 — domain AVAILABLE ────────────────────────────
                    if resp.status_code == 404:
                        return _result(full_domain, available=True)

                    # ── HTTP 429 / 5xx — throttle, auto-wait, no prompt ────────
                    if resp.status_code == 429 or resp.status_code >= 500:
                        transient_failures -= 1    # throttle doesn't count
                        print(f"  [~] {full_domain} — HTTP {resp.status_code} "
                              f"(throttle/server error) on {fb_label}, "
                              f"auto-waiting {RETRY_DELAY_THROTTLE}s ...")
                        time.sleep(RETRY_DELAY_THROTTLE)
                        # Do NOT advance attempt_in_pass — try same attempt again
                        attempt_in_pass -= 1
                        continue

                    # ── Other 4xx — permanent error, stop immediately ──────────
                    return _result(
                        full_domain, None,
                        error=f"HTTP {resp.status_code}: {resp.text[:120]}"
                    )

                except requests.exceptions.Timeout:
                    last_error = (f"Timeout ({fb_label}, "
                                  f"attempt {attempt_in_pass + 1}/{MAX_RETRIES})")
                    if attempt_in_pass < MAX_RETRIES - 1:
                        print(f"  [~] {full_domain} — timeout, "
                              f"waiting {RETRY_DELAY_CONNECTION}s "
                              f"(attempt {attempt_in_pass + 1}/{MAX_RETRIES}) ...")
                        time.sleep(RETRY_DELAY_CONNECTION)

                except requests.exceptions.ConnectionError as exc:
                    last_error = (f"Connection error ({fb_label}, "
                                  f"attempt {attempt_in_pass + 1}/{MAX_RETRIES}): "
                                  f"{str(exc)[:80]}")

                    if _is_dns_error(exc):
                        # DoH was tried inside _do_request and also failed.
                        # Retrying this server won't help — break to next fallback.
                        next_fb = fb_index + 1
                        if next_fb < len(fallbacks):
                            print(f"  [~] {full_domain} — DNS failed for {hostname} "
                                  f"(system + DoH), switching to fallback "
                                  f"{next_fb + 1}/{len(fallbacks)} ...")
                        else:
                            print(f"  [~] {full_domain} — DNS failed for {hostname} "
                                  f"(system + DoH), no more fallbacks.")
                        got_result = False
                        break   # break attempt loop -> move to next fallback server

                    if attempt_in_pass < MAX_RETRIES - 1:
                        print(f"  [~] {full_domain} — connection error, "
                              f"waiting {RETRY_DELAY_CONNECTION}s "
                              f"(attempt {attempt_in_pass + 1}/{MAX_RETRIES}) ...")
                        time.sleep(RETRY_DELAY_CONNECTION)

                except requests.exceptions.RequestException as exc:
                    last_error = (f"Request error ({fb_label}, "
                                  f"attempt {attempt_in_pass + 1}/{MAX_RETRIES}): "
                                  f"{str(exc)[:80]}")
                    if attempt_in_pass < MAX_RETRIES - 1:
                        print(f"  [~] {full_domain} — request error, "
                              f"waiting {RETRY_DELAY_CONNECTION}s "
                              f"(attempt {attempt_in_pass + 1}/{MAX_RETRIES}) ...")
                        time.sleep(RETRY_DELAY_CONNECTION)

            else:
                # for-else: loop completed without a DNS break — all MAX_RETRIES
                # attempts on this pass failed with transient errors.
                prompt_round += 1
                decision = _ask_retry_or_skip(full_domain, prompt_round)

                if decision == "skip":
                    return _result(
                        full_domain, None,
                        error=f"Skipped by user after {MAX_RETRIES * prompt_round} attempts"
                    )
                # "retry" — while True will loop back for another MAX_RETRIES pass
                continue

            # We get here only when the DNS break fired — move to next fallback
            break   # break while True -> outer for loop tries next fallback

    # All fallback servers exhausted
    return _result(
        full_domain, None,
        error=f"All {len(fallbacks)} RDAP server(s) failed"
    )


# ---------------------------------------------------------------------------
# Result builder and RDAP parsers
# ---------------------------------------------------------------------------

def _result(domain, available, registrar=None, created=None, expires=None, error=None):
    """Build a consistent result dict."""
    return {
        "domain":    domain,
        "available": available,
        "registrar": registrar,
        "created":   created,
        "expires":   expires,
        "error":     error,
    }


def _extract_registrar(data: dict) -> str | None:
    """Pull registrar name from RDAP response entities."""
    for entity in data.get("entities", []):
        if "registrar" in entity.get("roles", []):
            vcard = entity.get("vcardArray", [])
            if len(vcard) > 1:
                for field in vcard[1]:
                    if field[0] == "fn":
                        return field[3]
    return None


def _extract_event_date(data: dict, event_action: str) -> str | None:
    """Pull YYYY-MM-DD date from RDAP events list by action name."""
    for event in data.get("events", []):
        if event.get("eventAction") == event_action:
            date_str = event.get("eventDate", "")
            return date_str[:10] if date_str else None
    return None


# ---------------------------------------------------------------------------
# Output formatting
# ---------------------------------------------------------------------------

def format_result(result: dict) -> str:
    """Format a single domain result as a console-printable line."""
    domain = result["domain"]

    if result["error"]:
        return f"  [?] ERROR      {domain:<34}  {result['error'][:60]}"

    if result["available"] is True:
        return f"  [v] AVAILABLE  {domain}"

    if result["available"] is False:
        reg     = result["registrar"] or "unknown registrar"
        expires = result["expires"]   or "?"
        return (f"  [x] TAKEN      {domain:<34}"
                f"  via {reg:<28} | expires {expires}")

    return f"  [?] UNKNOWN    {domain}"


def print_summary(available: list, taken: list, errors: list) -> None:
    """Print the final three-section summary."""
    w = 68
    print()
    print("=" * w)
    print("  RESULTS SUMMARY")
    print("=" * w)

    # ── AVAILABLE ─────────────────────────────────────────────────────────────
    print(f"\n  {'─' * (w - 2)}")
    print(f"  AVAILABLE  ({len(available)})")
    print(f"  {'─' * (w - 2)}")
    if available:
        for d in available:
            print(f"    [v]  {d}")
    else:
        print("    (none)")

    # ── TAKEN ─────────────────────────────────────────────────────────────────
    print(f"\n  {'─' * (w - 2)}")
    print(f"  TAKEN  ({len(taken)})")
    print(f"  {'─' * (w - 2)}")
    if taken:
        for d in taken:
            print(f"    [x]  {d}")
    else:
        print("    (none)")

    # ── ERRORS ────────────────────────────────────────────────────────────────
    print(f"\n  {'─' * (w - 2)}")
    print(f"  ERRORS / SKIPPED  ({len(errors)})")
    print(f"  {'─' * (w - 2)}")
    if errors:
        for d, reason in errors:
            print(f"    [?]  {d:<34}  {reason[:50]}")
    else:
        print("    (none)")

    print()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    print()
    print("=" * 68)
    print("  Domain Availability Checker  --  RDAP (free, no API key)")
    print("=" * 68)
    print("  Supports all popular TLDs: .com .net .org .io .app .dev")
    print("  .co .ai .cc .me .tv .info .biz .uk .us .ca .de .fr .au")
    print("  .in .shop .online .site .tech .xyz .store  ...and more.")
    print()
    print("  Enter a comma-separated list of full domain names.")
    print("  Mixed TLDs are supported in one input.")
    print()
    print("  Example: toolnest.app, worknest.io, myapp.cc, project.me")
    print()

    # ── Get non-empty input ────────────────────────────────────────────────────
    while True:
        raw = input("  Domains > ").strip()
        if raw:
            break
        print("  [!] Input cannot be empty. Please enter at least one domain.\n")

    domains = parse_input(raw)

    if not domains:
        print("\n  [!] No valid domains found after parsing. Exiting.\n")
        sys.exit(1)

    print()
    print(f"  Checking {len(domains)} domain(s) ...\n")

    # ── Result buckets ─────────────────────────────────────────────────────────
    available_list: list[str]             = []
    taken_list:     list[str]             = []
    error_list:     list[tuple[str, str]] = []   # (domain, reason)

    # ── Process each domain ────────────────────────────────────────────────────
    for name, tld in domains:
        result = check_domain(name, tld)
        print(format_result(result))

        if result["available"] is True:
            available_list.append(result["domain"])
        elif result["available"] is False:
            taken_list.append(result["domain"])
        else:
            error_list.append((result["domain"], result["error"] or "unknown error"))

        time.sleep(REQUEST_DELAY)

    # ── Final summary ──────────────────────────────────────────────────────────
    print_summary(available_list, taken_list, error_list)


if __name__ == "__main__":
    main()