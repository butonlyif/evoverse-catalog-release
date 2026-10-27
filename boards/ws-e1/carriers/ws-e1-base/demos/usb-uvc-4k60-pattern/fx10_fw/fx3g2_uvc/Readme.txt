
  EZ-USB FX10 USB Video Class (UVC) Application
  =============================================

  1. Introduction
  ---------------

  This application implements a UVC 1.1 compliant camera application using the FX10
  device. An integrated USB Audio Class interface is provided to stream audio data
  received from a PDM microphone.

  The video stream can either be received through the Sensor Interface Ports (SIP)
  of the FX10 device or generated internally using a link level loopback feature.
  The SIP of FX10 can be configured in a number of different modes using different
  compiler switches.

  2. Features of UVC Application
  ------------------------------

  i.   USB Specifications: USB 2.0 (HS only) and USB3.2 Gen2/Gen1
       Note: UVC and UAC functions are not supported in USB Full Speed connections.
  ii.  Video Format: Uncompressed YUY2(YUYV)
  iii. Video Resolutions Supported:
       a. USB3.2(Gen1/Gen2): 3840*2160 (4K), 1280*720(720p) and 640*480 (VGA)
       b. USB2.0(HS): 640*480 (VGA)

  This example currently does not implement any UVC control functions such as
  brightness, contrast, exposure etc.

  This application demonstrates the following:
  i.  The usage of the FX10 APIs to implement a standard USB video class device.
      The application shows how class specific USB control requests can be processed
      at the application level.
  ii. Streaming of video data at USB 3.2 Gen2 speeds (4K video stream at ~60 fps)
      from the SIP to USB endpoint. A bulk endpoint is used for video streaming
      to enable the maximum throughput which can exceed the maximum that the USB
      specification allows over Isochronous endpoints.

  3. Video Streaming Data-path
  ----------------------------

  The Application enables EP 1-IN as BULK Endpoints with maximum packet size of 1024 bytes.
  In case of USB3.2 Gen1/Gen2, the endpoint is configured to support a maximum burst of
  16 packets.

  The device will take the data received through LVDS/LVCMOS Adapter 0 Socket 0 and send
  it on EP 1-IN. Four DMA buffers of 61472 bytes size (~61K) are used to hold the data
  while it is being forwarded.

  i. Modes for Metadata (UVC Header) Addition in Video Frame
  ----------------------------------------------------------

  A 32-byte UVC header is added to each buffer containing 61440 bytes of video data, and
  the resulting 61472 bytes are sent to the USB host. By default, the header addition
  is performed by a firmware task. If the FPGA which drives the SIP interface of FX10
  supports "enhanced mode" commands, the application can be configured to enable hardware
  based UVC header addition; thereby speeding up the streaming operation.

  - Firmware adds 32 bytes of UVC Header in data received from the LVDS/LVCMOS side
    before data is sent to the USB side on UVC BULK Endpoint 1-IN.
  - UVC header is inserted using LVDS/LVCMOS IP itself. To enable this feature, you
    need to enable the INMD_EN flag in the makefile. This option can only be used if
    the FPGA which provides the video data supports "enhanced mode" commands to trigger
    the UVC header (metadata) addition.


  4. Logging Configuration
  ------------------------

  SCB1 is used as UART with a baud rate of 921600 to send out log messages. P8.1 pin of
  FX10 can be monitored to obtain the log messages.

  5. How the application works
  ----------------------------

  The application flow involves three main steps:

  i. Initialization

     During Initialization, the following actions are performed:
        a. All the required data structures are initialized.
        b. USBD and USB driver (CAL) layers are initialized.
        c. Application registers all descriptors supported by function/application
           with the USBD layer.
        d. Application registers callback functions for different events like
           RESET, SUSPEND, RESUME, SET_CONFIGURATION, SET_INTERFACE, SET_FEATURE
           and CLEAR_FEATURE. USBD will call the respective callback function when
           the corresponding events are detected.
        e. Initialize the data transfer state machines.
        f. Application registers handlers for all relevant interrupts.
        g. Application initializes the SIP block on FX10 as required by the selected
           LVDS/LVCMOS operating mode.
        h. Application makes the USB device visible to the host by calling the
           Connect API.
  
  ii. Enumeration:

        a. During USB device enumeration, the host requests for descriptors which
           are already registered with the USBD layer during the initialization phase.
        b. Host will send SET_CONFIGURATION command and SET_INTERFACE commands to
           activate required function in the device.
        c. After SET_CONFIGURATION and SET_INTERFACE command, the application task
           takes control and enables the endpoints for data transfer.
  
  iii. UVC Data transfer:

        a. Loopback Mode(LVDS Interface):
            1. Loopback program (Video Data & Control Bytes) is stored in HBWSS SRAM.
            2. Data is moved by Thread 3 to PORT1 through DMA and GPIF.
            3. Link level loopback is enabled so that data generated by PORT1 is
               received by PORT0.
            4. Data moves from PORT0 to USB 3.x BULK Endpoint-IN through GPIF and DMA.
            5. Data moves from Device BULK Endpoint-IN to HOST UVC Application.
  
        b. Normal Mode:
            1. Depending on compile time options, LVDS/LVCMOS Interface, PORT1/PORT0,
               Narrow_Link/Wide_Link are selected.
            2. Metadata(UVC Header) inserted in Video Frames by LVDS/LVCMOS IP or by
               Firmware depending on INMD_EN flag value in the makefile.
            3. Once the streaming DMA channel is enabled, DMA ready flag on the SIP
               interface asserts and the FPGA data source starts streaming video data
               to the FX10 device.
            4. Video data moves from the LVDS/LVCMOS subsystem to SRAM through High
               Bandwidth DMA.
            5. The data is forwarded on the USBSS or USBHS EP 1-IN, based on the active
               USB connection speed. DataWire DMA channels are used in the case of USBHS
               transfers and High BandWidth DMA channels are used in case of USBSS
               transfers.
            6. Video data moves from USB Device BULK Endpoint-IN to HOST UVC Application.

  6. Integrated Audio Interface
  -----------------------------

  In addition to the USB Video camera interface, this application also implements a
  USB Audio Class interface which carries data received from a PDM microphone.

  The P4.1 and P4.2 pins of the FX10 device are used to interface to the PDM microphone.
  - P4.1 is the clock output from the FX10 device which will be generated at 3.072 MHz
  - P4.2 is the data input from the PDM microphones to the FX10 device.

  A pair of microphones in stereo configuration can be connected. Selection between Mono
  and Stereo microphone configuration is done using the STEREO_ENABLE pre-processor
  setting which can be updated through the makefile. By default, the interface is configured
  for Mono operation.

  7. Compilation Options
  ----------------------

  The application uses the GNU ARM 11.3 tool-chain which is part of the Modus ToolBox
  installation for compilation.

  - Run the "make" command to compile the application and generate the stand-alone
    binary. This binary can be programmed on to the FX10 device through the SWD
    interface using the OpenOCD tool. Please refer to the User Guide document for
    details.
  - Run the "make BLENABLE=yes" command to compile the application and generate
    a USB boot-loader compatible binary. This binary can be programmed to the
    FX10 device using the EZ-USB Control Center GUI application.

  By default, the application is configured to receive data from a 32-bit wide
  LVCMOS interface in DDR mode and make a USB 3.2 Gen2 data connection. These
  settings can be modified by passing additional options on the build command
  line as well as by modifying settings in the Makefile.

  a. Add "GEN1=yes" to the build command line to enable a USB 3.2 Gen1 data connection
     instead of a USB 3.2 Gen2 data connection.
     e.g.: make BLENABLE=yes GEN1=yes

  b. Add "LPBK_EN=yes" to the build command line to make the application use
     an internally generated colorbar pattern for streaming instead of an external
     video source. This configuration can be used on the FX10 DVK without requiring
     any additional boards or connections.
     e.g.: make BLENABLE=yes LPBK_EN=yes

     Note: Please note that the internal data path used for this function has
     throughput limitations and can only support about 26 frames per second of
     a 4K video stream (~411 MBps). Using an external video source is required
     to achieve the data rates enabled by the USB 3.2 Gen2 data connection.

  c. Changing the SIP configuration requires changes to be made in the Makefile
     directly.

     1. LVCMOS_EN: Enable(Set to 1) for LVCMOS IP selection.
        If set to 0, LVDS IP selected for data insertion from FPGA.
        In LVDS operation, the gearing ratio is set to 4:1 and can only be changed
        by updating the firmware sources.

     2. WL_EN: Enable (Set to 1) it for enabling Widelink mode operation for
        LVDS/LVCMOS Interface. If set to 0, it operates in narrow link mode.

     3. PORT1_EN: Enable(Set to 1) it for selecting PORT1 for LVDS/LVCMOS Interface.
        If set to 0, PORT0 is selected. This parameter is only valid if WL_EN is set to 0.

     4. LVCMOS_DDR_EN: Enable (Set to 1) it for DDR Mode in LVCMOS, else SDR Mode selected
        in LVCMOS.

     5. INMD_EN: Enable (Set to 1) for Metadata (32 Bytes UVC Header) insertion from
        LVDS/LVCMOS IP. If set to 0, Metadata (32 Bytes UVC Header) will be inserted
        by Firmware.

  8. Application Files
  ------------------

  a. cy_gpif_header_lvcmos.h: Generated Header file for GPIF State configuration for LVCMOS Interface.
  b. cy_gpif_header_lvds.h:   Generated Header file for GPIF State configuration for LVDS Interface.
  c. cy_usb_app.c:            C source file implementing UVC 1.1 application logic.
  d. cy_usb_app.h:            Header file for Application Data structures and functions declaration.
  e. cy_usb_uvc_device.h:     Header file with UVC application constants and the video frame configurations.
  f. fx3g2_descriptors.c:     C source file containing the USB descriptors.
  g. main.c:                  C source file for Device Initialization, ISRs, LVDS/LVCMOS Interface Initialization etc.
  h. cy_uac_app.c:            C source file with UAC interface handlers.
  i. Makefile:                GNU make compliant build script for compiling this example.

  9. Change History
  -----------------

  V1.0.0.81:
        1. Initial version of USB Video Class application for FX10 device family.

[]
