
  EZ-USB FX USB HS/SS Common Stack
     (Current version: 1.0.1.91)
  --------------------------------

  This folder provides the drivers and device controller stack for the USB High Speed (MXS40USBHSDEV)
  and USB SuperSpeedPlus (MXS40USB32DEV) IP blocks on the EZ-USB FX devices. The USBD stack is combined
  to work with both of the HS and SS USB IP blocks.

  Files:
  ------

  This folder contains the following source and header files:
        - cy_usbd_version.h     : Version information for the USB device stack module
        - cy_usb_common.h       : Common data structure definitions
        - cy_usb_usbd.c         : USB device stack implementation
        - cy_usb_usbd.h         : USB device stack type and function declarations
        - cy_usbhs_cal_drv.c    : Controller Abstraction Layer (driver) for the MXS40USBHSDEV block.
        - cy_usbhs_cal_drv.h    : USBHS driver type and function declarations
        - cy_usbss_cal_drv.c    : Controller Abstraction Layer (driver) for the MXS40USB32DEV block.
        - cy_usbss_cal_drv.h    : USB32 driver type and function declarations

  Compilation Switches:
  ---------------------

  The USB device driver and stack are maintained in source form and the compilation switches are
  expected to be set at the application level.

  The only feature specific compiler switch (pre-processor definition) supported by the code is
  the "#if FREERTOS_ENABLE" enable switch. If this switch is enabled, all USB interrupt processing
  will be done in a deferred task context using a dedicated RTOS task. If this switch is disabled,
  all USB interrupt processing is done directly from the ISR itself.

  If -DFREERTOS_ENABLE=1 is added as part of the CFLAGS in the application makefile, it is expected
  that the application code will take care of implementing a vPortSetupTimerInterrupt function which
  registers the SysTick interrupt handler and also calling vTaskStartScheduler() to start the RTOS
  kernel scheduler.

  Change History:
  ---------------

  V1.0.1.91:
     1. Added support for new revision of FX10 Silicon as well as FX20 and FX5N devices.
     2. Added support for dual-lane Enhanced SuperSpeed USB Operation. The usbSpeed parameter
        to the Cy_USBD_ConnectDevice() API can be set as CY_USBD_USB_DEV_SS_GEN2X2 or
        CY_USBD_USB_DEV_SS_GEN1X2 to select 20 Gbps (Gen2x2) or 10 Gbps (Gen1x2) operation.
        This functionality is subject to the use of the right EZ-USB FX Device and the
        capabilities of the USB host controller or hub.
     3. Added a new callback for CY_USB_USBD_CB_EP0_RCV_DONE which can be registered and
        invoked when a Control OUT data transfer has been completed.
     4. Updated Enhanced SuperSpeed USB link state machine handlers for more efficient
        operation and robust handling of USB low power mode entry/exit sequences.

  V0.2.0.89:
     1. Added API called Cy_USBD_IsEp0ReceiveDone to check whether EP0 out
        transfer has been completed.

  V0.2.0.88:
     1. Merged in SSCAL and USBD changes required to fix race conditions seen
        during USB compliance testing.
     2. USBD updated with a timer that keeps the link in U0 for a minimum of
        10 ms after it returns from U1, U2 or U3.
     3. Updated LTSSM compliance state handler to use RTL mechanism to select
        active compliance pattern instead of trying to force it from firmware.
        
  V0.2.0.87:
     1. In HS_CAL layer and USBD layer some supporting functions are addressed.

  V0.2.0.86:
     1. Updated Cy_USB_USBD_SendEndp0Data function to properly terminate EP0 data
        transfers with a ZLP where required (in cases where the application is
        responding with less data than requested by the host controller).
     2. Fixed possible case where the GEN2 elasticity buffer depth gets set to
        an invalid value due to improper initialization of the context structure.

  V0.2.0.85:
     1. Reverted GEN2 PHY elasticity buffer depth to 12 by default.
     2. Added an API which allows the GEN2 PHY elasticity buffer depth setting to
        be modified before USB connection is enabled.

  V0.2.0.84:
     1. Increased elasticity buffer depth in GEN2 PHY to 13 (from 12).
     2. Added an interrupt handler for PHY elasticity buffer overflow and underflow
        interrupts.
     3. Corrected USBHS endpoint configuration function to set the ISOINPKTS field
        only for ISO endpoints.

  V0.2.0.83:
     1. Updated USBHS init code to use the new config bits to reduce round trip latency
        when device is responding to data packets.

  V0.2.0.82:
     1. Added few defines in common.h and usbd.h and change magic numbers to
        define value in code. Some place define name changed to make it more relevant.

  V0.2.0.81:
     1. Enabled EP specific interrupt code in the USBSS CAL. Currently, only the RETRY
        and OOSERR interrupts are enabled for both IN and OUT endpoints.

  V0.2.0.80:
     1. Added application callback for SET_ADDR notification which can be used by the
        application to determine current USB connection speed.
     2. Updated SSCAL and USBD with proper handlers for DATA_RATE_CHANGE interrupt.

  V0.2.0.79:
     1. Jira CDT_005497-507: Enabled sequence number check on ISO ingress and egress
        endpoints.
     2. Updated Cy_USBSS_Cal_FlushEPM function to EPM flush only when the read or write
        pointer has a non-zero value.

  V0.2.0.78:
     1. Jira CDT_005497-1292: Set EEPM_CS.A_RQ_EMPTY_DLY value to 5 to avoid data
        corruption on USB egress data path.

  V0.2.0.77:
     1. Fix for Jira FX3G2SW-103: Enabled SET_ADDR interrupt and updated corresponding
        handler in USBD.
     2. Updated cy_stc_usb_endp_config_t with a field to store the polling interval for
        periodic endpoints, and updated the Cy_USBSS_Cal_EndpConfig function to set the
        PROT_EPI_CS2.BINTERVAL field as required for ISOCHRONOUS IN endpoints.
     3. Added a new API called Cy_USBD_EndpSetPktsPerBuffer which should be used when
        configuring USB 3.x OUT endpoints having a maximum packet size which is not a
        power of 2.

  V0.2.0.76:
     1. Jira FX3F2SW-97: Removed code that attempts re-connect immediately after
        LTSSM_DISCONNECT interrupt is received. Instead, it is expected that the application
        will use the DisconnectCb callback to implement appropriate retry logic.
     2. Jira FX3G2SW-98: Added code to disable EP0 endpoints as part of disconnect processing
        and IEPM flush as part of Reset processing.

  V0.2.0.75:
     1. Jira FX3G2SW-95 updated: Added code to ensure that L1 exit is only attempted by
        the device is L1 state has lasted for more than 100 us.

  V0.2.0.74:
     1. Changed the PROT_ENHANCE.DISABLE_SI_MODE setting to 0 by default based on design team's
        recommendation.
     2. Updated SS disconnect function in USBD to do EPM flush after the EP0 DMA channels are
        reset.

  V0.2.0.73:
     1. Supporting function to control Status stage of control transfer in SS mode. This is similar
        to CONT_TO_DATA feature in HS mode. These two feature looks similar but works in different way.
        For more info check register descriptions.
     2. Ths feature is tested with supporting code and after testing those code are removed. 
        Only required API's at USBD AND SS_cAL layer is commited.

  V0.2.0.72:
     1. Bug related to CONT_TO_DATA is solved and zlp does not require NAK to enabled so removed.

  V0.2.0.71:
     1. Updated USBD to do retry buffer allocation for IN endpoints only in Gen2 connection.

  V0.2.0.70:
     1. hsCal layer zlp handling changed as per design team's request.
     2. ZLP-OUT interrupt should be cleared after it is handled so now clearing at application.

  V0.2.0.69:
     1. Fix related to JIRA FX3G2SW-85 where ZLP message skip USBD and directly send to application. 
        Now DMA and ZLP message directly goes to application.
     2. As soon as ZLP comes for out endpoint, sending NAK is enabled in USBHS.

  V0.2.0.68:
     1. USBD and USBHS CAL layer function added to hold data stage ACK before "OUT endpoint0" data validated.

  V0.2.0.67:
     1. Updated USB drivers with register map changes for 12-Oct-22 RTL release.
     2. Added Cy_USBD_LpmDisable and Cy_USBD_LpmEnable APIs to enable/disable hardware acceptance
        of U1/U2 entry requests.
     3. Updated SET_FEATURE and CLEAR_FEATURE request handlers to handle U1_ENABLE/U2_ENABLE
        feature selectors properly. User callbacks are generated so that the application logic
        can make the decision on whether to enable LPM transitions or not.
     4. Updated USBD to initiate a transition into SS.Disabled state on Port-CAP or Port-CFG
        timeout.
     5. Disabled custom link layer timeout settings made during initial IP bring-up.
     6. Added code to force U1/U2 transition acceptance based on the SetLinkFunction LMP settings.
     7. Added PSVP specific work-around to cycle link back to the Rx.Detect state if a transition
        to SS.Disabled happens from the Polling.Configuration or Polling.Idle states.
     8. Update SSCAL implementation to clear EP0 stall conditions on receiving new SUTOK
        interrupt.

  V0.2.0.66:
     1. Updated USBD to keep LPM-L1 entry disallowed from beginning of USB 2.0 connection
        till the device is configured.
     2. Enabled the PID_MISMATCH_ON_NAK interrupt and added a simple handler for the same.
     3. Spelling correction in USBHS CAL internal API names.

  V0.2.0.65:
     1. Updated SLP handling code for endp0. Now endp0 and other endpoint SLP handling are same.

  V0.2.0.64:
     1. #if OUT_SLP_ZLP_DELAYED_HANDLER is removed from USBHS.
     2. #if 0 code removed from USBSS CAL layer.
     3. in common.h, CAL messages based on functions are clubbed together ie USBHS, LNK, PROT messages brough together.
     4. USBHS enabled at Compliance message (this is temp arrangement to test SS/HS speed negotiation).
     5. Unwanted masking and unmasking at interrupt service routine is removed.

  V0.2.0.63:
     1. Code added related to HS/SS speed negotiation and kept under "SS_HS_SPEED_NEGO".
     2. connect/disconnect code optimized with required functions.
     3. some function call introduced SS/HS CAL layer.
     4. Debug message streamlined to allign with usb traces. This will help in debugging.
     5. In main file available at usbss directory, HS-ISR and USBHS descriptor setting were missing which is added now.
     6. Descriptor.c file, HS related descriptors were missing so included the same.

  V0.2.0.62:
     1. Removed the Cy_USBD_FlushResetEndp() API. The Cy_USBD_FlushEndp and Cy_USBD_ResetEndp
        APIs should be used instead.

  V0.2.0.61:
     1. Flush and reset endpoint related API are re-written. Old API we are keeping as it is.
        Once team moves to new API then we will remove old one. 


  V0.2.0.60:
     1. In SS_CAL layer Added code to bring EPI/EPO - CS1/CS2 register to bring in default state.
     2. While configuring any endpoint, flush, reset, bring to default state then configure the endpoint.
        This code is added in SS_cAL layer.
     3. In USBD file, transfer size 0 check is added in send/rcvendpoint0SS function. 
     4. Added code which allocates retry buffer region when configuring Egress BULK and
        CONTROL endpoints.

  V0.2.0.59:
     1. Added a new parameter to the Cy_USBD_FlushResetEndp to specify whether the sequence
        number in USB3 connection should be preserved. This parameter must be set to true if
        the EP is being reset outside of a CLEAR_FEATURE(EP_HALT) handler.
     2. Updated Cy_USB_USBD_SendEndp0DataSs() function to allow sending of data located outside
        of the High BandWidth SRAM. The function will copy the data into a scratch buffer in
        the High BandWidth SRAM and then initiate the DMA transfer.
     3. Updated SET_FEATURE and CLEAR_FEATURE command handling in USBD to handle the U1_ENABLE,
        U2_ENABLE and LTM_ENABLE cases properly.
     4. Added interrupt handler for LTSSM_STATE_CHG interrupt and configured the block to
        generate this interrupt only for important transitions.
     5. Added the Cy_USBSS_Cal_InitEventLog function which can be used to get the SSCAL to
        log important state changes into a circular RAM buffer.

  V0.2.0.57:
     1. Handling disconnect for super speed device at CAL layer.
     2. Handling of disconnect when LLTSSM sends disconnect message.
     3. Handling SS related code when disconnect is called from application or module when VBUS disconnect is detected.
     4. API at CAL layer to enable/Disable SS device.

  V0.2.0.57:
     1. Corrected typo fix in the Cy_USBSS_Cal_EndpMapStream() function resulting in incorrect
        behavior when multiple streams are enabled for an endpoint.

  V0.2.0.56:
     1. API to check STALL is set or not for an endpoint added in USBD, HS_CAL and SS_CAL layer. 
     2. NAKALL check included in isNakSet function.
     3. some more checks are added in different API.

  V0.2.0.55:
     1. Modified HSCAL to clear the OUT EP SLP/ZLP interrupts in the ISR itself instead of
        requiring the application code to do so.
     2. Modified USBHS applications to manually send trigger to DMA channel on getting SLP
        callback.

  V0.2.0.54:
     1. Enable/Disable interrupt API at SS_CAL layer.
     2. one common changes which were missing in code.

  V0.2.0.53:
     1. At SS_CAL Api related to EPMflush, socketFlush is added.

  V0.2.0.52:
     1. Updated endpoint configuration function with code to enable stream #1 for bulk endpoints
        that support multiple streams.
     2. Added Cy_USBD_EndpMapStream function that allows setting/changing the stream mapping
        for bulk endpoints.

  V0.2.0.51:
     1. In SS_CAL layer, before doing any configuration we need to disable endpoint ie make it invalid.
     2. in SS cal layer, make sure all config is updated then enable endpoint.
     3. Enable/disable endpoint interrupt based on config parameters.

  V0.2.0.50:
     1. Earlier all fetch/get descriptor related API's can be used by application with activConfiguration
        and that is updated after enumeration.  With these changes it can be used before enumeration also.
     2. API Cy_USBD_SetDeviceSpeedAtUSBDOnly() Introduced to set speed at USBD layer before enumeration done.
        This API enable application to fetch speed dependednt descriptor info even before enumeration.
     3. Cleanedup setConfig () command with config value 0x00.

  V0.2.0.49:
     1. Updated Cy_USBHS_Cal_EndpConfig() function to disable the endpoint first before applying
        the configuration changes.
     2. Updated Cy_USBHS_Cal_UpdateEpIntrMask() function to not clear any pending EP interrupts
        while updating the mask settings.

  V0.2.0.48:
     1. Added a new callback for notification of DONE interrupt on USBHS OUT endpoints. The
        corresponding interrupt is only enabled when the allowNakTillDmaRdy feature is enabled
        on the corresponding endpoint.
     2. Increased size of USBD message queue to 32 entries to address the possibility of
        DONE interrupt related messages coming from all OUT endpoints.

  V0.2.0.47:
     1. at USBD level resetController API is implemented and supporting function written at CAL layer.

  V0.2.0.46:
     1. Fixed possible race condition in USBHS CAL which could cause redundant SLP callbacks
        to be raised.

  V0.2.0.45:
     1. As per H/W team's recommendation flush all endpoint added during disconnect caused by
        application or caused by lower layer message.
     2. provision made to handle cleanup based on speed also during disconnect.
     3. Infra related to callback for disconnect is added so that application get information
        if disconnect event generated due to lower level (HW) activity.
     4. Cy_USBD_DisConnectDevice() function is replaced by Cy_USBD_DisconnectDevice().

  V0.2.0.44:
     1. added Cy_USB_USBD_RetireRecvEndp0Data() in USBD layer and support functions for that.

  V0.2.0.43:
     1. Added the Cy_USBD_SetEpBurstMode() API to enable/disable MULT feature on USB endpoints
        and associated DMA sockets.

  V0.2.0.42:
     1. Enabled the code to set the IEPM_ENDPOINT.ALLOW_NAK_TILL_DMA_RDY bit based on the
        cy_stc_usb_endp_config_t.allowNakTillDmaRdy field. The application code is expected
        to set this configuration field as false when the handling to set the transfer count
        on OUT EPs is not enabled.

  V0.2.0.41:
     1. RecvEndp0Data in USBD is already non blocking so need to remove busy waiting.
        With version 41 we have removed busy waiting.

  V0.2.0.40:
     1. Added compile time option CMR3_ENABLE to select USBSS CAL changes associated with the
        CMR+3 RTL and bit files.
     2. Updated Cy_USBSS_Cal_EndpConfig() function to program the burst size value properly in
        the endpoint configuration register.

  V0.2.0.39:
     1. Added new HSCAL API called Cy_USBHS_Cal_EnableCtrlSlpIntr to enable(unmask) SLP_RCVD interrupt
        on EP0-OUT.
     2. Updated Cy_USB_USBD_RecvEndp0Data implementation to use the ISR to clear the SLP_RCVD interrupt
        as soon as possible instead of requiring the task to clear this.

  V0.2.0.38:
     1. Endpoint and companion dscr related API added so that Application can retrieve required
        information in more cleaner way.
     2. Cleanedup some application code by using API.
     3. NULL check added in some of the place.

  V0.2.0.37:
     1. API added in USBD layer to get various parameters from capability descriptors
        under BoS descriptor umbrella.

  V0.2.0.36:
     1. Update related to USB SS and USB SSP endpoint companion descriptor APIs.

  V0.2.0.35:
     1. Updated SET_FEATURE and CLEAR_FEATURE command handlers in USBD to pass any requests
        addressed to an interface to the Setup callback registered by the application.

  V0.2.0.34:
     1. Updated Cy_USBD_ConnectDevice function to assume that USB connection will be made with the
        usbSpeed parameter. This is a work-around for missing LTSSM_CONNECT interrupt during USB3
        connection in some bit files.

  V0.2.0.33:
     1. Corrected Cy_USBHS_Cal_GetRemoteWakeupStatus implementation to check whether remote wake from
        L2-Suspend is enabled by the host instead of checking for enable of remote wake from L1 state.

  V0.2.0.32:
     1. Some more changes to complete "allowNakTillDmaRdy" feature coding.

  V0.2.0.31:
     1. Added infra related to allowNakTillDmaRdy. Still this is not enabled in CAL layer.

  V0.2.0.30:
     1. Added an HSCAL function called Cy_USBHS_Cal_GetLinkActive() which will initiate remote wake
        to get into L0 state if the link is currently in L1 state.
     2. Added a corresponding USBD function called Cy_USBD_GetUSBLinkActive() to perform the same
        function. Only HS mode is supported at present.
     3. Updated USBHS EP0 handlers to make use of the Cy_USBD_GetUSBLinkActive() function to ensure
        that control transfers are completed without error.

  V0.2.0.29:
     1. Updated stack folder with bring-up version of USB 3.2 CAL and USBD.

  V0.2.0.28:
     1. Updated endpoint configure function in USBHS CAL to configure/enable/disable EP0-OUT and EP0-IN
        at the same time. This change is required for compatibility with RTL release dated
        31 May 2022.

  V0.2.0.26:
     1. Handling reset functionality for SS.

  V0.2.0.26:
     1. Replaced PrintString(), PrintByte() and PrintBuffer() with DBG_USBD_X APIs.

  V0.2.0.25:
     1. Replaced block delay functions (Cy_SysLib_Delay) in the EP0 send/receive functions with
        code that allows other threads/tasks to run.
     2. Updated EP0 send/receive functions for SuperSpeed to match the changes made in the
        hb_dma library.

  V0.2.0.24:
     1. Debug infra usage started in USBD layer. Initialy some places err message is implemented.

  V0.2.0.23:
     1. L2 suspend, L1 suspend and host initiated L2/1 resume handling.

  V0.2.0.22:
     1. Added a work-around in the Send/Recv Ep0 Data functions to send remote wake signalling once
        in 512 ms (to be updated to check current link state once the RTL fix is available).

  V0.2.0.21:
     1. Updated USBD implementation to not re-enable LPM-L1 entry after handling control transfers
        if the application has previously called Cy_USB_LpmSetClearNYET to disable it.

  V0.2.0.20:
     1. If string dscr not register then return STALL for getStringDscr as per usb 2.0 spec section 9.6.7.
     2. If String dscr (index 0) is register but other string dscr not register then also return stall.
        This is as per usb2.0 spec section 9.6.7
     3. added couple of NULL check and cleanup the code.

  V0.2.0.19:
     1. check related to endp number and direction added in Cy_USBHS_Cal_EnableEndp().
     2. XferCount API in CAL layer comment corrected and endpoint number/direction check added.
     3. Cy_USB_USBD_EndpSetClearNakAll api declaration in .h file is replaced by Cy_USB_USBD_EndpSetClearNakNrdyAll.

  V0.2.0.18:
     1. Increased the USBD Task Priority.

  V0.2.0.17:
     1. Cy_USBD_GetEndpDscr was going in infinite loop in error case. Now it is corrected.
     2. Other required #define included in usbd.h
     3. ctxt_NULL taken care in some API to avoid crash.

  V0.2.0.16:
     1. First Round of USBD cleanup to handle Jira tickets.
     2. API Cy_USB_USBD_GetAltSetting() changed to Cy_USB_USBD_GetActiveAltSetting().
     3. API descriptoin and return values are corrected.
     4. Removed unwanted API Cy_USB_USBD_GetInfNum().
     5. Cy_USBD_GeIntfDscr is replaceg by Cy_USBD_GetIntfDscr.


  V0.2.0.15:
     1. Updated Cy_USBD_HandleSetConfiguration() to return after handling SET_CONFIGURATION request
        for configuration number 0.

  V0.2.0.14:
     1. While calling "disconnectDevice some cleanup is done related to speed/state and other data structures.
     2. Cleanup related to altSetting done during "reset". Potention bug is taken care.
     3. Introduce CAL layer API to set FS/HS speed. This will take care end-end flow for speed configuration (HS/FS).

  V0.2.0.13:
     1. Jira FX3G2SW-47: Corrected endpoint data toggle clear implementation as part of
        Cy_USBHS_Cal_EndpSetClearStall() API.

  V0.2.0.12:
     1. Fix for Jira ticket 40 where ErrLimit interrupt handling is required.
     2. Removed "Cy_USBHS_Cal_EnableRemotWakup" API from CAL layer and "Cy_USBD_EnableRemotWakup" from USB layer.
     3. Added API Cy_USBD_GetRemoteWakeupStatus and Cy_USBHS_Cal_GetRemoteWakeupStatus to check status of
        L2 remote wakeup.
     4. One more commit went in where function related to endpoint0 size is corrected.

  V0.2.0.11:
     1. Fix for Jira ticket 54 (wrong return value) in devSpeed and devState and CDT 386694 to support
        BOS descriptor in FS.

  V0.2.0.10:
     1. Added a timeout (2.5 seconds) in the Cy_USB_USBD_RecvEndp0Data function implementation.

  V0.2.0.9:
     1. Protocol interrupt handling in SS cal layer and corresponding message infra in USBD layer.

  V0.2.0.8:
     1. Re-enabled compile time option (-DEP0_DATAWIRE_EN=1) to use DataWire instead of DMAC
        for EP0 data transfers. This is only a work-around for PSVP CDT 386202 and is not intended to
        be maintained/retained in the future.

  V0.2.0.7:
     1. Updated Cy_USBHS_Cal_EnableEndp where EPO register were used instead of EPI for ingress ENDPOINT.
     2. When set config "0" comes then making active Config Null and informing application through callback.
     2. Added check for dscrIndex in case of GetConfigDscr.

  V0.2.0.6:
     1. Updated Cy_USBHS_Cal_EndpConfig function to allow MULT (additional transactions
        per microframe) to non-zero value for Interrupt endpoints as well.

  V0.2.0.5:
     1. Updated USBD to return device state to ADDRESSED if a SET_CONFIGURATION(0) request
        is received.
     2. Removed incorrectly placed index validity check in GET DESCRIPTOR(CONFIG) handler.

  V0.2.0.4:
     1. Updated the USBHS CAL code to use the standard PDL register definitions from the
        pdl/COMPONENT_CAT1E/include folder instead of using a local fx3g2_regs.h header file.
        -DUSBHS_REGS_EN=1 has to be added to the application level CFLAGS to compile code
        after this change.

     2. Removed makefile and main_cm4.c files from the fx3g2_usb_common folder. No user impact.

     3. Added a Cy_USBHS_Cal_HandleCtrlOutSlp() API in the USBHS CAL to avoid direct register
        access from USBD code. No user impact.

     4. Jira FX3G2SW-45: Updated USBD code to disable L1 entry as soon as the SUDAV interrupt
        is received and queued for processing in the task. No user impact.

  V0.2.0.3:
     1. Moved all register headers from CMR+1 version to CMR+2 version of SAS XLS.
        This version of stack is only compatible with CMR+2 based FPGA bit files after this change.

  V0.2.0.2:
     1. Initial version of combined USB stack for USBHS and USB32 IP blocks.

[EOF]

