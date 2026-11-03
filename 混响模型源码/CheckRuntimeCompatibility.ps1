param([string]$RuntimeRoot='C:\Program Files\MATLAB\MATLAB Runtime\R2025b')
$ErrorActionPreference='Stop'
$packageRoot=$PSScriptRoot
$deps=(Get-Content -LiteralPath (Join-Path $packageRoot 'buildresult.json') -Raw|ConvertFrom-Json).RuntimeDependencies
$versionFile=Join-Path $RuntimeRoot 'VersionInfo.xml'
$version=$null
if(Test-Path -LiteralPath $versionFile){[xml]$version=Get-Content -LiteralPath $versionFile -Raw}
$products=Join-Path $RuntimeRoot 'appdata\products'
$rows=@($deps|ForEach-Object{
    $pattern=$_.DisplayName+' 25.2 *.xml'
    $found=@(Get-ChildItem -LiteralPath $products -Filter $pattern -File -ErrorAction SilentlyContinue)
    [pscustomobject]@{ID=$_.ID;Required=$_.DisplayName;InstalledManifestFound=($found.Count-gt0);ManifestPaths=@($found.FullName)}
})
$registryRoot=(Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\MathWorks\MATLAB Runtime\25.2' -ErrorAction SilentlyContinue).MATLABROOT
$report=[ordered]@{
    Status=if($version-and$version.MathWorks_version_info.release-eq'R2025b'-and@($rows|Where-Object{-not $_.InstalledManifestFound}).Count-eq0){'PASS_INSTALLATION_MANIFEST_CHECK'}else{'HOLD_INSTALLATION_COMPONENTS'}
    RuntimeRoot=$RuntimeRoot
    RegistryRuntimeRoot=$registryRoot
    RuntimeVersion=if($version){$version.MathWorks_version_info.version}else{$null}
    RuntimeRelease=if($version){$version.MathWorks_version_info.release}else{$null}
    Dependencies=$rows
    EXESHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $packageRoot 'ZSDXReverb.exe')).Hash
    Scope='Read-only installation check. Actual EXE execution is a separate gate.'
}
$report|ConvertTo-Json -Depth 6
