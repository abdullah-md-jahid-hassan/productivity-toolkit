# n8n Workflow Automation AGENT.md — Local Rules

> Works together with the global AGENT.md and the backend rulebooks. Place this file wherever n8n workflow JSON/exports live for a project, or consult it whenever building or reviewing n8n workflows. **This is a rulebook, not a description of one running workflow set.** The patterns in §13 are worked examples — apply whichever matches something your project actually has.

## Anatomy of an n8n Workflow (read this before building anything)

- A workflow is a graph of **nodes** connected by **connections**. Data flows between nodes as an **array of items** — every node receives items from the node(s) before it and outputs items for the node(s) after it, even if there's only one of each.
- **Trigger nodes** start a workflow and sit at the far left with no input connection: `Webhook` (external HTTP call), `Schedule Trigger` (cron), `Manual Trigger` (testing), `Error Trigger` (fires when another workflow fails — see §7), and `Execute Workflow Trigger` (fires when *this* workflow is called as a sub-workflow by another — see §2).
- **Regular/action nodes** transform, branch, or send data: `Set` (shape data), `IF`/`Switch` (branch), `HTTP Request` (call an external API), `Code` (custom JavaScript/Python, used sparingly — see §9).
- **Expressions** (`{{ $json.fieldName }}`, `{{ $node["Node Name"].json.field }}`) reference data from the current or a named prior node. Prefer expressions and built-in nodes over a Code node wherever the logic is simple enough to express that way.
- **Pinned data** freezes a node's output so you can re-run everything downstream of it without re-triggering the real webhook or spending real API credits — use this constantly while building and testing (see §11).
- Every node has a **name** — the default (`HTTP Request1`, `IF1`) is never acceptable in a workflow anyone else will read. Rename every node to describe what it does specifically (see §3).

## 1. Modularity — Sub-Workflows as Reusable Node Groups

This is the direct n8n equivalent of the "services layer" and "modular function" rules in the backend files — a sub-workflow is n8n's version of a reusable, independently-testable function.

- Use the `Execute Workflow` node (parent) and `Execute Workflow Trigger` node (child) to break a large process into focused, single-responsibility workflows instead of one workflow that does everything.
- **If a workflow exceeds 15–20 nodes, or has more than three distinct branching paths, that's the signal to refactor it into sub-workflows** — not a suggestion to tidy up later, a concrete threshold to act on now.
- Each sub-workflow does one job: validate a payload, send a notification, enrich a record, log an error. If you can't describe what it does in one short sentence, it's doing too much and should be split further.
- The `Execute Workflow Trigger`'s defined input fields are a contract — the parent knows exactly what to send, the sub-workflow knows exactly what it will receive. Treat changing that contract like changing a function signature: check every parent workflow that calls it before changing it.
- Sub-workflows give you three real benefits, not just tidiness: **memory isolation** (each sub-workflow's memory is released when it completes, which matters for large batch processing), **independent testability** (open the sub-workflow alone and run it with the Manual Trigger or pinned test data — see §11), and **fix-once-benefit-everywhere** reuse (a shared "Send Slack Alert" sub-workflow means fixing the Slack API in one place fixes it for every workflow that calls it).
- Don't create a sub-workflow for something trivial that's only ever used once — the same over-engineering caution from the global rules applies here too.

## 2. Reusable Nodes & Naming Conventions

- Rename every node from its default label to a specific, descriptive name — `Validate Lead Payload`, not `IF1`; `Send Order Confirmation Email`, not `Workflow 4`. A workflow's node names should be readable top-to-bottom like a table of contents for what it does.
- Name workflows the same way: describe what they do, not a version number or a person's initials.
- Use n8n's folders/tags to organize workflows by domain, mirroring the backend's domain names where relevant (an "auth" tag, a "leads" tag) so the same boundaries hold across the whole stack.
- When the same small piece of logic (a formatting step, a lookup, a notification) shows up copy-pasted across more than one or two workflows, that's the signal to extract it into a shared sub-workflow (§1) instead of maintaining N copies that will inevitably drift apart.

## 3. Credential & Secrets Management

- All credentials go through n8n's encrypted credential manager — never pasted into a `Code`/`Set`/`HTTP Request` node's parameters as a literal string, and never constructed inline inside a `Code` node even "temporarily."
- Give each integration its own dedicated, least-privilege credential — a scoped API key or service account for that one purpose, not a shared admin-level credential reused across every workflow that happens to need "some" access to that service.
- For regulated data or at real scale, move beyond environment-variable-backed credentials to a dedicated secrets manager (HashiCorp Vault, AWS Secrets Manager, or similar) that n8n reads from at runtime.
- **Before sharing or exporting a workflow (to a teammate, to git, to a template library), check that no credential or API key rode along in the exported JSON.** This is one of the most common real leaks — a workflow gets exported to share the logic, and a hardcoded value goes with it because it was typed directly into a node parameter instead of referenced through the credential manager.
- Audit periodically: which webhooks have no authentication configured, which credentials are shared across many unrelated workflows, and which workflows haven't been reviewed since they were built as a "temporary" fix.

## 4. Webhook Security

**The default state of a new Webhook node is no authentication. That is acceptable for local testing and never acceptable for anything reachable in production.**

- Layer at least two of the following — one is not enough on its own:
  1. **Built-in authentication** on the Webhook node itself (Header Auth or JWT auth; Basic Auth only over HTTPS and only for low-sensitivity internal use).
  2. **HMAC signature verification.** n8n has no native HMAC-verification node, so this is done with a `Code` node placed immediately after the trigger: extract the provider's signature header, compute the expected HMAC over the **raw** request body (not the re-serialized parsed JSON — re-stringifying changes whitespace and key order and will silently break verification) using the shared secret, and compare using a **timing-safe** comparison, never `==`. Include and check a timestamp header to reject replayed requests that are older than a small tolerance window (e.g. 5 minutes).
  3. **IP allowlisting** at the reverse proxy in front of n8n, when the caller's IP ranges are known and stable (most payment and CRM providers publish theirs).
- **Verify before you do anything expensive.** The signature/auth check is the first real node after the trigger — don't run enrichment, database writes, or downstream API calls before trust is established.
- **Respond fast, process async.** Send a minimal `200`/`202` acknowledgment back to the caller quickly, then hand off to the actual processing (a sub-workflow, a queue) rather than making the calling provider wait on your entire pipeline. Several providers will treat a slow response as a failure and retry the same webhook, which then causes duplicate processing if you're not also idempotent (§7).
- Webhook URLs are secrets in their own right — long, unique, and rotated periodically. A leaked webhook URL without any of the above layers is a fully open, unauthenticated endpoint.
- Keep the webhook-processing endpoints network-separate from the n8n editor/admin interface where your hosting setup allows it, so a webhook-focused attack surface doesn't also expose workflow-editing access.

## 5. The Leads Callback Contract (Connecting Back to the Backend)

This ties directly to the "External dispatch & callback domains" pattern (§10C) in the Django/FastAPI rulebooks — read that pattern alongside this section, since they describe the same contract from opposite ends.

- When the backend dispatches work to n8n, it sends a **per-dispatch token** generated at dispatch time. The n8n workflow includes that same token, unchanged, in the callback request it sends back to the backend's callback endpoint. The backend verifies it matches the original dispatch before trusting the callback's result — n8n's job here is simply to carry that token through faithfully, not to invent its own auth scheme for the callback leg.
- When something external calls **into** n8n via a webhook (not a callback from your own dispatch, but an inbound event from a provider), that's a full webhook-security case — apply §4 in full, including HMAC verification, since this is an unrelated third party, not your own backend.
- Callbacks n8n sends to the backend must be idempotent-safe on the backend's side, but n8n should also avoid sending the same callback twice for the same event — if a workflow retries after a partial failure (§7), make sure the retry doesn't also re-fire a callback that already succeeded earlier in the same execution.

## 6. Error Handling — Retry, Dead Letter, and Alerting

- **Every node has an On Error setting.** Use `Continue` only for genuinely optional steps where failure shouldn't block the main flow (an analytics ping, a nice-to-have notification). Leave critical steps on `Stop Workflow` (the default) or route them to `Continue Using Error Output` when you need custom recovery logic for that specific failure.
- **Retry on Fail** (per node, in Settings) is appropriate for transient failures — timeouts, temporary rate limits. A sensible default is 3 retries with a wait between them (roughly 1 second for most APIs, longer for known rate-limited ones).
- **Know the real limitation here: n8n's built-in retry is fixed-delay, with no native exponential backoff or jitter.** If every failed execution retries at exactly the same interval, and you're running queue mode with multiple workers, many concurrent retries can hit the same struggling upstream API at the same moment — a thundering-herd problem the built-in retry doesn't protect against on its own. For anything calling a rate-limited or already-degraded external service, add a `Wait` node with a small randomized delay between manual retry attempts instead of relying on the fixed built-in interval alone.
- **Every workflow needs a dedicated Error Workflow set in its settings**, not just per-node retries. A workflow with retries but no Error Workflow means a retry that ultimately still fails disappears silently — nobody finds out until a customer complains days later. The Error Trigger workflow should, at minimum, log the failure (workflow name, node, error message, execution ID, timestamp, severity) to a durable store and alert a real channel (Slack, PagerDuty, email) — not just leave it in n8n's own execution list where nobody is looking.
- **A failure that exhausts its retries routes to a dead-letter path for manual reprocessing — it never just stops and disappears.** For anything tied to the ledger/refund patterns in the backend files (a failed lead dispatch, a failed payment-related step), this dead-letter path is what eventually triggers the compensating action (a refund) described in that pattern — the n8n side and the backend side of that guarantee only work together if both halves are actually implemented.
- Review your centralized error log periodically, not just when something is actively on fire — a small number of workflows are usually responsible for a disproportionate share of failures, and that log is how you find them instead of guessing.

## 7. Rate Limiting & Concurrency (Protecting Upstream APIs)

- n8n has no built-in outbound throttle equivalent to the backend's DRF/dependency-based rate limiting — if a workflow calls an external API in a loop, nothing stops it from firing requests faster than that API allows unless you add the limit yourself.
- For bulk operations, use `Split in Batches`/`Loop Over Items` with a `Wait` node between batches, sized to stay under the external API's documented rate limit — don't discover the limit by getting throttled in production.
- Respect rate-limit response headers from the external API where it provides them (a `Retry-After`-style header), the same way the backend rules require honoring `Retry-After` exactly rather than guessing.
- In queue mode, set the execution concurrency limit deliberately rather than leaving it at the default — unbounded concurrency is what turns "one external API is slow today" into "our database connection pool is exhausted and everything is slow today."

## 8. Data Validation & the Code Node

- Never trust an incoming webhook payload's shape just because it "should" be well-formed — validate required fields and types before passing the data into any side-effecting node (a database write, a payment action, a dispatch to another system).
- Prefer built-in nodes (`Set`, `IF`, `Filter`, `Switch`) over a `Code` node wherever the logic is simple enough to express that way — built-in nodes are easier to review at a glance, and a `Code` node is the most common place a hardcoded secret or an unvalidated assumption quietly sneaks in.
- When a `Code` node is genuinely necessary, keep it small and single-purpose (one clear transformation, not a multi-step mini-program), and reference credentials through n8n's expression/credential system rather than pasting a secret value into the code body.

## 9. Scaling — Queue Mode

- Production n8n runs in **queue mode** (a main process plus separate worker processes), not the default single-process mode — this is what allows executions to scale horizontally instead of queuing up behind each other.
- Queue mode needs a real database (Postgres), not SQLite, and its own environment-variable configuration separate from a single-instance setup.
- Monitor **queue depth** as an actual metric, not just individual execution success/failure — a growing queue depth is the earliest sign that executions are arriving faster than workers can process them, well before anything actually starts failing.

## 10. Testing Workflows

- Use pinned data (see Anatomy above) or the Manual Trigger to test a workflow or sub-workflow without re-triggering a real external webhook or spending real API quota/credits.
- Test a sub-workflow in isolation, directly in the editor, before wiring it into a parent workflow — this is the same principle as unit-testing a function before integration-testing the system that calls it.
- Never test against production credentials or a live payment/CRM provider. Use a staging n8n instance or a staging credential set with sandbox/test-mode credentials from the provider wherever one is offered.

## 11. Version Control & Change Management

- Export workflow JSON and commit it to git rather than relying solely on n8n's internal execution/version history — internal history isn't a substitute for a reviewable diff before a change goes live.
- Treat editing an active, production webhook-triggered workflow like deploying a code change — review it, understand what the change actually does, before saving and activating it. A quick edit to a live workflow that's currently receiving real traffic is exactly how "temporary" unauthenticated webhooks and other shortcuts end up living in production for months.

## 12. Common Domain Patterns (Worked Examples, Not Mandatory Workflows)

**A. Inbound webhook-triggered domains** (a payment provider, a CRM, a git host calling in)
- Full §4 webhook security applies. Verify → fast ack → hand off to async processing. Never process the payload's business logic before verification succeeds.

**B. External dispatch + callback domains** (the leads pattern — see §5)
- Dispatch a per-token-carrying request out, do the external work, call back with the same token. Idempotent on both ends. Failure after retries triggers the backend's compensating action (refund), not a silent drop.

**C. Scheduled sync/batch domains** (nightly usage syncs, periodic data pulls)
- Idempotent by a period key, same as the backend's usage-metering pattern — a re-run for an already-processed period must not double-apply. Rate-limit and batch large pulls (§7).

**D. Notification/alerting domains**
- The Error Workflow pattern in §6 is itself an instance of this — a dedicated, focused workflow whose only job is turning a failure signal into a human-visible alert.

## 13. Implementation Discipline — Precautions Before Building a Workflow

Before building or modifying any workflow, work through this checklist.

**Modularity**
- Is this workflow approaching 15–20 nodes or three-plus branches? That's the signal to extract a sub-workflow now, not after it becomes unreadable (§1).
- Does this repeat logic that already exists as a sub-workflow elsewhere? Reuse it instead of copy-pasting nodes.

**Security**
- Does this workflow have a Webhook trigger? Is authentication configured — not left on the default of none (§4)?
- Does anything in this workflow use a credential? Is it pulled from the credential manager, never typed directly into a node parameter (§3)?
- Is this workflow about to be exported or shared? Check the JSON for a hardcoded secret before sending it anywhere.

**Reliability**
- Does every node that calls an external service have Retry on Fail configured appropriately, and does the workflow as a whole have an Error Workflow set (§6)? A retry without an Error Workflow behind it is a failure that will eventually vanish silently.
- If this workflow calls an external API in a loop, is there a batching/wait strategy so it can't outrun that API's rate limit (§7)?
- Does this workflow's failure path lead to a dead-letter/manual-reprocessing step, or does a failed execution just stop with nothing else happening?

**When something doesn't fit cleanly**
If a workflow's requirements don't map cleanly onto one of these checks — an unusual integration, an ambiguous retry/compensation case — say so explicitly and flag the tradeoff, instead of silently picking an approach.

## 14. Workflow Backup JSON File Store Rule and Folder Structure
### Folder Structure
1. Root: `backups/`
2. Top-level Workflow type:
`main_workflow/`
`sub_workflow/`
3. Under the sub workflow each sub workflow will have their own folder with their name Without versioning tag
`sub_workflow_name/`
4. Inside the main workflow folder or each sub-workflow folder, there will be a versioning folder.
`v1`
`v2`
`v3`

### File name structure
`{number_of_backup(ex:1/2/3)}_{yy-mm-dd_hh-mm}_{short_state_identifier(ex:successful-image-upload-done)}.json`

#### Example
```txt
├── backups/
│   ├── main_workflow/
│   │   ├── v1/
│   │   │   └── 1_26-09-03_22-50_successful-image-upload-done.json
│   │   ├── v2/
│   │   └── ...
│   ├── sub_workflow/
│   │   ├── process-webflow-tags/
│   │   │   ├── v1/
│   │   │   └── 1_26-09-03_22-55_tags-updated.json
│   │   ├── send-confirmation-email/
│   │   │   ├── v1/
│   │   │   └── 1_26-09-03_22-56_email-sent.json
│   │   └── ...
```

### How and When to take the Automatic backup?

#### How
1. For a specific workflow find all versions. For example:
   - Main workflow: v1, v2, v3, v4
   - Sub workflow 1: v1, v2, v3
   - Sub workflow 2: v1, v2, v3
2. Then check the last backup for each version workflow. 
   - For main workflow last backup time is 26-09-03_22-50 (v1)
3. Use the MCP and check the workflow of all relative versions and check the rules for backup (mentioned below).
4. During MCP Explore if any Workflow doesn't have MCP enabled and If you need it, then ask the user to enable it first or and write "Continue" to continue the work after enabling the MCP server. Else give them the option to continue without enabling the MCP server and take backups only for MCP-server-enabled workflows. 

#### When
If scenario matches these conditions, then an automatic backup will trigger. 
1. If workflow changes are significant.
2. **AND** If there were changes in the workflow after the last backup. (last backup time < Last changes time)

**OR**

1. Use Specifically ask for backup. (e.g: "Take a backup of all/the workflow").
