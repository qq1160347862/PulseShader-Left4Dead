# PulseGirlsFrontline 光晕修复说明（本仓库分支）

> 本文件对应本仓库的非官方分支。上游 0.10.0 的 stencil 头发阴影会直接改掉并关闭
> 引擎的 stencil 状态，L4D2 的幸存者光晕因此可能被填满；本分支改为保存/恢复引擎
> stencil 状态，两者都保留。上游 CONTRIBUTING 不允许引擎钩子，因此这是分支专用实现，
> 不要按原样向上游提 PR。

## 问题

使用 `PulseGirlsFrontline` 时，队友在墙后/不可见时的蓝色轮廓光晕（以及被 Boomer 喷胆汁后的黄色轮廓光晕）会变成**整个身体剪影被实心色块填满**，而不是只在身体外圈显示一圈细轮廓。

## 原因

L4D2 的幸存者光晕在绘制实体时，会把“光晕内部遮罩”写进 stencil buffer，之后 halo 只在遮罩外的像素叠加。

`PulseGirlsFrontline` 的 `$face` / `$casthairshadow` 头发阴影功能会在**同一次实体绘制中**调用 `IShaderDynamicAPI::SetStencilState`，并且在每个 pass 结束时把 stencil 关掉。这会覆盖/禁用引擎为当前实体设置的光晕 stencil 状态；后续绘制的身体、衣服等 mesh 不再写内部遮罩，halo 失去裁剪，于是整身变成实心光晕色。

## 修复（当前版本：保存/恢复引擎状态）

不再“用完就关”，而是**把引擎上一次设置的 stencil 状态原样恢复**：

- 第一次绘制时，在 shader API 的 vtable 槽 170（`SetStencilState`，偏移 `0x2A8`）上装一个记录钩子。引擎自己的调用都会经过这里（`materialsystem.dll` 的转发桩是 `mov eax,[g_pShaderAPI]; mov eax,[eax+0x2A8]; jmp eax`），每次调用都会把完整的 32 字节 `ShaderStencilState_t` 记下来。
- 我们的 stencil pass 用保存的原始函数指针直接调用原函数，不经过钩子，所以记录里永远只有引擎的状态。
- 每个头发阴影 pass 开始时快照这份状态，`Draw()` 结束后原样写回。pass 之外的任何绘制都看不到我们的改动。
- 如果还没捕获到引擎状态（最初几帧，或钩子装不上），该 pass 直接 `Draw(false)` 跳过：光晕保持修复后的样子，头发阴影暂时不出现，**不会**退回“关闭 stencil”。
- 私有 stencil 位是 `0x04`：L4D2 halo 的 stencil 测试掩码是 `0xFA`（包含上游用过的 `0x40`、不包含 `0x04`），两者互不干扰。

`$face` 面部阴影/鼻子高光、`$outlinewidth` 描边、PBR 光照等都不受影响；`$casthairshadow`、`$hairshadowoffset`、`$hairshadowstrength` 重新生效。

## 与上游 0.10.0 的差异

- 上游 0.10.0 打开着 stencil 头发阴影，但每个 pass 结束调用 `PulseDisableStencil`
  关闭 stencil：在 L4D2 上会覆盖引擎为光晕设置的内部遮罩状态，表现为整条剪影被填满。
- 本分支改成每个 pass 结束把引擎上一次设置的状态原样写回：光晕和头发阴影同时正常。
- 代价是运行时替换 shader API 虚表中的一个函数指针（内存级钩子），不改磁盘上的 Valve 文件、不注入、不改玩法；如果钩子不可用，会自动回到“光晕正常、阴影跳过”。

## 产物

从源码构建后（`build_local.bat`）输出到：

```text
dist/left4dead2/bin/game_shader_generic_pulse.dll
dist/left4dead2/bin/game_shader_generic_pulse        (空文件)
dist/left4dead2/shaders/fxc/pulse_*.vcs              (10 个)
dist/PulseShader-0.10.0-hairshadow.zip               (上述文件的压缩包)
```

**必须整套替换**。DLL 的 combo 索引来自本版本生成的 `.inc`，不能与别的版本的 `.vcs` 或 DLL 混用。

## 安装 / 测试

1. 关闭游戏。
2. 先备份 `left4dead2\bin\game_shader_generic_pulse*` 和 `left4dead2\shaders\fxc\pulse_*.vcs`。
3. 把 `dist\left4dead2\*` 整体复制到游戏 `left4dead2\` 下，或解压 Release 里的 zip：

   ```powershell
   Expand-Archive -Path "dist\PulseShader-0.10.0-hairshadow.zip" `
     -DestinationPath "<Steam>\steamapps\common\Left 4 Dead 2" -Force
   ```

4. 用 `-insecure -pulse_log` 启动，测试：
   - 队友在墙后时，蓝色光晕是身体外圈的细轮廓，**身体内部不再被填满**；
   - Boomer 胆汁后的黄色光晕同样正常；
   - 角色刘海在脸上投下的阴影恢复；`$hairshadowstrength` 调 0/1 能看到变化；
   - 面部阴影、描边、物品光晕、水面/水下没有新异常；
   - 没有崩溃。
5. 日志在 `%TEMP%\pulse_shader.log`，应能看到：

   ```text
   stencil: hook installed on slot 170
   stencil: engine state captured
   stencil: engine state enable=... ref=... test=... write=...
   hairshadow: DRAWER running, strength=...
   hairshadow: MARKER running
   ```

   如果日志里出现 `stencil: hook unavailable` 或
   `hairshadow: no engine stencil state captured yet, shadow pass skipped`，
   说明钩子不可用/未捕获，此时头发阴影会自动跳过（光晕仍然正常）；把日志发回来。

## 验证记录

- 2026-11-21，retail L4D2，实测：刘海阴影生效；蓝色队友光晕与 Boomer 黄色光晕都是细轮廓，没有整身实心；未崩溃。
- 该次测试启动项里没有 `-pulse_log`，所以没有日志文件；后来加参数复测方法见上一节。
  行为上能确认钩子捕获/恢复链路生效：头发阴影只有捕获到引擎状态才会绘制，未捕获时该 pass 会被跳过。

## 回滚

回到“光晕正常、头发阴影关闭”的行为：把之前备份的 `game_shader_generic_pulse*` 和
`pulse_*.vcs` 整套还原，或用上游 0.10.0 源码重新构建一套替换。DLL 和 `.vcs` 仍然必须整套对应。

## 重新构建

本机没有安装 CMake 时使用仓库内的本地构建脚本：

```bat
build_local.bat
```

它会：

1. 用 `tools/build_shaders.ps1` 生成 `build\inc\*.inc` 和 `dist\...\*.vcs`；
2. 用 Visual Studio x86 工具集把 DLL 编译到 `dist\left4dead2\bin\`；
3. 生成 Source 需要的无扩展名文件。

只改了 C++ 侧（比如这次只动 stencil 逻辑）可以用 `build_local.bat --dll-only` 复用已有的 `.inc` 和 `.vcs`。修改 HLSL 或 combo 后必须同时重新生成 `.vcs` 和 DLL，二者不能分开更新。官方 `build.bat`（需要 CMake）保持不变。
