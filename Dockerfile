# Boba — runtime Dockerfile.
#
# Один образ для всего монорепо: core (domain+infra) + web-chainlit UI +
# два CLI + adapter'ы + config-источники + tool-extension'ы. Что именно
# запускается — выбирается на стороне docker-compose.yml через
# ``command:``/``entrypoint:`` для каждого service'а.
#
# Зависимости приходят декларативно из ``packages/<name>/pyproject.toml``.
# Offline build остаётся: pip ходит за wheel'ами через
# ``--find-links=/tmp/wheels`` (mirror prepared в boba-artifacts/wheels)
# плюс pip.conf конфигурирует internal index.

FROM boba-base:latest AS deps

COPY boba-artifacts/local/pip.conf  /etc/pip.conf
COPY boba-artifacts/wheels/         /tmp/wheels/

# Копируем пакеты целиком: setuptools.package-dir в boba/pyproject.toml
# указывает на реальные src/-пути (boba — namespace-package с двумя
# src-корнями: domain + infra), поэтому одних pyproject.toml не хватает —
# egg_info проверяет существование package_dir на диске.
COPY boba/packages/ /tmp/boba/packages/

# Ставим наши пакеты со всеми транзитивами, потом удаляем metadata
# самих наших пакетов: их исходники едут в финальный stage и ставятся
# editable там. Транзитивы остаются в site-packages — копируются дальше.
RUN pip3 install --no-cache-dir --find-links=/tmp/wheels \
      /tmp/boba/packages/boba \
      /tmp/boba/packages/boba-adapter-fs-workspace \
      /tmp/boba/packages/boba-adapter-messages \
      /tmp/boba/packages/boba-adapter-openai \
      /tmp/boba/packages/boba-adapter-prompt-providers \
      /tmp/boba/packages/boba-config-cli \
      /tmp/boba/packages/boba-config-env \
      /tmp/boba/packages/boba-config-toml \
      /tmp/boba/packages/boba-ext-files \
      /tmp/boba/packages/boba-ext-chromadb \
      /tmp/boba/packages/boba-ext-confluence \
      /tmp/boba/packages/boba-ext-html \
      /tmp/boba/packages/boba-cli-agent-run \
      /tmp/boba/packages/boba-cli-vector-index \
      /tmp/boba/packages/boba-web-chainlit \
 && pip3 uninstall -y \
      boba \
      boba-adapter-fs-workspace \
      boba-adapter-messages \
      boba-adapter-openai \
      boba-adapter-prompt-providers \
      boba-config-cli \
      boba-config-env \
      boba-config-toml \
      boba-ext-files \
      boba-ext-chromadb \
      boba-ext-confluence \
      boba-ext-html \
      boba-cli-agent-run \
      boba-cli-vector-index \
      boba-web-chainlit

FROM boba-base:latest

COPY boba-artifacts/local/pip.conf /etc/pip.conf

COPY --from=deps /opt/python3.11/lib/python3.11/site-packages /opt/python3.11/lib/python3.11/site-packages
COPY --from=deps /opt/python3.11/bin                          /opt/python3.11/bin

# Порядок важен: core ставится первым, остальные импортируют его.
# Внутри namespace-пакета ``boba.*`` каждый дистрибутив добавляет
# свои подпакеты (boba.domain, boba.infra, boba.adapter.*,
# boba.config.*, boba.ext.*, boba.cli.*, boba.web.*).
COPY boba/packages/boba/                          /app/packages/boba/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba

COPY boba/packages/boba-adapter-fs-workspace/     /app/packages/boba-adapter-fs-workspace/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-adapter-fs-workspace

COPY boba/packages/boba-adapter-messages/         /app/packages/boba-adapter-messages/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-adapter-messages

COPY boba/packages/boba-adapter-openai/           /app/packages/boba-adapter-openai/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-adapter-openai

COPY boba/packages/boba-adapter-prompt-providers/ /app/packages/boba-adapter-prompt-providers/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-adapter-prompt-providers

COPY boba/packages/boba-config-cli/               /app/packages/boba-config-cli/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-config-cli

COPY boba/packages/boba-config-env/               /app/packages/boba-config-env/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-config-env

COPY boba/packages/boba-config-toml/              /app/packages/boba-config-toml/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-config-toml

COPY boba/packages/boba-ext-files/                /app/packages/boba-ext-files/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-ext-files

COPY boba/packages/boba-ext-chromadb/             /app/packages/boba-ext-chromadb/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-ext-chromadb

COPY boba/packages/boba-ext-confluence/           /app/packages/boba-ext-confluence/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-ext-confluence

COPY boba/packages/boba-ext-html/                 /app/packages/boba-ext-html/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-ext-html

COPY boba/packages/boba-cli-agent-run/            /app/packages/boba-cli-agent-run/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-cli-agent-run

COPY boba/packages/boba-cli-vector-index/         /app/packages/boba-cli-vector-index/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-cli-vector-index

COPY boba/packages/boba-web-chainlit/             /app/packages/boba-web-chainlit/
RUN pip3 install --no-cache-dir --no-deps         /app/packages/boba-web-chainlit

WORKDIR /app
EXPOSE 8501

CMD ["boba-web-chainlit"]
