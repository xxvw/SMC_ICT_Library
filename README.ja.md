# MetaTrader 5向け SMC/ICTライブラリ

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

MT5でSmart Money Concepts（SMC）とInner Circle Trader（ICT）のパターンを検出・取得する、MITライセンスのMQL5ライブラリです。EA内で型付きスナップショットを取得でき、同じ結果をJSONとしてPython、TypeScript、C#、Go、Java、Rustから読み取れます。

検出には確定足とブローカー時間を使用します。数値による判定条件は、このプロジェクトで定義した変更可能なルールです。[検出ルール（英語）](docs/ICT_RULES.md)を参照してください。翻訳に差異がある場合は英語版を正とします。

## 含まれる機能

| 分野 | 機能 |
| --- | --- |
| 構造とゾーン | 確定スイング、BOS、CHoCH、Order Block、FVG、Breaker Block、Liquidity、Premium/Discount、OTE、セッション |
| 追加のICTパターン | Displacement、MSS、IFVG、BPR、前日・前週・完了セッションの高安、ブローカー基準の日次・週次始値ギャップ、SMT Divergence、Power of Three |
| データ取得 | `SmcConfig`、`SmcSnapshot`、概念ごとの取得状態、安定したレコードID、ライフサイクル状態、UTF-8 JSON、既存CSV出力 |
| サンプル | 発注しないスナップショット出力EA、6言語のJSON読み取りコード、既存のVisualizerと売買サンプルEA |
| オプション分析 | 通貨強弱、ヒストリカルボラティリティ、Python学習スクリプト、ONNXユーティリティ |

## MT5で使い始める

1. MT5で **ファイル → データフォルダを開く** を選びます。
2. `Include/SMC/`を`MQL5/Include/SMC/`に、`Experts/SMC_Snapshot_Export.mq5`を`MQL5/Experts/`にコピーします。
3. MetaEditorで出力EAをコンパイルし、チャートに適用してエキスパートログを確認します。このEAは足の確定後にスナップショットを出力し、発注しません。
4. MT5の共有ディレクトリ`Terminal/Common/Files/`に出力されたJSONを、下記のサンプルで読み取ります。

MQL5から利用する場合は、設定を初期化し、更新の成功とスナップショットの状態を確認します。

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
      return; // 詳細はGetStatus()/GetSnapshot()で確認できます。

   SmcSnapshot snapshot;
   if(!smc.GetSnapshot(snapshot) || snapshot.status != SMC_STATUS_READY)
      return;

   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept == ICT_IFVG)
         Print(snapshot.records[i].id, " ", snapshot.records[i].state);
}

void OnDeinit(const int reason) { smc.Clean(); }
```

既存の`Init()`、`Update()`、`Clean()`、getterは引き続き利用できます。[クイックスタート](docs/QUICKSTART.md)、[スナップショットAPI](docs/SNAPSHOT_API.md)、[互換性について](docs/SNAPSHOT_API.md#compatibility)は英語で提供しています。

## 他の言語から結果を読む

各サンプルはスナップショットのパスを受け取り、`--concept IFVG --direction bearish`で絞り込めます。共通fixtureと期待出力を使用し、検出処理はMQL5側で実行します。

| 言語 | セットアップ・実行手順 |
| --- | --- |
| Python | [examples/python](examples/python/README.md) |
| TypeScript | [examples/typescript](examples/typescript/README.md) |
| C# | [examples/csharp](examples/csharp/README.md) |
| Go | [examples/go](examples/go/README.md) |
| Java | [examples/java](examples/java/README.md) |
| Rust | [examples/rust](examples/rust/README.md) |

[データ仕様](docs/DATA_CONTRACT.md)と[JSON Schema](schemas/snapshot.schema.json)で、バージョン、時刻、状態、レコードのフィールドを定義しています。ブローカー時刻にはUTCの接尾辞を付けません。履歴不足と、正常に評価した結果の「該当なし」は区別されます。

## ドキュメントと開発

- [ドキュメント一覧](docs/README.md)：従来の日本語リファレンスも掲載しています。
- [検出ルールと既定値（英語）](docs/ICT_RULES.md)。
- [ローカル検証と開発手順（英語）](docs/DEVELOPMENT.md)。
- [貢献ガイド](CONTRIBUTING.md)、[行動規範](CODE_OF_CONDUCT.md)、[セキュリティ報告](SECURITY.md)、[変更履歴](CHANGELOG.md)。

変更は小さなPRで`main`へ反映し、ローカル検証後にsquash mergeします。一つの目的の変更をcommit・検証・pushしてから、次の変更に進みます。CIはローカルで実行し、GitHub hosted/self-hosted runnerは不要です。

```sh
python -m pip install -r requirements-dev.txt
python tools/setup_hooks.py
python tools/check_all.py
```

完全な検証にはMetaEditor/MT5と各サンプル言語のツールチェーンも必要です。[開発ガイド](docs/DEVELOPMENT.md)に従って準備してください。ツール不足や検証の中断は失敗として扱います。

PythonのCSV処理、MT5直接接続、ML学習の依存関係は分離しています。[Pythonの導入手順](docs/QUICKSTART.md#python-data-and-training)を参照してください。

## ライセンス

[MIT](LICENSE)。このライブラリとサンプルは研究・ソフトウェア開発を支援するものです。パターン検出はデータであり、収益性を示すものではありません。既存の`SMC_Sample_EA.mq5`は発注できます。データ取得のみの連携には`SMC_Snapshot_Export.mq5`を使用してください。
