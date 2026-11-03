$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$exe = Join-Path $root 'ZSDXReverb.exe'
$template = Join-Path $root 'ParanConfigToZS.json'
$runDir = Join-Path $root 'work\cmd_run'
$outputDir = Join-Path $runDir 'output'
$tempDir = Join-Path $runDir 'temp'
$runJson = Join-Path $runDir 'case_runtime.json'
New-Item -ItemType Directory -Force -Path $runDir,$outputDir,$tempDir | Out-Null
$cfg = Get-Content -Raw -Encoding UTF8 -LiteralPath $template | ConvertFrom-Json
$cfg.File.outputPath = ($outputDir -replace '\\','/')
$cfg.Runtime.TempWorkDir = ($tempDir -replace '\\','/')
$cfg.Environment.sspPath = ((Join-Path $root 'env\deep_sea_ssp_0_2000m.txt') -replace '\\','/')
$jsonText = $cfg | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($runJson,$jsonText,[Text.UTF8Encoding]::new($false))
& $exe $runJson
exit $LASTEXITCODE
