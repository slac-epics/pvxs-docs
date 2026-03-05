.. _building:

.. _includepvxs:

Including PVXS in your application
===================================

Including PVXS in an application/IOC using the EPICS Makefiles is straightforward.
Add PVXS to the application configure/RELEASE or RELEASE.local file. ::

    cat <<EOF >> configure/RELEASE.local
    PVXS=/path/to/your/build/of/pvxs
    EPICS_BASE=/path/to/your/build/of/epics-base
    EOF

Then add the pvxs and pvxsIoc libraries as a dependencies to your IOC or support module. eg. ::

    PROD_IOC += myioc
    ...
    myioc_DBD += pvxsIoc.dbd
    ...
    myioc_LIBS += pvxsIoc pvxs
    myioc_LIBS += $(EPICS_BASE_IOC_LIBS)

The "pvxsIoc" library should only be included for IOCs.
It can, and should, be omitted for standalone applications
(eg. GUI clients).

Add the pvxs library as a dependency to your executable or library. eg. ::

    PROD_IOC += myapp
    ...
    myapp_LIBS += pvxs
    myapp_LIBS += Com

libevent will be automatically added for linking.

For those interested, this is accomplished with the logic found in
"cfg/CONFIG_PVXS_MODULE".

For instructions on building PVXS from source, see the
`PVXS documentation <https://slac-epics.github.io/pvxs-tls/>`_.
