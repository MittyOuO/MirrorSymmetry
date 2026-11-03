# ZSDXReverb 交付说明

## 交付边界

- `ZSDXReverb.exe` 保持直接单工况调用兼容；由 `readZSDX.m` 调用时，一个 EXE 进程按 `thetaList` 顺序完成全部角度。
- 角度遍历支持 ArrayType 1/2/3：垂直阵 theta、水平阵有效方位角 phi、圆柱阵 theta。每个角度重新计算方向图、重新生成 BELLHOP 环境并重新追踪声线；MATLAB 散射并行池只建立一次并在角度间复用。
- `SYSU` 是旧临时打包版本。本次自动频率与共享面元逻辑先在 `Re` 完成，并已按用户要求同步到 `Code`；`Reverb.mlapp` 的开始仿真入口也已接入同一判定规则。

## 核心变化

- `frequencyChannelMode` 已从 JSON 删除。CW/HFM 单分量自动使用一个传播频率；`HFM_CW`/`CW_HFM` 中，CW 位于 HFM 频带内（含边界）时只在 CW 频率计算一组 `h(t)`，CW 位于带外时自动建立 HFM 中心频率与 CW 频率两个传播通道。
- 所有频率和路径的 BELLHOP 作业以独立系统进程并发完成；随后海底/海面散射按 `x` 维度使用 MATLAB 并行池并行，但每个 `x` 内同时计算各频率通道，因此海底网格只遍历一次，需要海面散射时海面网格也只遍历一次。各频率在同一个网格单元和路径族共享同一内部相位基础。
- `RandomSeed` 与 `ScatterGrid` 不再是 JSON 输入。面元坐标无抖动，面元和路径对应的共享相位由内部固定规则生成。
- 带内共用传播响应不会改变发射波形：同一个 `h(t)` 分别作用于原始 CW 与完整 HFM 扫频波形。带外时各分量先在复线性时域独立处理、按原起始时刻移位并相加，最后再统一计算功率、平滑和 dB；BTR 同样遵循这一顺序。
- `Beam.fBeam` 为人工配置权威值，不再由信号频率覆盖。支持垂直线阵、水平线阵、圆柱阵、自定义主瓣四类阵型；俯仰上下旁瓣与水平左右旁瓣可分别设置范围和抑制，并在复幅度域联合加权。
- SSP 支持 MAT/TXT/CSV，按海深截断或连续 Munk 延拓；BELLHOP 的 `ZBox`、`RBox` 随水深和最大距离动态设置。
- 底质、散射系数、坡度预设集中解析；砾石参数为 `cB=1800 m/s`、`rhoB=2.10 g/cm³`、`alphaB=0.20 dB/λ`。
- `Environment.modelType=2` 时，海面项采用 NRL 粗糙界面与风生近海面气泡云的线性功率和，并自动加入独立水体体积混响。水体项为固定种子、475–525 Hz 带限的非相干散射过程：近程段快速指数衰减，远程段从第一海底到达附近以幂律接管长时尾部。它只加入 `ySca`，不会修改直达波、海底/海面冲激响应或到达几何。气泡云与独立水体项在诊断信息中分别标记。
- 实测验证会自动检测实测时域文件。文件存在时，仅在检测出的直达事件窗口内按实测直达波绝对峰值截断仿真接收电压，并由截断后的时域电压重算 RL；窗口外样点保持不变。未提供实测信号时不截断。验证脚本原有绘图数量、布局和曲线组织未改动。

## 输出约定

- 固定生成：`InputConfig.json`、`RunSummary.json`、`CallResult.json`。
- `Output.saveSelection`：默认 0 不保存结果文件；1 时响 FIG，2 时响 BIN，3 时响 MAT，4 BTR FIG，5 BTR MAT。
- `readZSDX` 返回的 `timeRt/yTotal/yDir/ySca/BTR` 均为 MATLAB 内存中的 double 数组；跨进程临时返回缓存读取后立即删除，不再返回 `timeAxis` 或 `BTRLinear`。
- 时响 BIN 的逻辑矩阵为 `[timeRt; yTotal]`（`thetaCount+1` 行），每个复数按实部/虚部两个 little-endian double 交错保存。
- `TimeResponse.mat` 不再包含 `ChannelResults` 或事件表。
- 事件表仅在 BTR 计算期间存在，BTR 完成后立即清空；不再提供事件诊断开关，也不写出事件诊断文件。
- `Computation.Itg` 已从外部 JSON 移除，内部固定为 0.02 s。
- `TimeResponse.bin` 无文件头，按 `[timeRt; yTotal]` 的列优先顺序写入复数实部/虚部对。
- BTR MAT 中矩阵方向为行=扫描角、列=时间。
- `readZSDX` 结果结构体只包含 `arrayType/thetaList/timeRt/yTotal/yDir/ySca/BTR/timeBTR/scanAngles`。

## 已完成验证

- 自动频率单元验证：11 项通过，覆盖 CW、HFM、两种组合顺序、带内、带外和上下边界，并核验带内通道保留完整组合波形。
- 带外实算（HFM 400–600 Hz、CW 700 Hz）：自动选择 `[500,700]`，6/6 个 BELLHOP 作业，海底网格遍历 1 次。
- 带内实算（HFM 400–600 Hz、CW 550 Hz）：自动选择 `[550]`，3/3 个 BELLHOP 作业，海底网格遍历 1 次。
- `Code`/App 使用的 `RunReverbSimulation` 实际入口已完成带内工况验证：1 个传播频率、3/3 个 BELLHOP 作业、共享海底网格遍历 1 次，并成功生成 `yTotal`。
- 新编译 EXE 已通过 `readZSDX` 的带外与带内实算：带外 6/6 作业、带内 3/3 作业，两种工况海底网格均只遍历 1 次；返回结构体仍严格包含 9 个约定字段。
- 相同输入重复计算的复时域输出最大误差为 0。
- 海底+海面+BTR 实算：10/10 个 BELLHOP 作业，海底/海面各遍历 1 次，8886 个事件，BTR 尺寸 `3×31`。
- 编译后 EXE 独立实算退出码 0；最新交付包已完成两角度循环 FIG 实算，两个纵向子图、共同时间轴与共同对称纵轴均自动核验通过。
- 单进程两角度实算：并行池状态为“首角度新建、第二角度复用”；两个角度均重新完成 6/6 个 BELLHOP 作业，主波束及写入 `.env` 的发射角范围随 theta 改变。
- 当前单元验证 15 项通过，其中新增海况—有效风速—气泡云附加量递增验证，以及“仅直达窗口限幅、窗口外零改动、RL严格由限幅后电压重算”验证。

## 运行环境

发布包需要 MATLAB R2025b 对应的 MATLAB Runtime。请保持 `ZSDXReverb.exe`、`bellhop.exe`、`env/`、JSON 和 `readZSDX.m` 的相对发布结构。

联调参数查表文档为 `内置环境参数输入对照表.docx`，内容由当前 `GetBottomPreset.m` 与 `ResolveScatteringPreset.m` 的内置映射生成。
