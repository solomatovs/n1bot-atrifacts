# Boba — runtime Dockerfile.

FROM boba-base:latest AS deps

COPY boba-artifacts/local/pip.conf  /etc/pip.conf
COPY boba-artifacts/wheels/         /tmp/wheels/

# нужны реальные src/-каталоги: setuptools.packages.find/egg_info их проверяет
COPY boba/packages/ /tmp/boba/packages/

# stage deps: ставим пакеты с транзитивами (offline, из /tmp/wheels), затем
# сносим metadata наших пакетов — исходники едут в финальный stage (no-deps).
# Транзитивы остаются в site-packages и копируются дальше.
RUN pip3 install --no-cache-dir --find-links=/tmp/wheels \
      /tmp/boba/packages/core/boba-patterns \
      /tmp/boba/packages/core/boba-settings \
      /tmp/boba/packages/core/boba-workspace \
      /tmp/boba/packages/core/boba-indexing \
      /tmp/boba/packages/core/boba-tools \
      /tmp/boba/packages/core/boba-llm \
      /tmp/boba/packages/core/boba-agent \
      /tmp/boba/packages/infra/llm/boba-openai \
      /tmp/boba/packages/infra/format/boba-html \
      /tmp/boba/packages/infra/format/boba-kbdoc \
      /tmp/boba/packages/infra/format/boba-liteparse \
      /tmp/boba/packages/infra/format/boba-markdown \
      /tmp/boba/packages/infra/format/boba-text \
      /tmp/boba/packages/infra/transport/boba-transport-fs \
      /tmp/boba/packages/infra/transport/boba-transport-http \
      /tmp/boba/packages/infra/db/boba-db-postgres \
      /tmp/boba/packages/tools/boba-tool-chart \
      /tmp/boba/packages/tools/boba-tool-doc \
      /tmp/boba/packages/tools/boba-tool-files \
      /tmp/boba/packages/tools/boba-tool-kb \
      /tmp/boba/packages/tools/boba-tool-postgres \
      /tmp/boba/packages/tools/boba-tool-shell \
      /tmp/boba/packages/tools/boba-tool-web \
      /tmp/boba/packages/agents/boba-cli \
      /tmp/boba/packages/agents/boba-chainlit \
 && pip3 uninstall -y \
      boba-patterns \
      boba-settings \
      boba-workspace \
      boba-indexing \
      boba-tools \
      boba-llm \
      boba-agent \
      boba-openai \
      boba-html \
      boba-kbdoc \
      boba-liteparse \
      boba-markdown \
      boba-text \
      boba-transport-fs \
      boba-transport-http \
      boba-db-postgres \
      boba-tool-chart \
      boba-tool-doc \
      boba-tool-files \
      boba-tool-kb \
      boba-tool-postgres \
      boba-tool-shell \
      boba-tool-web \
      boba-cli \
      boba-chainlit

FROM boba-base:latest

COPY boba-artifacts/local/pip.conf /etc/pip.conf

COPY --from=deps /opt/python3.11/lib/python3.11/site-packages /opt/python3.11/lib/python3.11/site-packages
COPY --from=deps /opt/python3.11/bin                          /opt/python3.11/bin

# --no-deps: транзитивы уже в site-packages из stage deps. Порядок core ->
# infra -> tools -> agents — только ради читабельности.

# --- core ---
COPY boba/packages/core/boba-patterns/             /app/packages/core/boba-patterns/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-patterns

COPY boba/packages/core/boba-settings/             /app/packages/core/boba-settings/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-settings

COPY boba/packages/core/boba-workspace/            /app/packages/core/boba-workspace/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-workspace

COPY boba/packages/core/boba-indexing/             /app/packages/core/boba-indexing/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-indexing

COPY boba/packages/core/boba-tools/                /app/packages/core/boba-tools/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-tools

COPY boba/packages/core/boba-llm/                  /app/packages/core/boba-llm/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-llm

COPY boba/packages/core/boba-agent/                /app/packages/core/boba-agent/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-agent

# --- infra ---
COPY boba/packages/infra/llm/boba-openai/          /app/packages/infra/llm/boba-openai/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/llm/boba-openai

COPY boba/packages/infra/format/boba-html/         /app/packages/infra/format/boba-html/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/format/boba-html

COPY boba/packages/infra/format/boba-kbdoc/        /app/packages/infra/format/boba-kbdoc/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/format/boba-kbdoc

COPY boba/packages/infra/format/boba-liteparse/    /app/packages/infra/format/boba-liteparse/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/format/boba-liteparse

COPY boba/packages/infra/format/boba-markdown/     /app/packages/infra/format/boba-markdown/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/format/boba-markdown

COPY boba/packages/infra/format/boba-text/         /app/packages/infra/format/boba-text/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/format/boba-text

COPY boba/packages/infra/transport/boba-transport-fs/   /app/packages/infra/transport/boba-transport-fs/
RUN pip3 install --no-cache-dir --no-deps               /app/packages/infra/transport/boba-transport-fs

COPY boba/packages/infra/transport/boba-transport-http/ /app/packages/infra/transport/boba-transport-http/
RUN pip3 install --no-cache-dir --no-deps               /app/packages/infra/transport/boba-transport-http

COPY boba/packages/infra/db/boba-db-postgres/      /app/packages/infra/db/boba-db-postgres/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/db/boba-db-postgres

# --- tools (boba.plugins entry-points) ---
COPY boba/packages/tools/boba-tool-chart/          /app/packages/tools/boba-tool-chart/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-chart

COPY boba/packages/tools/boba-tool-doc/            /app/packages/tools/boba-tool-doc/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-doc

COPY boba/packages/tools/boba-tool-files/          /app/packages/tools/boba-tool-files/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-files

COPY boba/packages/tools/boba-tool-kb/             /app/packages/tools/boba-tool-kb/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-kb

COPY boba/packages/tools/boba-tool-postgres/       /app/packages/tools/boba-tool-postgres/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-postgres

COPY boba/packages/tools/boba-tool-shell/          /app/packages/tools/boba-tool-shell/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-shell

COPY boba/packages/tools/boba-tool-web/            /app/packages/tools/boba-tool-web/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-web

# --- agents (entry-point apps) ---
COPY boba/packages/agents/boba-cli/                /app/packages/agents/boba-cli/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/agents/boba-cli

COPY boba/packages/agents/boba-chainlit/           /app/packages/agents/boba-chainlit/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/agents/boba-chainlit

# OCR-модели *.traineddata (offline, см. README 2b). tesseract — в wheel liteparse.
# boba не передаёт tessdata_path, путь отдаём через env: TESSDATA_PATH (wrapper
# liteparse) + TESSDATA_PREFIX (движок tesseract, fallback).
COPY boba-artifacts/tessdata/ /opt/tessdata/
ENV TESSDATA_PREFIX=/opt/tessdata \
    TESSDATA_PATH=/opt/tessdata

# liteparse 2.0.x: ensure_traineddata НЕ разбивает ocr_language по '+' и для
# "rus+eng" ищет один файл rus+eng.traineddata, не находит -> качает его с
# github -> HTTP 404 (offline тем более). Сам tesseract api.init("rus+eng")
# при этом корректно бьёт строку по '+' и грузит rus/eng по отдельности.
# Обходим: создаём симлинк-маркер на склеенное имя, чтобы проверка существования
# прошла и скачивание не запускалось. Линкуем оба порядка (rus+eng / eng+rus).
RUN ln -sf eng.traineddata /opt/tessdata/rus+eng.traineddata && \
    ln -sf rus.traineddata /opt/tessdata/eng+rus.traineddata

WORKDIR /app
EXPOSE 8501

CMD ["boba-chainlit"]
