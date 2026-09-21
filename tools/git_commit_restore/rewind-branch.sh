#!/usr/bin/env bash
#
# rewind-branch.sh
# ----------------
# Interactive tool to rewind a branch to a known-good commit and
# force-push it to the remote, so the remote becomes an exact copy
# of the clean local state. All commits AFTER the chosen commit are
# removed from the branch (a dated backup branch is created first).
#
# Typical use case: recovering from a malicious / unwanted push.
#
# Safety features:
#   - Creates a local backup branch of the current tip before reset.
#   - Verifies the target commit exists before doing anything.
#   - Refuses to run with uncommitted changes (they would be destroyed).
#   - Asks for explicit "yes" confirmation before reset and before push.
#   - Uses --force-with-lease first; falls back to --force only if the
#     user explicitly approves.
#
# Requirements: git >= 2.23 (uses `git switch`), bash >= 4.

set -u  # treat unset variables as an error (we handle errors manually, so no set -e)

# ---------------------------------------------------------------------------
# Pretty printing helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

info()  { printf "${CYAN}[INFO]${NC} %s\n"  "$1"; }
ok()    { printf "${GREEN}[ OK ]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
fail()  { printf "${RED}[FAIL]${NC} %s\n"  "$1"; exit 1; }

# ---------------------------------------------------------------------------
# Step 1: Ask for the repository location (default: current folder)
# ---------------------------------------------------------------------------
printf "\n=== Branch Rewind Tool ===\n\n"

read -r -p "Path to the local repository [default: ./]: " REPO_PATH
REPO_PATH="${REPO_PATH:-./}"

# Resolve to an absolute path and make sure it exists.
REPO_PATH="$(cd "$REPO_PATH" 2>/dev/null && pwd)" \
    || fail "Directory does not exist: check the path and try again."

cd "$REPO_PATH" || fail "Cannot enter directory: $REPO_PATH"

# Confirm this is really a git working tree (not just any folder,
# and not the inside of a bare repo).
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    fail "No git repository found at: $REPO_PATH (missing/invalid .git)"
fi

# Warn if we're in a subfolder of the repo, and move to its root so
# every later command runs from a predictable place.
TOPLEVEL="$(git rev-parse --show-toplevel)"
if [ "$TOPLEVEL" != "$REPO_PATH" ]; then
    warn "You pointed inside a repo. Using its root instead: $TOPLEVEL"
    cd "$TOPLEVEL" || fail "Cannot enter repo root."
fi
ok "Repository: $TOPLEVEL"

# ---------------------------------------------------------------------------
# Step 2: Refuse to run if there are uncommitted changes.
#         `git reset --hard` would silently destroy them.
# ---------------------------------------------------------------------------
if [ -n "$(git status --porcelain)" ]; then
    warn "You have uncommitted changes (or untracked files listed below):"
    git status --short
    fail "Commit or stash your changes first. A hard reset would destroy them."
fi

# ---------------------------------------------------------------------------
# Step 3: Show local branches and let the user pick one
# ---------------------------------------------------------------------------
printf "\n"
info "Local branches:"

# Collect branch names into an array (plain names, no '*' marker).
mapfile -t BRANCHES < <(git for-each-ref --format='%(refname:short)' refs/heads/)

if [ "${#BRANCHES[@]}" -eq 0 ]; then
    fail "No local branches found in this repository."
fi

CURRENT_BRANCH="$(git branch --show-current)"

for i in "${!BRANCHES[@]}"; do
    MARK=""
    [ "${BRANCHES[$i]}" = "$CURRENT_BRANCH" ] && MARK="  (current)"
    printf "  %2d) %s%s\n" "$((i + 1))" "${BRANCHES[$i]}" "$MARK"
done

printf "\n"
read -r -p "Select the branch to rewind [1-${#BRANCHES[@]}]: " BRANCH_NUM

# Validate: must be a number within range.
case "$BRANCH_NUM" in
    ''|*[!0-9]*) fail "Invalid input. Please enter a number." ;;
esac
if [ "$BRANCH_NUM" -lt 1 ] || [ "$BRANCH_NUM" -gt "${#BRANCHES[@]}" ]; then
    fail "Number out of range."
fi

BRANCH="${BRANCHES[$((BRANCH_NUM - 1))]}"
ok "Selected branch: $BRANCH"

# ---------------------------------------------------------------------------
# Step 4: Show recent commits on that branch and ask for the target hash
# ---------------------------------------------------------------------------
printf "\n"
info "Last 15 commits on '$BRANCH':"
printf "\n"
# %h short hash | %ad date | %an author | %s subject
git log -15 --format='  %C(yellow)%h%Creset  %ad  %C(cyan)%an%Creset  %s' \
    --date=format:'%Y-%m-%d %H:%M' "$BRANCH"

printf "\n"
printf '%b!! WARNING !!%b Every commit AFTER the one you choose will be\n' "$YELLOW" "$NC"
printf "removed from '%s' (locally AND on the remote after push).\n" "$BRANCH"
printf "Choose carefully. A backup branch will be created, but double-check\n"
printf "the hash before continuing.\n\n"

read -r -p "Enter the commit hash to rewind to (short or full): " TARGET_HASH
[ -z "$TARGET_HASH" ] && fail "No commit hash entered."

# Verify the hash exists AND is a commit (^{commit} also resolves tags).
if ! git rev-parse --verify --quiet "${TARGET_HASH}^{commit}" >/dev/null; then
    fail "Commit '$TARGET_HASH' was not found in this repository."
fi
FULL_HASH="$(git rev-parse "${TARGET_HASH}^{commit}")"

# Make sure the commit actually belongs to the selected branch's history.
# Rewinding to a commit from a different branch is almost always a mistake.
if ! git merge-base --is-ancestor "$FULL_HASH" "$BRANCH"; then
    fail "Commit $FULL_HASH is NOT part of '$BRANCH' history. Wrong hash or wrong branch."
fi

printf "\n"
info "You are about to rewind '$BRANCH' to this commit:"
printf "\n"
git show --no-patch --format='  Hash    : %H%n  Author  : %an <%ae>%n  Date    : %ad%n  Message : %s' "$FULL_HASH"
printf "\n"

# Show exactly which commits will be removed, so there are no surprises.
REMOVED_COUNT="$(git rev-list --count "${FULL_HASH}..${BRANCH}")"
if [ "$REMOVED_COUNT" -eq 0 ]; then
    ok "'$BRANCH' is already at this commit locally. Nothing to reset."
else
    warn "These $REMOVED_COUNT commit(s) will be REMOVED from '$BRANCH':"
    git log --format='  %C(red)%h%Creset  %an  %s' "${FULL_HASH}..${BRANCH}"
    printf "\n"
fi

read -r -p "Type 'yes' to continue: " CONFIRM
[ "$CONFIRM" = "yes" ] || fail "Aborted by user. Nothing was changed."

# ---------------------------------------------------------------------------
# Step 5: Create a temporary backup branch at the CURRENT tip
# ---------------------------------------------------------------------------
BACKUP_BRANCH="backup/${BRANCH}-$(date +%Y%m%d-%H%M%S)"

# `git branch <name> <start-point>` creates the branch without switching to it.
if git branch "$BACKUP_BRANCH" "$BRANCH"; then
    ok "Backup branch created: $BACKUP_BRANCH (points at the old tip)"
else
    fail "Could not create backup branch. Stopping before any destructive step."
fi

# ---------------------------------------------------------------------------
# Step 6: Switch to the branch and hard-reset it to the target commit
# ---------------------------------------------------------------------------
# `git switch` is the modern, clearer replacement for `git checkout <branch>`.
if ! git switch "$BRANCH" >/dev/null 2>&1; then
    fail "Could not switch to branch '$BRANCH'."
fi

if git reset --hard "$FULL_HASH" >/dev/null; then
    ok "Local '$BRANCH' now points at $FULL_HASH"
else
    fail "git reset failed. Your backup branch '$BACKUP_BRANCH' is untouched."
fi

# ---------------------------------------------------------------------------
# Step 7: Force-push so the remote becomes an exact copy of local
# ---------------------------------------------------------------------------
# Figure out which remote this branch pushes to (default: origin).
REMOTE="$(git config --get "branch.${BRANCH}.remote" || true)"
REMOTE="${REMOTE:-origin}"

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
    warn "No remote named '$REMOTE' found. Local reset is done; nothing was pushed."
    exit 0
fi

printf "\n"
info "Ready to push '$BRANCH' to remote '$REMOTE' ($(git remote get-url "$REMOTE"))"
warn "This will OVERWRITE the remote branch. All remote-only commits vanish."
read -r -p "Type 'yes' to force-push: " PUSH_CONFIRM
[ "$PUSH_CONFIRM" = "yes" ] || {
    warn "Push skipped. Local branch is reset; remote is unchanged."
    warn "Push later with: git push $REMOTE $BRANCH --force-with-lease"
    exit 0
}

# First attempt: --force-with-lease.
# It refuses to push if the remote moved past what our local repo last saw
# (i.e. someone pushed again in the meantime). Safer than plain --force.
if git push "$REMOTE" "$BRANCH" --force-with-lease; then
    ok "Remote '$REMOTE/$BRANCH' now exactly matches local '$BRANCH'."
else
    printf "\n"
    warn "--force-with-lease was rejected."
    warn "This usually means the remote has commits your local repo has not"
    warn "seen yet (e.g. the attacker pushed again, or a teammate pushed)."
    warn "Review the situation. Only continue if you are SURE you want to"
    warn "overwrite whatever is on the remote right now."
    read -r -p "Type 'FORCE' (capitals) to push with plain --force: " HARD_CONFIRM
    if [ "$HARD_CONFIRM" = "FORCE" ]; then
        if git push "$REMOTE" "$BRANCH" --force; then
            ok "Remote '$REMOTE/$BRANCH' overwritten successfully."
        else
            fail "Push failed. Check your permissions / branch protection rules."
        fi
    else
        warn "Push skipped. Local branch is reset; remote is unchanged."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "\n=== Summary ===\n"
printf "  Repository     : %s\n" "$TOPLEVEL"
printf "  Branch         : %s\n" "$BRANCH"
printf "  Now points at  : %s\n" "$FULL_HASH"
printf "  Backup branch  : %s (delete later with: git branch -D %s)\n" "$BACKUP_BRANCH" "$BACKUP_BRANCH"
printf "\nTeammates should run:  git fetch %s && git checkout %s && git reset --hard %s/%s\n\n" \
    "$REMOTE" "$BRANCH" "$REMOTE" "$BRANCH"