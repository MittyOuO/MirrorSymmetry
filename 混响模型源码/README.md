# ZSDXReverb 混响计算程序

`ZSDXReverb.exe` 直接调用时接收一个 JSON 并运行一个工况：

```text
ZSDXReverb.exe ParanConfigToZS.json
```

阵列指向角遍历由外部 MATLAB 函数发起：

```matlab
result = readZSDX('ParanConfigToZS.json', -30, 5, 5);
```

`readZSDX` 会先读取 `Beam.ArrayType`：1 修改 `verticalArray.thetaDeg`，2 将外部 theta 映射到水平阵实际使用的 `horiArray.phiDeg`，3 修改 `cylinArray.thetaDeg`；自定义主瓣 ArrayType=4 不参与 theta 遍历。

角度循环只启动一次 EXE。EXE 内按 `thetaList` 顺序计算，每个角度都会重新解析阵列方向图、重新生成独立 BELLHOP `.env`、重新运行各频率/路径的声线追踪；散射 `parfor` 只建立一个本地 `Processes` 并行池，worker 数取该 profile 的完整可用容量，后续角度复用同一池。运行日志会记录 profile、requested、actual 与 reused；不再硬编码 2 或 6 workers，也不静默降级。

程序固定生成 `InputConfig.json`、`RunSummary.json` 和 `CallResult.json`。`Output.saveSelection` 默认值为 0：不保存时响或 BTR 产品；1=`TimeResponse.fig`，2=`TimeResponse.bin`，3=`TimeResponse.mat`，4=`BTR.fig`，5=`BTR.mat`。`readZSDX` 返回 `arrayType`、`thetaList`、`timeRt`、`yTotal`、`yDir`、`ySca`、`RL`、`BTR`、`timeBTR` 和 `scanAngles`。新增的 `RL` 与 `yTotal` 尺寸相同，行为指向角、列为时间，使用 50 ms 滑动能量窗及 JSON `Intensity` 标定参数计算；它不改变 `saveSelection` 语义。

时响 BIN 的逻辑矩阵为 `[timeRt; yTotal]`，共 `thetaCount+1` 行。矩阵按 MATLAB 列优先顺序展开，每个复数元素依次写入两个 little-endian double：实部、虚部。MAT 文件只包含 `timeRt` 和 `yTotal`。

`Computation.Itg` 不再是外部 JSON 参数，内部固定为 0.02 s。旧 JSON 中的该字段会被忽略并移除。

事件表没有外部开关：仅在 `BTR.enable=true` 时作为 BTR 中间量创建，BTR 完成后立即从内存释放，且不会保存为 MAT/BIN/FIG 等结果文件。

BTR 正式数值链使用事件真实 `X/Y/Z` 与阵元 `ElementXYZ`：三维球面路径差、四抽头 Lagrange 亚采样时延、实际发射波形解析匹配滤波和随频率变化的 TTD steering。多个传播频率通道先按 `SignalStartTime` 在复时域合并，再功率化、按 `SmoothTime` 平滑并输出到 `BTRFs`。矩阵方向保持“行=扫描角、列=时间”。`RunBTRValidationStandalone.m` 可直接读取标准 MAT（`BTR/timeBTR/scanAngles`）或兼容 FIG，并与 App 第三页、`build/SYSU/RunZSDXMeasuredValidation.m` 共用正式峰匹配核心；无有效匹配时状态为 `NOT_COMPUTED`，不会以最大单峰兜底判 PASS。

当 `Environment.modelType=2` 启用海面混响时，海面散射使用已有 NRL 总散射模型：粗糙海面界面散射与风生近海面气泡云体积散射先在线性功率域相加。程序还会自动加入独立的水体体积混响统计分量；它使用固定种子的带限非相干散射过程和幂律功率衰减，只进入 `ySca`，不修改直达波、边界冲激响应和几何到达时间。`SeaSurface.seaState` 按蒲福风级解析为 10 m 风速区间；若 `SeaSurface.windSpeed` 位于该区间内则采用该精确值，否则采用该海况的区间代表值。近海面气泡云项在有效风速不超过 3 m/s 时为零，随后随风速、频率和掠射角按 NRL 模型计算；独立水体项与之分开记录。

`build/SYSU/RunZSDXMeasuredValidation.m` 会先检测实测时域文件是否存在。存在实测信号时，以实测和仿真直达事件的峰值作共同对齐，只在实测直达事件时窗内把仿真接收电压对称硬限幅到实测直达波绝对峰值；第一海底峰和后续混响不被限幅。仿真 RL 随后由限幅后的最终时域电压重新计算。未提供实测信号时不启用该限幅。原有两行时域/RL图窗及可选 BTR 图窗结构不变。

`Computation.frequencyChannelMode` 已删除。程序按信号自动决定传播频率：CW、HFM 或 LFM 单分量只运行一个频率；`HFM_CW`/`CW_HFM` 中，若 CW 频率位于 HFM 频带内（含上下边界），只在 CW 频率计算一组传播响应，并用同一 `h(t)` 分别卷积原始 CW 波形与完整 HFM 扫频波形；若 CW 在 HFM 带外，则并发运行两个频率的 BELLHOP。无论一组还是两组频率，海底/海面散射始终按 `x` 并行，并在每个 `x` 内的一次面元遍历中计算全部频率事件。面元坐标和共享相位规则为内部固定实现，JSON 不包含 `RandomSeed` 或 `ScatterGrid`。

运行需要与 MATLAB R2025b 对应的 MATLAB Runtime。`bellhop.exe`、`env/`、示例 JSON 和参数参考文件必须保留在发布目录中。

2026-09-20 BeamWeight / SSP 更新：真实阵型使用 V2 分层权重，依次评估非对称 3 dB Gaussian 主瓣核心、自动 `3 dB→first null` 主瓣裙边、全部达内部阈值的次级主瓣、左右/上下独立能量等效残余旁瓣。方位范围支持 `left>right` 表示跨 ±180°；自定义波束继续走 V1 兼容链。实测 SSP 深水延拓使用输入剖面全局最小声速样点作为工程参考轴，`RunSummary.sspResolved.axisInfo` 同时记录检测规则、轴深、最小声速、边界标志和是否实际用于延拓。JSON 输入 schema 未改变。

参与联调人员可直接查阅 `内置环境参数输入对照表.docx`：其中列出全部 13 种 Bottom 预设、8 种 `miuMode` 和 5 种 `bottomSlopeMode` 的合法输入名称、内置数值、单位与手动模式规则。

2026-10-10 Runtime兼容修订：取消ThetaBatchProgress文件协议；每个角度开始时打印英文theta与中文当前指向角两行。实际Runtime依赖恢复为旧版7组件，详见RUNTIME_COMPATIBILITY_20261010.md。
