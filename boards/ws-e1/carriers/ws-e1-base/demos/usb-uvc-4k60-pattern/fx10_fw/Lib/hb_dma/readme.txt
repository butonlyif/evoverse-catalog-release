
  EZ-USB FX High BandWidth DMA Manager Library
           (Current version: 1.0.1.30)
  ---------------------------------------------

  This folder provides the driver and channel manager implementation for the High BandWidth DMA
  SubSystem on EZ-USB FX Devices (FX20, FX10, FX5N, FX5 and FX2G3).

  Files:
  ------

  This folder contains the following source and header files:
        - cy_hbdma_version.h    : Library version information.
        - cy_hbdma.h            : Data structure and interface definition for the HBW DMA driver.
        - cy_hbdma.c            : HBW DMA driver implementation.
        - cy_hbdma_buf_alloc.c  : DMA buffer allocator implementation.
        - cy_hbdma_dscr_list.c  : HBW DMA Descriptor free list implementation.
        - cy_hbdma_mgr.h        : Data structure and interface definition for the HBW DMA manager.
        - cy_hbdma_mgr.c        : HBW DMA manager implementation.

  Compilation Switches:
  ---------------------

  1. FREERTOS_ENABLE: Setting FREERTOS_ENABLE=1 causes the library to use an RTOS task to
     handle DMA interrupts.
  2. CY_HBDMA_ERRORDETECTION: Setting CY_HBDMA_ERRORDETECTION=1 causes the library to enable
     checks for memory leaks and corruption in the DMA buffer manager. The feature is enabled
     by default in the Makefile.
  3. HBDMA_64KB_EN: Setting HBDMA_64KB_EN=1 enables support for 64 KB (65536 byte) DMA buffers
     in the DMA manager library. This feature is only available on the second revision of
     EZ-USB FX Silicon and will automatically get turned off if an older silicon revision
     is detected.

  Change History:
  ---------------

  V1.0.1.30:
     1. Added support for new revision of FX10 silicon as well as FX5N and FX20 devices.
     2. Added support for DMA buffers with size of 64 KB. This feature can only be used
        with latest revision of FX10 parts.
     3. Updated cy_stc_hbdma_chn_config_t and cy_stc_hbdma_channel_t structures to use
        32-bit unsigned integer for buffer size and 16-bit unsigned integer for buffer
        count. More than 256 buffers can now be used while creating a single channel.
     4. Added an API called Cy_HBDma_Channel_SetWrapUp() to forcibly complete an ingress
        data transfer and make the data available to the consumer.
     5. Added an API called Cy_HBDma_Mgr_DmaCallbackConfigure() which can be used to speed
        up DMA callback processing in cases where data at speeds higher than 10 Gbps is
        being handled with firmware intervention in the channel flow.

  V0.1.1.25:
     1. Added a new API called Cy_HBDma_Channel_GetBufferInfo which returns
        the list of DMA buffers allocated for a channel. These buffers can
        be used if the same buffers are to be used for DataWire/DMAC based
        channel setup.
     2. Updated Cy_HBDma_Channel_DiscardBuffer API to support discarding
        packets in IP to IP DMA channels as well.
     3. Added an API called Cy_HBDma_Channel_AutoDropData which can be used
        to modify an active AUTO DMA channel so that all incoming data is
        dropped internally.

  V0.1.1.24:
     1. FX3G2SW-115 Jira fix: Updated event handler for 2:1 channels to
        take care of cases where the produce event from the two sockets
        are seen out of order.

  V0.1.1.23:
     1. Modified ADAPTER_CTRL.TR_OUT_DELAY setting to 0x1E (30) instead of
        0x14 (20).
     2. Added code to flush the AHB read cache before reading any descriptor
        to ensure that stale data values from the cache are not obtained.

  V0.1.1.22:
     1. Updated DMA adapter initialization to set the default value for the
        ADAPTER_CTRL.TR_OUT_DELAY field instead of zeroing it out.

  V0.1.1.21:
     1. Issue related to event handling fixed.

  V0.1.1.20:
     1. Set HBDMA_TRIGMUX_ENABLE to 1 so that events to sockets are generated
        through the Trigger Multiplexer by default.
     2. Updated the socket event generation code using trigger multiplexer to
        use edge sensitive triggers.

  V0.1.1.19:
     1. Updated channel creation logic to make provision for header addition
        in IP to MEM channels. This is required to ensure that there is space
        where the UVC header can be added when creating DMA channels for LVDS
        to USBHS UVC transfers.
     2. Updated Cy_HBDma_Channel_Destroy implementation to avoid memory leaks
        in the descriptor pool and buffer memory when destroying multi-socket
        channels.

  V0.1.1.18:
     1. Updated Cy_HBDma_DeInit function with code that disables all sockets
        and DMA adapters.

  V0.1.1.17:
     1. Disabled the code which tries to filter out spurious consume event
        interrupts due to possible race condition which leads to valid
        interrupts being filtered out.

  V0.1.1.16:
     1. Added option to avoid interrupt queue overflow by disabling HBDMA
        adapter interrupts when the queue is nearly full. The option is only
        enabled when a relevant callback is registered from the application.

  V0.1.1.15:
     1. Corrected Cy_HBDma_Channel_WaitForSendCplt implementation to not
        disable socket prematurely on the basis of a spurious consume event
        interrupt.
     2. Updated code used to filter out spurious consume event interrupts to
        fix (reduce) the likelihood of dropping valid interrupts.

  V0.1.1.14:
     1. Increase depth of DMA manager message queue from 32 to 64 entries.
     2. Enabled use of all DMA descriptors instead of only those with even indices.

  V0.1.1.13:
     1. Disabled descriptor prefetch in the USB ingress and egress DMA adapters based on
        suggestion from designer.
     2. Added work-around to filter out spurious consume events on USB egress sockets in
        the ISR itself. The active descriptor at the time of interrupt is tracked and
        interrupts are ignored if the descriptor does not change.

  V0.1.1.12:
     1. Cleaned up build options.

  V0.1.1.11:
     1. Removed the LVDS_ENABLE compiler switch. LVDS sockets can be used if a non-NULL
        lvds_base parameter is passed to the Cy_HBDma_Init() API. USB32 sockets can be used
        if a non-NULL usbss_base parameter is passed to the Cy_HBDma_Init() API.

  V0.1.1.10:
     1. Changes for CMR+4 RTL compatibility: Marker bit for the DMA desciptor is moved to
        MSB of the DSCR_BUFFER field from bit 0 of the DSCR_SIZE field.
     2. Updated Cy_HBDma_Init() with two new parameters which specify the fetch queue depth and
        read queue control settings for the USB egress DMA adapter.
     3. Updated DMA descriptor update functions with a work-around to leave the upper 8 bits
        of the DMA buffer address out when writing to the DSCR_BUFFER field.
     4. Updated Cy_HBDma_Channel_Enable() function to enable the SUSPEND and TRANS_DONE interrupts
        on the sockets when they are being enabled with a finite transfer size. However, the
        CY_HBDMA_CB_SUSPENDED and CY_HBDMA_CB_XFER_CPLT callbacks for DMA channels will only be
        sent if the user has registered for these callbacks by setting the SCK_INTR_SUSPEND and
        SCK_INTR_TRANS_DONE bits respectively in the intrEnable config parameter for the channel.

  V0.1.1.9:
     1. Added the Cy_HBDma_Mgr_UpdateMultEn() API and related code to enable/disable MULT setting
        on sockets associated with USB endpoints.

  V0.1.1.8:
     1. Corrected copy-paste error in the code which sets up event trigger connections between
        HBW sockets.
     2. CDT 388860: Updated implementation to allow multiple trigger inputs to one socket so as to
        enable AUTO 1:2 and 2:1 channel operation.

  V0.1.1.7:
     1. Re-organized fields in the channel and channel config structures to reduce memory wastage
        due to padding.
     2. Updated DMA manager code with proper code to create and manage 1:2 and 2:1 Manual DMA channels.
     3. Updated HBW SRAM base location to 0x1C000000 to match the CMR+3 RTL versions.
     4. Added CMR3_ENABLE compile time switch to enable changes associated with CMR+3 RTL and bit files.

  V0.1.1.6:
     1. No functionality change. Just updated file to increase increase readability.

  V0.1.1.5:
     1. Added FreeRTOS support in the DMA library. DMA related interrupts are relayed to the DMA
        manager for processing through a message queue when compiled with FREERTOS_ENABLE set to 1.
     2. CDT 389514 work-around: SetDescriptor function now writes twice to the descriptor locations
        in the High BandWidth SRAM.

  V0.1.1.4:
     1. Added an LVDS_ENABLE compile time macro to enable initialization of LVDS sockets during
        start-up. This can be enabled in projects that use the HbDma library with the LVDS/LVCMOS
        interfaces.

  V0.1.1.3:
     1. Updated library with proper implementation for manual channels (created with eventEnable = 0).
     2. Implemented GetBuffer, CommitBuffer and DiscardBuffer (only for IP -> MEM channels) properly
        for 1:1 use cases.
     3. Implementation tested with USB3 bit files using bulk endpoints.

  V0.1.1.2:
     1. Added Cy_HBDma_SendSocketEvent and Cy_HbDma_ConnectEventTrigger functions in the HbDma driver.
     2. Modified DMA channel management code to only enable produce/consume event connections based on
        eventEnable field from the channel configuration structure.
     3. Updated DMA driver to configure the trigger mux to forward events between paired sockets.

  V0.1.1.1:
     1. Updated enum cy_hbdma_adapter_id_t to start from 1.
     2. Marking odd descriptors as "USED". This is a workaround for a known bug in RTL which
        expects the descriptors to be 32bit aligned.
     3. Updated Cy_HBDma_Channel_DiscardBuffer API.
     4. Updated Cy_HBDma_Channel_GetBuffer API.
     5. Added CY_HBDma_Channel_Cb API to handle socket interrupts.

  V0.1.0.1:
     1. Split the Cy_HBDma_Channel_SendData and Cy_HBDma_Channel_ReceiveData functions into
        functions that initiate the transfer and those that wait for transfer to be
        completed.
     2. Added a library version header and API to retrieve version information.

[EOF]


