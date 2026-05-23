# boba-artifacts

Сборочный проект для [boba]: Astra Linux CE 2.12 +
glibc 2.28 + Python 3.11. Хранит `Dockerfile`'ы, pre-downloaded `wheels/`, тарболы
glibc/gcc/python и `docker-compose.yml`.

Должен лежать рядом с `boba/`:

```
<parent>/
├── boba/               # исходники (monorepo: packages/core|infra|tools|agents)
└── boba-artifacts/     # этот репо
```

## Структура

```
boba-artifacts/
├── local/                   # build- и deployment-конфиги + runtime-state (*.example — в git, реальные — не в git):
│   ├── .env              # deployment runtime: URL'ы (LLM) + секреты (читается docker-compose)
│   ├── config.toml       # все остальные настройки приложения ([agent]/[cli]/[chainlit]/[tool.*])
│   ├── apt-sources.list  # override apt-репо (пустой = дефолт rootfs)
│   ├── ca-chain.crt      # корпоративные CA (PEM, пустой = public-only)
│   ├── nginx-boba.conf   # reverse-proxy (include в http-server nginx)
│   ├── pip.conf          # /etc/pip.conf внутри рантайма (закрытый PyPI-mirror)
│   ├── litellm-config.yaml.example  # пример конфига litellm-proxy
│   ├── prompts.example/  # шаблонные system-prompts → копируются в prompts/
│   ├── prompts/          # реальные system-prompts (читает PromptLoader,
│   │                       путь — [agent] dir)
│   ├── workspaces/       # session workspaces агента (project + history)
│   ├── chainlit/         # chainlit data dir (sessions/translations/…)
│   ├── docs/, manual/    # справочные документы, доступные tool-плагинам
│   ├── cache/            # runtime-кэш (embeddings, fetched pages и т.п.)
│   └── logs/             # runtime логи всех сервисов
├── gcc-src/, glibc-src/,
│   python-src/              # исходники для Dockerfile.base
├── wheels/                  # pre-downloaded .whl (generated командой из Шага 2)
├── images/                  # экспорт `docker save` (generated, не в git)
├── Dockerfile               # runtime (на основе boba-base) — единый образ для всех приложений
├── Dockerfile.base          # сборка glibc+gcc+python из astra_linux_ce
└── docker-compose.yml       # сервисы: chainlit (daemon), cli-agent (CLI через --profile cli)
```

В `local/` все файлы с суффиксом `.example` коммитятся, без суффикса — загитигнорены
(коммитим только шаблоны).

**Полная изоляция** dev и deployment:

- `boba-artifacts/local/` — **deployment-песочница**. Свой `.env`
  (URL'ы + секреты), свой `config.toml` (всё остальное),
  свои `prompts/`, `workspaces/`, `logs/`, `cache/`. docker-compose
  монтирует эту папку как `/app/local` в контейнер. Шаблоны
  (`.env.example`, `config.toml.example`, `prompts.example/`)
  закоммичены в репо `boba-artifacts`.
- `../boba/local/` — **dev-песочница**. Используется VSCode
  launch.json для локального запуска через
  `pip install -r dev-install.txt`. Шаблоны живут в репо `boba/`.
  См. [`../boba/local/README.md`](../boba/local/README.md).

Эти две папки **не пересекаются**: контейнер не видит dev-данные, dev
не видит prod-state. Симметричная структура внутри обеих папок —
оператор может использовать одни и те же команды и навигацию.

## 0. Локальные конфиги из шаблонов

Build-оверрайды и deployment-конфиг — в `boba-artifacts/local/`,
коммитим только `*.example` и `*.example/**`. Перед первым билдом
скопируйте шаблоны в рабочие имена:

```bash
cd boba-artifacts
for f in local/*.example; do cp -n "$f" "${f%.example}"; done
cp -rn local/prompts.example local/prompts
# отредактировать local/.env       — BOBA_AGENT__BASE_URL,
#                                     BOBA_AGENT__API_KEY,
#                                     BOBA_CHAINLIT__AUTH_SECRET
# отредактировать local/config.toml — [agent] log_level/log_file/loop,
#                                     [chainlit] model/host/port/UI,
#                                     [tool.*] enable + overlay'ы
# отредактировать local/prompts/*.md под deployment-нужды
```

Разделение между `.env` и `config.toml`:

- **`.env`** — только то, что варьируется между средами и/или
  чувствительно: URL'ы внешних сервисов, API-ключи, JWT-секреты.
  `BOBA_CONFIG_PATH` тоже здесь — это путь до TOML внутри контейнера.
- **`config.toml`** — всё остальное: `[agent]` (core+workspaces+openai+
  prompts+runtime), `[cli]` (AgentRunConfig), `[chainlit]` (ChainlitConfig),
  `[tool.<name>]` (enable + per-tool overlays). Поля симметричны dev-конфигу
  `../boba/local/config.toml`.
- **per-service env в `docker-compose.yml`** — пусто. Поле `[agent].log_file`
  оканчивается на `_file` и коллидирует с конвенцией `EnvFileSource`
  (Docker secrets), поэтому в env работать не будет — задаётся только
  в TOML.

Конвенция ключей (EnvSource):

- env: `BOBA_<SEG>__<SEG>__<FIELD>` — двойной `_` между сегментами,
  одиночный после префикса `BOBA_`. Сегмент в UPPER_CASE, `_` внутри
  сегмента сохраняется (`max_iterations` → `MAX_ITERATIONS`).
- TOML: `[<seg>.<seg>] <field>`.

Приоритет источников: CLI > env-file > env > TOML.

Dev-конфиг (для локального запуска через VSCode) — отдельная папка
`../boba/local/`, со своими шаблонами и onboarding (см.
[`../boba/local/README.md`](../boba/local/README.md)).

## 1. Base-образ (разово, ~30 мин)

Использует `local/apt-sources.list` (закрытый контур — пропишите свои
зеркала, пустой файл = дефолт rootfs; GPG-ключи не нужны) и
`local/ca-chain.crt` (PEM-цепочка корпоративных CA; без `BEGIN CERTIFICATE`
блоков — no-op, доверяем только public CA из rootfs):

```bash
cd boba-artifacts
docker build -f Dockerfile.base -t boba-base:latest .
```

## 2. Build wheels (после правки pyproject.toml-ов в `../boba/packages/`)

Runtime-зависимости декларируются в `pyproject.toml` каждого пакета
(`../boba/packages/<group>/<name>/`, где `<group>` — `core` / `infra/*` /
`tools` / `agents`). `pip wheel` собирает их транзитивы по графу.

Требует готовый `boba-base:latest`.

### Открытый контур (pypi.org)

```bash
cd boba-artifacts
docker run --rm \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$(pwd)":/artifacts \
  -v "$(pwd)/../boba":/boba:ro \
  -w /artifacts \
  --entrypoint sh boba-base:latest -c '
    set -e
    rm -rf wheels && mkdir wheels
    cp -r /boba/packages /tmp/packages   # writable копия (хост :ro, .egg-info живёт в /tmp)
    pip3 wheel --no-cache-dir \
        /tmp/packages/core/boba-patterns \
        /tmp/packages/core/boba-settings \
        /tmp/packages/core/boba-workspace \
        /tmp/packages/core/boba-indexing \
        /tmp/packages/core/boba-tools \
        /tmp/packages/core/boba-llm \
        /tmp/packages/core/boba-agent \
        /tmp/packages/infra/llm/boba-openai \
        /tmp/packages/infra/format/boba-html \
        /tmp/packages/infra/format/boba-kbdoc \
        /tmp/packages/infra/format/boba-markdown \
        /tmp/packages/infra/format/boba-text \
        /tmp/packages/infra/transport/boba-transport-fs \
        /tmp/packages/infra/transport/boba-transport-http \
        /tmp/packages/infra/db/boba-db-postgres \
        /tmp/packages/tools/boba-tool-files \
        /tmp/packages/tools/boba-tool-kb \
        /tmp/packages/tools/boba-tool-postgres \
        /tmp/packages/tools/boba-tool-shell \
        /tmp/packages/agents/boba-cli-agent \
        /tmp/packages/agents/boba-chainlit-agent \
        pip setuptools wheel \
        -w wheels/
    chown -R "$HOST_UID:$HOST_GID" wheels
  '
```

### Закрытый контур (внутреннее PyPI-зеркало)

Пропишите `index-url`/`extra-index-url`/`trusted-host` в `local/pip.conf` и
прокиньте его в контейнер как `/etc/pip.conf`:

```bash
cd boba-artifacts
docker run --rm \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$(pwd)":/artifacts \
  -v "$(pwd)/../boba":/boba:ro \
  -v "$(pwd)/local/pip.conf":/etc/pip.conf:ro \
  -w /artifacts \
  --entrypoint sh boba-base:latest -c '
    set -e
    rm -rf wheels && mkdir wheels
    cp -r /boba/packages /tmp/packages   # writable копия (хост :ro, .egg-info живёт в /tmp)
    pip3 wheel --no-cache-dir \
        /tmp/packages/core/boba-patterns \
        /tmp/packages/core/boba-settings \
        /tmp/packages/core/boba-workspace \
        /tmp/packages/core/boba-indexing \
        /tmp/packages/core/boba-tools \
        /tmp/packages/core/boba-llm \
        /tmp/packages/core/boba-agent \
        /tmp/packages/infra/llm/boba-openai \
        /tmp/packages/infra/format/boba-html \
        /tmp/packages/infra/format/boba-kbdoc \
        /tmp/packages/infra/format/boba-markdown \
        /tmp/packages/infra/format/boba-text \
        /tmp/packages/infra/transport/boba-transport-fs \
        /tmp/packages/infra/transport/boba-transport-http \
        /tmp/packages/infra/db/boba-db-postgres \
        /tmp/packages/tools/boba-tool-files \
        /tmp/packages/tools/boba-tool-kb \
        /tmp/packages/tools/boba-tool-postgres \
        /tmp/packages/tools/boba-tool-shell \
        /tmp/packages/agents/boba-cli-agent \
        /tmp/packages/agents/boba-chainlit-agent \
        pip setuptools wheel \
        -w wheels/
    chown -R "$HOST_UID:$HOST_GID" wheels
  '
```

## 3. Build (оффлайн)

Зависит только от `wheels/` и `boba-base:latest`. В сеть не ходит.

```bash
cd boba-artifacts
docker compose build
```

Ставит транзитивы через `pip install --find-links=/tmp/wheels` для всех
локальных pyproject'ов (core + infra + tools-плагины + cli-agent +
chainlit-agent), потом no-deps installs наших пакетов.

## 4. Save images (для переноса в закрытый контур)

Экспортирует готовые образы в gzip-архивы. На целевом хосте (air-gapped)
загружаются через `docker load` и дальше `docker compose up -d` работает
как обычно.

```bash
cd boba-artifacts
mkdir -p images
docker save boba-base:latest | gzip > images/boba-base.tar.gz
docker save boba:latest      | gzip > images/boba.tar.gz
```

Загрузка на целевом хосте:

```bash
docker load --input images/boba-base.tar.gz
docker load --input images/boba.tar.gz
```

## 5. Run

Секреты и deployment-tunables читаются из `boba-artifacts/local/.env`.
Перед первым `up` создайте его из шаблона и заполните реальными
значениями (см. шаг 0 выше).

### Daemon: chainlit UI

```bash
cd boba-artifacts
docker compose up -d chainlit
```

### Ad-hoc CLI

CLI — **schema-driven**: каждое поле конфига доступно как
dotted-path флаг `--<section>.<field>=<value>` (либо
`--<section>.<field> <value>`). Позиционных аргументов нет.
Тот же ConfigKey мапится в env (`BOBA_<SEG>__<SEG>__<FIELD>`) и TOML
(`[section] field`). Тире внутри сегмента конвертируются в
подчёркивания (`--cli.max-tokens` == `--cli.max_tokens`). Что задано
в `local/config.toml` — можно не писать на CLI.

#### cli-agent — одиночный запрос или REPL

`model` — **обязательное поле**. Если задать его в config.toml
как `[cli] model = "qwen3"`, на CLI можно не указывать.
Если `query` пуст → REPL; задан → single-shot.

```bash
# Одиночный запрос (-T отключает TTY-аллокацию для не-интерактива)
docker compose run --rm -T cli-agent \
    --cli.model qwen3 \
    --cli.query "Привет"

# Запрос с sampling-параметрами
docker compose run --rm -T cli-agent \
    --cli.model qwen3.5-35b \
    --cli.query "Объясни RAG" \
    --cli.temperature 0.2 \
    --cli.max_tokens 800

# REPL (query не задан → интерактивный цикл)
docker compose run --rm cli-agent \
    --cli.model qwen3
# »  /exit, /quit, :q — выход
# »  /clear           — сбросить историю
```

`cli-agent` помечен `profiles: ["cli"]` — он НЕ стартует при
`docker compose up`, только через `run --rm cli-agent`.

#### tool-плагины

Tool-плагины включаются через `[tool.<name>].enable = true` в
`local/config.toml`. Discovery — через entry-point group
`boba.plugins`, регистрируется автоматически при импорте пакета.

Доступные плагины (по умолчанию все `enable = false`):

| `[tool.<name>]` | Пакет | Tools |
|---|---|---|
| `files` | `boba-tool-files` | 16 файловых tools: `cat`, `ls`, `grep`, `edit`, `write`, `append`, `cd`, `pwd`, `tree`, `cp`, `mv`, `rm`, `mkdir`, `touch`, `stat` |
| `kb`    | `boba-tool-kb`    | `kb_search_hybrid`, `kb_search_vector`, `kb_search_fts`, `confluence_search_cql`, `confluence_list_spaces`, `confluence_ingest_spaces`, `confluence_ingest_pages`, `confluence_ingest_cql`, `confluence_download` (поверх postgres+pgvector с гибридным RRF) |
| `pg`    | `boba-tool-postgres` | `query`, `list_tables`, `describe_table`, `fts_search` — ad-hoc read-only SQL/FTS поверх `boba-db-postgres` |
| `shell` | `boba-tool-shell` | `bash_local` (локальный bash; sandbox-вариант `bash_sandbox` через bubblewrap опционально) |

Подробнее по полям секций — `local/config.toml.example`.

## Команды

```bash
docker compose build                          # пересобрать runtime-образ
docker compose up -d chainlit                 # daemon UI
docker compose logs -f chainlit               # логи UI
docker compose run --rm -T cli-agent ARGS...  # одиночный CLI-запуск
docker compose run --rm cli-agent ARGS...     # CLI REPL
docker compose down                           # остановить daemon-сервисы
```
