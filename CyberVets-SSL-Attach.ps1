<#
.SYNOPSIS
  Attaches ACM SSL/TLS certificates to CloudFront or ALB, with optional Route 53 DNS updates.

.DESCRIPTION
  Interactive or parameter-driven script that discovers ACM certificates, attaches them
  to CloudFront distributions or ALB listeners, and optionally creates/updates Route 53
  ALIAS records for root and www subdomains.

.PARAMETER Domain
  Base domain (e.g. cybervetssolutions.com). Omit for interactive prompt.

.PARAMETER Target
  CloudFront or ALB. Omit for interactive prompt.

.PARAMETER Region
  AWS region for ALB (cert must be in same region). Omit for interactive prompt.

.PARAMETER UpdateDns
  Update Route 53 DNS records. Omit for interactive prompt.

.PARAMETER DistributionId
  CloudFront distribution ID. When set, skips interactive distribution picker.

.PARAMETER LoadBalancerArn
  ALB ARN. Requires ListenerArn. Skips interactive ALB picker.

.PARAMETER ListenerArn
  ALB listener ARN. Requires LoadBalancerArn. Skips interactive listener picker.

.PARAMETER CertificateArn
  ACM certificate ARN. When set, skips certificate discovery.

.PARAMETER WhatIf
  Show what would be done without making changes.

.PARAMETER Verbose
  Show detailed progress messages.

.EXAMPLE
  .\CyberVets-SSL-Attach.ps1
  Interactive mode with prompts.

.EXAMPLE
  .\CyberVets-SSL-Attach.ps1 -Domain example.com -Target CloudFront -UpdateDns -WhatIf
  Dry-run for CloudFront + Route 53.

.EXAMPLE
  .\CyberVets-SSL-Attach.ps1 -Domain example.com -Target CloudFront -DistributionId E1234ABCD -UpdateDns
  Non-interactive CloudFront with specific distribution.

.EXAMPLE
  .\CyberVets-SSL-Attach.ps1 -Domain example.com -Target ALB -Region us-east-1 -LoadBalancerArn arn:... -ListenerArn arn:... -UpdateDns
  Non-interactive ALB with specific listener.
#>

# =========================
# CyberVets SSL Attach Helper
# Works for: CloudFront OR ALB
# Also can update Route 53 DNS
# =========================

[CmdletBinding(SupportsShouldProcess)]
param(
  [Parameter()]
  [string]$Domain,

  [Parameter()]
  [ValidateSet("CloudFront", "ALB")]
  [string]$Target,

  [Parameter()]
  [string]$Region,

  [Parameter()]
  [switch]$UpdateDns,

  [Parameter()]
  [string]$DistributionId,

  [Parameter()]
  [string]$LoadBalancerArn,

  [Parameter()]
  [string]$ListenerArn,

  [Parameter()]
  [string]$CertificateArn
)

$ErrorActionPreference = "Stop"

# ---- Pre-flight: verify AWS CLI ----
Write-Verbose "Checking AWS CLI..."
if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
  throw "AWS CLI not found. Install it from https://aws.amazon.com/cli/ and run 'aws configure'."
}
aws sts get-caller-identity 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "AWS CLI not configured or credentials invalid. Run 'aws configure'."
}

function Ask($msg, $default = $null) {
  if ($null -ne $default -and $default -ne "") {
    $v = Read-Host "$msg [$default]"
    if ($v -eq "") { return $default }
    return $v
  } else {
    return (Read-Host $msg)
  }
}

function Choose($title, $options) {
  Write-Host ""
  Write-Host $title
  for ($i = 0; $i -lt $options.Count; $i++) {
    Write-Host "  $($i + 1)) $($options[$i])"
  }
  while ($true) {
    $c = Read-Host "Choose 1-$($options.Count)"
    if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $options.Count) {
      return $options[[int]$c - 1]
    }
  }
}

function Invoke-AwsCli {
  param([string]$Command)
  Write-Verbose "AWS: $Command"
  $output = Invoke-Expression $Command 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "AWS CLI failed (exit $LASTEXITCODE): $Command`n$output"
  }
  return $output
}

# Convert Windows path to file:// URL for AWS CLI (handles backslashes)
function Get-FileUriForAws {
  param([string]$Path)
  $abs = [System.IO.Path]::GetFullPath($Path)
  return "file:///$($abs.Replace('\', '/'))"
}

# ---- Inputs ----
$domain = if ($Domain) { $Domain } else { Ask "Base domain" "cybervetssolutions.com" }

# Choose target FIRST so we know which region to use for ACM
# CloudFront requires us-east-1; ALB requires cert in same region as ALB
$target = if ($Target) {
  if ($Target -eq "ALB") { "Application Load Balancer (ALB)" } else { "CloudFront" }
} else {
  Choose "`n== 1) Where do you want to attach the certificate? ==" @("CloudFront", "Application Load Balancer (ALB)")
}

if ($target -eq "CloudFront") {
  $regionAcm = "us-east-1"  # MUST be us-east-1 for CloudFront certs
} else {
  $regionAlb = if ($Region) { $Region } else { Ask "ALB region" "us-east-1" }
  $regionAcm = $regionAlb   # ALB cert must be in same region as ALB
}

if ($CertificateArn) {
  Write-Host "`n== 2) Using provided certificate ARN =="
  $certDesc = Invoke-AwsCli "aws acm describe-certificate --region $regionAcm --certificate-arn $CertificateArn --output json" | ConvertFrom-Json
  if ($certDesc.Certificate.Status -ne "ISSUED") {
    throw "Certificate $CertificateArn is not ISSUED (status: $($certDesc.Certificate.Status))."
  }
  $certArn = $CertificateArn
  $best = $certDesc.Certificate
  Write-Host "Using certificate ARN: $certArn"
  Write-Host "Certificate domains (SANs):"
  $best.SubjectAlternativeNames | ForEach-Object { Write-Host "  - $_" }
} else {
  Write-Verbose "ACM region: $regionAcm"
Write-Host "`n== 2) Finding ISSUED ACM certificate for $domain in $regionAcm =="

  # Find best matching cert (issued) that includes domain (and ideally www)
  $certsJson = Invoke-AwsCli "aws acm list-certificates --region $regionAcm --certificate-statuses ISSUED --output json" | ConvertFrom-Json
  if (-not $certsJson.CertificateSummaryList) {
    throw "No ISSUED certs found in ACM ($regionAcm)."
  }

  # NOTE: Avoid $matches - it's a PowerShell automatic variable (regex results)
  $certMatches = $certsJson.CertificateSummaryList | Where-Object { $_.DomainName -eq $domain }
  if (-not $certMatches) {
    # fallback: any cert that is for base or wildcard or something containing domain
    $certMatches = $certsJson.CertificateSummaryList | Where-Object {
      $_.DomainName -like "*$domain*" -or $_.DomainName -eq "*.$domain"
    }
  }

  if (-not $certMatches) {
    throw "Could not find an ISSUED ACM cert that matches $domain in $regionAcm."
  }

  # If multiple, pick the newest by NotAfter (requires describe)
  $best = $null
  $bestNotAfter = [DateTime]::MinValue
  foreach ($m in $certMatches) {
    $d = Invoke-AwsCli "aws acm describe-certificate --region $regionAcm --certificate-arn $($m.CertificateArn) --output json" | ConvertFrom-Json
    $na = [DateTime]$d.Certificate.NotAfter
    if ($na -gt $bestNotAfter) {
      $bestNotAfter = $na
      $best = $d.Certificate
    }
  }

  $certArn = $best.CertificateArn
  Write-Host "Using certificate ARN: $certArn"
  Write-Host "Certificate domains (SANs):"
  $best.SubjectAlternativeNames | ForEach-Object { Write-Host "  - $_" }
}

# ---- Optional DNS update ----
$doDns = if ($PSBoundParameters.ContainsKey("UpdateDns")) {
  $UpdateDns.IsPresent
} else {
  (Ask "`nDo you want this script to also update Route 53 DNS (A/AAAA ALIAS for root + www)? (y/n)" "y").ToLower().StartsWith("y")
}

# Find hosted zone for domain
$hzId = $null
if ($doDns) {
  Write-Host "`n== Finding Route 53 hosted zone for $domain =="
  $hzName = "$domain."
  $hzPath = Invoke-AwsCli "aws route53 list-hosted-zones --query `"HostedZones[?Name=='$($hzName.Replace("'","''"))'].Id | [0]`" --output text"
  if (-not $hzPath -or $hzPath -eq "None") {
    throw "No hosted zone found in Route 53 for $domain. Create/verify hosted zone first."
  }
  $hzId = $hzPath.Split("/")[-1]
  Write-Host "Hosted Zone ID: $hzId"
}

$tempFiles = @()

try {
  if ($target -eq "CloudFront") {
    # --------------------------
    # CLOUD FRONT
    # --------------------------
    if ($DistributionId) {
      $distId = $DistributionId
      Write-Host "`n== 3) CloudFront: using distribution $distId (from parameter) =="
    } else {
      Write-Host "`n== 3) CloudFront: pick a distribution =="
      $dists = Invoke-AwsCli "aws cloudfront list-distributions --output json" | ConvertFrom-Json
      $items = $dists.DistributionList.Items
      if (-not $items) { throw "No CloudFront distributions found in this account." }

      $choices = @()
      foreach ($it in $items) {
        $aliases = ""
        if ($it.Aliases -and $it.Aliases.Items) { $aliases = ($it.Aliases.Items -join ", ") }
        $choices += "$($it.Id) | $($it.DomainName) | Aliases: $aliases"
      }
      $pick = Choose "Select the CloudFront distribution to update:" $choices
      $distId = ($pick.Split("|")[0]).Trim()
    }

    Write-Verbose "Fetching CloudFront config for $distId..."
    Write-Host "`nUpdating distribution $distId to use ACM cert + aliases..."
    $cfg = Invoke-AwsCli "aws cloudfront get-distribution-config --id $distId --output json" | ConvertFrom-Json
    $etag = $cfg.ETag
    $config = $cfg.DistributionConfig

    # Merge root + www into existing aliases (do not overwrite other aliases)
    $existing = @()
    if ($config.Aliases -and $config.Aliases.Items) { $existing = @($config.Aliases.Items) }
    $required = @($domain, "www.$domain")
    $aliasList = ($existing + $required) | Select-Object -Unique
    $config.Aliases.Quantity = $aliasList.Count
    $config.Aliases.Items = @($aliasList)

    # Set ViewerCertificate to ACM
    $config.ViewerCertificate = @{
      ACMCertificateArn      = $certArn
      SSLSupportMethod       = "sni-only"
      MinimumProtocolVersion = "TLSv1.2_2021"
    }

    # Redirect http->https on all cache behaviors (DefaultCacheBehavior + CacheBehaviors)
    if ($config.DefaultCacheBehavior) {
      $config.DefaultCacheBehavior.ViewerProtocolPolicy = "redirect-to-https"
    }
    if ($config.CacheBehaviors -and $config.CacheBehaviors.Items) {
      foreach ($beh in $config.CacheBehaviors.Items) {
        $beh.ViewerProtocolPolicy = "redirect-to-https"
      }
    }

    if ($WhatIfPreference) {
      Write-Host "`n[WhatIf] Would update CloudFront distribution $distId with:"
      Write-Host "  - ACM cert: $certArn"
      Write-Host "  - Aliases: $($aliasList -join ', ')"
      Write-Host "  - ViewerProtocolPolicy: redirect-to-https (all behaviors)"
    } else {
      $tmp = Join-Path $env:TEMP "cf-config-$([Guid]::NewGuid().ToString('N').Substring(0,8)).json"
      $tempFiles += $tmp
      ($config | ConvertTo-Json -Depth 50) | Out-File -Encoding utf8 $tmp

      $cfgUri = Get-FileUriForAws $tmp
      Invoke-AwsCli "aws cloudfront update-distribution --id $distId --if-match $etag --distribution-config `"$cfgUri`"" | Out-Null
      Write-Host "CloudFront update submitted."
    }

    if ($doDns) {
      Write-Host "`n== 4) Route 53: create/update ALIAS records to CloudFront =="
      $cfDomain = (Invoke-AwsCli "aws cloudfront get-distribution --id $distId --query `"Distribution.DomainName`" --output text").Trim()
      $cfHz = "Z2FDTNDATAQYW2"

      if ($WhatIfPreference) {
        Write-Host "[WhatIf] Would UPSERT Route 53 records in $hzId :"
        Write-Host "  - $domain (A, AAAA) -> $cfDomain"
        Write-Host "  - www.$domain (A, AAAA) -> $cfDomain"
      } else {
      $changes = @(
        @{
          Action           = "UPSERT"
          ResourceRecordSet = @{
            Name            = $domain
            Type            = "A"
            AliasTarget     = @{
              HostedZoneId         = $cfHz
              DNSName             = $cfDomain
              EvaluateTargetHealth = $false
            }
          }
        },
        @{
          Action           = "UPSERT"
          ResourceRecordSet = @{
            Name            = "www.$domain"
            Type            = "A"
            AliasTarget     = @{
              HostedZoneId         = $cfHz
              DNSName             = $cfDomain
              EvaluateTargetHealth = $false
            }
          }
        },
        @{
          Action           = "UPSERT"
          ResourceRecordSet = @{
            Name            = $domain
            Type            = "AAAA"
            AliasTarget     = @{
              HostedZoneId         = $cfHz
              DNSName             = $cfDomain
              EvaluateTargetHealth = $false
            }
          }
        },
        @{
          Action           = "UPSERT"
          ResourceRecordSet = @{
            Name            = "www.$domain"
            Type            = "AAAA"
            AliasTarget     = @{
              HostedZoneId         = $cfHz
              DNSName             = $cfDomain
              EvaluateTargetHealth = $false
            }
          }
        }
      )

      $batch = @{ Comment = "Point $domain + www to CloudFront"; Changes = $changes } | ConvertTo-Json -Depth 20
      $dnsFile = Join-Path $env:TEMP "r53-alias-cf-$([Guid]::NewGuid().ToString('N').Substring(0,8)).json"
      $tempFiles += $dnsFile
      $batch | Out-File -Encoding utf8 $dnsFile

      $dnsUri = Get-FileUriForAws $dnsFile
      $chgId = (Invoke-AwsCli "aws route53 change-resource-record-sets --hosted-zone-id $hzId --change-batch `"$dnsUri`" --query `"ChangeInfo.Id`" --output text").Trim()
      Write-Host "Route 53 change submitted: $chgId"
      Invoke-AwsCli "aws route53 wait resource-record-sets-changed --id $chgId" | Out-Null
      Write-Host "Route 53 change INSYNC."
      }
    }

    if ($WhatIfPreference) {
      Write-Host "`n[WhatIf] DONE. No changes were made. Run without -WhatIf to apply."
    } else {
      Write-Host "`nDONE. CloudFront will take a few minutes to fully deploy. Check:"
      Write-Host "  - CloudFront distribution status"
      Write-Host "  - Then test: https://$domain and https://www.$domain"
    }

  } else {
    # --------------------------
    # ALB
    # --------------------------
    if ($PSBoundParameters.ContainsKey("LoadBalancerArn") -and $PSBoundParameters.ContainsKey("ListenerArn") -and $LoadBalancerArn -and $ListenerArn) {
      $lbArn = $LoadBalancerArn
      $listenerArn = $ListenerArn
      Write-Host "`n== 3) ALB: using LoadBalancerArn and ListenerArn (from parameters) =="
    } else {
      Write-Host "`n== 3) ALB: pick an ALB listener to attach cert =="
      $lbs = Invoke-AwsCli "aws elbv2 describe-load-balancers --region $regionAlb --output json" | ConvertFrom-Json
      if (-not $lbs.LoadBalancers) { throw "No load balancers found in $regionAlb." }

      $lbChoices = @()
      foreach ($lb in $lbs.LoadBalancers) {
        $lbChoices += "$($lb.LoadBalancerArn) | $($lb.LoadBalancerName) | $($lb.DNSName)"
      }
      $lbPick = Choose "Select the ALB to use:" $lbChoices
      $lbArn = ($lbPick.Split("|")[0]).Trim()

      $listeners = Invoke-AwsCli "aws elbv2 describe-listeners --region $regionAlb --load-balancer-arn $lbArn --output json" | ConvertFrom-Json
      if (-not $listeners.Listeners) { throw "No listeners found on that ALB." }

      $lisChoices = @()
      foreach ($l in $listeners.Listeners) {
        $lisChoices += "$($l.ListenerArn) | Port $($l.Port) | Protocol $($l.Protocol)"
      }
      $lisPick = Choose "Select the listener to attach the certificate to (usually HTTPS:443):" $lisChoices
      $listenerArn = ($lisPick.Split("|")[0]).Trim()
    }

    $lbInfo = Invoke-AwsCli "aws elbv2 describe-load-balancers --region $regionAlb --load-balancer-arns $lbArn --output json" | ConvertFrom-Json
    $lbDns = $lbInfo.LoadBalancers[0].DNSName
    $lbHz = $lbInfo.LoadBalancers[0].CanonicalHostedZoneId
    $lbIpType = if ($lbInfo.LoadBalancers[0].IpAddressType) { $lbInfo.LoadBalancers[0].IpAddressType } else { "ipv4" }

    if ($WhatIfPreference) {
      Write-Host "`n[WhatIf] Would attach certificate $certArn to ALB listener $listenerArn"
    } else {
      Write-Verbose "Attaching cert to listener $listenerArn"
    Write-Host "`nAttaching certificate to ALB listener..."
      Invoke-AwsCli "aws elbv2 modify-listener --region $regionAlb --listener-arn $listenerArn --certificates `"CertificateArn=$certArn`"" | Out-Null
      Write-Host "ALB listener updated."
    }

    if ($doDns) {
      Write-Host "`n== 4) Route 53: create/update ALIAS records to ALB =="
      $changes = @(
        @{
          Action           = "UPSERT"
          ResourceRecordSet = @{
            Name            = $domain
            Type            = "A"
            AliasTarget     = @{
              HostedZoneId         = $lbHz
              DNSName             = $lbDns
              EvaluateTargetHealth = $false
            }
          }
        },
        @{
          Action           = "UPSERT"
          ResourceRecordSet = @{
            Name            = "www.$domain"
            Type            = "A"
            AliasTarget     = @{
              HostedZoneId         = $lbHz
              DNSName             = $lbDns
              EvaluateTargetHealth = $false
            }
          }
        }
      )
      # Add AAAA records for dual-stack ALBs (IPv6)
      if ($lbIpType -eq "dualstack") {
        $changes += @(
          @{
            Action           = "UPSERT"
            ResourceRecordSet = @{
              Name            = $domain
              Type            = "AAAA"
              AliasTarget     = @{
                HostedZoneId         = $lbHz
                DNSName             = $lbDns
                EvaluateTargetHealth = $false
              }
            }
          },
          @{
            Action           = "UPSERT"
            ResourceRecordSet = @{
              Name            = "www.$domain"
              Type            = "AAAA"
              AliasTarget     = @{
                HostedZoneId         = $lbHz
                DNSName             = $lbDns
                EvaluateTargetHealth = $false
              }
            }
          }
        )
      }

      if ($WhatIfPreference) {
        $recordTypes = if ($lbIpType -eq "dualstack") { "A, AAAA" } else { "A" }
        Write-Host "[WhatIf] Would UPSERT Route 53 records in $hzId :"
        Write-Host "  - $domain ($recordTypes) -> $lbDns"
        Write-Host "  - www.$domain ($recordTypes) -> $lbDns"
      } else {
      $batch = @{ Comment = "Point $domain + www to ALB"; Changes = $changes } | ConvertTo-Json -Depth 20
      $dnsFile = Join-Path $env:TEMP "r53-alias-alb-$([Guid]::NewGuid().ToString('N').Substring(0,8)).json"
      $tempFiles += $dnsFile
      $batch | Out-File -Encoding utf8 $dnsFile

      $dnsUri = Get-FileUriForAws $dnsFile
      $chgId = (Invoke-AwsCli "aws route53 change-resource-record-sets --hosted-zone-id $hzId --change-batch `"$dnsUri`" --query `"ChangeInfo.Id`" --output text").Trim()
      Write-Host "Route 53 change submitted: $chgId"
      Invoke-AwsCli "aws route53 wait resource-record-sets-changed --id $chgId" | Out-Null
      Write-Host "Route 53 change INSYNC."
      }
    }

    if ($WhatIfPreference) {
      Write-Host "`n[WhatIf] DONE. No changes were made. Run without -WhatIf to apply."
    } else {
      Write-Host "`nDONE. Test:"
      Write-Host "  https://$domain"
      Write-Host "  https://www.$domain"
    }
  }
} finally {
  # Clean up temp files
  foreach ($f in $tempFiles) {
    if (Test-Path $f) {
      try { Remove-Item $f -Force -ErrorAction SilentlyContinue } catch { }
    }
  }
}
