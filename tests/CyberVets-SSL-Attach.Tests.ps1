BeforeAll {
  $scriptPath = Join-Path $PSScriptRoot '..' 'CyberVets-SSL-Attach.ps1'
  $scriptPath = Resolve-Path $scriptPath
}

Describe 'CyberVets-SSL-Attach script' {
  It 'loads without syntax errors' {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath.Path, [ref]$null, [ref]$errs)
    $errs | Should -BeNullOrEmpty
  }

  It 'has expected parameters' {
    $params = (Get-Command $scriptPath.Path -ErrorAction SilentlyContinue).Parameters.Keys
    $params | Should -Contain 'Domain'
    $params | Should -Contain 'Target'
    $params | Should -Contain 'WhatIf'
    $params | Should -Contain 'Verbose'
  }
}

Describe 'CloudFront alias merge logic' {
  # Same logic as in CyberVets-SSL-Attach.ps1
  function Merge-CloudFrontAliases {
    param($ExistingItems, $Domain)
    $existing = @()
    if ($ExistingItems) { $existing = @($ExistingItems) }
    $required = @($Domain, "www.$Domain")
    ($existing + $required) | Select-Object -Unique
  }

  It 'merges root and www into empty aliases' {
    $result = Merge-CloudFrontAliases -ExistingItems $null -Domain 'example.com'
    $result | Should -Contain 'example.com'
    $result | Should -Contain 'www.example.com'
    $result.Count | Should -Be 2
  }

  It 'preserves existing aliases' {
    $existing = @('api.example.com', 'cdn.example.com')
    $result = Merge-CloudFrontAliases -ExistingItems $existing -Domain 'example.com'
    $result | Should -Contain 'example.com'
    $result | Should -Contain 'www.example.com'
    $result | Should -Contain 'api.example.com'
    $result | Should -Contain 'cdn.example.com'
    $result.Count | Should -Be 4
  }

  It 'deduplicates when domain already in aliases' {
    $existing = @('example.com', 'www.example.com')
    $result = Merge-CloudFrontAliases -ExistingItems $existing -Domain 'example.com'
    $result.Count | Should -Be 2
    $result | Should -Contain 'example.com'
    $result | Should -Contain 'www.example.com'
  }
}
