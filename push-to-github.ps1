# Push CyberVets SSL Attach to GitHub
# Run this after creating the repo at https://github.com/new

$repoName = "cybervets-ssl-attach"
$createUrl = "https://github.com/new?name=$repoName&description=ACM+SSL+certificate+attachment+for+CloudFront+or+ALB+with+Route+53+DNS"

Write-Host "Opening GitHub to create repository: $repoName" -ForegroundColor Cyan
Write-Host "1. Create the repo (leave empty - no README)" -ForegroundColor Yellow
Write-Host "2. Click Create repository" -ForegroundColor Yellow
Write-Host "3. This script will push when ready" -ForegroundColor Yellow
Start-Process $createUrl

$null = Read-Host "`nPress Enter after you've created the repo to push"
Write-Host "Pushing to origin..." -ForegroundColor Cyan
Set-Location $PSScriptRoot
git push -u origin master
if ($LASTEXITCODE -eq 0) {
  Write-Host "`nDone! https://github.com/CyberVet13/$repoName" -ForegroundColor Green
} else {
  Write-Host "`nPush failed. Ensure the repo exists and you're authenticated." -ForegroundColor Red
}
