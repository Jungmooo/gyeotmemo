param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference = 'Stop'
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$wpf = Join-Path $framework 'WPF'
$dotnet = (Get-Command dotnet -ErrorAction Stop).Source
$sdk = (& $dotnet --list-sdks | Select-Object -Last 1) -replace '\s+\[.*$', ''
$sdkRoot = Join-Path (Split-Path $dotnet) ('sdk\' + $sdk)
$compiler = Join-Path $sdkRoot 'Roslyn\bincore\csc.dll'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'A .NET SDK with the Roslyn compiler is required to build.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$buildArgs = @($compiler, '/nologo', '/noconfig', '/nostdlib+', '/target:winexe', '/platform:anycpu', '/optimize+', '/langversion:latest', '/utf8output', ('/out:' + (Join-Path $OutputDirectory 'GyeotMemo.exe')), ('/win32icon:' + (Join-Path $PSScriptRoot 'app.ico')), ('/win32manifest:' + (Join-Path $PSScriptRoot 'app.manifest')), ('/resource:' + (Join-Path $PSScriptRoot 'MainWindow.xaml') + ',MainWindow.xaml'), ('/resource:' + (Join-Path $PSScriptRoot 'app.ico') + ',app.ico'))
foreach ($assembly in @('mscorlib.dll','System.dll','System.Core.dll','System.Xml.dll','System.Xaml.dll','System.Web.Extensions.dll','System.Windows.Forms.dll','System.Drawing.dll')) { $buildArgs += '/reference:' + (Join-Path $framework $assembly) }
foreach ($assembly in @('WindowsBase.dll','PresentationCore.dll','PresentationFramework.dll')) { $buildArgs += '/reference:' + (Join-Path $wpf $assembly) }
foreach ($source in @('Models.cs','Program.cs','SelfTests.cs','AssemblyInfo.cs')) { $buildArgs += Join-Path $PSScriptRoot $source }
& $dotnet @buildArgs
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'GyeotMemo.exe.config') -Destination $OutputDirectory -Force
Write-Output (Join-Path $OutputDirectory 'GyeotMemo.exe')
