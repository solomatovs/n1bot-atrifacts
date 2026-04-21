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
├── local/                   # все локальные оверрайды (*.example — в git, реальные — не в git):
│   ├── apt-sources.list  # override apt-репо (пустой = дефолт rootfs)
│   ├── ca-chain.crt      # корпоративные CA (PEM, пустой = public-only)
│   ├── env.secrets       # LITELLM_API_KEY, CONFLUENCE_TOKEN, CHAINLIT_AUTH_SECRET
│   ├── env.tunables      # LLM_BASE_URL, CHAINLIT_MODELS, CHAINLIT_ROOT_PATH, …
│   └── pip.conf          # /etc/pip.conf внутри рантайма (для отладки)
├── gcc-src/, glibc-src/,
│   python-src/              # исходники для Dockerfile.base
├── wheels/                  # pre-downloaded .whl (generated командой из Шага 2)
├── images/                  # экспорт `docker save` (generated, не в git)
├── Dockerfile               # runtime (на основе boba-base)
├── Dockerfile.base          # сборка glibc+gcc+python из astra_linux_ce
└── docker-compose.yml
```

В `local/` все файлы с суффиксом `.example` коммитятся, без суффикса — загитигнорены
(коммитим только шаблоны).

## 0. Локальные конфиги и секреты из шаблонов

Всё локальное — в `local/`, коммитим только `*.example`. Перед первым
билдом скопируйте шаблоны в рабочие имена:

```bash
cd boba-artifacts
for f in local/*.example; do cp -n "$f" "${f%.example}"; done
```

## 1. Base-образ (разово, ~30 мин)

Использует `local/apt-sources.list` (закрытый контур — пропишите свои
зеркала, пустой файл = дефолт rootfs; GPG-ключи не нужны) и
`local/ca-chain.crt` (PEM-цепочка корпоративных CA; без `BEGIN CERTIFICATE`
блоков — no-op, доверяем только public CA из rootfs):

```bash
cd boba-artifacts
docker build -f Dockerfile.base -t boba-base:latest .
```

## 2. Build wheels (после правки `../boba/requirements.txt`)

Top-level runtime-зависимости живут в исходниках — `../boba/requirements.txt`.
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
    pip3 wheel --no-cache-dir \
        -r /boba/requirements.txt \
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
    pip3 wheel --no-cache-dir \
        -r /boba/requirements.txt \
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
`pip install --no-index --find-links=../boba-artifacts/wheels -r requirements.txt`
(внутри билд-контекста `boba/requirements.txt`).

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

Секреты и настройки — runtime-зависимости, нужны только на `up`.
Приложение читает всё из env (приоритет выше любого code-дефолта).

```bash
cd boba-artifacts
# local/env.secrets   — заполните реальными значениями:
#   LITELLM_API_KEY, CONFLUENCE_TOKEN,
#   CHAINLIT_AUTH_SECRET (для последнего: openssl rand -hex 32)
# local/env.tunables  — дефолты deployment-specific:
#   LLM_BASE_URL=http://litellm:4000, CHAINLIT_ROOT_PATH=/boba,
#   CHAINLIT_MODELS=… (CSV), и опциональные AGENT_*/LLM_*/LOG_* (см. файл)
docker compose up -d
```

## Команды

```bash
docker compose build     # пересобрать runtime
docker compose up -d     # запустить
docker compose logs -f   # логи
docker compose down      # остановить
```
