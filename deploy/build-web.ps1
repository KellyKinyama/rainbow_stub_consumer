#!/usr/bin/env pwsh
# Build the chatstub Flutter web app for production and package it for
# transfer to the server (Apache docroot, e.g. /var/www/html).
#
#   pwsh deploy/build-web.ps1
#
# Produces: deploy/chatstub-web.tar.gz
$ErrorActionPreference = 'Stop'

# Project root is the parent of this deploy/ folder.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host '==> flutter build web (release, CanvasKit bundled locally)'
# --no-web-resources-cdn bundles CanvasKit/engine instead of fetching from
# the gstatic CDN (works behind restricted networks).
flutter build web --release --base-href / --no-web-resources-cdn

$webDir  = Join-Path $root 'build\web'
$tarball = Join-Path $PSScriptRoot 'chatstub-web.tar.gz'
if (Test-Path $tarball) { Remove-Item $tarball -Force }

Write-Host "==> packaging $webDir -> $tarball"
tar -czf $tarball -C $webDir .

Write-Host ''
Write-Host "==> done: $tarball"
Write-Host 'Next: scp this tarball + deploy/deploy.sh to the server, then run deploy.sh there.'
