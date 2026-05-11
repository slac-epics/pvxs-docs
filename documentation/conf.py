# -*- coding: utf-8 -*-
#
# Configuration file for the Sphinx documentation builder.
#
# This file does only contain a selection of the most common options. For a
# full list see the documentation:
# http://www.sphinx-doc.org/en/master/config

# -- Path setup --------------------------------------------------------------

# If extensions (or modules to document with autodoc) are in another directory,
# add these directories to sys.path here. If the directory is relative to the
# documentation root, use os.path.abspath to make it absolute, like shown here.
#
# import os
# import sys
# sys.path.insert(0, os.path.abspath('.'))

import json
import os
import sys
import time

# -- Variant selection ------------------------------------------------------
#
# DOCS_VARIANT is set by the Makefile / build-docs.sh / CI to either
# "release" or "dev". The variant determines the version string and the
# html_context flag that the sidebar dropdown reads. Invalid values fall
# back to "release" with a warning.
_VALID_VARIANTS = ("release", "dev")
docs_variant = os.environ.get("DOCS_VARIANT", "release")
if docs_variant not in _VALID_VARIANTS:
    print(
        "WARNING: DOCS_VARIANT={!r} is not one of {}; falling back to 'release'".format(
            docs_variant, _VALID_VARIANTS
        ),
        file=sys.stderr,
    )
    docs_variant = "release"

rst_prolog = """
.. |security| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">security</i>
.. |guide| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">developer_guide</i>
.. |terminal| raw:: html

   <i class="material-icons" style="vertical-align: middle;">computer</i>
.. |1| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">counter_1</i>
.. |2| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">counter_2</i>
.. |3| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">counter_3</i>
.. |4| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">counter_4</i>
.. |5| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">counter_5</i>
.. |6| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">counter_6</i>
.. |7| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">counter_7</i>
.. |8| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">counter_8</i>
.. |9| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">counter_9</i>
.. |10%| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">clock_loader_10</i>
.. |20%| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">clock_loader_20</i>
.. |40%| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">clock_loader_40</i>
.. |60%| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">clock_loader_60</i>
.. |80%| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">clock_loader_80</i>
.. |90%| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">clock_loader_90</i>
.. |pre-packaged| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">deployed_code</i>
.. |step-by-step| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">checklist</i>
.. |step| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">done_all</i>
.. |learn| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">local_library</i>
.. |cli| raw:: html

   <i class="material-symbols-outlined" style="vertical-align: middle;">terminal</i>
"""
project = 'PVXS'
copyright = time.strftime('%Y Michael Davidsaver, George McIntyre, Osprey DCS LLC, and SLAC')
author = 'Michael Davidsaver and George McIntyre'

# Version strings depend on the selected variant. Release is the
# currently-shipping pvxs tag; dev is the next-release-in-progress tag
# that the dev variant of the docs is being authored against.
if docs_variant == "release":
    version = '1.4'
    release = '1.4.1'
else:
    version = '1.5'
    release = '1.5.1'


# -- General configuration ---------------------------------------------------

# If your documentation needs a minimal Sphinx version, state it here.
#
# needs_sphinx = '1.0'

# Add any Sphinx extension module names here, as strings. They can be
# extensions coming with Sphinx (named 'sphinx.ext.*') or your custom
# ones.
extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.githubpages',
    'breathe',
    'sphinx_reredirects',
]

# Legacy URL redirects: maintained as a JSON file at documentation/legacy-redirects.json
# so CI can read the same source-of-truth when regenerating site-root stubs with the
# explicit release/ prefix in the combine-and-deploy step (Decision 9).
#
# Both per-variant builds emit relative-target stubs (correct inside the variant
# subtree); the CI job rewrites them at site root with the release/ prefix.
with open(os.path.join(os.path.dirname(__file__), 'legacy-redirects.json')) as _f:
    redirects = json.load(_f)

# Add any paths that contain templates here, relative to this directory.
templates_path = ['_templates']

# The suffix(es) of source filenames.
# You can specify multiple suffix as a list of string:
#
# source_suffix = ['.rst', '.md']
source_suffix = '.rst'

# The master toctree document.
master_doc = 'index'

# The language for content autogenerated by Sphinx. Refer to documentation
# for a list of supported languages.
#
# This is also used if you do content translation via gettext catalogs.
# Usually you set "language" from the command line for these cases.
language = 'en'

# List of patterns, relative to source directory, that match files and
# directories to ignore when looking for source files.
# This pattern also affects html_static_path and html_extra_path.
exclude_patterns = ['_build', 'Thumbs.db', '.DS_Store']

default_role = "any"
primary_domain = "cpp"

# The name of the Pygments (syntax highlighting) style to use.
pygments_style = None


# -- Options for HTML output -------------------------------------------------

# The theme to use for HTML and HTML Help pages.  See the documentation for
# a list of builtin themes.
#
html_theme = 'furo'

# Theme options are theme-specific and customize the look and feel of a theme
# further.  For a list of options available for each theme, see the
# documentation.
#
# html_theme_options = {}

# Add any paths that contain custom static files (such as style sheets) here,
# relative to this directory. They are copied after the builtin static files,
# so a file named "default.css" will overwrite the builtin "default.css".
html_static_path = ['_static']

html_css_files = [
    'https://fonts.googleapis.com/icon?family=Material+Icons',
    'https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined',
    'version-switcher.css',
]
html_js_files = [
    'spva-search-fix.js',
    'version-switcher.js',
]

# html_context is passed into every Jinja template render. The sidebar
# override (_templates/sidebar/brand.html) reads docs_variant to preselect
# the correct dropdown option.
html_context = {
    "docs_variant": docs_variant,
}

html_favicon = 'favicon.png'


# -- Options for HTMLHelp output ---------------------------------------------

# Output file base name for HTML help builder.
htmlhelp_basename = 'PVXSdoc'


# -- Options for LaTeX output ------------------------------------------------

latex_elements = {
    # The paper size ('letterpaper' or 'a4paper').
    #
    # 'papersize': 'letterpaper',

    # The font size ('10pt', '11pt' or '12pt').
    #
    # 'pointsize': '10pt',

    # Additional stuff for the LaTeX preamble.
    #
    # 'preamble': '',

    # Latex figure (float) alignment
    #
    # 'figure_align': 'htbp',
}

# Grouping the document tree into LaTeX files. List of tuples
# (source start file, target name, title,
#  author, documentclass [howto, manual, or own class]).
latex_documents = [
    (master_doc, 'PVXS.tex', 'PVXS Documentation',
     'Michael Davidsaver', 'manual'),
]


# -- Options for manual page output ------------------------------------------

# One entry per manual page. List of tuples
# (source start file, name, description, authors, manual section).
man_pages = [
    (master_doc, 'pvxs', 'PVXS Documentation',
     [author], 1)
]


# -- Options for Texinfo output ----------------------------------------------

# Grouping the document tree into Texinfo files. List of tuples
# (source start file, target name, title, author,
#  dir menu entry, description, category)
texinfo_documents = [
    (master_doc, 'PVXS', 'PVXS Documentation',
     author, 'PVXS', 'One line description of project.',
     'Miscellaneous'),
]


# -- Options for Epub output -------------------------------------------------

# Bibliographic Dublin Core info.
epub_title = project

# The unique identifier of the text. This can be a ISBN number
# or the project homepage.
#
# epub_identifier = ''

# A unique identification for the text.
#
# epub_uid = ''

# A list of files that should not be packed into the epub file.
epub_exclude_files = ['search.html']


# -- Extension configuration -------------------------------------------------


breathe_default_project = "PVXS"

breathe_projects = {
    "PVXS": "xml/pvxs",
    "PVXS_CMS": "xml/pvxs-cms",
    "EPICS_BASE": "xml/epics-base",
}
