# Push CyberVets SSL Attach to GitHub
# Uses Personal Access Token (PAT) for authentication.
# Usage: $env:GITHUB_TOKEN = "ghp_xxx"; .\push-to-github.ps1
#    or: .\push-to-github.ps1  (will prompt for token)

param([switch]$CreateRepo)

$repoName = "cybervets-ssl-attach"
$createUrl = "https://github.com/new?name=$repoName&description=ACM+SSL+certificate+attachment+for+CloudFront+or+ALB+with+Route+53+DNS"

# Get token: env var, or prompt
$token = $env:GITHUB_TOKEN
if (-not $token) {
  $sec = Read-Host "GitHub Personal Access Token" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

if (-not $token) { throw "Token required. Set GITHUB_TOKEN or enter when prompted." }

if ($CreateRepo) {
  Write-Host "Opening GitHub to create repository: $repoName" -ForegroundColor Cyan
  Start-Process $createUrl
  $null = Read-Host "Press Enter after you've created the repo"
}

Write-Host "Pushing to origin..." -ForegroundColor Cyan
Set-Location $PSScriptRoot

# Use credential helper to avoid token in command line / process args / history
$credScript = Join-Path $env:TEMP "git-cred-helper-$([Guid]::NewGuid().ToString('N').Substring(0,8)).ps1"
@'
$null = [System.Console]::In.ReadToEnd()  # consume credential protocol from stdin
Write-Output "username=CyberVet13"
Write-Output "password=$env:GIT_CREDENTIAL_PASSWORD"
'@ | Out-File -Encoding utf8 $credScript
try {
  $env:GIT_CREDENTIAL_PASSWORD = $token
  $credScriptPath = $credScript.Replace('\', '/')  # Git on Windows may strip backslashes
  $credHelper = "!powershell -NoProfile -ExecutionPolicy Bypass -File `"$credScriptPath`""
  $branch = git branch --show-current
  if (-not $branch) { $branch = "main" }  # fallback for detached HEAD
  git -c "credential.helper=$credHelper" push -u origin "${branch}:main" 2>&1
} finally {
  $env:GIT_CREDENTIAL_PASSWORD = $null
  $token = $null
  if (Test-Path $credScript) { Remove-Item $credScript -Force -ErrorAction SilentlyContinue }
}

if ($LASTEXITCODE -eq 0) {
  git branch --set-upstream-to=origin/main (git branch --show-current) 2>$null
  Write-Host "`nDone! https://github.com/CyberVet13/$repoName" -ForegroundColor Green
} else {
  Write-Host "`nPush failed. Check repo exists and token has repo scope." -ForegroundColor Red
}
