# Build runtime image. Тег образа берётся из git-репозитория ИСХОДНИКОВ
# (../boba) — именно его код едет в образ:
#   - на HEAD висит git-тег   -> этот тег        (напр. v1.2.3)
#   - тега нет                -> короткий commit (напр. a1b2c3d)
#   - рабочее дерево грязное   -> суффикс -dirty
# Переопределить вручную: `make build BOBA_TAG=1.2.3`.
# Источник исходников можно сменить: `make build SRC_DIR=/path/to/boba`.

SRC_DIR ?= ../boba

GIT_TAG := $(shell git -C $(SRC_DIR) describe --tags --exact-match 2>/dev/null)
GIT_SHA := $(shell git -C $(SRC_DIR) rev-parse --short HEAD 2>/dev/null)
DIRTY   := $(shell test -n "$$(git -C $(SRC_DIR) status --porcelain 2>/dev/null)" && echo -dirty)

ifeq ($(strip $(BOBA_TAG)),)
  ifneq ($(strip $(GIT_TAG)),)
    BOBA_TAG := $(GIT_TAG)$(DIRTY)
  else
    BOBA_TAG := $(GIT_SHA)$(DIRTY)
  endif
endif

export BOBA_TAG

.DEFAULT_GOAL := help
.PHONY: help build up down print-tag write-env base wheels

help:
	@echo "Boba runtime — make-цели (тег образа: $(BOBA_TAG)):"
	@echo "  make base       собрать базовый образ boba-base (glibc 2.28 + gcc 8 + python 3.11)"
	@echo "  make wheels     пересобрать offline-wheels внутри boba-base по ../boba/packages"
	@echo "  make build      собрать runtime boba:<тег> (+ boba:latest)"
	@echo "  make up         поднять chainlit (docker compose up -d)"
	@echo "  make down       остановить (docker compose down)"
	@echo "  make print-tag  показать тег, который будет присвоен образу"
	@echo ""
	@echo "Параметры: BOBA_TAG=<тег> (запинить), SRC_DIR=<путь> (другой каталог исходников)"
	@echo "Полный цикл с нуля: make base && make wheels && make build"

# Базовый образ (glibc 2.28 + gcc 8 + python 3.11). Долгий; нужен один раз
# или при смене версий в Dockerfile.base. README шаг 1.
base:
	docker build -f Dockerfile.base -t boba-base:latest .

# Пересобрать offline-wheels внутри boba-base (glibc 2.28) по исходникам
# $(SRC_DIR)/packages — бинарники ровно под целевой образ. Требует собранного
# boba-base; pip.conf пробрасывается для закрытого контура. README шаг 2.
# Пакеты перечисляются автоматически (все каталоги с pyproject.toml).
wheels:
	docker run --rm \
	  -e HOST_UID="$$(id -u)" -e HOST_GID="$$(id -g)" \
	  -v "$$(pwd)":/artifacts \
	  -v "$(abspath $(SRC_DIR))":/boba:ro \
	  -v "$$(pwd)/local/pip.conf":/etc/pip.conf:ro \
	  -w /artifacts --entrypoint sh boba-base:latest -c '\
	    set -e; rm -rf wheels && mkdir wheels; \
	    cp -r /boba/packages /tmp/packages; \
	    pip3 wheel --no-cache-dir \
	      $$(find /tmp/packages -name pyproject.toml -printf "%h ") \
	      pip setuptools wheel -w wheels/; \
	    chown -R "$$HOST_UID:$$HOST_GID" wheels'

build: write-env
	@echo ">>> source:   $(SRC_DIR) @ $(BOBA_TAG)"
	@echo ">>> building: boba:$(BOBA_TAG)  (+ boba:latest)"
	docker compose build

up: write-env
	docker compose up -d

down:
	docker compose down

print-tag:
	@echo $(BOBA_TAG)

# Фиксируем BOBA_TAG в .env рядом с docker-compose.yml: голый
# `docker compose build/up` (без make) подхватит тот же тег через
# variable-interpolation.
write-env:
	@echo "BOBA_TAG=$(BOBA_TAG)" > .env
