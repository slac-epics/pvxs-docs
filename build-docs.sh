#!/usr/bin/env bash
#
# build-docs.sh — Build PVXS HTML documentation from RST sources
#
# Mirrors the root Makefile. Generates Mermaid diagrams (per-variant
# _images/), runs Doxygen against sibling epics-base / pvxs / pvxs-cms,
# converts SVGs, then runs Sphinx to compile the variant subtree into HTML.
# The Doxygen step produces XML consumed by Breathe directives in authored
# RST pages plus a tag file (pvxs-docs.tag) published at the site root.
#
# Default output directory: ../pvxs-pages  (sibling of this repository).
# Per-variant builds write into ../pvxs-pages/release/ and ../pvxs-pages/dev/.
#
# Prerequisites (install once):
#   brew install inkscape doxygen
#   pip install sphinx breathe furo sphinx-reredirects
#   npm install -g @mermaid-js/mermaid-cli   # OR: npx fetches it on the fly
#   sibling clones at ../epics-base, ../pvxs (branch tls), ../pvxs-cms (branch main)
#
# Usage (preferred):
#   ./build-docs.sh release        # build release variant into ../pvxs-pages/release/
#   ./build-docs.sh dev            # build dev     variant into ../pvxs-pages/dev/
#   ./build-docs.sh all            # build BOTH variants + root meta-refresh stub
#
# Usage (legacy, single-variant — equivalent to `release`):
#   ./build-docs.sh                # implicit `all`
#   ./build-docs.sh --no-mermaid   # skip mermaid regeneration
#   ./build-docs.sh --no-doxygen   # skip Doxygen extraction
#   ./build-docs.sh --no-inkscape  # skip inkscape SVG conversion
#   ./build-docs.sh --clean        # remove previous output and intermediates

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOC_DIR="${SCRIPT_DIR}/documentation"
DIAGRAM_SPECS_DIR="${DOC_DIR}/diagram_specs"
OUTPUT_DIR="${OUTPUT_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)/pvxs-pages}"

PYTHON="${PYTHON:-python3}"
INKSCAPE="${INKSCAPE:-inkscape}"

DO_MERMAID=true
DO_DOXYGEN=true
DO_INKSCAPE=true
DO_CLEAN=false
VARIANT_CMD="all"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

for arg in "$@"; do
    case "${arg}" in
        release|dev|all) VARIANT_CMD="${arg}" ;;
        --no-mermaid)  DO_MERMAID=false ;;
        --no-doxygen)  DO_DOXYGEN=false ;;
        --no-inkscape) DO_INKSCAPE=false ;;
        --clean)       DO_CLEAN=true ;;
        -h|--help)
            echo "Usage: $0 [release|dev|all] [--no-mermaid] [--no-doxygen] [--no-inkscape] [--clean]"
            echo ""
            echo "  release        Build release variant only (sourced from documentation/release/)"
            echo "  dev            Build dev     variant only (sourced from documentation/dev/)"
            echo "  all            Build BOTH variants + root meta-refresh stub (default)"
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
    rm -rf "${DOC_DIR}/release/_images" "${DOC_DIR}/dev/_images"
    rm -f "${DOC_DIR}/pvxs-docs.tag" "${DOC_DIR}/pvxs-docs-epics-base.tag" "${DOC_DIR}/pvxs-docs-pvxs.tag" "${DOC_DIR}/pvxs-docs-pvxs-cms.tag"
fi

# ---------------------------------------------------------------------------
# Step 1 — Generate Mermaid diagrams  (.mmd → .png)
# ---------------------------------------------------------------------------

if ${DO_MERMAID}; then
    if [ -d "${DIAGRAM_SPECS_DIR}" ] && ls "${DIAGRAM_SPECS_DIR}"/*.mmd &>/dev/null; then
        info "Generating Mermaid diagrams (per-variant _images/)"

        MMDC_CMD=""
        if require_cmd mmdc; then
            MMDC_CMD="mmdc"
        else
            MMDC_CMD="npx --yes @mermaid-js/mermaid-cli"
        fi

        PUPPETEER_CFG="$(mktemp)"
        cat > "${PUPPETEER_CFG}" <<'PCFG'
{
  "args": ["--no-sandbox", "--disable-setuid-sandbox"]
}
PCFG
        trap 'rm -f "${PUPPETEER_CFG}"' EXIT

        mkdir -p "${DOC_DIR}/release/_images" "${DOC_DIR}/dev/_images"

        for mmd_file in "${DIAGRAM_SPECS_DIR}"/*.mmd; do
            base_name="$(basename "${mmd_file}" .mmd)"
            release_png="${DOC_DIR}/release/_images/${base_name}.png"
            dev_png="${DOC_DIR}/dev/_images/${base_name}.png"
            info "  ${base_name}.mmd → release/_images/${base_name}.png + dev/_images/"
            ${MMDC_CMD} -i "${mmd_file}" -o "${release_png}" -s 2 -p "${PUPPETEER_CFG}"
            cp "${release_png}" "${dev_png}"
        done
    else
        info "No Mermaid diagram specs found — skipping"
    fi
else
    info "Skipping Mermaid diagram generation (--no-mermaid)"
fi

# ---------------------------------------------------------------------------
# Step 2 — Doxygen extraction from sibling epics-base, pvxs, and pvxs-cms checkouts
# ---------------------------------------------------------------------------

if ${DO_DOXYGEN}; then
    if require_cmd doxygen; then
        if [ -d "${SCRIPT_DIR}/../epics-base" ] && [ -d "${SCRIPT_DIR}/../pvxs" ] && [ -d "${SCRIPT_DIR}/../pvxs-cms" ]; then
            info "Running Doxygen (cross-repo C++ API extraction)"

            mkdir -p "${DOC_DIR}/xml"

            info "  epics-base (../epics-base)"
            (cd "${DOC_DIR}" && cat Doxyfile Doxyfile-epics-base.local | doxygen -)

            info "  pvxs (../pvxs)"
            (cd "${DOC_DIR}" && cat Doxyfile Doxyfile-pvxs.local | doxygen -)

            info "  pvxs-cms (../pvxs-cms)"
            (cd "${DOC_DIR}" && cat Doxyfile Doxyfile-pvxs-cms.local | doxygen -)

            info "  Concatenating tag files into pvxs-docs.tag"
            (cd "${DOC_DIR}" && cat pvxs-docs-epics-base.tag pvxs-docs-pvxs.tag pvxs-docs-pvxs-cms.tag > pvxs-docs.tag)
        else
            warn "Sibling repos not present (../epics-base and/or ../pvxs and/or ../pvxs-cms) — skipping Doxygen."
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
# Step 4 — Build HTML with Sphinx (per variant)
# ---------------------------------------------------------------------------

if ! "${PYTHON}" -c "import sphinx" 2>/dev/null; then
    error "Sphinx not found.  Install with:  pip install sphinx breathe"
    exit 1
fi

build_variant() {
    local variant="$1"
    local source_dir="${DOC_DIR}/${variant}"
    local variant_out="${OUTPUT_DIR}/${variant}"

    info "Building ${variant} variant"
    info "  Source:  ${source_dir}"
    info "  Output:  ${variant_out}"

    mkdir -p "${variant_out}"

    DOCS_VARIANT="${variant}" "${PYTHON}" -m sphinx \
        -c "${DOC_DIR}" \
        -j 1 \
        -b html \
        -E \
        "${source_dir}" \
        "${variant_out}"

    for f in pvalink-schema-0.json qsrv2-schema-0.json; do
        if [ -f "${DOC_DIR}/${f}" ]; then
            cp "${DOC_DIR}/${f}" "${variant_out}/"
        fi
    done

    if [ -f "${DOC_DIR}/pvxs-docs.tag" ]; then
        cp "${DOC_DIR}/pvxs-docs.tag" "${variant_out}/pvxs-docs.tag"
    fi

    touch "${variant_out}/.nojekyll"
}

case "${VARIANT_CMD}" in
    release)
        build_variant release
        ;;
    dev)
        build_variant dev
        ;;
    all)
        build_variant release
        build_variant dev
        info "Writing combined root meta-refresh stub"
        mkdir -p "${OUTPUT_DIR}"
        printf '<!DOCTYPE html><meta http-equiv="refresh" content="0; url=release/">\n' \
            > "${OUTPUT_DIR}/index.html"
        if [ -f "${OUTPUT_DIR}/release/pvxs-docs.tag" ]; then
            cp "${OUTPUT_DIR}/release/pvxs-docs.tag" "${OUTPUT_DIR}/pvxs-docs.tag"
        fi
        touch "${OUTPUT_DIR}/.nojekyll"
        ;;
esac

info "Documentation built successfully!"
case "${VARIANT_CMD}" in
    all)
        info "  ${OUTPUT_DIR}/index.html       (meta-refresh → release/)"
        info "  ${OUTPUT_DIR}/release/index.html"
        info "  ${OUTPUT_DIR}/dev/index.html"
        ;;
    *)
        info "  ${OUTPUT_DIR}/${VARIANT_CMD}/index.html"
        ;;
esac
echo ""
echo "Serve locally with:"
echo "  ${PYTHON} -m http.server --directory \"${OUTPUT_DIR}\" 8000"
echo "  Then open http://localhost:8000"
