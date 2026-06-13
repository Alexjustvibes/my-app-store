# sync-notes.ps1
# Commits and pushes any changes under notes/ (a Windows junction pointing at
# C:\Users\andre\LLM Wiki). Designed to run unattended on a schedule:
#   - does nothing, cleanly, when no notes changed
#   - commits with a timestamped message when they did
#   - pushes only when there are local commits to send
#   - fails quietly when offline, leaving the commit for the next run to push
#
# Git follows a directory junction like a normal folder, so the real note FILES
# get committed (not a symlink reference). No core.symlinks config is needed.

# --- config: edit this if you move the repo ---
$Repo = 'C:\Users\andre\Documents\my-app-store'

if (-not (Test-Path -LiteralPath $Repo)) { exit 0 }
Set-Location -LiteralPath $Repo

# Any new/modified/deleted files under notes/ since the last commit?
$changes = git status --porcelain -- notes
if ($changes) {
    git add -- notes
    # Commit only if something is actually staged (avoids an empty-commit error).
    git diff --cached --quiet -- notes
    if ($LASTEXITCODE -ne 0) {
        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        git commit -m "notes sync $stamp" --quiet | Out-Null
    }
}

# Push only if the local branch is ahead of its upstream (covers this run's
# commit plus any that piled up while offline). Discard stderr and never throw,
# so an offline run just leaves the work for next time.
$ahead = git rev-list --count '@{u}..HEAD' 2>$null
if ($LASTEXITCODE -eq 0 -and [int]$ahead -gt 0) {
    git push --quiet 2>$null | Out-Null
}

exit 0
