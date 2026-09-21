param([Parameter(Mandatory=$true)][string]$AcquisitionDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
python (Join-Path $PSScriptRoot 'portable_region.py') --acquisition-directory $AcquisitionDirectory --output-directory $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw 'Portable terrain region reproduction failed' }
