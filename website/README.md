# CyberVets Solutions Website

Static site for CyberVets Solutions. Deploy to **S3** (optionally **CloudFront**) for lowest-cost AWS hosting.

## Quick deploy (S3 only)

```powershell
.\deploy-website.ps1 -BucketName your-website-bucket -Region us-east-1 -MakePublic
```

**Note:** In S3 console, turn off "Block all public access" for the bucket so the public read policy can take effect. Your site will be at:

`http://your-website-bucket.s3-website-us-east-1.amazonaws.com`

## Add HTTPS + custom domain (CloudFront)

1. Create a CloudFront distribution with origin = your S3 website endpoint (`your-bucket.s3-website-region.amazonaws.com`)
2. Request an ACM certificate in `us-east-1` for your domain
3. Run **CyberVets-SSL-Attach.ps1** from the parent folder:

   ```powershell
   .\CyberVets-SSL-Attach.ps1 -Domain cybervetssolutions.com -Target CloudFront -WhatIf
   ```

## Structure

```
website/
├── index.html      # Home
├── 404.html        # Error page
├── css/style.css
├── deploy-website.ps1
└── README.md
```
