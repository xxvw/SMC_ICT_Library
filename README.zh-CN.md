# MetaTrader 5 SMC/ICT 库

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

采用 MIT 许可证的 MQL5 库，用于在 MT5 中检测和读取 Smart Money Concepts（SMC）与 Inner Circle Trader（ICT）形态。可在 EA 中使用类型化快照，也可通过 Python、TypeScript、C#、Go、Java 或 Rust 读取相同结果的 JSON 数据。

检测使用已收盘 K 线和经纪商时间。数值规则是本项目明确、可配置的定义，详见[检测规则](docs/ICT_RULES.md)。英文文档为权威版本。

## 包含的功能

| 领域 | 功能 |
| --- | --- |
| 结构与区域 | 已确认的摆动高低点、BOS、CHoCH、订单块、FVG、破坏块、流动性、溢价/折价、OTE 和交易时段 |
| 其他 ICT 形态 | 位移、MSS、IFVG、BPR、前一日/周及已结束交易时段的高低点、经纪商日/周开盘缺口、SMT 背离和 Power of Three |
| 数据访问 | `SmcConfig`、`SmcSnapshot`、各概念的就绪状态、稳定的记录 ID、生命周期状态、UTF-8 JSON 及现有 CSV 导出 |
| 示例 | 不下单的快照导出 EA、六种外部语言的 JSON 读取器、现有可视化工具和示例交易 EA |
| 可选分析 | 货币强弱、历史波动率分析、Python 训练脚本和 ONNX 工具 |

## 在 MT5 中开始使用

1. 在 MT5 中选择 **文件 → 打开数据文件夹**。
2. 将 `Include/SMC/` 复制到 `MQL5/Include/SMC/`，将 `Experts/SMC_Snapshot_Export.mq5` 复制到 `MQL5/Experts/`。
3. 在 MetaEditor 中编译导出 EA，将其加载到图表，并查看 Experts 日志。每根 K 线收盘时，它会导出新快照，不会下单。
4. 使用下方示例读取 MT5 共享目录 `Terminal/Common/Files/` 中的 JSON 文件。

在 MQL5 中集成时，请初始化配置，并同时检查更新是否成功和快照状态：

```cpp
#include <SMC/SmcManager.mqh>

CSmcManager smc;

int OnInit()
{
   SmcConfig config;
   config.SetDefaults();
   return smc.Init(_Symbol, _Period, config) ? INIT_SUCCEEDED : INIT_FAILED;
}

void OnTick()
{
   if(!smc.Update())
      return; // Read GetStatus()/GetSnapshot() for unavailable-module details.

   SmcSnapshot snapshot;
   if(!smc.GetSnapshot(snapshot) || snapshot.status != SMC_STATUS_READY)
      return;

   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept == ICT_IFVG)
         Print(snapshot.records[i].id, " ", snapshot.records[i].state);
}

void OnDeinit(const int reason) { smc.Clean(); }
```

现有的 `Init()`、`Update()`、`Clean()` 和 getter 接口仍然可用。请参阅[快速入门](docs/QUICKSTART.md)、[快照 API](docs/SNAPSHOT_API.md) 和[兼容性说明](docs/SNAPSHOT_API.md#compatibility)。

## 使用其他语言读取结果

每个示例都接受快照路径，以及可选的 `--concept IFVG --direction bearish` 筛选参数。读取器共用测试数据和预期输出；检测仍由 MQL5 执行。

| 语言 | 配置与运行说明 |
| --- | --- |
| Python | [examples/python](examples/python/README.md) |
| TypeScript | [examples/typescript](examples/typescript/README.md) |
| C# | [examples/csharp](examples/csharp/README.md) |
| Go | [examples/go](examples/go/README.md) |
| Java | [examples/java](examples/java/README.md) |
| Rust | [examples/rust](examples/rust/README.md) |

[数据契约](docs/DATA_CONTRACT.md) 和 [JSON Schema](schemas/snapshot.schema.json) 定义了版本管理、时间戳、状态和记录字段。经纪商时间戳不带 UTC 后缀。历史数据缺失与成功完成评估但未找到匹配的情况会分别报告。

## 文档与开发

- [文档索引](docs/README.md)，包含保留的日文参考指南。
- [检测规则与默认值](docs/ICT_RULES.md)。
- [本地验证与开发](docs/DEVELOPMENT.md)。
- [贡献指南](CONTRIBUTING.md)、[行为准则](CODE_OF_CONDUCT.md)、[安全问题报告](SECURITY.md) 和[变更记录](CHANGELOG.md)。

所有变更都通过面向 `main` 的小型 PR 提交，并在 squash 合并前完成本地验证。每完成一个独立单元，先提交、验证并推送，再开始下一个单元。CI 在本地运行；无需 GitHub 托管或自托管运行器。

```sh
python -m pip install -r requirements-dev.txt
python tools/setup_hooks.py
python tools/check_all.py
```

完整验证还需要 MetaEditor/MT5 和示例语言的工具链，请遵循[开发指南](docs/DEVELOPMENT.md)。缺少工具或检查中断均视为验证失败。

Python CSV 处理、终端连接和机器学习训练各有独立的依赖集。请参阅[快速入门：Python](docs/QUICKSTART.md#python-data-and-training)。

## 许可证

[MIT](LICENSE)。本库及示例用于研究和软件开发。形态检测结果只是数据，不能证明盈利能力。现有的 `SMC_Sample_EA.mq5` 可以下单；仅需数据集成时，请使用 `SMC_Snapshot_Export.mq5`。
