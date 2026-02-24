# deploy-website.ps1 tests
$scriptPath = if ($env:SCRIPT_PATH) {
  $env:SCRIPT_PATH
} elseif ($env:GITHUB_WORKSPACE) {
  Join-Path $env:GITHUB_WORKSPACE 'website/deploy-website.ps1'
} else {
  Join-Path (Split-Path $PSScriptRoot -Parent) 'website/deploy-website.ps1'
}
$scriptPath = [System.IO.Path]::GetFullPath($scriptPath)
if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Script not found: $scriptPath" }

Describe 'deploy-website.ps1' {
  It 'loads without syntax errors' {
    $errs = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errs)
    if ($null -ne $errs -and @($errs).Count -gt 0) { throw "Parse errors: $($errs -join '; ')" }
  }

  It 'has expected parameters' {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)
    $params = $ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }
    foreach ($p in @('BucketName', 'Region', 'WhatIf', 'MakePublic')) {
      if ($params -notcontains $p) { throw "Missing parameter: $p" }
    }
  }
}
