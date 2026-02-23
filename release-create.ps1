# Create GitHub Release v1.0.0
# Usage: $env:GITHUB_TOKEN = "ghp_xxx"; .\release-create.ps1
#    or: .\release-create.ps1 -Token ghp_xxx
#    or: .\release-create.ps1  (will prompt for token)
param([string]$Token = $env:GITHUB_TOKEN)

if (-not $Token) {
  $sec = Read-Host "GitHub Personal Access Token (repo scope)" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  $Token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}
if (-not $Token) { throw "Token required. Set GITHUB_TOKEN or enter when prompted." }

$owner = "CyberVet13"
$repo = "cybervets-ssl-attach"
$tag = "v1.0.0"
$notesPath = Join-Path $PSScriptRoot "RELEASE_NOTES_v1.0.0.md"
$notes = Get-Content $notesPath -Raw

$body = @{
  tag_name         = $tag
  name             = $tag
  body             = $notes
  draft            = $false
  prerelease       = $false
} | ConvertTo-Json

$headers = @{
  Authorization = "Bearer $Token"
  Accept        = "application/vnd.github+json"
  "X-GitHub-Api-Version" = "2022-11-28"
}

try {
  $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$owner/$repo/releases" -Method Post -Headers $headers -Body $body -ContentType "application/json; charset=utf-8"
  Write-Host "Release created: $($response.html_url)" -ForegroundColor Green
} catch {
  $code = $null
  if ($_.Exception.Response) { $code = $_.Exception.Response.StatusCode.value__ }
  if ($code -eq 422) {
    Write-Host "Release v1.0.0 may already exist. Check: https://github.com/$owner/$repo/releases" -ForegroundColor Yellow
  } elseif ($code -eq 401) {
    Write-Host "Unauthorized. Use a PAT with 'repo' scope: .\release-create.ps1 -Token YOUR_PAT" -ForegroundColor Red
  } else {
    throw
  }
}
