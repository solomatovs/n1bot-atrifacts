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
├── apt/sources.list{,.example}   # override apt-репо (пустой = дефолт rootfs)
├── certs/ca-chain.crt{,.example} # корпоративные CA (PEM, пустой = public-only)
├── config/                       # chainlit.config.toml, config.{example.,}toml
├── gcc-src/, glibc-src/,
│   python-src/                   # исходники для Dockerfile.base
├── pip/pip.conf{,.example}       # /etc/pip.conf внутри рантайма (для отладки)
├── requirements.txt              # top-level runtime-зависимости
├── secrets/*{,.example}          # Docker secrets (реальные — не в git)
├── wheels/                       # pre-downloaded .whl (generated)
├── images/                       # экспорт `docker save` (generated, не в git)
├── Dockerfile                    # runtime (на основе boba-base)
├── Dockerfile.base               # сборка glibc+gcc+python из astra_linux_ce
└── docker-compose.yml
```

Файлы без суффикса `.example` загитигнорены — коммитим только шаблоны.

## 0. Локальные конфиги и секреты из шаблонов

Все локальные файлы (apt-репо, pip-индекс, Docker secrets, config.toml)
закоммичены как `*.example` и загитигнорены — перед первым билдом
скопируйте их в реальные имена:

```bash
cd boba-artifacts
cp -n apt/sources.list.example   apt/sources.list
cp -n certs/ca-chain.crt.example certs/ca-chain.crt
cp -n pip/pip.conf.example       pip/pip.conf
cp -n config/config.example.toml config/config.toml
for f in secrets/*.example; do cp -n "$f" "${f%.example}"; done
```

## 1. Base-образ (разово, ~30 мин)

Использует `apt/sources.list` (закрытый контур — пропишите свои зеркала,
пустой файл = дефолт rootfs; GPG-ключи не нужны) и `certs/ca-chain.crt`
(PEM-цепочка корпоративных CA; без `BEGIN CERTIFICATE` блоков — no-op,
доверяем только public CA из rootfs):

```bash
cd boba-artifacts
docker build -f Dockerfile.base -t boba-base:latest .
```

## 2. Build wheels (после правки `requirements.txt`)

Требует готовый `boba-base:latest`.

### Открытый контур (pypi.org)

```bash
cd boba-artifacts
docker run --rm \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$(pwd)":/artifacts -w /artifacts \
  --entrypoint sh boba-base:latest -c '
    set -e
    rm -rf wheels && mkdir wheels
    pip3 wheel --no-cache-dir \
        -r requirements.txt \
        pip setuptools wheel \
        -w wheels/
    chown -R "$HOST_UID:$HOST_GID" wheels
  '
```

### Закрытый контур (внутреннее PyPI-зеркало)

Пропишите `index-url`/`extra-index-url`/`trusted-host` в `pip/pip.conf` и
прокиньте его в контейнер как `/etc/pip.conf`:

```bash
cd boba-artifacts
docker run --rm \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$(pwd)":/artifacts -w /artifacts \
  -v "$(pwd)/pip/pip.conf":/etc/pip.conf:ro \
  --entrypoint sh boba-base:latest -c '
    set -e
    rm -rf wheels && mkdir wheels
    pip3 wheel --no-cache-dir \
        -r requirements.txt \
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

Ставит зависимости через
`pip install --no-index --find-links=../boba-artifacts/wheels -r requirements.txt`.

## 4. Save images (для переноса в закрытый контур)

Экспортирует готовые образы в gzip-архивы. На целевом хосте (air-gapped)
загружаются через `docker load` и дальше `docker compose up -d` работает
как обычно.

```bash
cd boba-artifacts
mkdir -p images
docker save boba-base:latest     | gzip > images/boba-base.tar.gz
docker save boba-chainlit:latest | gzip > images/boba-chainlit.tar.gz
```

Загрузка на целевом хосте:

```bash
docker load --input images/boba-base.tar.gz
docker load --input images/boba-chainlit.tar.gz
```

## 5. Run

Конфиг и секреты — runtime-зависимости, нужны только на `up`.
Заполните реальными значениями (см. Шаг 0):

```bash
cd boba-artifacts
# config/config.toml       — параметры приложения (правьте вручную)
# secrets/litellm_api_key  — LiteLLM API key
# secrets/confluence_token — Confluence API token
# secrets/chainlit_auth_secret — случайная строка, напр.:
#   openssl rand -hex 32 > secrets/chainlit_auth_secret
docker compose up -d
```

## Команды

```bash
docker compose build     # пересобрать runtime
docker compose up -d     # запустить
docker compose logs -f   # логи
docker compose down      # остановить
```

## Сервис chainlit

Наружу не выставляется: доступен внутри сети `docker` как `boba-chainlit:8080`
и публично через nginx на `https://loshara.com/boba/`. Параметры (host/port/
root_path/auth_secret/models) читаются из `[chainlit]` в `config/config.toml`.
`LITELLM_API_KEY` и `CHAINLIT_AUTH_SECRET` — через Docker secrets в `secrets/`.
Workspaces/логи — в volume'ах `chainlit-workspaces` / `chainlit-logs`.
