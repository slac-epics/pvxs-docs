# Makefile — SPVA Documentation Build
#
# Builds Sphinx HTML documentation from RST sources, with optional
# Doxygen extraction of C++ API reference from sibling repos
# (../../pvxs and ../../pvxs-cms relative to documentation/).
#
# Targets:
#   make            — full build (mermaid + doxygen + sphinx)
#   make html       — sphinx only (skip mermaid + doxygen)
#   make mermaid    — regenerate mermaid diagrams only
#   make doxygen    — run Doxygen for both sibling repos (xml/ + tag file)
#   make clean      — remove build artifacts
#   make serve      — build and serve locally on port 8000
#
# Prerequisites:
#   pip install sphinx breathe furo sphinx-reredirects
#   npm install -g @mermaid-js/mermaid-cli   (or use npx)
#   doxygen (1.9.x apt-get on linux, 1.10.x brew on macOS)
#   sibling clones ../../pvxs (branch tls) and ../../pvxs-cms (branch main)

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
all: mermaid doxygen html

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
# Doxygen — C++ API extraction from sibling repos
# ---------------------------------------------------------------------------
#
# Two runs share documentation/Doxyfile (the bulk of the configuration) and
# layer on per-project overrides from documentation/Doxyfile-pvxs.local
# and documentation/Doxyfile-pvxs-cms.local. The shared file's INPUT,
# XML_OUTPUT, GENERATE_TAGFILE, and PROJECT_NAME are intentionally empty;
# the per-run file fills them in. Output:
#   documentation/xml/pvxs/         (Breathe project: PVXS — default)
#   documentation/xml/pvxs-cms/     (Breathe project: PVXS_CMS)
#   documentation/pvxs-docs.tag     (concatenation of the two per-project tags)

.PHONY: doxygen doxygen-pvxs doxygen-pvxs-cms
doxygen: doxygen-pvxs doxygen-pvxs-cms
	@printf '\033[1;34m==>\033[0m Concatenating tag files\n'
	@cd $(DOC_DIR) && cat pvxs-docs-pvxs.tag pvxs-docs-pvxs-cms.tag > pvxs-docs.tag

doxygen-pvxs:
	@test -d ../pvxs || (echo "ERROR: sibling ../pvxs not present. Clone slac-epics/pvxs branch tls into the workspace (a sibling of pvxs-docs) before running doxygen." && false)
	@printf '\033[1;34m==>\033[0m Doxygen run: pvxs\n'
	@mkdir -p $(DOC_DIR)/xml
	@cd $(DOC_DIR) && cat Doxyfile Doxyfile-pvxs.local | doxygen -

doxygen-pvxs-cms:
	@test -d ../pvxs-cms || (echo "ERROR: sibling ../pvxs-cms not present. Clone slac-epics/pvxs-cms branch main into the workspace (a sibling of pvxs-docs) before running doxygen." && false)
	@printf '\033[1;34m==>\033[0m Doxygen run: pvxs-cms\n'
	@mkdir -p $(DOC_DIR)/xml
	@cd $(DOC_DIR) && cat Doxyfile Doxyfile-pvxs-cms.local | doxygen -

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
	@# Copy Doxygen tag file to site root so external sites can cross-link
	@if [ -f "$(DOC_DIR)/pvxs-docs.tag" ]; then \
		cp "$(DOC_DIR)/pvxs-docs.tag" "$(OUTPUT_DIR)/pvxs-docs.tag"; \
		printf '\033[1;34m==>\033[0m Published tag file: %s/pvxs-docs.tag\n' "$(OUTPUT_DIR)"; \
	fi
	@printf '\033[1;34m==>\033[0m Done: %s/index.html\n' "$(OUTPUT_DIR)"

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

.PHONY: clean
clean:
	rm -rf $(OUTPUT_DIR)
	rm -rf $(DOC_DIR)/_build $(DOC_DIR)/_image
	rm -rf $(DOC_DIR)/xml
	rm -f $(DOC_DIR)/pvxs-docs.tag $(DOC_DIR)/pvxs-docs-pvxs.tag $(DOC_DIR)/pvxs-docs-pvxs-cms.tag

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
	@echo "  all      (default) Build mermaid + Doxygen + Sphinx HTML"
	@echo "  html     Build Sphinx HTML only (skip mermaid + Doxygen)"
	@echo "  mermaid  Regenerate Mermaid diagrams only"
	@echo "  doxygen  Run Doxygen for both sibling repos (xml/ + tag file)"
	@echo "  clean    Remove build output"
	@echo "  serve    Build and serve locally on port $(SERVE_PORT)"
	@echo "  help     Show this message"
	@echo ""
	@echo "Variables:"
	@echo "  OUTPUT_DIR   Output directory (default: ../pvxs-pages)"
	@echo "  SERVE_PORT   HTTP server port (default: 8000)"
	@echo "  PYTHON       Python interpreter (default: python3)"
