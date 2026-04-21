# ============================================================
# Boba — runtime Dockerfile
#
# Требует boba-base:latest (Dockerfile.base, собирается один раз).
# Runtime-зависимости берутся оффлайн из wheels/ — см. README.
#
# Контекст сборки — родительская папка (содержит boba/ и
# boba-artifacts/). docker compose build из boba-artifacts/
# подставляет его автоматически.
# ============================================================

FROM boba-base:latest AS deps

COPY boba-artifacts/requirements.txt /tmp/requirements.txt
COPY boba-artifacts/wheels/           /tmp/wheels/

RUN pip3 install --no-cache-dir --no-index \
      --find-links=/tmp/wheels \
      -r /tmp/requirements.txt

# ============================================================
# Runtime
# ============================================================
FROM boba-base:latest

# pip config для отладки (`docker exec ... pip install ...`).
# Сама сборка им не пользуется — всё оффлайн из wheels/.
COPY boba-artifacts/pip/pip.conf /etc/pip.conf

COPY --from=deps /opt/python3.11/lib/python3.11/site-packages /opt/python3.11/lib/python3.11/site-packages
COPY --from=deps /opt/python3.11/bin                          /opt/python3.11/bin

# Монорепозиторий: boba.* — неявный namespace-пакет через PYTHONPATH.
# Файла boba/__init__.py намеренно нет — Python 3.3+ склеит namespace сам.
COPY boba/src/domain/src/boba/     /app/src/domain/src/boba/
COPY boba/src/app/src/boba/        /app/src/app/src/boba/
COPY boba/src/adapters/src/boba/   /app/src/adapters/src/boba/
COPY boba/src/infra/src/boba/      /app/src/infra/src/boba/
COPY boba/src/chainlit/src/boba/   /app/src/chainlit/src/boba/

ENV PYTHONPATH="/app/src/domain/src:/app/src/app/src:/app/src/adapters/src:/app/src/infra/src:/app/src/chainlit/src"

# chainlit ищет свой .chainlit/ относительно cwd.
WORKDIR /app/chainlit
EXPOSE 8080
CMD ["python3", "-m", "boba.chainlit"]
