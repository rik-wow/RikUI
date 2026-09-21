param(
    [Parameter(Mandatory = $true)][string]$AcquisitionDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'portable_bake.py') --acquisition-directory $AcquisitionDirectory --output-directory $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw 'External terrain bake failed; inspect the named output log.' }
