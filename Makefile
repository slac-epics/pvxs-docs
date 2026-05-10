# Makefile — SPVA Documentation Build
#
# Builds Sphinx HTML documentation from RST sources, with optional
# Doxygen extraction of C/C++ API reference from sibling repos
# (../../epics-base, ../../pvxs, and ../../pvxs-cms relative to documentation/).
#
# Targets:
#   make            — full build (mermaid + doxygen + sphinx)
#   make html       — sphinx only (skip mermaid + doxygen)
#   make mermaid    — regenerate mermaid diagrams only
#   make doxygen    — run Doxygen for all sibling repos (xml/ + tag file)
#   make clean      — remove build artifacts
#   make serve      — build and serve locally on port 8000
#
# Prerequisites:
#   pip install sphinx breathe furo sphinx-reredirects
#   npm install -g @mermaid-js/mermaid-cli   (or use npx)
#   doxygen (1.9.x apt-get on linux, 1.10.x brew on macOS)
#   sibling clones ../../epics-base, ../../pvxs (branch tls), and ../../pvxs-cms (branch main)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PYTHON       ?= python3
SPHINXBUILD  ?= $(PYTHON) -m sphinx
DOC_DIR      := documentation
OUTPUT_DIR   ?= ../pvxs-pages
DIAGRAM_DIR  := $(DOC_DIR)/diagram_specs
SERVE_PORT   ?= 8000

SPHINXOPTS   := -j 1 -E

# Mermaid
MMDC         := $(shell command -v mmdc 2>/dev/null)
ifndef MMDC
  MMDC       := npx --yes @mermaid-js/mermaid-cli
endif

MMD_SOURCES      := $(wildcard $(DIAGRAM_DIR)/*.mmd)
MMD_PNGS_RELEASE := $(patsubst $(DIAGRAM_DIR)/%.mmd,$(DOC_DIR)/release/_images/%.png,$(MMD_SOURCES))
MMD_PNGS_DEV     := $(patsubst $(DIAGRAM_DIR)/%.mmd,$(DOC_DIR)/dev/_images/%.png,$(MMD_SOURCES))
MMD_PNGS         := $(MMD_PNGS_RELEASE) $(MMD_PNGS_DEV)

# Puppeteer config (CI-safe, no sandbox)
PUPPETEER_CFG := $(shell mktemp)

# ---------------------------------------------------------------------------
# Default target
# ---------------------------------------------------------------------------
#
# `make all` (default) builds BOTH variants into $(OUTPUT_DIR)/release and
# $(OUTPUT_DIR)/dev, plus a tiny root-level index.html meta-refresh stub
# pointing at /release/ so the combined OUTPUT_DIR is browsable directly
# (matching the deployed gh-pages site shape).
#
# `make release` and `make dev` build a single variant into
# $(OUTPUT_DIR)/<variant>; they're used independently by CI.

.PHONY: all
all: release dev combined-root

.PHONY: release
release:
	@$(MAKE) html-variant VARIANT=release

.PHONY: dev
dev:
	@$(MAKE) html-variant VARIANT=dev

# Internal target — do not invoke directly.
.PHONY: html-variant
html-variant: mermaid doxygen
	@$(MAKE) html \
	    SOURCEDIR=$(DOC_DIR)/$(VARIANT) \
	    OUTPUT_DIR=$(OUTPUT_DIR)/$(VARIANT) \
	    DOCS_VARIANT_OVERRIDE=$(VARIANT)

# When invoked via `make release` / `make dev`, the html target inherits
# DOCS_VARIANT_OVERRIDE; otherwise it falls through to whatever DOCS_VARIANT
# the user set in their env.
ifdef DOCS_VARIANT_OVERRIDE
export DOCS_VARIANT := $(DOCS_VARIANT_OVERRIDE)
endif

# Root-level index.html meta-refresh stub so opening $(OUTPUT_DIR)/index.html
# (or http://localhost:$(SERVE_PORT)/) lands on /release/.
.PHONY: combined-root
combined-root:
	@mkdir -p $(OUTPUT_DIR)
	@printf '<!DOCTYPE html><meta http-equiv="refresh" content="0; url=release/">\n' > $(OUTPUT_DIR)/index.html
	@printf '\033[1;34m==>\033[0m Wrote combined root meta-refresh: %s/index.html → release/\n' "$(OUTPUT_DIR)"

# ---------------------------------------------------------------------------
# Mermaid diagram generation
# ---------------------------------------------------------------------------

.PHONY: mermaid
mermaid: $(MMD_PNGS)

# Mermaid output is per-variant: each .mmd is rendered into
# documentation/release/_images/<name>.png (the canonical render) and then
# cp'd into documentation/dev/_images/<name>.png so each Sphinx variant build
# can resolve `.. image:: /_images/<name>.png` against its own source root.
$(DOC_DIR)/release/_images/%.png: $(DIAGRAM_DIR)/%.mmd
	@mkdir -p $(DOC_DIR)/release/_images
	@printf '\033[1;34m==>\033[0m  %s → %s\n' "$<" "$@"
	@printf '{"args":["--no-sandbox","--disable-setuid-sandbox"]}\n' > $(PUPPETEER_CFG)
	$(MMDC) -i $< -o $@ -s 2 -p $(PUPPETEER_CFG)
	@rm -f $(PUPPETEER_CFG)

$(DOC_DIR)/dev/_images/%.png: $(DOC_DIR)/release/_images/%.png
	@mkdir -p $(DOC_DIR)/dev/_images
	@cp $< $@

# ---------------------------------------------------------------------------
# Doxygen — C/C++ API extraction from sibling repos
# ---------------------------------------------------------------------------
#
# Two runs share documentation/Doxyfile (the bulk of the configuration) and
# layer on per-project overrides from documentation/Doxyfile-pvxs.local
# documentation/Doxyfile-pvxs-cms.local, and documentation/Doxyfile-epics-base.local.
# The shared file's INPUT,
# XML_OUTPUT, GENERATE_TAGFILE, and PROJECT_NAME are intentionally empty;
# the per-run file fills them in. Output:
#   documentation/xml/pvxs/         (Breathe project: PVXS — default)
#   documentation/xml/pvxs-cms/     (Breathe project: PVXS_CMS)
#   documentation/xml/epics-base/   (Breathe project: EPICS_BASE)
#   documentation/pvxs-docs.tag     (concatenation of the three per-project tags)

.PHONY: doxygen doxygen-epics-base doxygen-pvxs doxygen-pvxs-cms
doxygen: doxygen-epics-base doxygen-pvxs doxygen-pvxs-cms
	@printf '\033[1;34m==>\033[0m Concatenating tag files\n'
	@cd $(DOC_DIR) && cat pvxs-docs-epics-base.tag pvxs-docs-pvxs.tag pvxs-docs-pvxs-cms.tag > pvxs-docs.tag

doxygen-epics-base:
	@test -d ../epics-base || (echo "ERROR: sibling ../epics-base not present. Clone slac-epics/epics-base into the workspace (a sibling of pvxs-docs) before running doxygen." && false)
	@printf '\033[1;34m==>\033[0m Doxygen run: epics-base\n'
	@mkdir -p $(DOC_DIR)/xml
	@cd $(DOC_DIR) && cat Doxyfile Doxyfile-epics-base.local | doxygen -

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

# SOURCEDIR is the variant subtree being built. The config dir is always
# documentation/ (where conf.py lives), passed explicitly via `-c` so Sphinx
# does not look for conf.py inside SOURCEDIR.
#
# Default SOURCEDIR is documentation/release so legacy `make html` keeps
# working until Phase B adds the explicit `release` / `dev` Make targets.
SOURCEDIR    ?= $(DOC_DIR)/release

.PHONY: html
html:
	@printf '\033[1;34m==>\033[0m Building HTML: %s → %s (config: %s)\n' "$(SOURCEDIR)" "$(OUTPUT_DIR)" "$(DOC_DIR)"
	@mkdir -p $(OUTPUT_DIR)
	$(SPHINXBUILD) -c $(DOC_DIR) -b html $(SPHINXOPTS) $(SOURCEDIR) $(OUTPUT_DIR)
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
	rm -rf $(DOC_DIR)/release/_images $(DOC_DIR)/dev/_images
	rm -f $(DOC_DIR)/pvxs-docs.tag $(DOC_DIR)/pvxs-docs-pvxs.tag $(DOC_DIR)/pvxs-docs-pvxs-cms.tag $(DOC_DIR)/pvxs-docs-epics-base.tag

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
	@echo "  all       (default) Build BOTH variants into release/ + dev/ + root index.html"
	@echo "  release   Build release variant into \$$(OUTPUT_DIR)/release/"
	@echo "  dev       Build dev variant     into \$$(OUTPUT_DIR)/dev/"
	@echo "  html      Build Sphinx HTML only against \$$(SOURCEDIR) → \$$(OUTPUT_DIR)"
	@echo "             (default SOURCEDIR=documentation/release; set DOCS_VARIANT to flag the build)"
	@echo "  mermaid   Regenerate Mermaid diagrams (per-variant _images/)"
	@echo "  doxygen   Run Doxygen for all sibling repos (xml/ + tag file)"
	@echo "  clean     Remove build output"
	@echo "  serve     Build all and serve locally on port $(SERVE_PORT)"
	@echo "  help      Show this message"
	@echo ""
	@echo "Variables:"
	@echo "  OUTPUT_DIR   Output directory (default: ../pvxs-pages)"
	@echo "  SERVE_PORT   HTTP server port (default: 8000)"
	@echo "  PYTHON       Python interpreter (default: python3)"
