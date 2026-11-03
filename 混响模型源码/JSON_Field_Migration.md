# JSON 字段迁移说明

旧 `SYSU` JSON 仍可作为业务参数来源，但应迁移到 `Re/ParanConfigToZS.json` 的结构后再运行新 EXE。

| 旧字段/行为 | 新字段/行为 | 说明 |
|---|---|---|
| `Beam.BeamElevLower`、`Beam.BeamElevUpper` | `Beam.customMainBeam.lowerDeg`、`Beam.customMainBeam.upperDeg` | 自定义阵型的自然角度顺序为 lower、upper；内部 BELLHOP 主瓣仍写成 `[upper lower]`。 |
| `Beam.deltaDeg` 或旧版逐 EXE 角度循环 | `readZSDX(jsonFile,startTheta,deltaDeg,thetaCount)` | 外部生成 `thetaList`，一次 EXE 在同一进程中顺序计算；每角度重跑 BELLHOP，仅复用散射并行池。 |
| 各子阵列对象中的 `fBeam` | 顶层 `Beam.fBeam` | 顶层字段是唯一权威输入，不被信号频率覆盖。 |
| 俯仰旁瓣缺省或旧的隐式旁瓣 | `Beam.sideRangeDeg`、`Beam.sideDownDb` | `sideRangeDeg=[]` 表示上下零宽旁瓣；范围顺序为 `[下外 下内;上内 上外]`，抑制顺序为 `[下 上]`，数值必须不大于 0 dB。 |
| 旧版无水平旁瓣接口 | `Beam.azimuthSearchRangeDeg`、`Beam.AzSideRangeDeg`、`Beam.AzSideDownDb` | 水平范围顺序为 `[左外 左内;右内 右外]`，抑制顺序为 `[左 右]`；`AzSideRangeDeg=[]` 表示左右零宽旁瓣。 |
| `Computation.frequencyChannelMode` | 删除，不再是 JSON 输入 | 内部根据信号自动判定：CW/HFM 单分量只算一次；组合信号中 CW 在 HFM 频带内（含边界）时只算 CW 频率并共用同一 `h(t)`，在频带外时算两个频率。旧字段会被忽略并移除。 |
| 固定海深/声速剖面 | `Environment.sspPath`、`Environment.waterDepth` | SSP 可为 MAT/TXT/CSV，并自动截断或 Munk 延拓。 |
| `Computation.RandomSeed`、`Computation.ScatterGrid` | 删除，不再是 JSON 输入 | 模型内部固定使用无抖动的共享面元坐标与共享相位规则；两频率在同一次遍历中计算。旧字段会被忽略并从实际配置中移除。 |
| 旧输出开关 | `Output.saveSelection=[0..5]` | 默认 0 不保存；1 时响 FIG，2 时响 BIN，3 时响 MAT，4 BTR FIG，5 BTR MAT。 |
| `Computation.Itg` | 不再对外提供 | 内部固定为 0.02 s；旧字段会被忽略并删除。 |
| 仅保存最终响应 | 固定审计文件 | 每次运行固定写入 InputConfig、RunSummary、CallResult。 |

完整字段、允许值、默认值、单位和模型映射见 `ParameterReference.md` 与 `ParameterCatalog.json`。

## 海面混响字段说明

- `Environment.modelType=1`：仅计算海底混响。
- `Environment.modelType=2`：同时计算海底、海面以及独立水体体积混响；海面散射内部仍为 NRL 粗糙界面与风生气泡云的功率和，独立水体项另行加入 `ySca`。
- 新配置使用 `Scattering.bottomRmsSlopeRad`（rad）；旧 `bottomRmsSlopeDeg` 仍可读取，但只在JSON边界转换一次。
- `SeaSurface.seaState`：0–12 的蒲福风级。若显式 `windSpeed` 不落在该风级的标准 10 m 风速区间内，程序使用该等级的代表风速。
- `SeaSurface.windSpeed`：单位 m/s；落在所选海况区间内时作为精确模型输入。NRL 气泡云项在有效风速不超过 3 m/s 时为零。
