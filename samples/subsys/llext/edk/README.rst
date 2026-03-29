.. zephyr:code-sample:: llext-edk
   :name: Linkable loadable extensions EDK
   :relevant-api: llext_apis

    Enable linkable loadable extension development outside the Zephyr tree using
    LLEXT EDK (Extension Development Kit).

Overview
********

This sample demonstrates how to use the Zephyr LLEXT EDK (Extension Development
Kit). It is composed of one Zephyr application, which provides APIs for the
extensions that it loads. The provided API is a simple publish/subscribe system,
based on :ref:`Zbus <zbus>`, which extensions use to communicate with each other.

This sample was modified from the original on upstream Zephyr to use Zig for the
extensions ``k-ext1`` (that runs on kernel space) and ``ext1`` (that runs on user
space). Their builds is sligtly different, but one can get an idea of how they work
from the ``build.sh`` files inside the ``zigbuild`` directory in each. Or, one can
check https://uncollected-garbage.me/zig-zephyr-part-i for more info (note that
this is the first post in a series exploring Zig and Zephyr extensions).

The application is composed of a subscriber thread, which listens for events
published and republishes them via Zbus to the extensions that are
subscribers. There are four extensions, which are loaded by the application and
run in different contexts. Extensions ``ext1``, ``ext2`` and ``ext3`` run in
userspace, each demonstrating different application and Zephyr API usage, such as
semaphores, spawning threads to listen for events or simply publishing or
subscribing to events. Extension ``kext1`` runs in a kernel thread, albeit similar
to ``ext3``.

The application also creates different memory domains for each extension, thus
providing some level of isolation - although the kernel one still has access
to all of Zephyr kernel.

Note that the kernel extension is only available when the EDK is built with
the :kconfig:option:`CONFIG_LLEXT_EDK_USERSPACE_ONLY` option disabled.


The application is built using the Zephyr build system. The EDK is built using
the Zephyr build system as well, via ``llext-edk`` target. The EDK is then
extracted and the extensions are built using CMake.

Finally, the way the application loads the extensions is by including them
during build time, which is not really practical. This sample is about the EDK
providing the ability to build extensions independently from the application.
One could build the extensions in different directories, not related to the
Zephyr application - even on different machines, using only the EDK. At the
limit, one could even imagine a scenario where the extensions are built by
different teams, using the EDK provided by the application developer.

Building the EDK
****************

To build the EDK, use the ``llext-edk`` target. For example:

.. zephyr-app-commands::
   :zephyr-app: samples/subsys/llext/edk/app
   :board: qemu_cortex_r5
   :goals: build llext-edk
   :west-args: -p=always
   :compact:

Copy the EDK to some place and extract it:

.. code-block:: console

    mkdir /tmp/edk
    cp build/zephyr/llext-edk.tar.xz /tmp/edk
    cd /tmp/edk
    tar -xf llext-edk.tar.xz

Then set ``LLEXT_EDK_INSTALL_DIR`` to the extracted directory:

.. code-block:: console

    export LLEXT_EDK_INSTALL_DIR=/tmp/edk/llext-edk

This variable is used by the extensions to find the EDK.

Building the extensions
***********************

The :envvar:`ZEPHYR_SDK_INSTALL_DIR` environment variable is used by the
extensions to find the Zephyr SDK, so you need to ensure it's properly set:

.. code-block:: console

    export ZEPHYR_SDK_INSTALL_DIR=</path/to/zephyr-sdk>

To build the extensions, in the ``edk`` directory, just use the ``build.sh``
script, which takes care of building the Zig extensions too:

.. code-block:: console

   ./build.sh

Alternatively, you can set the ``LLEXT_EDK_INSTALL_DIR`` directly in the
CMake invocation:

.. code-block:: console

    cmake -B build -DLLEXT_EDK_INSTALL_DIR=/tmp/edk/llext-edk
    make -C build

Building the application
************************

Now, build the application, including the extensions, and run it:

.. zephyr-app-commands::
   :zephyr-app: samples/subsys/llext/edk/app
   :board: qemu_cortex_r5
   :goals: build run
   :west-args: -p=always
   :compact:

You should see something like:

.. code-block:: console

    [app]Subscriber thread [0x20b28] started.
    [app]Loading extension [kext1].
    [app]Thread 0x20840 created to run extension [kext1], at privileged mode.
    [k-ext1]Waiting sem
    [app]Thread [0x222a0] registered event [0x223c0]
    [k-ext1]Waiting event
    [app]Loading extension [ext1].
    [app]Thread 0x20a30 created to run extension [ext1], at userspace.
    [app]Thread [0x20a30] registered event [0x26060]
    [ext1]Waiting event
    [app]Loading extension [ext2].
    [app]Thread 0x20938 created to run extension [ext2], at userspace.
    [ext2]Publishing tick
    [app][subscriber_thread]Got channel tick_chan
    [ext1]Got event, reading channel
    [ext1]Read val: 0
    [ext1]Waiting event
    [k-ext1]Got event, giving sem
    [k-ext1]Got sem, reading channel
    [k-ext1]Read val: 0
    [k-ext1]Waiting sem
    (...)
