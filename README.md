# PulseShader

<p align="center">
  <img alt="Source Engine branch: L4D2" src="https://img.shields.io/badge/SOURCE_ENGINE_BRANCH-L4D2-0078D4?style=for-the-badge">
  <img alt="DirectX: 9" src="https://img.shields.io/badge/DIRECTX-9-107C10?style=for-the-badge">
</p>

Custom PBR and NPR model shaders for Left 4 Dead 2. PulseShader installs as a
`game_shader_generic_*` module without replacing Valve files. It supports models
and ps_3_0 only.

> [!NOTE]
> This is an unofficial fork of
> [ToppiOfficial/PulseShader-Left4Dead](https://github.com/ToppiOfficial/PulseShader-Left4Dead).
> It keeps the upstream shaders and adds the survivor-glow / `$casthairshadow`
> stencil fix plus a build script for machines without CMake. See
> [Fork changes](#fork-changes).

- **PulsePBR** - OpenPBR Surface for realistic models.
- **PulseGirlsFrontline** - PulsePBR with optional lighting ramps, face shading,
  hair shadows, stockings, and outlines.
- **PulseNPR** - cel shading with outlines and matcaps.
- **PulseUmamusume** - character shading with authored lit and shadow masks.
- **PulseToonEye** - gaze-tracked toon eyes with catchlights and eyelid overlays.

> [!WARNING]
> Valve does not guarantee that third-party DLLs are VAC-safe. Use this mod on
> secure servers at your own risk, and use `-insecure` while testing.

## Fork changes

- **`$casthairshadow` works again.** Upstream 0.10.0 leaves the stencil hair
  shadow enabled; on L4D2 the pass can overwrite the engine's survivor-glow
  stencil state and make the glow fill the whole silhouette. This fork saves and
  restores that state around the hair-shadow passes instead, so the shadow and
  the glow both work. See
  [Survivor glow compatibility](#survivor-glow-compatibility) and
  [`PULSE_GLOWFIX.md`](PULSE_GLOWFIX.md) (Chinese technical note).
- **Face SDF edge blending.** `$face` now feathers the region mask through the
  mask's mip chain (`$facemapedgefeather`, default `48` face-map texels, clamped
  `0`–`128`, `0` keeps the authored hard edge), so the SDF shading dissolves into
  the skin at the mask edge instead of ending on a visible cut. That lets
  `$facemaptexturetransform` go back to aligning the field on the face rather
  than hiding the seam.
- **Local build without CMake.** [`build_local.bat`](build_local.bat) produces the
  DLL and the ten `.vcs` archives with the Visual Studio x86 tools directly. Its
  output is the same layout as the official CMake build.
- **No required VMT changes.** Existing materials work unchanged; the face
  feather defaults to a useful value and is only worth setting per material if
  the map's mask edge needs more or less softening. No parameter was removed or
  renamed.

## Install

Download the latest release zip (`PulseShader-0.10.0-*.zip`, built and tested
against the retail L4D2 build), or use your own `dist/` build output, then copy
its contents into your Left 4 Dead 2 folder:

```text
<steam>/steamapps/common/Left 4 Dead 2/
  left4dead2/bin/game_shader_generic_pulse.dll
  left4dead2/bin/game_shader_generic_pulse        (extensionless, required)
  left4dead2/shaders/fxc/pulse_*.vcs
```

Use `left4dead2/bin/` inside the `left4dead2` folder, not the `bin/` beside the
game executable. Both `game_shader_generic_pulse` files are required. The DLL and
all ten `.vcs` files are one unit; do not mix them with another build's files.

On a clean install, these are all new files. If Windows asks to overwrite
anything, continue only if you are updating an existing PulseShader install.
Otherwise, stop and check the existing file first.

## Uninstall

Delete only these files:

```text
left4dead2/bin/game_shader_generic_pulse.dll
left4dead2/bin/game_shader_generic_pulse
left4dead2/shaders/fxc/pulse_*.vcs
```

Steam's **Verify integrity of game files** does not remove extra mod files, and
reinstalling without deleting the game folder may leave them behind. Delete them
manually. You can run Verify afterward to confirm that Valve's files are intact.

Materials still using a `Pulse*` shader will show the error material until they
are changed back to a stock shader.

## Survivor glow compatibility

L4D2 renders the blue teammate glow and the yellow Boomer-bile glow with an
interior stencil mask written while the entity is drawn, plus a halo that is
composited only outside that mask. A material shader that calls
`IShaderDynamicAPI::SetStencilState` during the same draw and then disables
stencil replaces the engine's state for the meshes that follow. Those meshes stop
writing the mask, the halo is no longer cut out over the body, and the whole
silhouette fills solid with the glow colour.

`PulseGirlsFrontline`'s `$face` / `$casthairshadow` hair shadow needs stencil, so
the pass cannot simply be dropped. This fork instead:

1. records the engine's last `ShaderStencilState_t` by replacing the shader API's
   `SetStencilState` entry point (virtual-table slot 170, `0x2A8`) with a
   forwarder on the first draw;
2. lets its own calls bypass the recorder, so the recorded state is always the
   engine's;
3. restores that state after each hair-shadow pass instead of disabling stencil;
4. skips the pass entirely when no engine state has been captured yet, which
   keeps the glow correct even if the recorder is unavailable.

The hair shadow uses stencil bit `0x04`. L4D2's halo test mask is `0xFA`, which
excludes that bit, so the shadow and the glow never touch each other's bits.

Verified in game on the retail L4D2 build (2026-11-21): occluded teammates show
the thin outline instead of a filled silhouette, for both the blue and the yellow
glow, and the hair shadow is visible again.

## How it works

Source loads `game_shader_generic*` modules from `left4dead2/bin`. The
extensionless file is the name Source discovers; it appends `.dll` and loads
`ShaderDLL004`. PulseShader does not inject code, patch the executable, replace
Valve files, or change gameplay.

This fork adds one runtime state recorder for the stencil fix described above: it
swaps a single entry in the shader API object's virtual table for a forwarder that
remembers the engine's last stencil state, and the hair-shadow pass restores it
when it is done. That is a memory-level hook, not a file replacement, and it only
keeps stencil state consistent while `PulseGirlsFrontline` draws its hair shadow.
The upstream project's contribution rules do not allow engine hooks, so this
change is fork-specific and is not proposed upstream as-is.

All shader and compiled file names use a `pulse_` prefix, so PulseShader can be
installed alongside other shader mods, including NekoShaders. If Valve closes
this interface or rejects third-party shader modules, this project will be
archived rather than switching to injection or patched binaries.

## Build

### CMake build (upstream)

Clone the repository with its pinned SDK submodules:

```text
git clone --recurse-submodules https://github.com/ToppiOfficial/PulseShader-Left4Dead.git
```

For an existing clone, run `git submodule update --init`. Install Visual Studio
C++ x86 build tools, CMake, the Windows SDK, Python 3, and Git for Windows, then
run `build.bat`. Distributable files are written to `dist/`. The Valve HLSL
headers in `sdk/valve-stdshaders/` are already vendored.

### Local build without CMake

[`build_local.bat`](build_local.bat) mirrors the CMake build with the Visual
Studio x86 compiler directly. It needs the Visual Studio C++ x86 build tools, the
Windows SDK (`fxc.exe`), Python 3, and Git for Windows' Perl:

```bat
build_local.bat
```

Outputs, which must be installed together:

```text
dist/left4dead2/bin/game_shader_generic_pulse.dll
dist/left4dead2/bin/game_shader_generic_pulse
dist/left4dead2/shaders/fxc/pulse_*.vcs
```

`build_local.bat --dll-only` reuses the generated `build/inc` headers and the
existing `.vcs` files after one full build, which is only useful when the change
is on the C++ side. Any HLSL or combo change needs a full run: the DLL's combo
indices come from the generated `.inc` headers, so the DLL and the `.vcs`
archives are a single unit.

Shader source layout and variant instructions are in
[`src/shaders/README.md`](src/shaders/README.md). Each shader's VMT parameters
are declared at the top of its `src/shaders/*_dx9.cpp` file.

## Troubleshooting stencil and glow

Start with `-insecure -pulse_log`. The shader writes `%TEMP%\pulse_shader.log`
and records the stencil path on the first frames:

```text
stencil: hook installed on slot 170
stencil: engine state captured
stencil: engine state enable=... ref=... test=... write=...
hairshadow: DRAWER running, strength=...
hairshadow: MARKER running
```

If the log reports `stencil: hook unavailable` or
`hairshadow: no engine stencil state captured yet, shadow pass skipped`, the
hair-shadow pass is being skipped on purpose and the glow is still correct.
Report it together with the log and a screenshot.

## License

This project derives from thexa4/source-pbr and Valve's Source SDK. It is
governed by the Source 1 SDK License: **free distribution only, no commercial
use**. See [`NOTICE`](NOTICE) for provenance and license details.

## 中文说明

这是 [ToppiOfficial/PulseShader-Left4Dead](https://github.com/ToppiOfficial/PulseShader-Left4Dead)
的非官方分支，保留上游全部着色器，只补上了 `PulseGirlsFrontline` 的光晕/头发阴影修复。

- **修复内容**：L4D2 队友蓝色光晕和 Boomer 黄色胆汁光晕不会再「整条剪影被实心填满」；
  `$casthairshadow` 头发阴影同时恢复。原理是记录并恢复引擎的 stencil 状态，
  而不是像上游 0.10.0 那样在绘制中直接改掉/关闭 stencil 状态。细节见 [`PULSE_GLOWFIX.md`](PULSE_GLOWFIX.md)。
- **面部 SDF 边缘融合**：`$face` 的遮罩边缘改为按贴图 mip 链羽化
  （`$facemapedgefeather`，单位 face map texel，默认 48，范围 0–128，0 恢复原来的硬边；
  2048 宽的图需约翻倍，如 96），SDF 光影在遮罩边界平滑淡入皮肤，
  不再出现一条硬边色阶；`$facemaptexturetransform` 回到调整 SDF 区域的本职，不必再用来掩盖接缝。
  现有 VMT 无需改动，默认值即生效。
- **安装**：下载 Release 里最新的 `PulseShader-0.10.0-*.zip`，解压到
  `steamapps\common\Left 4 Dead 2\`（压缩包内是 `left4dead2\` 结构）。
  DLL 和 10 个 `.vcs` 必须整套替换，不能与别的版本混用。
- **自行构建**：装好 VS x86 工具、Windows SDK、Python 3、Git Perl 后运行
  [`build_local.bat`](build_local.bat)；只改 C++ 可用 `--dll-only`。
- **注意**：本分支在运行时替换了 shader API 的一个虚表项来保存/恢复 stencil 状态，
  属于内存级钩子（不改磁盘上的 Valve 文件、不注入、不改玩法）。上游 CONTRIBUTING
  不允许引擎钩子，因此请把本分支当作独立分支使用，不要按原样向上游提 PR。
  VAC 风险提示同上，测试请加 `-insecure`。
