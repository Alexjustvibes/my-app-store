# sync-notes.ps1
# Commits and pushes any changes under notes/ (a Windows junction pointing at
# C:\Users\andre\LLM Wiki), and regenerates the Wiki app's index so the notes
# show up in the store app. Designed to run unattended on a schedule:
#   - rebuilds apps/wiki/notes-index.json from the current notes
#   - does nothing, cleanly, when nothing changed
#   - commits with a timestamped message when notes or the index changed
#   - pushes only when there are local commits to send
#   - fails quietly when offline, leaving the commit for the next run to push
#
# Git follows a directory junction like a normal folder, so the real note FILES
# get committed (not a symlink reference). No core.symlinks config is needed.

# --- config: edit this if you move the repo ---
$Repo = 'C:\Users\andre\Documents\my-app-store'

if (-not (Test-Path -LiteralPath $Repo)) { exit 0 }
Set-Location -LiteralPath $Repo
$notes = Join-Path $Repo 'notes'
$indexFile = Join-Path $Repo 'apps\wiki\notes-index.json'

# Rebuild the Wiki app's index (title + relative path for each markdown/text
# note). Titles come from the first H1, else the first non-empty line, else the
# filename. The index lives in the repo (not inside the junction), so the wiki
# folder is never written to.
if (Test-Path -LiteralPath $notes) {
  $items = Get-ChildItem -LiteralPath $notes -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.md', '.markdown', '.txt' } |
    ForEach-Object {
      $rel = $_.FullName.Substring($notes.Length).TrimStart('\').Replace('\', '/')
      $title = $_.BaseName
      $lines = Get-Content -LiteralPath $_.FullName -TotalCount 30 -Encoding UTF8 -ErrorAction SilentlyContinue
      $h1 = $lines | Where-Object { $_ -match '^\s*#\s+\S' } | Select-Object -First 1
      if ($h1) { $title = ($h1 -replace '^\s*#\s+', '').Trim() }
      else { $f = $lines | Where-Object { $_.Trim() } | Select-Object -First 1; if ($f) { $title = $f.Trim() } }
      [pscustomobject]@{ path = $rel; title = $title }
    } | Sort-Object path

  # Build a JSON array deterministically (per-item compress avoids the
  # single-element-unwrap quirk in Windows PowerShell's ConvertTo-Json).
  $parts = @($items | ForEach-Object { $_ | ConvertTo-Json -Compress })
  $json = '[' + ($parts -join ',') + ']'
  if (Test-Path -LiteralPath (Split-Path $indexFile)) {
    [IO.File]::WriteAllText($indexFile, $json, (New-Object System.Text.UTF8Encoding $false))
  }
}

# Any new/modified/deleted notes or a changed index since the last commit?
$changes = git status --porcelain -- notes apps/wiki/notes-index.json
if ($changes) {
  git add -- notes apps/wiki/notes-index.json
  # Only commit if something is actually staged (avoids an empty-commit error).
  git diff --cached --quiet -- notes apps/wiki/notes-index.json
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
