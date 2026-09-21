<#
.SYNOPSIS
    Interactive tool to rewind a git branch to a known-good commit and
    force-push it, so the remote becomes an exact copy of the clean local
    state. All commits AFTER the chosen commit are removed from the branch
    (a dated backup branch is created first).

.DESCRIPTION
    Typical use case: recovering from a malicious / unwanted push.

    Safety features:
      - Creates a local backup branch of the current tip before reset.
      - Verifies the target commit exists before doing anything.
      - Refuses to run with uncommitted changes (they would be destroyed).
      - Asks for explicit "yes" confirmation before reset and before push.
      - Uses --force-with-lease first; falls back to --force only if the
        user explicitly types FORCE.

.NOTES
    Compatible with Windows PowerShell 5.1 (built into Windows 10/11)
    and PowerShell 7+. Requires git >= 2.23 (uses `git switch`).

    If Windows blocks the script, run it like this:
        powershell -ExecutionPolicy Bypass -File .\rewind-branch.ps1
#>

# IMPORTANT: We deliberately keep the default 'Continue' error preference.
# In Windows PowerShell 5.1, setting $ErrorActionPreference = 'Stop' can make
# harmless stderr output from native commands (like git) throw a false
# "NativeCommandError". We don't need 'Stop' anyway: git never throws in
# PowerShell - we check $LASTEXITCODE manually after every git call instead.
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# Pretty printing helpers
# ---------------------------------------------------------------------------
function Write-Info ($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok   ($msg) { Write-Host "[ OK ] $msg" -ForegroundColor Green }
function Write-Warn ($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Fail       ($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "=== Branch Rewind Tool ===" -ForegroundColor White
Write-Host ""

# ---------------------------------------------------------------------------
# Step 0: Make sure git itself is available
# ---------------------------------------------------------------------------
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Fail "git was not found in PATH. Install Git for Windows first: https://git-scm.com/download/win"
}

# ---------------------------------------------------------------------------
# Step 1: Ask for the repository location (default: current folder)
# ---------------------------------------------------------------------------
$repoInput = Read-Host "Path to the local repository [default: ./]"
if ([string]::IsNullOrWhiteSpace($repoInput)) { $repoInput = "." }

# Resolve to an absolute path and make sure the directory exists.
$resolved = Resolve-Path -Path $repoInput -ErrorAction SilentlyContinue
if (-not $resolved) {
    Fail "Directory does not exist: $repoInput"
}
Set-Location -Path $resolved.Path

# Confirm this is really a git working tree (not just any folder).
# 2>$null hides git's own error text; we print our own message instead.
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Fail "No git repository found at: $($resolved.Path) (missing/invalid .git)"
}

# If the user pointed inside a subfolder of the repo, move to its root so
# every later command runs from a predictable place.
$topLevel = (git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($topLevel)) {
    Fail "Could not determine the repository root."
}
# git prints forward slashes even on Windows (e.g. C:/Users/...), while
# Resolve-Path gives backslashes (C:\Users\...). Normalize BOTH sides to
# forward slashes before comparing, so the comparison is reliable.
$topLevelWin  = $topLevel -replace '/', '\'
$topNormal    = ($topLevel -replace '\\', '/').TrimEnd('/')
$hereNormal   = ($resolved.Path -replace '\\', '/').TrimEnd('/')
if ($topNormal -ne $hereNormal) {
    Write-Warn "You pointed inside a repo. Using its root instead: $topLevelWin"
    Set-Location -Path $topLevel
}
Write-Ok "Repository: $topLevelWin"

# ---------------------------------------------------------------------------
# Step 2: Refuse to run if there are uncommitted changes.
#         `git reset --hard` would silently destroy them.
# ---------------------------------------------------------------------------
$dirty = git status --porcelain
if ($LASTEXITCODE -ne 0) { Fail "git status failed. Repository may be corrupted." }
if ($dirty) {
    Write-Warn "You have uncommitted changes (or untracked files listed below):"
    git status --short
    Fail "Commit or stash your changes first. A hard reset would destroy them."
}

# ---------------------------------------------------------------------------
# Step 3: Show local branches and let the user pick one
# ---------------------------------------------------------------------------
Write-Host ""
Write-Info "Local branches:"

# @( ) forces an array even when there is only one branch. Without it,
# PowerShell would return a single string and .Count / indexing break.
$branches = @(git for-each-ref --format='%(refname:short)' refs/heads/)
if ($LASTEXITCODE -ne 0 -or $branches.Count -eq 0) {
    Fail "No local branches found in this repository."
}

$currentBranch = (git branch --show-current)

for ($i = 0; $i -lt $branches.Count; $i++) {
    $mark = ""
    if ($branches[$i] -eq $currentBranch) { $mark = "  (current)" }
    Write-Host ("  {0,2}) {1}{2}" -f ($i + 1), $branches[$i], $mark)
}

Write-Host ""
$branchNum = Read-Host "Select the branch to rewind [1-$($branches.Count)]"

# Validate: must be a whole number within range. [int]::TryParse avoids
# exceptions on text input like "abc".
$parsed = 0
if (-not [int]::TryParse($branchNum, [ref]$parsed)) {
    Fail "Invalid input. Please enter a number."
}
if ($parsed -lt 1 -or $parsed -gt $branches.Count) {
    Fail "Number out of range."
}

$branch = $branches[$parsed - 1]
Write-Ok "Selected branch: $branch"

# ---------------------------------------------------------------------------
# Step 4: Show recent commits on that branch and ask for the target hash
# ---------------------------------------------------------------------------
Write-Host ""
Write-Info "Last 15 commits on '$branch':"
Write-Host ""
# %h short hash | %ad date | %an author | %s subject
git log -15 --format='  %h  %ad  %an  %s' --date=format:'%Y-%m-%d %H:%M' $branch
Write-Host ""

Write-Host "!! WARNING !! " -ForegroundColor Yellow -NoNewline
Write-Host "Every commit AFTER the one you choose will be"
Write-Host "removed from '$branch' (locally AND on the remote after push)."
Write-Host "Choose carefully. A backup branch will be created, but double-check"
Write-Host "the hash before continuing."
Write-Host ""

$targetHash = Read-Host "Enter the commit hash to rewind to (short or full)"
if ([string]::IsNullOrWhiteSpace($targetHash)) { Fail "No commit hash entered." }

# Verify the hash exists AND is a commit. The ^{commit} suffix also
# resolves annotated tags to their commit.
# NOTE for PowerShell: ^{commit} must be single-quoted when concatenated,
# otherwise { } could be misread. We build the string explicitly.
$revSpec = $targetHash + '^{commit}'
$fullHash = git rev-parse --verify --quiet $revSpec
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($fullHash)) {
    Fail "Commit '$targetHash' was not found in this repository."
}

# Make sure the commit actually belongs to the selected branch's history.
# Rewinding to a commit from a different branch is almost always a mistake.
git merge-base --is-ancestor $fullHash $branch
if ($LASTEXITCODE -ne 0) {
    Fail "Commit $fullHash is NOT part of '$branch' history. Wrong hash or wrong branch."
}

Write-Host ""
Write-Info "You are about to rewind '$branch' to this commit:"
Write-Host ""
git show --no-patch --format='  Hash    : %H%n  Author  : %an <%ae>%n  Date    : %ad%n  Message : %s' $fullHash
Write-Host ""

# Show exactly which commits will be removed, so there are no surprises.
$removedCount = [int](git rev-list --count "$fullHash..$branch")
if ($removedCount -eq 0) {
    Write-Ok "'$branch' is already at this commit locally. Nothing to reset."
}
else {
    Write-Warn "These $removedCount commit(s) will be REMOVED from '$branch':"
    git log --format='  %h  %an  %s' "$fullHash..$branch"
    Write-Host ""
}

$confirm = Read-Host "Type 'yes' to continue"
if ($confirm -cne 'yes') { Fail "Aborted by user. Nothing was changed." }

# ---------------------------------------------------------------------------
# Step 5: Create a temporary backup branch at the CURRENT tip
# ---------------------------------------------------------------------------
$stamp        = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupBranch = "backup/$branch-$stamp"

# `git branch <name> <start-point>` creates the branch without switching.
git branch $backupBranch $branch
if ($LASTEXITCODE -ne 0) {
    Fail "Could not create backup branch. Stopping before any destructive step."
}
Write-Ok "Backup branch created: $backupBranch (points at the old tip)"

# ---------------------------------------------------------------------------
# Step 6: Switch to the branch and hard-reset it to the target commit
# ---------------------------------------------------------------------------
# `git switch` is the modern, clearer replacement for `git checkout <branch>`.
# git writes its "Switched to branch..." notice to stderr; hide it since we
# print our own status lines.
git switch $branch 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Could not switch to branch '$branch'." }

git reset --hard $fullHash | Out-Null
if ($LASTEXITCODE -ne 0) {
    Fail "git reset failed. Your backup branch '$backupBranch' is untouched."
}
Write-Ok "Local '$branch' now points at $fullHash"

# ---------------------------------------------------------------------------
# Step 7: Force-push so the remote becomes an exact copy of local
# ---------------------------------------------------------------------------
# Figure out which remote this branch pushes to (default: origin).
$remote = git config --get "branch.$branch.remote" 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) { $remote = 'origin' }

$remoteUrl = git remote get-url $remote 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Warn "No remote named '$remote' found. Local reset is done; nothing was pushed."
    exit 0
}

Write-Host ""
Write-Info "Ready to push '$branch' to remote '$remote' ($remoteUrl)"
Write-Warn "This will OVERWRITE the remote branch. All remote-only commits vanish."
$pushConfirm = Read-Host "Type 'yes' to force-push"
if ($pushConfirm -cne 'yes') {
    Write-Warn "Push skipped. Local branch is reset; remote is unchanged."
    Write-Warn "Push later with: git push $remote $branch --force-with-lease"
    exit 0
}

# First attempt: --force-with-lease.
# It refuses to push if the remote moved past what our local repo last saw
# (i.e. someone pushed again in the meantime). Safer than plain --force.
git push $remote $branch --force-with-lease
if ($LASTEXITCODE -eq 0) {
    Write-Ok "Remote '$remote/$branch' now exactly matches local '$branch'."
}
else {
    Write-Host ""
    Write-Warn "--force-with-lease was rejected."
    Write-Warn "This usually means the remote has commits your local repo has not"
    Write-Warn "seen yet (e.g. the attacker pushed again, or a teammate pushed)."
    Write-Warn "Review the situation. Only continue if you are SURE you want to"
    Write-Warn "overwrite whatever is on the remote right now."
    $hardConfirm = Read-Host "Type 'FORCE' (capitals) to push with plain --force"
    if ($hardConfirm -ceq 'FORCE') {
        git push $remote $branch --force
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "Remote '$remote/$branch' overwritten successfully."
        }
        else {
            Fail "Push failed. Check your permissions / branch protection rules."
        }
    }
    else {
        Write-Warn "Push skipped. Local branch is reset; remote is unchanged."
        exit 0
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor White
Write-Host "  Repository     : $topLevelWin"
Write-Host "  Branch         : $branch"
Write-Host "  Now points at  : $fullHash"
Write-Host "  Backup branch  : $backupBranch (delete later with: git branch -D $backupBranch)"
Write-Host ""
Write-Host "Teammates should run:  git fetch $remote; git checkout $branch; git reset --hard $remote/$branch"
Write-Host ""