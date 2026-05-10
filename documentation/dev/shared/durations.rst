.. _duration_strings:

Duration Strings
================

Some PVACMS and authenticator settings use flexible duration strings rather
than only accepting a plain number. These settings are parsed by the
``parseDuration()`` family in pvxs-cms.

Accepted units
--------------

.. list-table::
   :header-rows: 1

   * - Suffix
     - Meaning
     - Example
   * - ``y``
     - calendar years
     - ``1y``
   * - ``M``
     - calendar months
     - ``6M``
   * - ``w``
     - weeks
     - ``2w``
   * - ``d``
     - days
     - ``3d``
   * - ``h``
     - hours
     - ``6h``
   * - ``m``
     - minutes
     - ``30m``
   * - ``s``
     - seconds
     - ``45s``

Components may be combined. Whitespace and punctuation between components
are ignored, so these examples are equivalent where the units match:

.. code-block:: text

   3d6h3m
   3d 6h 3m
   3d, 6h, 3m

A plain number with no unit is interpreted as minutes. For example,
``30`` means thirty minutes.

Examples
--------

.. list-table::
   :header-rows: 1

   * - String
     - Meaning
   * - ``30``
     - thirty minutes
   * - ``30m``
     - thirty minutes
   * - ``1d``
     - one day
   * - ``3d6h3m``
     - three days, six hours, and three minutes
   * - ``6M``
     - six calendar months
   * - ``1y6M``
     - one calendar year and six calendar months
   * - ``1y 6M 30d 12h 30m 45s``
     - one year, six months, thirty days, twelve hours, thirty minutes, and forty-five seconds

Calendar units are calendar-aware. ``1M`` means one calendar month from
the time the duration is evaluated, not a fixed number of seconds. This
means the exact number of seconds represented by ``1M`` or ``1y`` can vary
with leap years, month length, and daylight-saving transitions.

Inputs that accept duration strings
-----------------------------------

The flexible format is accepted by these user-entered values:

* Authenticator certificate requests:

  * ``authnstd -t`` / ``authnstd --time``
  * ``authnkrb -t`` / ``authnkrb --time``
  * ``authnldap -t`` / ``authnldap --time``
  * ``EPICS_PVA_AUTH_CERT_VALIDITY_MINS``

* PVACMS certificate-validity defaults:

  * ``pvacms --cert_validity``
  * ``pvacms --cert_validity-client``
  * ``pvacms --cert_validity-server``
  * ``pvacms --cert_validity-ioc``
  * ``EPICS_PVACMS_CERT_VALIDITY``
  * ``EPICS_PVACMS_CERT_VALIDITY_CLIENT``
  * ``EPICS_PVACMS_CERT_VALIDITY_SERVER``
  * ``EPICS_PVACMS_CERT_VALIDITY_IOC``

* PVACMS status-response freshness:

  * ``EPICS_PVACMS_CERT_STATUS_VALIDITY_MINS``

The ``_MINS`` suffix on some environment variable names is historical:
those values still accept the full duration-string syntax. A plain number
continues to mean minutes.

Inputs that are numeric only
----------------------------

PVACMS also has several timeout and maintenance settings that are numeric
seconds, days, request counts, or rates. For example,
``--cluster-discovery-timeout``, ``--monitor-interval-min``,
``--monitor-interval-max``, ``--backup-interval``, and
``EPICS_PVACMS_BACKUP_INTERVAL`` are not parsed as flexible duration
strings. Use the unit named by the option or environment-variable
description.
