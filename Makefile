SRC_DIR ?= ../boba
export SRC_DIR

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
.PHONY: help build print-tag base sources tessdata fastembed wheels


GLIBC_VERSION  ?= 2.28
GCC_VERSION    ?= 8.5.0
PYTHON_VERSION ?= 3.11.12
GMP_VERSION    ?= 6.1.2
MPFR_VERSION   ?= 4.0.2
MPC_VERSION    ?= 1.1.0

# OCR-модели tesseract (make tessdata) и embedding-веса fastembed (make fastembed)
TESS_LANGS    ?= eng rus osd
TESSDATA_REPO ?= https://github.com/tesseract-ocr/tessdata_best/raw/main
EMBED_MODELS  ?= intfloat/multilingual-e5-large

help:
	@echo "Boba runtime — make-цели (тег образа: $(BOBA_TAG)):"
	@echo "  make sources    скачать тарболы glibc/gcc/gmp/mpfr/mpc/python для base (нужен инет)"
	@echo "  make tessdata   скачать OCR-модели tesseract в tessdata/ (нужен инет)"
	@echo "  make base       собрать базовый образ boba-base (glibc 2.28 + gcc 8 + python 3.11)"
	@echo "  make wheels     пересобрать offline-wheels внутри boba-base по ../boba/packages"
	@echo "                  (закрытый контур — через local/pip.conf + local/ca-chain.crt, если есть)"
	@echo "  make build      собрать runtime boba:<тег> (+ boba:latest), offline из wheels"
	@echo "  make fastembed  скачать embedding-веса в local/cache/fastembed (нужен boba:latest + инет)"
	@echo "  make print-tag  показать тег, который будет присвоен образу"
	@echo ""
	@echo "Параметры: BOBA_TAG=<тег> (запинить), SRC_DIR=<путь> (другой каталог исходников)"
	@echo "Полный цикл с нуля: make sources tessdata base wheels build fastembed"

# Скачать исходники для make base (glibc/gcc/gmp/mpfr/mpc/python)
sources:
	@mkdir -p glibc-src gcc-src python-src
	@set -e; for spec in \
	  "glibc-src/glibc-$(GLIBC_VERSION).tar.xz=https://ftp.gnu.org/gnu/glibc/glibc-$(GLIBC_VERSION).tar.xz" \
	  "gcc-src/gcc-$(GCC_VERSION).tar.xz=https://ftp.gnu.org/gnu/gcc/gcc-$(GCC_VERSION)/gcc-$(GCC_VERSION).tar.xz" \
	  "gcc-src/gmp-$(GMP_VERSION).tar.xz=https://ftp.gnu.org/gnu/gmp/gmp-$(GMP_VERSION).tar.xz" \
	  "gcc-src/mpfr-$(MPFR_VERSION).tar.xz=https://ftp.gnu.org/gnu/mpfr/mpfr-$(MPFR_VERSION).tar.xz" \
	  "gcc-src/mpc-$(MPC_VERSION).tar.gz=https://ftp.gnu.org/gnu/mpc/mpc-$(MPC_VERSION).tar.gz" \
	  "python-src/Python-$(PYTHON_VERSION).tar.xz=https://www.python.org/ftp/python/$(PYTHON_VERSION)/Python-$(PYTHON_VERSION).tar.xz" \
	; do \
	  dest="$${spec%%=*}"; url="$${spec#*=}"; \
	  if [ -f "$$dest" ]; then echo "  ✓ $$dest"; \
	  else echo ">>> $$url"; curl -fSL -o "$$dest" "$$url"; fi; \
	done

# Скачать OCR-модели tesseract в tessdata
tessdata:
	@mkdir -p tessdata
	@set -e; for lang in $(TESS_LANGS); do \
	  dest="tessdata/$$lang.traineddata"; \
	  if [ -f "$$dest" ]; then echo "  ✓ $$dest"; \
	  else echo ">>> $$lang"; curl -fSL -o "$$dest" "$(TESSDATA_REPO)/$$lang.traineddata"; fi; \
	done

# Базовый образ (glibc 2.28 + gcc 8 + python 3.11)
base:
	docker build -f Dockerfile.base -t boba-base:latest .

# Закрытый контур если есть local/ca-chain.crt
CA_CHAIN := $(wildcard local/ca-chain.crt)

# Пересобрать wheels offline
wheels:
	docker run --rm \
	  -e HOST_UID="$$(id -u)" -e HOST_GID="$$(id -g)" \
	  $(if $(CA_CHAIN),-v "$$(pwd)/local/ca-chain.crt":/tmp/ca-chain.crt:ro \
	    -e PIP_CERT=/tmp/ca-chain.crt -e REQUESTS_CA_BUNDLE=/tmp/ca-chain.crt -e SSL_CERT_FILE=/tmp/ca-chain.crt) \
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

build:
	@echo ">>> source:   $(SRC_DIR) @ $(BOBA_TAG)"
	@echo ">>> building: boba:$(BOBA_TAG)  (+ boba:latest)"
	docker compose build

# Скачать embedding-веса fastembed (ONNX) в local/cache/fastembed/
fastembed:
	@mkdir -p local/cache/fastembed
	docker run --rm \
	  -e HOST_UID="$$(id -u)" -e HOST_GID="$$(id -g)" \
	  -e EMBED_MODELS="$(EMBED_MODELS)" \
	  -v "$$(pwd)/local/cache":/cache \
	  --entrypoint sh boba:latest -c '\
	    for m in $$EMBED_MODELS; do echo ">>> fastembed: $$m"; \
	      python3 -c "import sys; from fastembed import TextEmbedding; \
	        e=TextEmbedding(model_name=sys.argv[1], cache_dir=\"/cache/fastembed\"); \
	        list(e.embed([\"probe\"]))" "$$m" \
	      || echo "!! $$m не скачан — не поддерживается этой версией fastembed (TextEmbedding.list_supported_models())"; \
	    done; \
	    chown -R "$$HOST_UID:$$HOST_GID" /cache'

print-tag:
	@echo $(BOBA_TAG)
