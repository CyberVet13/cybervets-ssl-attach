# CyberVets SSL Attach Helper

PowerShell script for attaching ACM SSL/TLS certificates to **CloudFront** or **Application Load Balancers (ALB)**, with optional Route 53 DNS updates. Part of the CyberVets Solutions AWS toolkit.

**GitHub:** [https://github.com/CyberVet13/cybervets-ssl-attach](https://github.com/CyberVet13/cybervets-ssl-attach)

## Prerequisites

- **AWS CLI** installed and configured (`aws configure`)
- **PowerShell** 5.1 or later
- IAM permissions: ACM (read), CloudFront or ELBv2 (read/write), Route 53 (read/write) as needed

The script runs pre-flight checks: it verifies AWS CLI is installed and credentials are valid before proceeding.

## Quick Start

```powershell
.\CyberVets-SSL-Attach.ps1
```

Interactive mode will prompt for domain, target (CloudFront/ALB), and whether to update Route 53.

## Usage Modes

### Interactive (default)

```powershell
.\CyberVets-SSL-Attach.ps1
```

### Non-interactive (parameters)

```powershell
# CloudFront with specific distribution
.\CyberVets-SSL-Attach.ps1 -Domain example.com -Target CloudFront -DistributionId E1234ABCD -UpdateDns

# ALB with specific listener
.\CyberVets-SSL-Attach.ps1 -Domain example.com -Target ALB -Region us-east-1 -LoadBalancerArn arn:aws:elasticloadbalancing:... -ListenerArn arn:aws:elasticloadbalancing:... -UpdateDns

# With specific certificate ARN (skips discovery)
.\CyberVets-SSL-Attach.ps1 -Domain example.com -Target CloudFront -CertificateArn arn:aws:acm:us-east-1:123456789012:certificate/abc-123 -DistributionId E1234ABCD -UpdateDns
```

### Dry-run (WhatIf)

```powershell
.\CyberVets-SSL-Attach.ps1 -Domain example.com -Target CloudFront -UpdateDns -WhatIf
```

Shows planned changes without applying them.

## Parameters

| Parameter | Description |
|-----------|-------------|
| `-Domain` | Base domain (e.g. cybervetssolutions.com) |
| `-Target` | `CloudFront` or `ALB` |
| `-Region` | AWS region for ALB (cert must be in same region) |
| `-UpdateDns` | Create/update Route 53 ALIAS records |
| `-DistributionId` | CloudFront distribution ID (skips picker) |
| `-LoadBalancerArn` | ALB ARN (use with `-ListenerArn`) |
| `-ListenerArn` | ALB listener ARN (use with `-LoadBalancerArn`) |
| `-CertificateArn` | ACM certificate ARN (skips auto-discovery) |
| `-WhatIf` | Dry-run; no changes made |
| `-Verbose` | Show detailed progress |

## Behavior

- **ACM region**: CloudFront requires certs in `us-east-1`; ALB requires certs in the same region as the ALB.
- **Certificate selection**: Prefers exact domain match, falls back to wildcard; picks newest by expiry when multiple match.
- **CloudFront**: SNI-only, TLSv1.2_2021, redirect-to-https on all cache behaviors.
- **Route 53**: UPSERTs ALIAS records for root and www. CloudFront always gets A + AAAA (inherently dual-stack). ALB gets A always; AAAA only when the ALB is dual-stack.

## Testing

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
Invoke-Pester -Path ./tests
```

For detailed output (Pester 5+): `Invoke-Pester -Path ./tests -Output Detailed`

## Help

```powershell
Get-Help .\CyberVets-SSL-Attach.ps1 -Full
```
