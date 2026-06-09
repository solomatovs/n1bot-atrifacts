# runtime Dockerfile

FROM boba-base:latest AS deps

# pip.conf
COPY local/pip.conf* /tmp/pipconf/
RUN if [ -f /tmp/pipconf/pip.conf ]; then cp /tmp/pipconf/pip.conf /etc/pip.conf; fi && rm -rf /tmp/pipconf
COPY wheels/         /tmp/wheels/

# copy from sources
COPY --from=boba packages/ /tmp/boba/packages/

# deps offline install
RUN pip3 install --no-cache-dir --no-index --find-links=/tmp/wheels \
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

# опц. pip.conf (glob *.example всегда матчится — COPY не падает без файла)
COPY local/pip.conf* /tmp/pipconf/
RUN if [ -f /tmp/pipconf/pip.conf ]; then cp /tmp/pipconf/pip.conf /etc/pip.conf; fi && rm -rf /tmp/pipconf
COPY wheels/ /tmp/wheels/

COPY --from=deps /opt/python3.11/lib/python3.11/site-packages /opt/python3.11/lib/python3.11/site-packages
COPY --from=deps /opt/python3.11/bin                          /opt/python3.11/bin

# core
COPY --from=boba packages/core/boba-patterns/             /app/packages/core/boba-patterns/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/core/boba-patterns

COPY --from=boba packages/core/boba-settings/             /app/packages/core/boba-settings/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/core/boba-settings

COPY --from=boba packages/core/boba-workspace/            /app/packages/core/boba-workspace/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/core/boba-workspace

COPY --from=boba packages/core/boba-indexing/             /app/packages/core/boba-indexing/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/core/boba-indexing

COPY --from=boba packages/core/boba-tools/                /app/packages/core/boba-tools/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/core/boba-tools

COPY --from=boba packages/core/boba-llm/                  /app/packages/core/boba-llm/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/core/boba-llm

COPY --from=boba packages/core/boba-agent/                /app/packages/core/boba-agent/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/core/boba-agent

# infra
COPY --from=boba packages/infra/llm/boba-openai/          /app/packages/infra/llm/boba-openai/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/infra/llm/boba-openai

COPY --from=boba packages/infra/format/boba-html/         /app/packages/infra/format/boba-html/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/infra/format/boba-html

COPY --from=boba packages/infra/format/boba-kbdoc/        /app/packages/infra/format/boba-kbdoc/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/infra/format/boba-kbdoc

COPY --from=boba packages/infra/format/boba-liteparse/    /app/packages/infra/format/boba-liteparse/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/infra/format/boba-liteparse

COPY --from=boba packages/infra/format/boba-markdown/     /app/packages/infra/format/boba-markdown/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/infra/format/boba-markdown

COPY --from=boba packages/infra/format/boba-text/         /app/packages/infra/format/boba-text/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/infra/format/boba-text

COPY --from=boba packages/infra/transport/boba-transport-fs/   /app/packages/infra/transport/boba-transport-fs/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels               /app/packages/infra/transport/boba-transport-fs

COPY --from=boba packages/infra/transport/boba-transport-http/ /app/packages/infra/transport/boba-transport-http/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels               /app/packages/infra/transport/boba-transport-http

COPY --from=boba packages/infra/db/boba-db-postgres/      /app/packages/infra/db/boba-db-postgres/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/infra/db/boba-db-postgres

# tools (boba.plugins entry-points)
COPY --from=boba packages/tools/boba-tool-chart/          /app/packages/tools/boba-tool-chart/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/tools/boba-tool-chart

COPY --from=boba packages/tools/boba-tool-doc/            /app/packages/tools/boba-tool-doc/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/tools/boba-tool-doc

COPY --from=boba packages/tools/boba-tool-files/          /app/packages/tools/boba-tool-files/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/tools/boba-tool-files

COPY --from=boba packages/tools/boba-tool-kb/             /app/packages/tools/boba-tool-kb/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/tools/boba-tool-kb

COPY --from=boba packages/tools/boba-tool-postgres/       /app/packages/tools/boba-tool-postgres/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/tools/boba-tool-postgres

COPY --from=boba packages/tools/boba-tool-shell/          /app/packages/tools/boba-tool-shell/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/tools/boba-tool-shell

COPY --from=boba packages/tools/boba-tool-web/            /app/packages/tools/boba-tool-web/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/tools/boba-tool-web

# agents
COPY --from=boba packages/agents/boba-cli/                /app/packages/agents/boba-cli/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/agents/boba-cli

COPY --from=boba packages/agents/boba-chainlit/           /app/packages/agents/boba-chainlit/
RUN pip3 install --no-cache-dir --no-deps --no-index --find-links=/tmp/wheels          /app/packages/agents/boba-chainlit

# OCR-модели
COPY tessdata/ /opt/tessdata/
ENV TESSDATA_PREFIX=/opt/tessdata \
    TESSDATA_PATH=/opt/tessdata

# liteparse 2.0 hotfix, rus+eng link
RUN ln -sf eng.traineddata /opt/tessdata/rus+eng.traineddata && \
    ln -sf rus.traineddata /opt/tessdata/eng+rus.traineddata

WORKDIR /app
EXPOSE 8501

CMD ["boba-chainlit"]
