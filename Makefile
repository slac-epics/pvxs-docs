# Makefile — SPVA Documentation Build
#
# Builds Sphinx HTML documentation from RST sources.
# No Doxygen / C++ code scanning; Breathe warnings are non-fatal.
#
# Targets:
#   make            — full build (mermaid + sphinx)
#   make html       — sphinx only (skip mermaid)
#   make mermaid    — regenerate mermaid diagrams only
#   make clean      — remove build artifacts
#   make serve      — build and serve locally on port 8000
#
# Prerequisites:
#   pip install sphinx breathe
#   npm install -g @mermaid-js/mermaid-cli   (or use npx)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PYTHON       ?= python3
SPHINXBUILD  ?= $(PYTHON) -m sphinx
DOC_DIR      := documentation
OUTPUT_DIR   ?= ../pvxs-pages
DIAGRAM_DIR  := $(DOC_DIR)/diagram_specs
SERVE_PORT   ?= 8000

SPHINXOPTS   := -j auto -E

# Mermaid
MMDC         := $(shell command -v mmdc 2>/dev/null)
ifndef MMDC
  MMDC       := npx --yes @mermaid-js/mermaid-cli
endif

MMD_SOURCES  := $(wildcard $(DIAGRAM_DIR)/*.mmd)
MMD_PNGS     := $(patsubst $(DIAGRAM_DIR)/%.mmd,$(DOC_DIR)/%.png,$(MMD_SOURCES))

# Puppeteer config (CI-safe, no sandbox)
PUPPETEER_CFG := $(shell mktemp)

# ---------------------------------------------------------------------------
# Default target
# ---------------------------------------------------------------------------

.PHONY: all
all: mermaid html

# ---------------------------------------------------------------------------
# Mermaid diagram generation
# ---------------------------------------------------------------------------

.PHONY: mermaid
mermaid: $(MMD_PNGS)

$(DOC_DIR)/%.png: $(DIAGRAM_DIR)/%.mmd
	@printf '\033[1;34m==>\033[0m  %s → %s\n' "$<" "$@"
	@printf '{"args":["--no-sandbox","--disable-setuid-sandbox"]}\n' > $(PUPPETEER_CFG)
	$(MMDC) -i $< -o $@ -s 2 -p $(PUPPETEER_CFG)
	@rm -f $(PUPPETEER_CFG)

# ---------------------------------------------------------------------------
# Sphinx HTML build
# ---------------------------------------------------------------------------

.PHONY: html
html:
	@printf '\033[1;34m==>\033[0m Building HTML: %s → %s\n' "$(DOC_DIR)" "$(OUTPUT_DIR)"
	@mkdir -p $(OUTPUT_DIR)
	$(SPHINXBUILD) -b html $(SPHINXOPTS) $(DOC_DIR) $(OUTPUT_DIR)
	@# Copy extra assets
	@for f in pvalink-schema-0.json qsrv2-schema-0.json; do \
		[ -f "$(DOC_DIR)/$$f" ] && cp "$(DOC_DIR)/$$f" "$(OUTPUT_DIR)/" || true; \
	done
	@if [ -d "$(OUTPUT_DIR)/_static/images" ]; then \
		mkdir -p "$(OUTPUT_DIR)/images"; \
		cp -r "$(OUTPUT_DIR)/_static/images/"* "$(OUTPUT_DIR)/images/" 2>/dev/null || true; \
	fi
	@if [ -d "$(OUTPUT_DIR)/_static/fonts" ]; then \
		mkdir -p "$(OUTPUT_DIR)/fonts"; \
		cp -r "$(OUTPUT_DIR)/_static/fonts/"* "$(OUTPUT_DIR)/fonts/" 2>/dev/null || true; \
	fi
	@touch $(OUTPUT_DIR)/.nojekyll
	@printf '\033[1;34m==>\033[0m Done: %s/index.html\n' "$(OUTPUT_DIR)"

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

.PHONY: clean
clean:
	rm -rf $(OUTPUT_DIR)
	rm -rf $(DOC_DIR)/_build $(DOC_DIR)/_image

# ---------------------------------------------------------------------------
# Serve locally
# ---------------------------------------------------------------------------

.PHONY: serve
serve: all
	@printf '\033[1;34m==>\033[0m Serving at http://localhost:$(SERVE_PORT)\n'
	$(PYTHON) -m http.server --directory $(OUTPUT_DIR) $(SERVE_PORT)

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

.PHONY: help
help:
	@echo "SPVA Documentation Build"
	@echo ""
	@echo "Targets:"
	@echo "  all      (default) Build mermaid diagrams + Sphinx HTML"
	@echo "  html     Build Sphinx HTML only (skip mermaid)"
	@echo "  mermaid  Regenerate Mermaid diagrams only"
	@echo "  clean    Remove build output"
	@echo "  serve    Build and serve locally on port $(SERVE_PORT)"
	@echo "  help     Show this message"
	@echo ""
	@echo "Variables:"
	@echo "  OUTPUT_DIR   Output directory (default: ../pvxs-pages)"
	@echo "  SERVE_PORT   HTTP server port (default: 8000)"
	@echo "  PYTHON       Python interpreter (default: python3)"
