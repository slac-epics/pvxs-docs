// pvxs-docs version switcher.
//
// Invoked by the <select onchange="..."> in _templates/sidebar/brand.html.
// Navigates from the current page in one variant to the equivalent page in
// the other variant, falling back to that variant's index when the target
// path does not exist.
//
// Resolution algorithm:
//   1. Find the "/release/" or "/dev/" segment in the current pathname.
//   2. If absent, the site has not been deployed as the combined two-variant
//      tree (e.g. a sphinx-only local build serving a single variant) -
//      treat the entire site as the current variant and navigate to the
//      sibling variant's index relative to the same parent.
//   3. Otherwise swap the segment, HEAD-probe the candidate URL, and
//      either navigate to it (2xx) or fall back to the target variant's
//      index (anything else, including the 404 we expect when the page
//      does not exist in the other variant).
(function () {
    "use strict";

    function siteRootRelativeIndex(target) {
        var pathname = window.location.pathname;
        var m = pathname.match(/^(.*?)\/(release|dev)\//);
        if (m) {
            return m[1] + "/" + target + "/";
        }
        return "/" + target + "/";
    }

    window.__pvxsSwitchVariant = function (target) {
        if (target !== "release" && target !== "dev") {
            return;
        }
        var pathname = window.location.pathname;
        var current = pathname.match(/\/(release|dev)\//);
        if (!current) {
            window.location.href = siteRootRelativeIndex(target);
            return;
        }
        if (current[1] === target) {
            return;
        }
        var candidate = pathname.replace(/\/(release|dev)\//, "/" + target + "/");
        var candidateUrl = window.location.origin + candidate + window.location.search;
        var fallback = window.location.origin + siteRootRelativeIndex(target);

        fetch(candidateUrl, { method: "HEAD", redirect: "follow" })
            .then(function (response) {
                window.location.href = response.ok ? candidateUrl : fallback;
            })
            .catch(function () {
                window.location.href = fallback;
            });
    };
})();
