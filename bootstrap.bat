@echo off
setlocal enabledelayedexpansion

rem Downloads the prebuilt WebUI static library and header for Windows.
rem
rem We link WebUI statically, so this fetches webui-2-static.lib rather than the
rem DLL the other bindings use. The header comes from the same archive on
rem purpose: a static link welds the two together, and a webui.h that disagrees
rem with the .lib produces a corrupt build rather than an honest error.
rem
rem   bootstrap.bat                                    (nightly)
rem   set WEBUI_VERSION=2.5.0-beta.3 && bootstrap.bat  (pin a tagged release)
rem
rem Re-running this after a nightly moves will relink the NIF on the next
rem `mix compile` -- the Makefiles depend on the static library, not just on
rem the C source.
rem
rem Linux and macOS use bootstrap.sh.

if "%WEBUI_VERSION%"=="" set WEBUI_VERSION=nightly
set BASE_URL=https://github.com/webui-dev/webui/releases/download/%WEBUI_VERSION%

rem The static library is MSVC-built, so the NIF must be too. Only x64 is
rem published for Windows.
set TARGET=webui-windows-msvc-x64
set CACHE=cache

echo WebUI Elixir Bootstrap
echo * Target:  %TARGET%
echo * Version: %WEBUI_VERSION%

if exist "%CACHE%" rmdir /s /q "%CACHE%"
mkdir "%CACHE%"

echo * Downloading [%TARGET%.zip]...
powershell -NoProfile -Command ^
  "$ErrorActionPreference='Stop'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%BASE_URL%/%TARGET%.zip' -OutFile '%CACHE%\%TARGET%.zip'"
if errorlevel 1 goto :download_failed

echo * Extracting...
powershell -NoProfile -Command ^
  "$ErrorActionPreference='Stop'; Expand-Archive -Path '%CACHE%\%TARGET%.zip' -DestinationPath '%CACHE%' -Force"
if errorlevel 1 goto :extract_failed

rem The release archives are not laid out consistently -- the Windows workflow
rem zips the folder's contents while Linux and macOS zip the folder itself --
rem so search for the files rather than assuming a path.
if not exist "%TARGET%" mkdir "%TARGET%"

powershell -NoProfile -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$lib = Get-ChildItem -Path '%CACHE%' -Filter 'webui-2-static.lib' -Recurse -File | Select-Object -First 1;" ^
  "if (-not $lib) { Write-Error 'webui-2-static.lib not found in %TARGET%.zip'; exit 1 };" ^
  "$hdr = Get-ChildItem -Path '%CACHE%' -Filter 'webui.h' -Recurse -File | Select-Object -First 1;" ^
  "if (-not $hdr) { Write-Error 'webui.h not found in %TARGET%.zip'; exit 1 };" ^
  "Copy-Item $lib.FullName -Destination '%TARGET%\webui-2-static.lib' -Force;" ^
  "Copy-Item $hdr.FullName -Destination '%TARGET%\webui.h' -Force"
if errorlevel 1 goto :copy_failed

rmdir /s /q "%CACHE%"

echo * Installed into [%TARGET%\]
echo Done. Build with: mix compile
exit /b 0

:download_failed
echo Error: failed to download %BASE_URL%/%TARGET%.zip 1>&2
if exist "%CACHE%" rmdir /s /q "%CACHE%"
exit /b 1

:extract_failed
echo Error: failed to extract %TARGET%.zip 1>&2
if exist "%CACHE%" rmdir /s /q "%CACHE%"
exit /b 1

:copy_failed
echo Error: expected files missing from %TARGET%.zip 1>&2
if exist "%CACHE%" rmdir /s /q "%CACHE%"
exit /b 1
