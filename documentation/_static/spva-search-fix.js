/* spva-search-fix.js
 *
 * Strip Material Icon HTML tags from Sphinx search result titles.
 *
 * The RST substitutions (|security|, |guide|, |terminal|, etc.) expand to
 * <i class="material-symbols-outlined" ...>iconname</i> inline HTML.
 * Sphinx includes these raw strings in the search index, producing garbled
 * titles like:
 *   <i class="material-symbols-outlined" style="...">security</i> Certificate Management
 *
 * ROOT CAUSE:
 * searchtools.js declares `const Search = { ... }` — a block-scoped const
 * that does NOT go through window.Search at all.  Object.defineProperty on
 * window.Search therefore never fires.
 *
 * SOLUTION:
 * DOMContentLoaded fires after all synchronous <script> tags at the end of
 * <body> have run (including searchtools.js AND searchindex.js which calls
 * Search.setIndex).  By that point Search._index is already populated.
 * We reach Search via the script's own scope by patching Search.setIndex so
 * any future call is also clean, and we directly clean the already-committed
 * index in the DOMContentLoaded handler.
 */
(function () {
    var ICON_TAG = /<i\s+[^>]*class="(?:material-icons|material-symbols-outlined)"[^>]*>[^<]*<\/i>\s*/g;

    function cleanTitles(index) {
        if (!index) return;
        if (Array.isArray(index.titles)) {
            for (var i = 0; i < index.titles.length; i++) {
                index.titles[i] = index.titles[i].replace(ICON_TAG, '');
            }
        }
        if (index.alltitles && typeof index.alltitles === 'object') {
            var cleaned = {};
            var keys = Object.keys(index.alltitles);
            for (var j = 0; j < keys.length; j++) {
                cleaned[keys[j].replace(ICON_TAG, '')] = index.alltitles[keys[j]];
            }
            index.alltitles = cleaned;
        }
    }

    /* DOMContentLoaded fires after all synchronous scripts at end-of-body
     * have executed, including searchtools.js (which defines const Search)
     * and searchindex.js (which calls Search.setIndex and populates
     * Search._index).  We can then reach Search._index directly. */
    document.addEventListener('DOMContentLoaded', function () {
        /* Search is a const in searchtools.js's script scope — not on window.
         * The only way to reach it from here is via the Search object's own
         * properties that were assigned after it was created.  Specifically,
         * Search._index is set by Search.setIndex() which searchindex.js
         * called synchronously before DOMContentLoaded fired. */
        if (typeof Search !== 'undefined' && Search._index) {
            cleanTitles(Search._index);
        }

        /* Also patch setIndex so any future re-indexing call is clean. */
        if (typeof Search !== 'undefined' && typeof Search.setIndex === 'function'
                && !Search.__spva_patched__) {
            Search.__spva_patched__ = true;
            var orig = Search.setIndex;
            Search.setIndex = function (index) {
                cleanTitles(index);
                return orig.call(this, index);
            };
        }

        /* Patch _performSearch so full-text term search results get section-level
         * anchors from alltitles instead of "" (which links to page top).
         *
         * Sphinx's performTermsSearch() hardcodes anchor="" for body-text
         * matches (searchtools.js line 655).  We walk alltitles for the same
         * document and pick the section whose title best matches the query.
         */
        if (typeof Search !== 'undefined' && typeof Search._performSearch === 'function'
                && !Search.__spva_anchors_patched__) {
            Search.__spva_anchors_patched__ = true;
            var orig = Search._performSearch;
            Search._performSearch = function (query, searchTerms, excludedTerms, highlightTerms, objectTerms) {
                var results = orig.call(this, query, searchTerms, excludedTerms, highlightTerms, objectTerms);

                if (Search._index && Search._index.alltitles) {
                    var allTitles = Search._index.alltitles;
                    var docNames = Search._index.docnames;
                    var queryLower = query.toLowerCase().trim();

                    for (var ri = 0; ri < results.length; ri++) {
                        var result = results[ri];
                        /* Only text-kind results from performTermsSearch have
                         * empty anchors.  Title/index/object results are fine. */
                        if (result[6] !== SearchResultKind.text) continue;
                        if (result[2]) continue;

                        var docName = result[0];
                        var bestAnchor = '';

                        for (var titleText in allTitles) {
                            if (!allTitles.hasOwnProperty(titleText)) continue;
                            var entries = allTitles[titleText];
                            for (var ei = 0; ei < entries.length; ei++) {
                                var fileIdx = entries[ei][0];
                                var sectionId = entries[ei][1];
                                if (docNames[fileIdx] === docName && sectionId !== null) {
                                    if (!bestAnchor) bestAnchor = '#' + sectionId;
                                    var titleLower = titleText.toLowerCase();
                                    if (titleLower.indexOf(queryLower) !== -1) {
                                        bestAnchor = '#' + sectionId;
                                        break;
                                    }
                                }
                            }
                        }

                        if (bestAnchor) result[2] = bestAnchor;
                    }
                }

                return results;
            };
        }
    });
})();
