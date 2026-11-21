@echo off
rem Local PulseShader build for machines without CMake.
rem
rem The official build.bat needs CMake. This script produces the same two
rem artifacts with the Visual Studio x86 tools directly:
rem   dist/left4dead2/bin/game_shader_generic_pulse.dll
rem   dist/left4dead2/shaders/fxc/pulse_*.vcs
rem
rem Keep the DLL and all .vcs files together: the DLL's combo indices come from
rem the generated .inc files, so mixing old and new files resolves shaders to the
rem wrong compiled variants.

setlocal EnableExtensions
cd /d "%~dp0"
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"

rem --dll-only reuses build/inc and the existing .vcs, for iterating on the C++
rem shader code after one full build.
set "DLL_ONLY=0"
if /I "%~1"=="--dll-only" set "DLL_ONLY=1"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: Visual Studio Installer vswhere.exe was not found.
    exit /b 1
)

for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSROOT=%%I"
if not defined VSROOT (
    echo ERROR: Visual Studio C++ x86/x64 tools were not found.
    exit /b 1
)

set "VCVARS=%VSROOT%\VC\Auxiliary\Build\vcvarsamd64_x86.bat"
if not exist "%VCVARS%" set "VCVARS=%VSROOT%\VC\Auxiliary\Build\vcvarsall.bat"
if not exist "%VCVARS%" (
    echo ERROR: no vcvars script found under %VSROOT%.
    exit /b 1
)

echo === PulseShader local build ===
echo Root:   %ROOT%
echo Visual Studio: %VSROOT%

echo.
echo [1/3] Building shader combo headers and .vcs archives...
if "%DLL_ONLY%"=="1" goto skip_shaders
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\tools\build_shaders.ps1"
if errorlevel 1 (
    echo ERROR: shader build failed.
    exit /b 1
)
goto shaders_done
:skip_shaders
echo Skipping shader build: --dll-only.

:shaders_done
echo.
echo [2/3] Compiling game_shader_generic_pulse.dll (x86)...
call "%VCVARS%" >nul
if errorlevel 1 (
    echo ERROR: vcvars failed.
    exit /b 1
)

set "SWARM=%ROOT%\sdk\alienswarm-sdk\src"
set "DIST=%ROOT%\dist\left4dead2\bin"
if not exist "%DIST%" mkdir "%DIST%"

cl /nologo /LD /MT /EHsc /W3 /std:c++14 ^
    /D WIN32 /D _WIN32 /D COMPILER_MSVC /D COMPILER_MSVC32 ^
    /I "%ROOT%\src\sdk_override" ^
    /I "%SWARM%\public" ^
    /I "%SWARM%\public\tier0" ^
    /I "%SWARM%\public\tier1" ^
    /I "%SWARM%\common" ^
    /I "%SWARM%\materialsystem" ^
    /I "%SWARM%\public\materialsystem" ^
    /I "%SWARM%\materialsystem\stdshaders" ^
    /I "%SWARM%\materialsystem\shaderlib" ^
    /I "%ROOT%\build\inc" ^
    /I "%ROOT%\src\shaders" ^
    /I "%ROOT%\src" ^
    /Fe:"%DIST%\game_shader_generic_pulse.dll" ^
    "%ROOT%\src\shaders\pbr_dx9.cpp" ^
    "%ROOT%\src\shaders\girlsfrontline_dx9.cpp" ^
    "%ROOT%\src\shaders\pulse_shader_convars.cpp" ^
    "%ROOT%\src\shaders\npr_dx9.cpp" ^
    "%ROOT%\src\shaders\umamusume_dx9.cpp" ^
    "%ROOT%\src\shaders\tooneye_dx9.cpp" ^
    "%ROOT%\src\basevsshader_impl.cpp" ^
    "%ROOT%\src\pulse_shaderdll.cpp" ^
    "%ROOT%\src\log.cpp" ^
    "%SWARM%\materialsystem\shaderlib\BaseShader.cpp" ^
    /link ^
    /IMPLIB:"%ROOT%\build\game_shader_generic_pulse.lib" ^
    "%SWARM%\lib\public\tier0.lib" ^
    "%SWARM%\lib\public\tier1.lib" ^
    "%SWARM%\lib\public\mathlib.lib" ^
    "%SWARM%\lib\public\vstdlib.lib" ^
    "%SWARM%\lib\public\interfaces.lib" ^
    legacy_stdio_definitions.lib
if errorlevel 1 (
    echo ERROR: DLL compile/link failed.
    exit /b 1
)

rem Source discovers game_shader_generic_<name> without an extension; the
rem extensionless file must exist next to the DLL.
if not exist "%DIST%\game_shader_generic_pulse" type nul > "%DIST%\game_shader_generic_pulse"

echo.
echo [3/3] Verifying outputs...
if not exist "%DIST%\game_shader_generic_pulse.dll" (
    echo ERROR: game_shader_generic_pulse.dll was not produced.
    exit /b 1
)
for %%P in (pulse_pbr pulse_girlsfrontline pulse_npr pulse_umamusume pulse_tooneye) do (
    for %%S in (vs30 ps30) do (
        if not exist "%ROOT%\dist\left4dead2\shaders\fxc\%%P_%%S.vcs" (
            echo ERROR: missing %%P_%%S.vcs
            exit /b 1
        )
    )
)

echo.
echo BUILD OK
echo   %DIST%\game_shader_generic_pulse.dll
echo   %DIST%\game_shader_generic_pulse
echo   %ROOT%\dist\left4dead2\shaders\fxc\pulse_*.vcs
endlocal
