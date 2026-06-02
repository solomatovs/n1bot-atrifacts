# Build runtime image with auto-incremented tools-X.Y.Z tag.
# Tag source: max existing `boba:tools-X.Y.Z` from `docker images`.
# Bump: patch. Override on the fly: `make build PART=minor|major`,
# or pin a tag: `make build BOBA_TAG=1.2.3`.

PART ?= patch

CURRENT_TAG := $(shell docker images boba --format '{{.Tag}}' \
	| grep -E '^tools-[0-9]+\.[0-9]+\.[0-9]+$$' \
	| sed 's/^tools-//' \
	| sort -V \
	| tail -1)

ifeq ($(BOBA_TAG),)
  ifeq ($(CURRENT_TAG),)
    NEXT_TAG := 0.0.1
  else
    MAJOR := $(word 1,$(subst ., ,$(CURRENT_TAG)))
    MINOR := $(word 2,$(subst ., ,$(CURRENT_TAG)))
    PATCH := $(word 3,$(subst ., ,$(CURRENT_TAG)))
    ifeq ($(PART),major)
      NEXT_TAG := $(shell echo $$(($(MAJOR)+1))).0.0
    else ifeq ($(PART),minor)
      NEXT_TAG := $(MAJOR).$(shell echo $$(($(MINOR)+1))).0
    else
      NEXT_TAG := $(MAJOR).$(MINOR).$(shell echo $$(($(PATCH)+1)))
    endif
  endif
else
  NEXT_TAG := $(BOBA_TAG)
endif

.PHONY: build tag print-tag
build:
	@echo ">>> previous: $(if $(CURRENT_TAG),boba:tools-$(CURRENT_TAG),<none>)"
	@echo ">>> building:  boba:tools-$(NEXT_TAG)  (+ boba:latest)"
	BOBA_TAG=$(NEXT_TAG) docker compose build

print-tag:
	@echo $(NEXT_TAG)
