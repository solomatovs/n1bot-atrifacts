# Boba — runtime Dockerfile.
#
# Один образ для всего монорепо: core (patterns/settings/workspace/
# indexing/tools/llm/agent) + infra (llm-openai/format-html|kbdoc|
# markdown|text/transport-fs|http/db-postgres) + tools-плагины
# (files/kb/postgres/shell) + agents (cli-agent + chainlit-agent).
# Что именно запускается — выбирается на стороне docker-compose.yml
# через ``entrypoint:``/``command:`` для каждого service'а.
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
      /tmp/boba/packages/core/boba-settings \
      /tmp/boba/packages/core/boba-workspace \
      /tmp/boba/packages/core/boba-indexing \
      /tmp/boba/packages/core/boba-tools \
      /tmp/boba/packages/core/boba-llm \
      /tmp/boba/packages/core/boba-agent \
      /tmp/boba/packages/infra/llm/boba-openai \
      /tmp/boba/packages/infra/format/boba-html \
      /tmp/boba/packages/infra/format/boba-kbdoc \
      /tmp/boba/packages/infra/format/boba-markdown \
      /tmp/boba/packages/infra/format/boba-text \
      /tmp/boba/packages/infra/transport/boba-transport-fs \
      /tmp/boba/packages/infra/transport/boba-transport-http \
      /tmp/boba/packages/infra/db/boba-db-postgres \
      /tmp/boba/packages/tools/boba-tool-files \
      /tmp/boba/packages/tools/boba-tool-kb \
      /tmp/boba/packages/tools/boba-tool-postgres \
      /tmp/boba/packages/tools/boba-tool-shell \
      /tmp/boba/packages/agents/boba-cli-agent \
      /tmp/boba/packages/agents/boba-chainlit-agent \
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
      boba-markdown \
      boba-text \
      boba-transport-fs \
      boba-transport-http \
      boba-db-postgres \
      boba-tool-files \
      boba-tool-kb \
      boba-tool-postgres \
      boba-tool-shell \
      boba-cli-agent \
      boba-chainlit-agent

FROM boba-base:latest

COPY boba-artifacts/local/pip.conf /etc/pip.conf

COPY --from=deps /opt/python3.11/lib/python3.11/site-packages /opt/python3.11/lib/python3.11/site-packages
COPY --from=deps /opt/python3.11/bin                          /opt/python3.11/bin

# Порядок не важен для --no-deps, но соблюдаем топологию ради
# читабельности: core → infra → tools → agents. Внутри namespace-пакета
# ``boba.*`` каждый дистрибутив добавляет свои подпакеты
# (boba.patterns, boba.settings, boba.workspace, boba.indexing,
#  boba.tools, boba.llm, boba.agent, boba.provider.openai,
#  boba.format.{html,kbdoc,markdown,text}, boba.transport.{fs,http},
#  boba.db.postgres, boba.tool.{files,kb,postgres,shell},
#  boba.cli.agent_run, boba.web.chainlit).

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
COPY boba/packages/tools/boba-tool-files/          /app/packages/tools/boba-tool-files/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-files

COPY boba/packages/tools/boba-tool-kb/             /app/packages/tools/boba-tool-kb/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-kb

COPY boba/packages/tools/boba-tool-postgres/       /app/packages/tools/boba-tool-postgres/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-postgres

COPY boba/packages/tools/boba-tool-shell/          /app/packages/tools/boba-tool-shell/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/tools/boba-tool-shell

# --- agents (entry-point apps) ---
COPY boba/packages/agents/boba-cli-agent/          /app/packages/agents/boba-cli-agent/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/agents/boba-cli-agent

COPY boba/packages/agents/boba-chainlit-agent/     /app/packages/agents/boba-chainlit-agent/
RUN pip3 install --no-cache-dir --no-deps          /app/packages/agents/boba-chainlit-agent

WORKDIR /app
EXPOSE 8501

CMD ["boba-chainlit-agent"]
