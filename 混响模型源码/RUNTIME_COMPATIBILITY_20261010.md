# Runtime compatibility / 指向角输出（2026-10-10）

此版本取消进度文件协议。`readZSDX` 仍以一个 EXE 进程顺序运行多个角度并复用并行池。
每个工况开始时，stdout 使用两行 UTF-8 文字：

```text
theta = -60 deg.
当前指向角：-60 度
```

不再生成或更新 `ThetaBatchProgress.json`，不再公布 progress locator，也不返回
`ThetaBatchProgressFile` / `ThetaBatchProgressLocator`。其余正式数值返回合同保持。
`yTotal` 为含声源级及同一次噪声的 µPa 解析复声压；`RL` 与之使用同一 realization。
`NoiseInfo` 和重复的 display 字段不作为 public result 返回。

## 实际编译器依赖

新 EXE 的外部及内部嵌入 `buildresult.json` 均为以下 7 个必需 Runtime 组件：

| ID | Component |
|---|---|
|35000|MATLAB Extended Runtime Addon|
|35002|MATLAB Graphics Runtime Addon|
|35003|MATLAB Standard Runtime Addon|
|35010|MATLAB Base Runtime|
|35108|Signal Processing Toolbox Runtime Addon|
|35119|Statistics and Machine Learning Toolbox Runtime Addon|
|35180|Parallel Computing Toolbox Standard Runtime Addon|

不再要求 DSP System Toolbox、Simulink Compiler、Fixed-Point Designer。
MATLAB Runtime 仅有“R2025b”目录并不能证明这 7 个组件全部存在；请同时检查安装组件。
可在此发布目录执行 `CheckRuntimeCompatibility.ps1`，该脚本只读，不修改 Runtime。

## 构建边界

构建使用受控 MATLAB 搜索路径和 `mcc -N/-I`，剔除其他已安装工具箱的间接依赖。
噪声 helper 的可选 `NoiseBandHz/bandpass` 分支不被正式 JSON/EXE 调用。
其调用位置仅增加 `%#exclude bandpass` 编译指令及注释；所有数值语句保持。
MATLAB 源码调用该 helper 时，原可选分支仍存在。本 EXE 不提供 NoiseBandHz 输入合同。
如果未来授权将该参数接入 EXE，必须重新审计并重建依赖，不能直接继承本次清单。

本机真实运行已使用 `C:\Program Files\MATLAB\MATLAB Runtime\R2025b` 的
`mclmcrrt25_2.dll`。另一台电脑的真实启动仍需在那里执行确认。

## 替换

将便携发布包完整解压到新的目录；保留 EXE、同版 readZSDX、noise helper、env、SYSU
及其他配套文件。不要只替换 EXE 却继续调用旧 wrapper。
在 MATLAB 用 `which readZSDX -all` 核对实际调用路径，再执行原有 readZSDX 调用。
源 JSON 字段名、Beam 模型、声源/接收校准、BTR 内外角坐标和二进制排列均保持。
