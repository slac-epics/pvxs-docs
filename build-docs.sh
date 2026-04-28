#!/usr/bin/env bash
#
# build-docs.sh — Build PVXS HTML documentation from RST sources
#
# Generates Mermaid diagrams, runs Doxygen (cross-repo C++ API extraction)
# against the sibling pvxs and pvxs-cms checkouts, converts SVGs, then runs
# Sphinx to compile the RST files into HTML. The Doxygen step produces XML
# consumed by Breathe directives in authored RST pages plus a tag file
# (pvxs-docs.tag) published at the site root for external cross-linking.
#
# Output directory: ../pvxs-pages  (sibling of this repository)
#
# Prerequisites (install once):
#   brew install inkscape doxygen        # SVG conversion + Doxygen
#   pip install sphinx breathe furo sphinx-reredirects
#   npm install -g @mermaid-js/mermaid-cli   # OR: npx will fetch it on the fly
#   sibling clones at ../pvxs (branch tls) and ../pvxs-cms (branch main)
#
# Usage:
#   ./build-docs.sh            # full build (mermaid + doxygen + inkscape + sphinx)
#   ./build-docs.sh --no-mermaid   # skip mermaid regeneration (reuse existing PNGs)
#   ./build-docs.sh --no-doxygen   # skip Doxygen extraction (reuse existing xml/)
#   ./build-docs.sh --no-inkscape  # skip inkscape SVG conversion
#   ./build-docs.sh --clean        # remove previous output and intermediates, then rebuild

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC_DIR="${SCRIPT_DIR}/documentation"
DIAGRAM_SPECS_DIR="${DOC_DIR}/diagram_specs"
OUTPUT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/pvxs-pages"

PYTHON="${PYTHON:-python3}"
INKSCAPE="${INKSCAPE:-inkscape}"

DO_MERMAID=true
DO_DOXYGEN=true
DO_INKSCAPE=true
DO_CLEAN=false

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

for arg in "$@"; do
    case "${arg}" in
        --no-mermaid)  DO_MERMAID=false ;;
        --no-doxygen)  DO_DOXYGEN=false ;;
        --no-inkscape) DO_INKSCAPE=false ;;
        --clean)       DO_CLEAN=true ;;
        -h|--help)
            echo "Usage: $0 [--no-mermaid] [--no-doxygen] [--no-inkscape] [--clean] [-h|--help]"
            echo ""
            echo "  --no-mermaid   Skip Mermaid diagram generation (reuse existing PNGs)"
            echo "  --no-doxygen   Skip Doxygen extraction (reuse existing xml/)"
            echo "  --no-inkscape  Skip Inkscape SVG conversion"
            echo "  --clean        Remove previous output before building"
            echo ""
            echo "Output goes to: ${OUTPUT_DIR}"
            exit 0
            ;;
        *)
            echo "Unknown option: ${arg}" >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mWARN:\033[0m %s\n' "$*"; }
error() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

if ${DO_CLEAN}; then
    info "Cleaning previous build artifacts"
    rm -rf "${OUTPUT_DIR}"
    rm -rf "${DOC_DIR}/_build"
    rm -rf "${DOC_DIR}/_image"
    rm -rf "${DOC_DIR}/xml"
    rm -f "${DOC_DIR}/pvxs-docs.tag" "${DOC_DIR}/pvxs-docs-pvxs.tag" "${DOC_DIR}/pvxs-docs-pvxs-cms.tag"
fi

# ---------------------------------------------------------------------------
# Step 1 — Generate Mermaid diagrams  (.mmd → .png)
# ---------------------------------------------------------------------------

if ${DO_MERMAID}; then
    if [ -d "${DIAGRAM_SPECS_DIR}" ] && ls "${DIAGRAM_SPECS_DIR}"/*.mmd &>/dev/null; then
        info "Generating Mermaid diagrams"

        MMDC_CMD=""
        if require_cmd mmdc; then
            MMDC_CMD="mmdc"
        else
            MMDC_CMD="npx --yes @mermaid-js/mermaid-cli"
        fi

        # Puppeteer config (disable sandbox for CI compatibility)
        PUPPETEER_CFG="$(mktemp)"
        cat > "${PUPPETEER_CFG}" <<'PCFG'
{
  "args": ["--no-sandbox", "--disable-setuid-sandbox"]
}
PCFG
        trap 'rm -f "${PUPPETEER_CFG}"' EXIT

        for mmd_file in "${DIAGRAM_SPECS_DIR}"/*.mmd; do
            base_name="$(basename "${mmd_file}" .mmd)"
            output_file="${DOC_DIR}/${base_name}.png"
            info "  ${base_name}.mmd → ${base_name}.png"
            ${MMDC_CMD} -i "${mmd_file}" -o "${output_file}" -s 2 -p "${PUPPETEER_CFG}"
        done
    else
        info "No Mermaid diagram specs found — skipping"
    fi
else
    info "Skipping Mermaid diagram generation (--no-mermaid)"
fi

# ---------------------------------------------------------------------------
# Step 2 — Doxygen extraction from sibling pvxs and pvxs-cms checkouts
# ---------------------------------------------------------------------------

if ${DO_DOXYGEN}; then
    if require_cmd doxygen; then
        if [ -d "${SCRIPT_DIR}/../pvxs" ] && [ -d "${SCRIPT_DIR}/../pvxs-cms" ]; then
            info "Running Doxygen (cross-repo C++ API extraction)"

            mkdir -p "${DOC_DIR}/xml"

            info "  pvxs (../pvxs)"
            (cd "${DOC_DIR}" && cat Doxyfile Doxyfile-pvxs.local | doxygen -)

            info "  pvxs-cms (../pvxs-cms)"
            (cd "${DOC_DIR}" && cat Doxyfile Doxyfile-pvxs-cms.local | doxygen -)

            info "  Concatenating tag files into pvxs-docs.tag"
            (cd "${DOC_DIR}" && cat pvxs-docs-pvxs.tag pvxs-docs-pvxs-cms.tag > pvxs-docs.tag)
        else
            warn "Sibling repos not present (../pvxs and/or ../pvxs-cms) — skipping Doxygen."
            warn "Maintainer-manual API-reference pages will render with empty Breathe directives."
        fi
    else
        warn "doxygen not found — skipping Doxygen step."
        warn "Install with: brew install doxygen  (or: apt-get install doxygen)"
    fi
else
    info "Skipping Doxygen extraction (--no-doxygen)"
fi

# ---------------------------------------------------------------------------
# Step 3 — Convert SVGs via Inkscape  (.svg → _image/*.svg)
# ---------------------------------------------------------------------------

if ${DO_INKSCAPE}; then
    svg_files=("${DOC_DIR}"/*.svg)
    if [ -e "${svg_files[0]}" ]; then
        if require_cmd "${INKSCAPE}"; then
            info "Converting SVGs with Inkscape"
            mkdir -p "${DOC_DIR}/_image"
            for svg in "${DOC_DIR}"/*.svg; do
                base_name="$(basename "${svg}")"
                out="${DOC_DIR}/_image/${base_name}"
                info "  ${base_name} → _image/${base_name}"
                "${INKSCAPE}" -l -o "${out}" "${svg}"
            done
        else
            warn "Inkscape not found — _image/ SVGs won't be regenerated."
            warn "Images in qgroup.rst may be missing. Install inkscape to fix."
        fi
    fi
else
    info "Skipping Inkscape SVG conversion (--no-inkscape)"
fi

# ---------------------------------------------------------------------------
# Step 4 — Build HTML with Sphinx
# ---------------------------------------------------------------------------

info "Building HTML documentation with Sphinx"
info "  Source:  ${DOC_DIR}"
info "  Output:  ${OUTPUT_DIR}"

# Verify Sphinx is available
if ! "${PYTHON}" -c "import sphinx" 2>/dev/null; then
    error "Sphinx not found.  Install with:  pip install sphinx breathe"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"

# Run Sphinx.
# • -j auto        — parallel build
# • -b html        — HTML builder
# • -W is omitted  — Breathe warnings (from missing Doxygen XML) are non-fatal
# • -D breathe_projects.PVXS=  — point Breathe at empty string so it warns
#   rather than erroring on missing xml/ dir
"${PYTHON}" -m sphinx \
    -j auto \
    -b html \
    -E \
    "${DOC_DIR}" \
    "${OUTPUT_DIR}"

# ---------------------------------------------------------------------------
# Step 5 — Copy extra assets into the output
# ---------------------------------------------------------------------------

info "Copying extra assets"

# JSON schema files expected by some pages
for f in pvalink-schema-0.json qsrv2-schema-0.json; do
    if [ -f "${DOC_DIR}/${f}" ]; then
        cp "${DOC_DIR}/${f}" "${OUTPUT_DIR}/"
    fi
done

# Ensure fonts and images from _static are accessible at root level
# (mirrors what the CI workflow does)
if [ -d "${OUTPUT_DIR}/_static/images" ]; then
    mkdir -p "${OUTPUT_DIR}/images"
    cp -r "${OUTPUT_DIR}/_static/images/"* "${OUTPUT_DIR}/images/" 2>/dev/null || true
fi
if [ -d "${OUTPUT_DIR}/_static/fonts" ]; then
    mkdir -p "${OUTPUT_DIR}/fonts"
    cp -r "${OUTPUT_DIR}/_static/fonts/"* "${OUTPUT_DIR}/fonts/" 2>/dev/null || true
fi

if [ -f "${DOC_DIR}/pvxs-docs.tag" ]; then
    info "Publishing Doxygen tag file: pvxs-docs.tag"
    cp "${DOC_DIR}/pvxs-docs.tag" "${OUTPUT_DIR}/pvxs-docs.tag"
fi

touch "${OUTPUT_DIR}/.nojekyll"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

info "Documentation built successfully!"
info "  ${OUTPUT_DIR}/index.html"
echo ""
echo "Serve locally with:"
echo "  ${PYTHON} -m http.server --directory \"${OUTPUT_DIR}\" 8000"
echo "  Then open http://localhost:8000"
