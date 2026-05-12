# Boba — runtime Dockerfile.
#
# Один образ для всего монорепо: core (patterns/schema/config/plugin/
# workspace/indexing/tools/llm/agent) + infra (config-toml/llm-openai/
# format-html|markdown|text/transport-fs|http/db-postgres) + tools-плагины
# (chromadb/confluence/files/html/postgres-fts) + agents (cli-agent +
# chainlit-agent). Что именно запускается — выбирается на стороне
# docker-compose.yml через ``entrypoint:``/``command:`` для каждого
# service'а.
#
# Зависимости приходят декларативно из ``packages/<group>/<name>/
# pyproject.toml``. Offline build остаётся: pip ходит за wheel'ами
# через ``--find-links=/tmp/wheels`` (mirror подготавливается в
# boba-artifacts/wheels), а pip.conf конфигурирует внутренний index.

FROM boba-base:latest AS deps

COPY boba-artifacts/local/pip.conf  /etc/pip.conf
COPY boba-artifacts/wheels/         /tmp/wheels/

# Копируем пакеты целиком: setuptools.packages.find в каждом pyproject
# смотрит на реальный src/-каталог, поэтому одних pyproject.toml не
# хватает — egg_info проверяет существование src/boba* на диске.
COPY boba/packages/ /tmp/boba/packages/

# Ставим наши пакеты со всеми транзитивами, потом удаляем metadata
# самих наших пакетов: их исходники едут в финальный stage и ставятся
# там no-deps. Транзитивы остаются в site-packages — копируются дальше.
RUN pip3 install --no-cache-dir --find-links=/tmp/wheels \
      /tmp/boba/packages/core/boba-patterns \
      /tmp/boba/packages/core/boba-schema \
      /tmp/boba/packages/core/boba-config \
      /tmp/boba/packages/core/boba-plugin \
      /tmp/boba/packages/core/boba-workspace \
      /tmp/boba/packages/core/boba-indexing \
      /tmp/boba/packages/core/boba-tools \
      /tmp/boba/packages/core/boba-llm \
      /tmp/boba/packages/core/boba-agent \
      /tmp/boba/packages/infra/config/boba-config-toml \
      /tmp/boba/packages/infra/llm/boba-openai \
      /tmp/boba/packages/infra/format/boba-html \
      /tmp/boba/packages/infra/format/boba-markdown \
      /tmp/boba/packages/infra/format/boba-text \
      /tmp/boba/packages/infra/transport/boba-transport-fs \
      /tmp/boba/packages/infra/transport/boba-transport-http \
      /tmp/boba/packages/infra/db/boba-db-postgres \
      /tmp/boba/packages/tools/boba-tool-chromadb \
      /tmp/boba/packages/tools/boba-tool-confluence \
      /tmp/boba/packages/tools/boba-tool-files \
      /tmp/boba/packages/tools/boba-tool-html \
      /tmp/boba/packages/tools/boba-tool-postgres-fts \
      /tmp/boba/packages/agents/boba-cli-agent \
      /tmp/boba/packages/agents/boba-chainlit-agent \
 && pip3 uninstall -y \
      boba-patterns \
      boba-schema \
      boba-config \
      boba-plugin \
      boba-workspace \
      boba-indexing \
      boba-tools \
      boba-llm \
      boba-agent \
      boba-config-toml \
      boba-openai \
      boba-html \
      boba-markdown \
      boba-text \
      boba-transport-fs \
      boba-transport-http \
      boba-db-postgres \
      boba-tool-chromadb \
      boba-tool-confluence \
      boba-tool-files \
      boba-tool-html \
      boba-tool-postgres-fts \
      boba-cli-agent \
      boba-chainlit-agent

FROM boba-base:latest

COPY boba-artifacts/local/pip.conf /etc/pip.conf

COPY --from=deps /opt/python3.11/lib/python3.11/site-packages /opt/python3.11/lib/python3.11/site-packages
COPY --from=deps /opt/python3.11/bin                          /opt/python3.11/bin

# Порядок не важен для --no-deps, но соблюдаем топологию ради
# читабельности: core → infra → tools → agents. Внутри namespace-пакета
# ``boba.*`` каждый дистрибутив добавляет свои подпакеты
# (boba.patterns, boba.schema, boba.config, boba.plugin, boba.workspace,
#  boba.indexing, boba.tools, boba.llm, boba.agent,
#  boba.config.source.toml, boba.provider.openai,
#  boba.format.{html,markdown,text}, boba.transport.{fs,http},
#  boba.db.postgres, boba.tool.{chromadb,confluence,files,html,postgres_fts},
#  boba.cli.agent_run, boba.web.chainlit).

# --- core ---
COPY boba/packages/core/boba-patterns/             /app/packages/core/boba-patterns/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-patterns

COPY boba/packages/core/boba-schema/               /app/packages/core/boba-schema/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-schema

COPY boba/packages/core/boba-config/               /app/packages/core/boba-config/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-config

COPY boba/packages/core/boba-plugin/               /app/packages/core/boba-plugin/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/core/boba-plugin

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
COPY boba/packages/infra/config/boba-config-toml/  /app/packages/infra/config/boba-config-toml/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/config/boba-config-toml

COPY boba/packages/infra/llm/boba-openai/          /app/packages/infra/llm/boba-openai/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/llm/boba-openai

COPY boba/packages/infra/format/boba-html/         /app/packages/infra/format/boba-html/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/infra/format/boba-html

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
COPY boba/packages/tools/boba-tool-chromadb/       /app/packages/tools/boba-tool-chromadb/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-chromadb

COPY boba/packages/tools/boba-tool-confluence/     /app/packages/tools/boba-tool-confluence/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-confluence

COPY boba/packages/tools/boba-tool-files/          /app/packages/tools/boba-tool-files/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-files

COPY boba/packages/tools/boba-tool-html/           /app/packages/tools/boba-tool-html/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-html

COPY boba/packages/tools/boba-tool-postgres-fts/   /app/packages/tools/boba-tool-postgres-fts/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-postgres-fts

# --- agents (entry-point apps) ---
COPY boba/packages/agents/boba-cli-agent/          /app/packages/agents/boba-cli-agent/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/agents/boba-cli-agent

COPY boba/packages/agents/boba-chainlit-agent/     /app/packages/agents/boba-chainlit-agent/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/agents/boba-chainlit-agent

WORKDIR /app
EXPOSE 8501

CMD ["boba-chainlit-agent"]
