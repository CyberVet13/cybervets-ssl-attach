# Deploy CyberVets Solutions website to S3 (static hosting)
# Usage: .\deploy-website.ps1 -BucketName my-website-bucket -Region us-east-1
# Optional: Add CloudFront + custom domain with CyberVets-SSL-Attach.ps1
param(
  [Parameter(Mandatory)]
  [string]$BucketName,
  [string]$Region = "us-east-1",
  [switch]$WhatIf,
  [switch]$MakePublic  # Apply bucket policy for public read (required for website)
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
  throw "AWS CLI not found. Install from https://aws.amazon.com/cli/"
}

# Ensure bucket exists (head-bucket returns no stdout; check exit code)
# SilentlyContinue prevents PowerShell from treating AWS CLI stderr as NativeCommandError
$prevEA = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
try {
  $null = aws s3api head-bucket --bucket $BucketName 2>&1
} finally {
  $ErrorActionPreference = $prevEA
}
$bucketExists = ($LASTEXITCODE -eq 0)
if (-not $bucketExists) {
  if ($WhatIf) {
    Write-Host "[WhatIf] Would create S3 bucket $BucketName in $Region"
  } else {
    Write-Host "Creating bucket $BucketName..."
    if ($Region -eq "us-east-1") {
      aws s3api create-bucket --bucket $BucketName --region $Region
    } else {
      aws s3api create-bucket --bucket $BucketName --region $Region --create-bucket-configuration "LocationConstraint=$Region"
    }
    if ($Region -ne "us-east-1") {
      aws s3api put-bucket-versioning --bucket $BucketName --versioning-configuration Status=Enabled 2>$null
    }
  }
}

# Enable static website hosting
if (-not $WhatIf) {
  Write-Host "Configuring static website hosting..."
  aws s3 website "s3://$BucketName" --index-document index.html --error-document 404.html
}

# Sync website files (exclude deploy script and README)
$source = Join-Path $scriptDir "."

if ($WhatIf) {
  Write-Host "[WhatIf] Would sync $source to s3://$BucketName"
  if ($bucketExists) {
    $prevEA = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try { aws s3 sync $source "s3://$BucketName" --exclude "*.ps1" --exclude "*.md" --exclude "*.yaml" --exclude "design-preview*.html" --dryrun 2>&1 } finally { $ErrorActionPreference = $prevEA }
  }
} else {
  Write-Host "Uploading files..."
  aws s3 sync $source "s3://$BucketName" --exclude "*.ps1" --exclude "*.md" --exclude "*.yaml" --exclude "design-preview*.html" --delete
}

# Optional: apply public read policy
if ($MakePublic -and -not $WhatIf) {
  Write-Host "Disabling Block Public Access (required for website)..."
  aws s3api put-public-access-block --bucket $BucketName --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
  $policy = @{
    Version = "2012-10-17"
    Statement = @(@{
      Sid = "PublicReadGetObject"
      Effect = "Allow"
      Principal = "*"
      Action = "s3:GetObject"
      Resource = "arn:aws:s3:::$BucketName/*"
    })
  } | ConvertTo-Json -Depth 5
  $policyFile = Join-Path $env:TEMP "s3-website-policy-$BucketName.json"
  $policy | Out-File -Encoding utf8 $policyFile
  try {
    aws s3api put-bucket-policy --bucket $BucketName --policy "file://$policyFile"
    Write-Host "Applied public read bucket policy."
  } finally {
    Remove-Item $policyFile -Force -ErrorAction SilentlyContinue
  }
} else {
  Write-Host "`nTip: Add -MakePublic to apply public read policy, or add manually in S3 console."
}

Write-Host "`nS3 website URL: http://$BucketName.s3-website-$Region.amazonaws.com"
Write-Host "For HTTPS + custom domain: Create CloudFront distribution, then run CyberVets-SSL-Attach.ps1"
