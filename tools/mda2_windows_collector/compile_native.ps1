param()

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.scratch\native'))
$expectedParent = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.scratch'))
if (-not $root.StartsWith($expectedParent + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'native_output_scope_rejected'
}
New-Item -ItemType Directory -Path $root -Force | Out-Null
$source = Join-Path $PSScriptRoot 'native\WindowsActivityCollector.cs'
$output = Join-Path $root 'WindowsActivityCollector.exe'
$compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'csc_unavailable' }
& $compiler /nologo /checked+ /warnaserror+ /target:exe /optimize+ /out:$output /reference:System.dll /reference:System.Core.dll /reference:System.Windows.Forms.dll $source
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output -PathType Leaf)) { throw 'native_compile_failed' }
$item = Get-Item -LiteralPath $output
$stream = [IO.File]::OpenRead($output)
try {
  $sha = [BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
} finally { $stream.Dispose() }
[pscustomobject]@{ output = $item.FullName; bytes = $item.Length; sha256 = $sha } | ConvertTo-Json -Compress
