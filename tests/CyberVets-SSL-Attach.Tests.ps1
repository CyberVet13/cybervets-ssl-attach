$scriptPath = (Resolve-Path (Join-Path (Join-Path $PSScriptRoot '..') 'CyberVets-SSL-Attach.ps1')).Path

# Same logic as CyberVets-SSL-Attach.ps1
function Merge-CloudFrontAliases {
  param($ExistingItems, $Domain)
  $existing = @()
  if ($ExistingItems) { $existing = @($ExistingItems) }
  $required = @($Domain, "www.$Domain")
  @(($existing + $required) | Select-Object -Unique)
}

Describe 'CyberVets-SSL-Attach script' {
  It 'loads without syntax errors' {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) { throw "Parse errors: $($errs -join '; ')" }
  }

  It 'has expected parameters' {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $params = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
    foreach ($p in @('Domain', 'Target', 'CertificateArn')) {
      if ($params -notcontains $p) { throw "Missing parameter: $p" }
    }
  }
}

Describe 'CloudFront alias merge logic' {
  It 'merges root and www into empty aliases' {
    $result = @(Merge-CloudFrontAliases -ExistingItems $null -Domain 'example.com')
    if ($result -notcontains 'example.com') { throw "Missing example.com" }
    if ($result -notcontains 'www.example.com') { throw "Missing www.example.com" }
    if ($result.Count -ne 2) { throw "Expected Count 2, got $($result.Count)" }
  }

  It 'preserves existing aliases' {
    $existing = @('api.example.com', 'cdn.example.com')
    $result = @(Merge-CloudFrontAliases -ExistingItems $existing -Domain 'example.com')
    foreach ($x in @('example.com', 'www.example.com', 'api.example.com', 'cdn.example.com')) {
      if ($result -notcontains $x) { throw "Missing: $x" }
    }
    if ($result.Count -ne 4) { throw "Expected Count 4, got $($result.Count)" }
  }

  It 'deduplicates when domain already in aliases' {
    $existing = @('example.com', 'www.example.com')
    $result = @(Merge-CloudFrontAliases -ExistingItems $existing -Domain 'example.com')
    if ($result.Count -ne 2) { throw "Expected Count 2, got $($result.Count)" }
    if ($result -notcontains 'example.com') { throw "Missing example.com" }
    if ($result -notcontains 'www.example.com') { throw "Missing www.example.com" }
  }
}
