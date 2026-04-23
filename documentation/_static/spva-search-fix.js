(function() {
  var ICON_TAG = /<i\s+class="(?:material-icons|material-symbols-outlined)"[^>]*>[^<]*<\/i>\s*/g;

  if (typeof Search !== 'undefined') {
    var origSetIndex = Search.setIndex;
    Search.setIndex = function(index) {
      if (index.titles) {
        for (var i = 0; i < index.titles.length; i++) {
          index.titles[i] = index.titles[i].replace(ICON_TAG, '');
        }
      }
      if (index.alltitles) {
        var cleaned = {};
        for (var key in index.alltitles) {
          if (index.alltitles.hasOwnProperty(key)) {
            cleaned[key.replace(ICON_TAG, '')] = index.alltitles[key];
          }
        }
        index.alltitles = cleaned;
      }
      return origSetIndex.call(this, index);
    };
  }
})();
