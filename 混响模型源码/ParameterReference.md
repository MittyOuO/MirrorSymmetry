# ZSDXReverb 参数参考

本文件与 `ParameterCatalog.json` 由 `GetParameterCatalog.m` 同一数据源生成。

| 英文标识 | 中文名称 | JSON 路径 | 允许值 | 默认值 | 单位 | 模型字段 | 物理含义 |
|---|---|---|---|---|---|---|---|
| Bottom.mode | 底质输入模式 | `Bottom.mode` | manual, preset, custom | preset | - | `Sediment` | 手动输入或从底质库解析地声参数 |
| Bottom.type | 底质类型 | `Bottom.type` | south_china_sea_silt, theoretical_clay, high_water_content_soft_mud, typical_soft_clay, dense_clay, apl_silty_clay, apl_sandy_clay, slightly_positive_speed_clay, dense_clay_silt_mix, compacted_clay, indian_ocean_silt, fine_sand, gravel | south_china_sea_silt | - | `Sediment.cB/rhoB/alphaB` | 预设底质英文标识 |
| Scattering.miuMode | 散射系数模式 | `Scattering.miuMode` | manual, smooth, low_roughness, low_to_medium_roughness, medium_roughness, medium_to_high_roughness, high_roughness, very_high_roughness | manual | - | `InputParams.Miu` | 选择或手动指定散射系数 |
| Scattering.bottomSlopeMode | 海底坡度模式 | `Scattering.bottomSlopeMode` | manual, flat, very_gentle_slope, gentle_slope, steep_slope | manual | - | `InputParams.Tht` | 手动模式优先读取bottomRmsSlopeRad；核心统一使用弧度，旧bottomRmsSlopeDeg仅作兼容 |
| Beam.ArrayType | 阵型类型 | `Beam.ArrayType` | 1, 2, 3, 4 | 1 | - | `Beam/ArrayGeom` | 1垂直线阵、2水平线阵、3圆柱阵、4自定义主瓣 |
| Beam.fBeam | 阵列波束形成频率 | `Beam.fBeam` | positive scalar | 500 | Hz | `InputParams.Beam.fBeam/BTRParams.fBeam` | 用户手动输入且不会被发射信号覆盖 |
| Beam.sideRangeDeg | 俯仰旁瓣范围 | `Beam.sideRangeDeg` | empty, 2x2 ordered matrix | [] | deg | `InputParams.Beam.SideRange` | 模型俯仰角顺序为[下外 下内;上内 上外]；空数组表示上下零宽旁瓣 |
| Beam.sideDownDb | 俯仰旁瓣抑制 | `Beam.sideDownDb` | finite scalar <= 0, two-element [lower upper] | [0 0] | dB | `InputParams.Beam.ElevSideDown_dB` | 下、上旁瓣分别抑制；复幅度使用10^(dB/20)，标量仍兼容 |
| Beam.azimuthSearchRangeDeg | 水平主瓣范围 | `Beam.azimuthSearchRangeDeg` | two finite values | [-180 180] | deg | `InputParams.Beam.AzimuthRange` | 水平左、右主瓣边界；[-180,180]表示水平全向 |
| Beam.AzSideRangeDeg | 水平旁瓣范围 | `Beam.AzSideRangeDeg` | empty, 2x2 ordered matrix | [] | deg | `InputParams.Beam.AzimuthSideRange` | 顺序为[左外 左内;右内 右外]；空数组表示左右零宽旁瓣 |
| Beam.AzSideDownDb | 水平旁瓣抑制 | `Beam.AzSideDownDb` | finite scalar <= 0, two-element [left right] | [0 0] | dB | `InputParams.Beam.AzimuthSideDown_dB` | 左、右旁瓣分别抑制；复幅度使用10^(dB/20)，标量仍兼容 |
| Array.receiverPitchDeg | 接收水平线阵姿态角 | `Array.receiverPitchDeg` | finite scalar, abs(value) < 90 | 0 | deg | `InputParams.TowedArray.PitchDeg` | 用户正值表示远离声源端向上；内部按正深度坐标取负值 |
| Array.headingDeg | 接收水平线阵航向角 | `Array.headingDeg` | finite scalar | 0 | deg | `InputParams.TowedArray.ArrayHeadingDeg` | 接收水平线阵在水平面内的航向角 |
| Signal.type | 信号类型 | `Signal.type` | CW, HFM, LFM, HFM_CW, CW_HFM, custom | HFM_CW | - | `TxSigInput.sigType` | 自动决定传播频率：单分量一次；组合信号中CW在HFM带内时共用CW频率，带外时计算两个频率 |
| PlatformMotion.dopplerMode | 多普勒模式 | `PlatformMotion.dopplerMode` | one_way, two_way, bistatic | two_way | - | `InputParams.DopplerMode` | 发射信号时间缩放的径向速度模式 |
| Output.saveSelection | 输出选择 | `Output.saveSelection` | 0, 1, 2, 3, 4, 5 | 0 | - | `InputParams.OutputSelection` | 0不保存，1时响fig，2时响bin，3时响mat，4 BTR fig，5 BTR mat |
| Environment.sspPath | 声速剖面文件 | `Environment.sspPath` | .mat, .txt, .csv | env/deep_sea_ssp_0_2000m.txt | - | `InputParams.SSP` | 读取、校验并截断或连续Munk延拓至海深 |
| Environment.waterDepth | 海深 | `Environment.waterDepth` | positive scalar | 4500 | m | `InputParams.WaterDepth` | SSP终点及BELLHOP深度盒基准 |
| Environment.modelType | 边界混响类型 | `Environment.modelType` | 1, 2 | 1 | - | `InputParams.OptionBorder` | 1仅海底混响；2海底加海面混响，海面项为NRL粗糙界面与风生气泡云体积散射的功率和 |
| SeaSurface.seaState | 蒲福海况等级 | `SeaSurface.seaState` | 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 | 2 | Beaufort | `InputParams.SeaState/InputParams.U` | 按标准10 m风速区间解析；显式风速不在该区间时使用区间代表风速，从而使海况控制气泡云体积附加量 |
| SeaSurface.windSpeed | 10 m风速 | `SeaSurface.windSpeed` | finite scalar >= 0 | 1.8 | m/s | `InputParams.U` | 位于所选海况标准区间内时作为NRL模型精确风速，否则由seaState代表风速替代；气泡云项在U<=3 m/s时为零 |
| Computation.SkipFastRL | 跳过快速RL | `Computation.SkipFastRL` | true, false | true | - | `InputParams.SkipFastRL` | true时FastRLCompute调用次数为0 |
