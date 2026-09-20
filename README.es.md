# Biblioteca SMC/ICT para MetaTrader 5

[English](README.md) · [日本語](README.ja.md) · [简体中文](README.zh-CN.md) · [Español](README.es.md)

Biblioteca MQL5 con licencia MIT para detectar y consultar patrones Smart Money Concepts (SMC) e Inner Circle Trader (ICT) en MT5. Utiliza instantáneas tipadas dentro de un EA o lee los mismos resultados en JSON desde Python, TypeScript, C#, Go, Java o Rust.

La detección utiliza velas cerradas y la hora del bróker. Las reglas numéricas son definiciones explícitas y configurables del proyecto; consulta las [reglas de detección](docs/ICT_RULES.md).

## Qué incluye

| Área | Funcionalidades |
| --- | --- |
| Estructura y zonas | Máximos y mínimos de oscilación confirmados, BOS, CHoCH, bloques de órdenes, FVG, bloques de ruptura, liquidez, prima/descuento, OTE y sesiones |
| Patrones ICT adicionales | Desplazamiento, MSS, IFVG, BPR, máximos/mínimos del día y la semana anteriores y de sesiones finalizadas, gaps de apertura diarios/semanales del bróker, divergencia SMT y Power of Three |
| Acceso a los datos | `SmcConfig`, `SmcSnapshot`, disponibilidad por concepto, identificadores de registro estables, estados del ciclo de vida, JSON UTF-8 y exportación CSV existente |
| Ejemplos | Un EA de exportación de instantáneas que no envía órdenes; seis lectores JSON en otros lenguajes; el visualizador y el EA de trading de ejemplo existentes |
| Análisis opcional | Fortaleza de divisas, análisis de volatilidad histórica, scripts de entrenamiento en Python y utilidades ONNX |

## Primeros pasos en MT5

1. En MT5, selecciona **Archivo → Abrir carpeta de datos**.
2. Copia `Include/SMC/` en `MQL5/Include/SMC/` y `Experts/SMC_Snapshot_Export.mq5` en `MQL5/Experts/`.
3. Compila el EA de exportación en MetaEditor, añádelo a un gráfico y consulta su registro de Expertos. Exporta una nueva instantánea al cierre de cada vela sin realizar operaciones.
4. Lee el archivo JSON del directorio compartido `Terminal/Common/Files/` de MT5 con uno de los ejemplos siguientes.

Para integrar la biblioteca en MQL5, inicializa una configuración y comprueba tanto el éxito de la actualización como el estado de la instantánea:

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
      return; // Consulta GetStatus()/GetSnapshot() para conocer los módulos no disponibles.

   SmcSnapshot snapshot;
   if(!smc.GetSnapshot(snapshot) || snapshot.status != SMC_STATUS_READY)
      return;

   for(int i = 0; i < ArraySize(snapshot.records); i++)
      if(snapshot.records[i].concept == ICT_IFVG)
         Print(snapshot.records[i].id, " ", snapshot.records[i].state);
}

void OnDeinit(const int reason) { smc.Clean(); }
```

Las interfaces existentes `Init()`, `Update()`, `Clean()` y los métodos de consulta siguen disponibles. Consulta la [guía de inicio rápido](docs/QUICKSTART.md), la [API de instantáneas](docs/SNAPSHOT_API.md) y las [notas de compatibilidad](docs/SNAPSHOT_API.md#compatibility).

## Leer los resultados en otro lenguaje

Cada ejemplo acepta la ruta de una instantánea y los filtros opcionales `--concept IFVG --direction bearish`. Los lectores comparten un archivo de prueba y un resultado esperado; la detección se realiza en MQL5.

| Lenguaje | Instrucciones de instalación y ejecución |
| --- | --- |
| Python | [examples/python](examples/python/README.md) |
| TypeScript | [examples/typescript](examples/typescript/README.md) |
| C# | [examples/csharp](examples/csharp/README.md) |
| Go | [examples/go](examples/go/README.md) |
| Java | [examples/java](examples/java/README.md) |
| Rust | [examples/rust](examples/rust/README.md) |

El [contrato de datos](docs/DATA_CONTRACT.md) y el [esquema JSON](schemas/snapshot.schema.json) definen el versionado, las marcas de tiempo, los estados y los campos de los registros. Las marcas de tiempo del bróker no llevan sufijo UTC. La falta de historial se indica de forma distinta a una evaluación correcta sin coincidencias.

## Documentación y desarrollo

La documentación en inglés es la referencia oficial del proyecto.

- [Índice de documentación](docs/README.md), que incluye las guías de referencia en japonés conservadas.
- [Reglas de detección y valores predeterminados](docs/ICT_RULES.md).
- [Validación local y desarrollo](docs/DEVELOPMENT.md).
- [Cómo contribuir](CONTRIBUTING.md), [código de conducta](CODE_OF_CONDUCT.md), [notificación de problemas de seguridad](SECURITY.md) e [historial de cambios](CHANGELOG.md).

Todos los cambios se realizan mediante PR pequeñas dirigidas a `main`, con validación local antes de fusionar mediante squash. Crea un commit por cada unidad terminada, valídalo y súbelo antes de comenzar la siguiente. La integración continua se ejecuta localmente; no se requieren ejecutores alojados por GitHub ni autohospedados.

```sh
python -m pip install -r requirements-dev.txt
python tools/setup_hooks.py
python tools/check_all.py
```

La validación completa también requiere MetaEditor/MT5 y las herramientas de los lenguajes de ejemplo; sigue la [guía de desarrollo](docs/DEVELOPMENT.md). Las herramientas ausentes y las comprobaciones interrumpidas hacen que la validación falle.

El procesamiento de CSV con Python, la conexión al terminal y el entrenamiento de modelos de aprendizaje automático tienen dependencias separadas. Consulta [inicio rápido: Python](docs/QUICKSTART.md#python-data-and-training).

## Licencia

[MIT](LICENSE). La biblioteca y los ejemplos sirven para la investigación y el desarrollo de software. Las detecciones de patrones son datos y no demuestran rentabilidad. El EA existente `SMC_Sample_EA.mq5` puede enviar órdenes; utiliza `SMC_Snapshot_Export.mq5` para integrar únicamente datos.
