param(
    [string]$ApplicationPath = (Join-Path (Split-Path $PSScriptRoot) 'dist\GyeotMemo.exe'),
    [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot) 'test-results')
)
$ErrorActionPreference = 'Stop'
$ApplicationPath = (Resolve-Path -LiteralPath $ApplicationPath).Path
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$dotnet = (Get-Command dotnet -ErrorAction Stop).Source
$sdk = (& $dotnet --list-sdks | Select-Object -Last 1) -replace '\s+\[.*$', ''
$compiler = Join-Path (Split-Path $dotnet) ('sdk\' + $sdk + '\Roslyn\bincore\csc.dll')
$executable = Join-Path $OutputDirectory 'layout-regression.exe'
$report = Join-Path $OutputDirectory 'layout-results.txt'
$arguments = @($compiler,'/nologo','/noconfig','/nostdlib+','/target:winexe',('/out:' + $executable),(Join-Path $PSScriptRoot 'LayoutRegression.cs'))
foreach ($name in @('mscorlib','System','System.Core','System.Xml','System.Xaml')) { $arguments += '/r:' + (Join-Path $framework ($name + '.dll')) }
foreach ($name in @('WindowsBase','PresentationCore','PresentationFramework')) { $arguments += '/r:' + (Join-Path $framework ('WPF\' + $name + '.dll')) }
& $dotnet @arguments
if ($LASTEXITCODE -ne 0) { throw 'Layout regression harness failed to compile.' }
$testProcess = Start-Process -FilePath $executable -ArgumentList @(('"' + $ApplicationPath + '"'),('"' + $report + '"')) -Wait -PassThru -WindowStyle Hidden
Get-Content -LiteralPath $report
if ($testProcess.ExitCode -ne 0) { throw 'Layout regression test failed.' }
