# boba-artifacts

Сборочный проект для `boba` (Astra Linux CE + glibc 2.28 + Python 3.11).
Должен лежать рядом с `boba/`:

```
<parent>/
├── boba/             # исходники (monorepo)
└── boba-artifacts/   # этот репо
```

## Структура

```
boba-artifacts/
├── local/                 # *.example — в git, без суффикса — gitignored
│   ├── .env               # URL'ы LLM + секреты (читается docker-compose)
│   ├── config.toml        # настройки приложения (см. config.toml.example)
│   ├── apt-sources.list   # override apt-репо (пусто = дефолт)
│   ├── ca-chain.crt       # корпоративные CA (PEM)
│   ├── pip.conf           # /etc/pip.conf внутри рантайма
│   ├── nginx-boba.conf    # reverse-proxy include
│   ├── prompts/, prompts.example/
│   ├── workspaces/, chainlit/, cache/, logs/
├── wheels/                # pre-downloaded .whl (см. шаг 2)
├── tessdata/              # *.traineddata для OCR liteparse (см. шаг 2b)
├── images/                # docker save → .tar.gz (gitignored)
├── gcc-src/, glibc-src/, python-src/   # для Dockerfile.base
├── Dockerfile             # runtime (FROM boba-base)
├── Dockerfile.base        # glibc+gcc+python из astra_linux_ce
└── docker-compose.yml     # chainlit (daemon), cli-agent (profile=cli)
```

`docker-compose` монтирует `boba-artifacts/local/` как `/app/local` в контейнер.

## 0. Конфиги из шаблонов

```bash
cd boba-artifacts
for f in local/*.example; do cp -n "$f" "${f%.example}"; done
cp -rn local/prompts.example local/prompts
# отредактировать local/.env       — BOBA_*__BASE_URL, *__API_KEY, *__AUTH_SECRET, *__PASSWORD
# отредактировать local/config.toml — model, postgres.main.*, профили, tool-флаги
```

Приоритет источников: CLI > env > TOML. Env-конвенция: `BOBA_<SEG>__<SEG>__<FIELD>`.

## 1. Base-образ (разово, ~30 мин)

```bash
docker build -f Dockerfile.base -t boba-base:latest .
```

## 2. Build wheels (после правки `../boba/packages/`)

Открытый контур:

```bash
docker run --rm \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$(pwd)":/artifacts \
  -v "$(pwd)/../boba":/boba:ro \
  -w /artifacts \
  --entrypoint sh boba-base:latest -c '
    set -e
    rm -rf wheels && mkdir wheels
    cp -r /boba/packages /tmp/packages
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
        /tmp/packages/tools/boba-tool-doc \
        /tmp/packages/tools/boba-tool-files \
        /tmp/packages/tools/boba-tool-kb \
        /tmp/packages/tools/boba-tool-postgres \
        /tmp/packages/tools/boba-tool-shell \
        /tmp/packages/tools/boba-tool-web \
        /tmp/packages/agents/boba-cli-agent \
        /tmp/packages/agents/boba-chainlit-agent \
        pip setuptools wheel \
        -w wheels/
    chown -R "$HOST_UID:$HOST_GID" wheels
  '
```

Закрытый контур — то же, но прокинуть `-v "$(pwd)/local/pip.conf":/etc/pip.conf:ro` и
прописать в `local/pip.conf` `index-url`/`extra-index-url`/`trusted-host`.

> `boba-tool-doc` тянет стороннюю зависимость `liteparse` (бинарный wheel
> `manylinux_2_28`, `cp311`). В открытом контуре она скачается в `wheels/`
> вместе с остальным; в закрытом — должна быть в вашем индексе/зеркале.
> Требует glibc ≥ 2.28 (base даёт ровно 2.28 — после сборки проверьте
> `docker run --rm boba:latest python3 -c "import liteparse"`).

## 2b. Tesseract-модели для OCR (для `boba-tool-doc`)

`boba-tool-doc` парсит PDF/DOCX/XLSX/изображения через liteparse. Для
сканов и картинок нужен OCR; сам движок Tesseract уже внутри wheel
liteparse — нужны только языковые модели `*.traineddata`. Скачать их
(на машине с доступом к github) в `tessdata/`; на build они копируются
в образ (`COPY` в `Dockerfile` → `/opt/tessdata`, `TESSDATA_PREFIX`):

```bash
cd boba-artifacts
mkdir -p tessdata
base=https://github.com/tesseract-ocr/tessdata_best/raw/main
for lang in eng rus osd; do
  curl -fSL -o "tessdata/$lang.traineddata" "$base/$lang.traineddata"
done
```

- `tessdata_best` — максимальная точность (eng+rus+osd ≈ 41 МБ), но
  медленнее. Для скорости — `tessdata_fast` (тот же путь, файлы меньше).
- Языки добавляются в список `for lang in …` (имя = код Tesseract).
- OCR включается в `local/config.toml`: `[tool.doc].ocr_enabled = true`
  (язык — `[tool.doc].ocr_language`, например `rus+eng`).
- OCR не нужен (только текстовый слой PDF) — `tessdata/` оставляют пустой
  (там лежит `.gitkeep`); папка обязана существовать, иначе `COPY` упадёт.

## 3. Build runtime (оффлайн, по `wheels/`)

```bash
docker compose build
```

## 4. Save images (для air-gapped переноса)

```bash
mkdir -p images
docker save boba-base:latest | gzip > images/boba-base.tar.gz
docker save boba:latest      | gzip > images/boba.tar.gz
```

На целевом хосте:

```bash
docker load --input images/boba-base.tar.gz
docker load --input images/boba.tar.gz
```

## 5. Run

### Chainlit UI (daemon)

```bash
docker compose up -d chainlit
docker compose logs -f chainlit
```

### Ad-hoc CLI агент

`model` — обязательно. Если задан в `[cli.agent].model` — на CLI можно не указывать.
Пустой `query` → REPL, заданный → single-shot.

```bash
# Single-shot (-T отключает TTY)
docker compose run --rm -T cli-agent --cli.agent.query "Привет"

# REPL
docker compose run --rm cli-agent
```

### KB CLI (миграции / ingest / download)

```bash
# Применить миграции и создать HNSW-индекс
docker compose run --rm --entrypoint python cli-agent -m boba.tool.kb.cli.kb_bootstrap

# Индексировать KbDoc-папку (/app/local/docs → коллекция kb_kbdoc)
docker compose run --rm --entrypoint python cli-agent -m boba.tool.kb.cli.kbdoc.ingest

# Скачать Confluence на ФС (/app/local/downloads)
docker compose run --rm --entrypoint python cli-agent -m boba.tool.kb.cli.confluence.download.http --page-ids 950276,950278

# Индексировать скачанное в kb_confluence
docker compose run --rm --entrypoint python cli-agent -m boba.tool.kb.cli.confluence.ingest.folder
```

## Tool-плагины

Включаются через `[tool.<name>].enable = true` в `local/config.toml`.

| `[tool.<name>]` | Пакет | Tools |
|---|---|---|
| `doc`   | `boba-tool-doc`   | `read_document`, `read_pages`, `document_outline`, `search_document` — парсинг PDF/DOCX/XLSX/картинок в текст (liteparse), поиск с координатами; OCR опц. (`ocr_enabled`, см. шаг 2b) |
| `files` | `boba-tool-files` | `cat`, `ls`, `grep`, `stat`, `tree`, `append`, `read_bytes`, `unzip` (+ опц. `cd`, `cp`, `edit`, `mkdir`, `mv`, `pwd`, `rm`, `touch`, `write`) |
| `kb`    | `boba-tool-kb`    | `kb_search_hybrid`/`vector`/`fts`, `confluence_search_cql`, `confluence_list_spaces`, `confluence_ingest_{spaces,pages,cql}`, `confluence_download` (поверх postgres+pgvector) |
| `pg`    | `boba-tool-postgres` | `query`, `list_tables`, `describe_table`, `list_targets` — ad-hoc read-only SQL |
| `shell` | `boba-tool-shell` | `bash_local`, `bash_sandbox` (через bubblewrap) |
| `web`   | `boba-tool-web`   | `web_fetch`, `web_download` — HTTP с hostname-whitelist'ом |

## Профили подключений

- `[postgres.<name>]` — named postgres-профили. Использование:
  - KB-tools/CLI: `[kb.storage].profile = "<name>"` (резолвится через
    `defaults_from=("kb.storage", "postgres.{kb.storage:profile}", "embedding")`).
  - `tool.pg`: `[tool.pg].profiles = ["<name>", ...]` — LLM указывает имя в `target=`.
- `[web.<name>]` (hostname + auth) — `[tool.web].profiles = ["<name>", ...]`;
  tool автоматически матчит по hostname URL'а.

Переключить целевой postgres-профиль для KB без правки TOML:
`BOBA_KB__STORAGE__PROFILE=replica`.

## Команды

```bash
docker compose build                                              # пересобрать runtime
docker compose up -d chainlit                                     # daemon UI
docker compose logs -f chainlit                                   # логи UI
docker compose run --rm -T cli-agent ARGS...                      # одиночный CLI
docker compose run --rm cli-agent ARGS...                         # CLI REPL
docker compose run --rm --entrypoint python cli-agent -m MODULE   # KB-CLI / других modules
docker compose down                                               # остановить daemon
```
