# Boba — runtime Dockerfile

FROM boba-base:latest AS deps

COPY boba/requirements.txt /tmp/requirements.txt
COPY boba-artifacts/wheels/           /tmp/wheels/

# traceloop-sdk (dep chainlit→literalai) тянет ~38 opentelemetry-instrumentation-*
# пакетов для трейсинга OpenAI/Anthropic/Langchain/etc. Из них обязательны
# при импорте только `logging` и `threading` — остальные грузятся лениво
# в try/except внутри Traceloop.init(). Сносим ~35 неиспользуемых
# после установки, чтобы не раздувать рантайм-образ.
RUN pip3 install --no-cache-dir --no-index \
      --find-links=/tmp/wheels \
      -r /tmp/requirements.txt \
 && pip3 list --format=freeze \
      | grep -E '^opentelemetry-instrumentation-' \
      | cut -d= -f1 \
      | grep -vxE 'opentelemetry-instrumentation-logging|opentelemetry-instrumentation-threading|opentelemetry-instrumentation' \
      | xargs -r pip3 uninstall -y

FROM boba-base:latest

COPY boba-artifacts/local/pip.conf /etc/pip.conf

COPY --from=deps /opt/python3.11/lib/python3.11/site-packages /opt/python3.11/lib/python3.11/site-packages
COPY --from=deps /opt/python3.11/bin                          /opt/python3.11/bin

COPY boba/src/domain/src/boba/     /app/src/domain/src/boba/
COPY boba/src/app/src/boba/        /app/src/app/src/boba/
COPY boba/src/adapters/src/boba/   /app/src/adapters/src/boba/
COPY boba/src/infra/src/boba/      /app/src/infra/src/boba/
COPY boba/src/chainlit/src/boba/   /app/src/chainlit/src/boba/

# Статический chainlit UI-конфиг (brand name, file upload limits, telemetry off).
# Не tunable per-deployment — бейкаем в образ. Chainlit регенерирует
# translations/ внутри этой папки на старте.
COPY boba/src/chainlit/.chainlit/  /app/chainlit/.chainlit/

ENV PYTHONPATH="/app/src/domain/src:/app/src/app/src:/app/src/adapters/src:/app/src/infra/src:/app/src/chainlit/src"

WORKDIR /app/chainlit
EXPOSE 8501
CMD ["python3", "-m", "boba.chainlit"]
