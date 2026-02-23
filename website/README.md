# CyberVets Solutions Website

Static site for CyberVets Solutions. Deploy to **S3** (optionally **CloudFront**) for lowest-cost AWS hosting.

## Option A: CloudFormation (S3 + CloudFront, private bucket)

```powershell
# Deploy stack (bucket name must be globally unique)
aws cloudformation deploy --template-file cloudformation-website.yaml --stack-name cybervets-website --parameter-overrides BucketName=cybervets-website-YOUR-SUFFIX

# Upload site files
$bucket = (aws cloudformation describe-stacks --stack-name cybervets-website --query "Stacks[0].Outputs[?OutputKey=='BucketName'].OutputValue" --output text)
aws s3 sync . "s3://$bucket" --exclude "*.ps1" --exclude "*.md" --exclude "*.yaml"
```

Then add HTTPS + custom domain with **CyberVets-SSL-Attach.ps1** from the parent folder.

## Option B: S3 only (simpler, HTTP)

```powershell
.\deploy-website.ps1 -BucketName your-website-bucket -Region us-east-1 -MakePublic
```

Site URL: `http://your-website-bucket.s3-website-us-east-1.amazonaws.com`

## Add HTTPS + custom domain (CloudFront)

1. Create a CloudFront distribution (or use Option A)
2. Request an ACM certificate in `us-east-1` for your domain
3. Run **CyberVets-SSL-Attach.ps1** from the parent folder:

   ```powershell
   .\CyberVets-SSL-Attach.ps1 -Domain cybervetssolutions.com -Target CloudFront -WhatIf
   ```

## Structure

```
website/
├── index.html
├── 404.html
├── css/style.css
├── cloudformation-website.yaml   # S3 + CloudFront stack
├── deploy-website.ps1            # S3-only deploy
└── README.md
```
