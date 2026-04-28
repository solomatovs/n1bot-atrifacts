# boba-artifacts

Сборочный проект для [boba]: Astra Linux CE 2.12 +
glibc 2.28 + Python 3.11. Хранит `Dockerfile`'ы, pre-downloaded `wheels/`, тарболы
glibc/gcc/python и `docker-compose.yml`.

Должен лежать рядом с `boba/`:

```
<parent>/
├── boba/               # исходники (src/, pyproject.toml)
└── boba-artifacts/     # этот репо
```

## Структура

```
boba-artifacts/
├── local/                   # build- и deployment-конфиги + runtime-state (*.example — в git, реальные — не в git):
│   ├── .env              # deployment runtime: только URL'ы (LLM) + секреты (читается docker-compose)
│   ├── config.toml       # все остальные настройки приложения (log_level, agent loop, chainlit, paths)
│   ├── apt-sources.list  # override apt-репо (пустой = дефолт rootfs)
│   ├── ca-chain.crt      # корпоративные CA (PEM, пустой = public-only)
│   ├── nginx-boba.conf   # reverse-proxy (include в http-server nginx)
│   ├── pip.conf          # /etc/pip.conf внутри рантайма (для отладки)
│   ├── litellm-config.yaml.example  # пример конфига litellm-proxy
│   ├── prompts.example/  # шаблонные system-prompts → копируются в prompts/
│   ├── prompts/          # реальные system-prompts (read'ится BOBA_PROMPTS_DIR)
│   ├── workspaces/       # session workspaces агента (project + history + scratch)
│   ├── logs/             # runtime логи всех сервисов
│   └── chroma/           # ChromaDB persistent state
├── gcc-src/, glibc-src/,
│   python-src/              # исходники для Dockerfile.base
├── wheels/                  # pre-downloaded .whl (generated командой из Шага 2)
├── images/                  # экспорт `docker save` (generated, не в git)
├── Dockerfile               # runtime (на основе boba-base) — единый образ для всех приложений
├── Dockerfile.base          # сборка glibc+gcc+python из astra_linux_ce
└── docker-compose.yml       # сервисы: chainlit (daemon), agent-run / vector-index (CLI через --profile cli)
```

В `local/` все файлы с суффиксом `.example` коммитятся, без суффикса — загитигнорены
(коммитим только шаблоны).

**Полная изоляция** dev и deployment:

- `boba-artifacts/local/` — **deployment-песочница**. Свой `.env`
  (URL'ы + секреты), свой `config.toml` (всё остальное),
  свои `prompts/`, свои `workspaces/`, `logs/`, `chroma/`. docker-compose
  монтирует эту папку как `/app/local` в контейнер. Шаблоны
  (`.env.example`, `config.toml.example`, `prompts.example/`)
  закоммичены в репо `boba-artifacts`.
- `../boba/local/` — **dev-песочница**. Используется VSCode
  launch.json для локального запуска через `pip install -r dev-install.txt`.
  Шаблоны живут в репо `boba/`. См.
  [`../boba/local/README.md`](../boba/local/README.md).

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
# отредактировать local/.env       — задать BOBA_LLM_BASE_URL,
#                                     BOBA_LLM_API_KEY,
#                                     BOBA_CHAINLIT_AUTH_SECRET
# отредактировать local/config.toml — log_level, agent loop, chainlit
#                                     models/UI, paths, ...
# отредактировать local/prompts/*.md под deployment-нужды
```

Разделение между `.env` и `config.toml`:

- **`.env`** — только то, что варьируется между средами и/или
  чувствительно: URL'ы внешних сервисов, API-ключи, JWT-секреты.
  `BOBA_CONFIG_PATH` тоже здесь — это путь до TOML внутри контейнера.
- **`config.toml`** — всё остальное: log_level, agent loop, chainlit
  server/UI, список моделей, пути под `/app/local/...`,
  `[ext.chromadb] persist_path`. Поля симметричны dev-конфигу
  `../boba/local/config.toml`.
- **per-service env в `docker-compose.yml`** — только то, что
  отличается между сервисами (сейчас это `BOBA_APP_LOG_FILE`:
  каждый сервис пишет в свой лог).

Приоритет источников: CLI > env > .env-файл > TOML-файл > [TOML].
Любое поле из `config.toml` можно перебить env-переменной
`BOBA_<SECTION>_<FIELD>=...` (например, для отладки).

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
(`../boba/packages/<name>/`). `pip wheel` собирает их транзитивы по
графу.

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
        /tmp/packages/boba \
        /tmp/packages/boba-adapter-fs-workspace \
        /tmp/packages/boba-adapter-messages \
        /tmp/packages/boba-adapter-openai \
        /tmp/packages/boba-adapter-prompt-providers \
        /tmp/packages/boba-config-cli \
        /tmp/packages/boba-config-env \
        /tmp/packages/boba-config-toml \
        /tmp/packages/boba-ext-files \
        /tmp/packages/boba-ext-chromadb \
        /tmp/packages/boba-ext-confluence \
        /tmp/packages/boba-ext-html \
        /tmp/packages/boba-cli-agent-run \
        /tmp/packages/boba-cli-vector-index \
        /tmp/packages/boba-web-chainlit \
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
        /tmp/packages/boba \
        /tmp/packages/boba-adapter-fs-workspace \
        /tmp/packages/boba-adapter-messages \
        /tmp/packages/boba-adapter-openai \
        /tmp/packages/boba-adapter-prompt-providers \
        /tmp/packages/boba-config-cli \
        /tmp/packages/boba-config-env \
        /tmp/packages/boba-config-toml \
        /tmp/packages/boba-ext-files \
        /tmp/packages/boba-ext-chromadb \
        /tmp/packages/boba-ext-confluence \
        /tmp/packages/boba-ext-html \
        /tmp/packages/boba-cli-agent-run \
        /tmp/packages/boba-cli-vector-index \
        /tmp/packages/boba-web-chainlit \
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

Ставит транзитивы через `pip install --find-links=/tmp/wheels` для
всех локальных pyproject'ов (boba core + adapter-* + config-* +
ext-* + cli-* + web-chainlit), потом editable-installs наших пакетов.

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

CLI — **schema-driven**: каждое поле конфига становится флагом
вида `--<section>-<field>`. Позиционных аргументов нет. Имя флага
строится по правилу `cli_flag_name(ConfigKey)` — то же ConfigKey,
которое мапится в env (`BOBA_<SECTION>_<FIELD>`) и TOML
(`[section] field`). Что задано в `local/config.toml` — можно
не писать на CLI.

Полный help: `docker compose run --rm vector-index --help`
(или `agent-run --help`) — там все поля с описаниями.

#### vector-index — индексатор ChromaDB

`persist_path` уже задан в `[ext.chromadb]` config.toml, его на CLI
передавать не нужно.

```bash
# Список коллекций
docker compose run --rm vector-index \
    --vector-index-action list

# Проиндексировать директорию в коллекцию
docker compose run --rm vector-index \
    --vector-index-action index \
    --vector-index-paths /app/local/docs \
    --vector-index-collection docs \
    --vector-index-description "Документация продукта"

# Несколько путей — CSV
docker compose run --rm vector-index \
    --vector-index-action index \
    --vector-index-paths /app/local/docs,/app/local/prompts \
    --vector-index-collection mixed

# Удалить коллекцию (без интерактивного подтверждения)
docker compose run --rm vector-index \
    --vector-index-action delete \
    --vector-index-collection docs \
    --vector-index-confirm-skip true

# Verbose-логирование (1=INFO, 2=DEBUG)
docker compose run --rm vector-index \
    --vector-index-action list \
    --vector-index-verbose 1
```

Чтобы индексировать локальные файлы — положите их в
`boba-artifacts/local/docs/` (или любую папку под `local/`),
внутри контейнера они будут доступны под `/app/local/...`.

#### agent-run — одиночный запрос или REPL

`model` — **обязательное поле**. Если задать его в config.toml
как `[agent_run] model = "qwen3"`, на CLI можно не указывать.

```bash
# Одиночный запрос (-T отключает TTY-аллокацию для не-интерактива)
docker compose run --rm -T agent-run \
    --agent-run-model qwen3 \
    --agent-run-query "Привет"

# Запрос с sampling-параметрами
docker compose run --rm -T agent-run \
    --agent-run-model qwen3.5-35b \
    --agent-run-query "Объясни RAG" \
    --agent-run-temperature 0.2 \
    --agent-run-max-tokens 800

# REPL (query не задан → интерактивный цикл)
docker compose run --rm agent-run \
    --agent-run-model qwen3
# »  /exit, /quit, :q — выход
# »  /clear           — сбросить историю
```

`vector-index` и `agent-run` помечены `profiles: ["cli"]` — они НЕ
стартуют при `docker compose up`, только через `run --rm <name>`.

## Команды

```bash
docker compose build                       # пересобрать runtime-образ
docker compose up -d chainlit              # daemon UI
docker compose logs -f chainlit            # логи UI
docker compose run --rm <cli-name> args... # одиночный CLI-запуск
docker compose down                        # остановить daemon-сервисы
```
