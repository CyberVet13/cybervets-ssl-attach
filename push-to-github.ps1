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
$pushUrl = "https://CyberVet13:$token@github.com/CyberVet13/$repoName.git"
git push $pushUrl master 2>&1
$token = $null  # Clear from memory

if ($LASTEXITCODE -eq 0) {
  git branch --set-upstream-to=origin/master master 2>$null
  Write-Host "`nDone! https://github.com/CyberVet13/$repoName" -ForegroundColor Green
} else {
  Write-Host "`nPush failed. Check repo exists and token has repo scope." -ForegroundColor Red
}
