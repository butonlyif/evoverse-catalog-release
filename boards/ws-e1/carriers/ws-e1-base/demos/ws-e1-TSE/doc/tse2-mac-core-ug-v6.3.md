# Triple Speed Ethernet MAC Core User Guide

**UG-CORE-TSEMAC-v6.3**

**June 2026**

[**www.efinixinc.com**](http://www.efinixinc.com)


## Contents

- ................................... 4
- Device Support......
- Resource Utilization...
- Release Notes.................
- Block Diagram....... .8
- Clock Sources................. 9
- Reset Signals........... 12
- Power Up Handshake with FPGA Transceiver............ 14
- Ethernet Packets, Frames, and IPG............ 15
- User Interface AXI4-Stream.......... 2
- TX AXI ST Interface........ 6
- RX AXI ST Interface.... 18
- CRC Generation and Check.. 19
- Programmable Inter Packet Gap (IPG). 19
- TX PHY Interface..... 20
- RGMII TX.. 21
- MII TX... 23
- RMII TX.. 23
- GMII TX.. 23
- SGMII TX. 24
- RX PHY Interface.. 25
- RGMII RX... 26
- MII RX... 27
- RMII RX.. 28
- GMII RX.. 28
- SGMII RX.. 28
- Data Streaming Modes for Transmission.. 29
- Cut Through Mode... 29
- Cut Through Mode with Width Adaptation. 29
- Store Forward Mode.... 30
- Data Streaming Modes for Reception.. 31
- Cut Through Mode.......
- FIFO Mode...
- Automatic Padding for Short TX Frames.
- Terminating Bad TX Frames...... 32
- Non-Compliant tx\_axis\_mac\_tlast. 32
- Assertion of tx\_axis\_mac\_tuser... 33
- Non-Streaming TX Data...... .33
- Dropped tx\_axis\_mac\_tvalid Before End of Frame. 34
- TX FIFO Overflow...... 34
- Erroneous RX Frame.... . 35
- Undersized RX Frame..... 35
- Oversized RX Frame.... .35
- Frame Check Sequence (FCS) Error... 35
- Mismatched Length RX Frame.... 36
- Non-Streaming RX Data Frame (SGMII).. 36
- Error Frame..... . 36
- Address Filtering and Broadcast Filtering at RX. 37
- Priority Flow Control (Duplex Mode).... . 40
- Send Pause Frame at TX....... 40

- Decoding Pause Frame at RX. 41
- Statistic Reporting.......... 42
- aFramesTransmittedOK. 42
- aTxPAUSEMACCtrlFrames. 42
- ifOutErrors.. .42
- aTxFifoOverflowFramesErrors 43
- aTxIncontinuityFramesErrors. 43
- aFramesReceivedLen.. .43
- etherStatsUndersizePkts. .43
- etherStatsOversizePkts. .44
- aRxFrameMismatchedLength .44
- aFrameCheckSequenceErrors . 44
- aRxFilterFramesErrors.. .44
- aRxPAUSEMACCtrlFrames. .45
- ifInErrors.. 45
- aFramesReceivedOK. 45
- etherStatsPkts. 45
- Latency..................... .46
- IP Manager..... 47
- Customizing the Triple Speed Ethernet MAC... 48
- Ports................................................. . 50
- Control and Status Registers....... ..55
- Triple Speed Ethernet MAC Example Design........... 61
- Example Design with External PHY........... .61
- Required Hardware..... 62
- Hardware Set Up for Trion® T120 BGA324 Development Board.. . 63
- Hardware Set Up for Titanium Ti60 F225 Development Board. . 65
- Using the Example with the RISC-V SDK.. 66
- Test Modes...... 67
- Realigning the PHY Clock.... 71
- RGMII Dynamic Clock Switch (Titanium only). 72
- Using Wireshark....... 73
- Example Design Configuration Registers...... 74
- Example Design with FPGA Transceiver.... .75
- Available Macros in the Transceiver Example Design. ..78
- Enabling the Macros in the Transceiver Example Design . 79
- Generating the Example Design... .. 80
- Virtual I/O Debugger Settings.. . 82
- Triple Speed Ethernet MAC Testbench.. 84
- Differences with Ethernet 10G MAC Core . 85
- Revision History.................................... .....86

## Introduction

The Triple Speed Ethernet MAC core is a configurable core that complies with the IEEE Std. 802.3-2008 specification. The core supports Ethernet speeds of 2500 Mbps, 1000 Mbps, 100 Mbps, and 10 Mbps, with full duplex transfer mode.


## Note: Starting with IP version 7.0:

• Packets filtered by address filtering or broadcast filtering are silently dropped when crc\_fwd = 0 • When AXI Data Width = 8 and TX/RX FIFO is disabled, **Cut Through** mode is implemented to achieve minimum latency.

TX and RX AXI4-Stream interface operates on tx\_mac\_aclk and gm\_rx\_c clock domains respectively in **Cut Through** mode. Hence, the tx\_axis\_clk and rx\_axis\_clk ports are not used and connect to logic 0.

— If tx\_axis\_mac\_tvalid is deasserted before the end of the frame in **Cut Through** mode, the frame is terminated and flagged as a bad frame. See **Terminating Bad TX Frames** on page 32. — See **Clock Sources** on page 9 and **Cut Through Mode** on page 29 for more details.

Use the IP Manager to select IP, customize it, and generate files. The Triple Speed Ethernet MAC core has an interactive wizard to help you set parameters. The wizard also has options to create a testbench and/or example design targeting an Efinix® development board.

## Features

• Compliant with the IEEE Std. 802.3-2008 specification

• Supports VLAN frame and jumbo frame

• Supports 2500 Mbps, 1000 Mbps, 100 Mbps, and 10 Mbps in full-duplex mode

• 8-bit, 16-bit, and 32-bit AXI4-Stream user interface for packet transfer

• RGMII, MII, RMII, GMII, and SGMII PHY interfaces

• Optional internal FIFO buffers

Programmable source and destination MAC addresses

• Programmable inter packet gap (IPG)

• Automatic padding on short frames

• Frame check sequence or CRC generation, checking, and forwarding

• Frame length check against user-defined MTU frame length for received packets

• Frame length check against the LENGTH field for received packets

• Supports broadcast, unicast, and multicast address filtering

• Supports pause frame flow control

• Management data I/O (MDIO) for PHY device management

• AXI4-Lite or APB user interface for MAC configuration register access

• Statistic reporting

• Includes an example design targeting:

— Trion T120 BGA324 Development Board

— Titanium Ti60 F225 Development Board

— Titanium Ti375 N1156 Development Board

## Device Support

Table 1: Triple Speed Ethernet MAC Core Device Support

| FPGAFamily | Supported Device |
| --- | --- |
| Trion | All |
| Titanium | All |
| Topaz | All |

## Resource Utilization


**Note:** The resources and performance values provided are based on some of the supported FPGAs. These values are just guidance and may change depending on the device resource utilization, design congestion, and user design.

Table 2: Resource Utilization

<table><tbody><tr><td>FPGA</td><td>Mode</td><td>LUTs</td><td>Flip-Flop</td><td>Memory Block</td><td>DSP Block</td><td>Efinity®Version(<sup>1</sup>)</td></tr><tr><td rowspan="2">T120F324</td><td>Cut-Through Mode (GMII)</td><td>2,131 /112,128(1.90%)</td><td>1,369 /112,128(1.22%)</td><td>12 / 1,056(1.14%)</td><td>0 / 320 (0%)</td><td rowspan="6">2025.1</td></tr><tr><td>Store-Forward Mode (GMII)</td><td>2,568 /112,128(2.29%)</td><td>1782 /112,128(1.59%)</td><td>23 / 1,056(2.18%)</td><td>0 / 320 (0%)</td></tr><tr><td rowspan="2">Ti375N1156</td><td>Cut-Through Mode (SGMII)</td><td>2,820 /362,880(0.77%)</td><td>1,515 /362,880(0.42%)</td><td>12 / 2,688(0.45%)</td><td>0 / 1,344 (0%)</td></tr><tr><td>Store-Forward Mode (SGMII)</td><td>3,401 /362,880(0.94%)</td><td>2,025 /362,880(0.56%)</td><td>21 / 2,688(0.78%)</td><td>0 / 1,344 (0%)</td></tr><tr><td rowspan="2">Tz75N676</td><td>Cut-Through Mode (SGMII)</td><td>2,820 /129,600(2.17%)</td><td>1,515 /129,600(1.17%)</td><td>12 / 960 (1.25%)</td><td>0 / 480 (0%)</td></tr><tr><td>Store-Forward Mode (SGMII)</td><td>3,401 /129,600(2.62%)</td><td>2,025 /129,600(1.56%)</td><td>21 / 960 (2.19%)</td><td>0 / 480 (0%)</td></tr></tbody></table>


**Note:** The resource utilization data is derived based on the default settings.

## Release Notes

You can refer to the IP Core Release Notes for more information about the IP core changes. The IP Core Release Notes are available on the [**Efinity Downloads**](https://www.efinixinc.com/support/efinity.php) page under each Efinity software release version.


**Note:** You must be logged in to the Support Center to view the IP Core Release Notes.

<small><span class="docvortex-page-footnote" data-block-type="page_footnote" style="color:#6b7280">(1) System Verilog 2005.</span></small>

## Functional Description

The Triple Speed Ethernet MAC core does the following functions:

• Convert TX data packets from the AXI4-Stream to the PHY interface format.

• Decodes RX data packets from PHY interface format to AXI4-Stream.

• Generates the pause frame to be transmitted at the PHY interface.

Identifies the pause frame and implements priority flow control through the pause mechanism based on the decoded PAUSE\_QUANT.

• Drops RX frames with a mismatched address through a bit-wise address filtering mask.

• Drops RX frames with broadcast address.

The Triple Speed Ethernet MAC core supports multiple industry-standard PHY interfaces. **Table 3: Supported PHY Interfaces and Speed** on page 7 provides an overview of the data bus widths and supported speeds.

For detailed descriptions, refer to **TX PHY Interface** on page 20 and **RX PHY Interface** on page 25.

Table 3: Supported PHY Interfaces and Speed

<table><tbody><tr><td rowspan="2">PHY Interface</td><td rowspan="2">Data Bus Width</td><td colspan="4">Speed</td></tr><tr><td>2.5 G</td><td>1 G</td><td>10/100/1000M</td><td>10/100M</td></tr><tr><td>RGMII</td><td>4-bit (Double datarate)</td><td>-</td><td></td><td></td><td></td></tr><tr><td>MII</td><td>4-bit</td><td>-</td><td>-</td><td>-</td><td></td></tr><tr><td>RMII</td><td>2-bit</td><td>-</td><td>-</td><td>-</td><td></td></tr><tr><td>GMII</td><td>8-bit</td><td>-</td><td></td><td>-</td><td>-</td></tr><tr><td>SGMII</td><td>16-bit</td><td></td><td></td><td></td><td></td></tr></tbody></table>

## Block Diagram

The Triple Speed Ethernet MAC core or efx\_mac1gbe comprises of the following modules:

Power-up sequence to handshake with the FPGA transceiver in SGMII mode.

• AXI4-stream user interface

TX engine with CRC generation

RX engine with CRC checker

• PHY interface

• Statistics reporting

• Priority flow control module

• Broadcast and address filtering

**Figure 1: Triple Speed Ethernet MAC Core Sub-Modules** on page 8 shows the modules inside the Triple Speed Ethernet MAC core.

Figure 1: Triple Speed Ethernet MAC Core Sub-Modules


Note: The power-up sequence module is instantiated for SGMII mode only. Details of the power-up sequence are described in Power Up Handshake with FPGA Transceiver on page 14.

## Clock Sources

## The Triple Speed Ethernet MAC core clock sources are shown in the following table.

Table 4: Clock Sources in the Triple Speed Ethernet MAC Core

<table><tbody><tr><td>Clock Name</td><td colspan="3">Frequency</td><td>Description</td></tr><tr><td>tx_axis_clk</td><td colspan="3">RefertoTable5:MinimumClockFrequencyRequirementfortx_axis_clk and rx_axis_clk on page 10.</td><td>AXI4-StreamTXclock</td></tr><tr><td>rx_axis_clk</td><td colspan="3">RefertoTable5:MinimumClockFrequencyRequirementfortx_axis_clk and rx_axis_clk on page 10.</td><td>AXI4-StreamRXclock</td></tr><tr><td>s_axi_aclk</td><td colspan="3">Trion:≤100MHz Others: ≤ 200 MHz</td><td>Registeraccessinterfaceclock</td></tr><tr><td>init_clk</td><td colspan="3">≤ 50 MHz</td><td>Tofacilitatethepower-upsequenceoftheFPGA transceiverPHY.CanbesourcedfromthePLLorCLKIN pin.</td></tr><tr><td colspan="5">RGMII/ GMII/ SGMII</td></tr><tr><td rowspan="5">tx_mac_aclk</td><td colspan="3">125 MHz</td><td>RGMII/ GMII Transmitpathreferenceclock.Providestiming referencefortheRGMIIandGMIItransmitinterface.</td></tr><tr><td>2500 Mbps</td><td colspan="2">156.25 MHz</td><td rowspan="4">SGMII • StooubrecesodufrrcoemsythnechFrPoGnoAutsraannsdceeilvimerinfoartweaardddeidtiocnloaclk clock PPM. • T1hGe PsCaSm ienf tohrew FaPrdGeAdtcraloncskceisivaelsr.ousedtoclockthe</td></tr><tr><td>1000 Mbps</td><td colspan="2">62.5 MHz</td></tr><tr><td>100 Mbps</td><td colspan="2">6.25 MHz</td></tr><tr><td>10 Mbps</td><td colspan="2">0.625 MHz</td></tr><tr><td rowspan="5">gm_rx_c</td><td colspan="3">125 MHz</td><td>GMII GMIIreceiveclocksourcedfromthePHY.</td></tr><tr><td colspan="2">2500 Mbps</td><td>156.25 MHz</td><td rowspan="4">SGMII • StooubreceSdoufrrocemStyhnecFhProGnAouTsraannsdceeivliemrinFoatrewaardddeitdioCnlaolck clock PPM. • T1hGePsCaSmienFthoerwFaPrGdeAdTCralnoscckeiisvealrs.ousedtoclockthe</td></tr><tr><td colspan="2">1000 Mbps</td><td>62.5 MHz</td></tr><tr><td colspan="2">100 Mbps</td><td>6.25 MHz</td></tr><tr><td colspan="2">10 Mbps</td><td>0.625 MHz</td></tr><tr><td rowspan="3">rgmii_rxc</td><td colspan="2">1000 Mbps</td><td>125 MHz</td><td rowspan="3">RGMIIreceiveclocksourcedfromthePHY.</td></tr><tr><td colspan="2">100 Mbps</td><td>25 MHz</td></tr><tr><td colspan="2">10 Mbps</td><td>2.5 MHz</td></tr><tr><td colspan="5">RMII</td></tr><tr><td>rmii_clk_ref</td><td colspan="3">50 MHz</td><td>RMIIreferenceclock.</td></tr><tr><td colspan="5">MII</td></tr><tr><td rowspan="2">mii_txc</td><td colspan="2">100 Mbps</td><td>25 MHz</td><td rowspan="2">MIItransmitclocksourcedfromthePHY.</td></tr><tr><td colspan="2">10 Mbps</td><td>2.5 MHz</td></tr><tr><td rowspan="2">mii_rxc</td><td colspan="2">100 Mbps</td><td>25 MHz</td><td rowspan="2">MIIreceiveclocksourcedfromthePHY.</td></tr><tr><td colspan="2">10 Mbps</td><td>2.5 MHz</td></tr></tbody></table>

To prevent the AXI4-stream interface from limiting the performance, its clocks must meet the minimum frequency requirement listed in **Table 5: Minimum Clock Frequency Requirement for tx\_axis\_clk and rx\_axis\_clk** on page 10.

Table 5: Minimum Clock Frequency Requirement for tx\_axis\_clk and rx\_axis\_clk

<table><tbody><tr><td>Speed (Mbps)</td><td>AXI4-StreamDataWidth</td><td>Min.ClockFrequency(MHz)</td></tr><tr><td rowspan="3">2500</td><td>8</td><td>312.5</td></tr><tr><td>16</td><td>156.25</td></tr><tr><td>32</td><td>78.125</td></tr><tr><td rowspan="3">1000</td><td>8</td><td>125</td></tr><tr><td>16</td><td>62.5</td></tr><tr><td>32</td><td>31.25</td></tr><tr><td rowspan="3">100</td><td>8</td><td>12.5</td></tr><tr><td>16</td><td>6.25</td></tr><tr><td>32</td><td>3.125</td></tr><tr><td rowspan="3">10</td><td>8</td><td>1.25</td></tr><tr><td>16</td><td>0.625</td></tr><tr><td>32</td><td>0.3125</td></tr></tbody></table>


**Figure 2: Triple Speed Ethernet MAC Core Clock Domain** on page 11 shows the clock domains in the Triple Speed Ethernet MAC core.

Figure 2: Triple Speed Ethernet MAC Core Clock Domain


i Note: In Cut Through mode, the AXI4-stream interface operates on the tx\_mac\_aclk and gm\_rx\_c clock domains. The tx\_axis\_clk andrx\_axis\_clk ports are not used in this mode and should be logic 0.

## Reset Signals

The Triple Speed Ethernet MAC core has 3 reset signals. These signals are asynchronous. init\_rst\_n is active low, but mac\_reset and proto\_reset are active high.

• mac\_reset (Global Reset)

• proto\_reset (Protocol Reset)

• init\_rst\_n (Initialization Reset)

During the FPGA power-up, intitalize mac\_reset and proto\_reset to 1, and init\_rst\_n to 0 to ensure the Triple Speed Ethernet MAC core is held in a known reset state.

• mac\_reset (Global Reset)

— Resets all logic within the Triple Speed Ethernet MAC core, including control and status registers.

— Only the power-up sequence module remains unaffected and operational.

• proto\_reset (Protocol Reset)

— Resets both the TX and RX data paths, as well as the statistics counters.

— Does not affect the power-up sequence module.

• init\_rst\_n (Initialization Reset)

— Used when pairing the Triple Speed Ethernet MAC core with an FPGA transceiver in SGMII mode.

— Requires a free-running init\_clk.

Upon IN\_USER, deassert init\_rst\_n to start the power-up handshake with the FPGA ransceiver.

— Must remain deasserted throughout normal operation.

Detailed power-up sequence is described in **Power Up Handshake with FPGA Transceiver** on page 14.

For synchronization reset, all three resets are asynchronous assertion or synchronous deassertion.

• init\_rst\_n is synchronized internally to init\_clk.

• mac\_reset and proto\_reset are synchronized internally to their respective clock domains.

• Each reset synchronizer introduces a 2 – 3 clock cycle latency upon deassertion.


**Note:** To ensure proper operation after reset deasssertion, you must delay data transmission by at least 3 clock cycles following the release of the reset signal. This delay allows sufficient time for the internal reset synchronizers to stabilize before any AXI4-Stream or PHY interface activity begins. Failure to observe this delay may result in undefined behavior or corrupted frame transmission during the startup process.

The **Figure 3: Triple Speed Ethernet MAC Core Reset Domains** on page 13 shows the reset domains in the Triple Speed Ethernet MAC core.

Figure 3: Triple Speed Ethernet MAC Core Reset Domains


## Power Up Handshake with FPGA Transceiver

Before starting the operation of the Triple Speed Ethernet MAC core, it needs to perform the power-up handshake with the FPGA transceiver.

The Triple Speed Ethernet MAC core includes a built-in power-up sequence module to handshake with the FPGA transceiver PHY. For the details on the power-up sequence in the FPGA transceiver, refer to the power-up sequence chapter of the [**Titanium SGMII 1G and 2.5G User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=UG-TiSGMII). **Figure 4: Power Up Handshake with the FPGA Transceiver PHY and PCS** on page 14 shows the power-up handshake between the Triple Speed Ethernet MAC core and the FPGA transceiver.

The power-up sequence between the Triple Speed Ethernet MAC core and the FPGA transceiver PHY is clocked by init\_clk. The assertion of phy\_init\_done indicates that the FPGA transceiver PHY is CDR-lock-to-data.

After the assertion of phy\_init\_done, you need to configure the FPGA transceiver PCS which uses the common APB interface. The APB interface is a common interface that is shared across all the 4 lanes within a Quad. You need to create APB modules to configure the PCS, based on the register mapping in the [**Titanium SGMII 1G and 2.5G User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=UG-TiSGMII). **Figure 4: Power Up Handshake with the FPGA Transceiver PHY and PCS** on page 14 includes an illustration of APB Write to enable PCS RX in lane 2.

Figure 4: Power Up Handshake with the FPGA Transceiver PHY and PCS



O **Important:** When the FPGA PHY is in reset, both mac\_reset and init\_rst\_n need to be asserted too. Once the FPGA PHY recovers from the reset, the user needs to repeat the entire power-up handshake by de-asserting the init\_rst\_n to restart the power-up sequence.

## Ethernet Packets, Frames, and IPG

**Figure 5: 802.3 Ethernet Packet and Frame Structure for Non-VLAN Tagged Frame** on page 15 illustrates the Ethernet packet and frame structure for non-VLAN tagged frame.

Figure 5: 802.3 Ethernet Packet and Frame Structure for Non-VLAN Tagged Frame

|  |  |  |  |  |  | 46 - 1500 |  |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Typically 12 Octets | 7 Octets | 1 Octet | 6 Octets | 6 Octets | 2 Octets | Octets | 4 Octets |
| INTER P(AIPCGK)ET GAP | PREAMBLE | DSETLAIMRITTE FRRA (SMFED) | DESTMINAACTION | SOMUARCCE | ETHLEERNTGYTPHE OR | PAYLOAD | SEFQRUAEMCNERC CCEH (E32C-Kbit) |

**Figure 6: 802.3 Ethernet Packet and Frame Structure for VLAN Tagged Frame** on page 15 illustrates the Ethernet packet and frame structure for VLAN tagged frame.

**Figure 6: 802.3 Ethernet Packet and Frame Structure for VLAN Tagged Frame**

| Typically 12 Octets | 7 Octets | 1 Octet | 6 Octets | 6 Octets | 4 Octets | 2 Octets | 42 - 1500 Octets | 4 Octets |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| INTER PACKET GAP (IPG) | PREAMBLE | START FRAME DELIMITER (SFD) | MAC DESTINATION | MAC SOURCE | VLAN TAG 802.1Q | ETHERTYPE OR LENGTH | PAYLOAD | FRAME CHECK SEQUENCE (32-bit) CRC |

## User Interface AXI4-Stream

AXI4-stream is a user interface comprising TX channel and RX channel.

## TX AXI ST Interface

At TX AXI ST interface, transmission starts when tx\_axis\_mac\_tready = 1. The assertion of tx\_axis\_mac\_tready indicates that Triple Speed Ethernet MAC core is ready to accept the TX data streaming from the user.

To transmit, assert tx\_axis\_mac\_tvalid, along with tx\_axis\_mac\_tdata, tx\_axis\_mac\_tstrb, tx\_axis\_mac\_tlast, and tx\_axis\_mac\_tuser.

tx\_axis\_mac\_tdata contains the data streaming to be transmitted to the selected PHY interface. Tranmission must begin with header information – destination address, source destination, ethernet length or type, and followed by the payload data.

• tx\_axis\_mac\_tlast indicates the final transfer in the data streaming.

• tx\_axis\_mac\_tstrb indicates the positional validity of the data byte within the data streaming.

• tx\_axis\_mac\_tuser indicates an error in the data streaming.

For Ethernet application, tx\_axis\_mac\_tdata must contain streaming data, i.e., data needs to be streaming and continuous, During streaming, all bytes must be valid, i.e., tx\_axis\_mac\_tstrb = all 1s, except for the final transfer when tx\_axis\_mac\_tlast is asserted. At tx\_axis\_mac\_tlast, tx\_axis\_mac\_tstrb indicates the number of valid bytes in the final word, starting from the least significant byte. For example, refer to **Figure 7: Streaming Data at TX AXI ST Interface** on page 16.

In the event of a non-data streaming, it is interpreted as a bad frame and is dropped. Similarly, asserting tx\_axis\_mac\_tuser during transmission results in a bad frame. Refer to **Terminating Bad TX Frames** on page 32.

When tx\_axis\_mac\_tready = 0, the Triple Speed Ethernet MAC core is not ready to accept any TX data. Hence, you need to hold all current tx\_axis\_macsignals, which are tx\_axis\_mac\_tdata, tx\_axis\_mac\_tlast, tx\_axis\_mac\_tvalid, tx\_axis\_mac\_tstrb, and tx\_axis\_mac\_tuser, until tx\_axis\_mac\_tready returns to 1. Refer to **Figure 8: User to Retain tx\_axis\_mac Signals Until tx\_axis\_mac\_tready Recovers** on page 17.

Figure 7: Streaming Data at TX AXI ST Interface

|  | tx_axis_clk |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  | mac_reset |  |  | Assertion of tx_axi_tready indicates that Triple Speed Ethernet MAC IP is ready to accept TX Data from User |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| tx_axis_mac_tready |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2nd and 3rd Frames are back-to-back Streaming TX Data Frames |  |  |  |  |  |  |  |  |  |  |  |  |  |
|  |  |  |  | 1 |  | Streaming TX Data (1st Frame) |  |  |  |  |  |  | 4 |  |  | Streaming TX Data (2nd Frame) |  |  |  |  |  |  |  |  |  | Streaming TX Data (3rd Frame) |  |  |  |  |
| tx_axis_mac_tvalid |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| tx_axis_mac_last |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| tx_axis_mac_strb[1:0] |  |  |  | 2′b112'b11 |  |  | 2°b11 |  | 2'b11 |  | 2'b11 |  |  | 2'b11 | 2'b11 |  | 2'b11 |  | 2b11 | 2'b01 |  | 2'b11 | 2b11 |  | 2b11 |  | 2'b11 | 2'b11 |  |  |
| tx_axis_mac_tdata[15:8] |  |  |  | DATA01DATA03 DATA00DATA02 |  |  | DATA05 DATA04 |  |  | DATA81DATA83 DATA80 DATA82 |  |  |  | DATA01 DATA00 | DATA03 DATA02 |  | DATA05 DATA04 |  | DATA57 DATA56 |  |  | DATA01 | DATA03 |  | DATA05/ |  |  | DATA65DATA67 |  |  |
| tx_axis_mac_tdata[7:0] |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | DATA58 |  | DATA00 | DATA02 |  | DATA04 |  | DATA64 | DATA66 |  |  |
|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |

Figure 8: User to Retain tx\_axis\_mac Signals Until tx\_axis\_mac\_tready Recovers


Notes: (1) When tx\_axis\_mac\_tready=0, you need to retain tx\_axis\_mac signals (tvalid, tlast, tstrb, tdata) until tx\_axis\_mac\_tready recovers. (2) When tx\_axis\_mac\_tready=1, you may change tx\_axis\_mac signals (tvalid, tlast, tstrb, tdata) to new values / states.

In **Cut Through** mode, if tx\_axis\_mac\_tvalid goes low before end-of-frame, the Triple Speed Ethernet MAC core ends the transmission with an error frame and drops the rest of the packet. However, in **Cut Through mode with width-adaptation** or **Store Forward** mode, when tx\_axis\_mac\_tvalid = 0, all tx\_axis\_mac signals for that cycle are ignored but no error occurs. Refer to **Terminating Bad TX Frames** on page 32.


**Note:** When the Triple Speed Ethernet MAC core is configured in **Cut Through mode with widthadaptation** or **Store Forward** mode, the TX AXI ST interface operates in the tx\_axis\_clk domain. You must ensure that the tx\_axis\_mac\_tvalid, tx\_axis\_mac\_tdata, tx\_axis\_mac\_tstrb, tx\_axis\_mac\_tlast, and tx\_axis\_mac\_tuser signals are properly registered and synchronous to tx\_axis\_clk before entering the Triple Speed Ethernet MAC core. When the Triple Speed Ethernet MAC core is configured in **Cut Through** mode, the TX AXI ST interface operates in the tx\_mac\_aclk domain, and these signals must be synchronous to tx\_mac\_aclk.


**Note:** The tx\_axis\_mac\_tstrb signal in the Triple Speed Ethernet MAC core functions as TKEEP in AXI4-Stream terminology, indicating a valid byte. The name is preserved as TSTRB for backward compatibility.

## RX AXI ST Interface

At the RX AXI ST interface, rx\_axis\_mac\_tvalid indicates the validity of the received data frame. rx\_axis\_mac\_tdata carries the data decoded from the selected PHY Interface, while rx\_axis\_mac\_tlast marks the final transfer of the frame. rx\_axis\_mac\_tstrb indicates the positional validity of the data byte within the RX data frame, and rx\_axis\_mac\_tuser signals that the received frame contains an error. See **Erroneous RX Frame** on page 35 for further details.

When crc\_fwd = 1, the rx\_axis\_mac\_tdata port includes both the RX data frame and CRC octets. More details on CRC forwarding are provided in **CRC Generation and Check** on page 19 and **Figure 10: RX Data Frame and CRC Octets at AXI ST Interface when crc\_fwd = 1** on page 18.

If the AXI4-Stream interface bandwidth exceeds the PHY interface bandwidth (for example, when using a wider AXI data width or a faster AXI clock, the RX AXI stream may appear non-streaming even for valid frames. This occurs because the PHY provides data at a lower rate than the AXI interface can accept, resulting in intermittent valid cycles (rx\_axis\_mac\_tvalid deasserted between data beats). This behavior is expected and does not indicate an error.


**Note:** Back pressure on the RX path through rx\_axis\_mac\_tready is not supported and may result in data corruption. Therefore, it is recommended to initialize rx\_axis\_mac\_tready to 1 to ensure reliable operation.

Figure 9: RX Data Frame at AXI ST Interface when crc\_fwd = 0


Figure 10: RX Data Frame and CRC Octets at AXI ST Interface when crc\_fwd = 1


Note: rx\_axis\_mac\_tdata includes Forwarded CRC Octets.

## CRC Generation and Check

At the TX channel, the Triple Speed Ethernet MAC core automatically generates CRC octets, appends them to the end of frame, and transmits to the selected PHY interface.

At the RX channel, the Triple Speed Ethernet MAC core decodes the Ethernet frames and checks them against 4 CRC octets that trail the Ethernet frame. At the RX AXI ST interface, by default, the CRC octets are not forwarded to the rx\_axis\_mac\_tdata port. To enable CRC forwarding to the rx\_axis\_mac\_tdata port, configure the crc\_fwd configuration bit to 1.

The CRC polynomial that is used in Triple Speed Ethernet MAC core is $\mathrm { x } ^ { 3 2 }   +   \mathrm { x } ^ { 2 6 }   +   \mathrm { x } ^ { 2 3 }   +$ $\mathrm{x}^{22}+\mathrm{x}^{16}+\mathrm{x}^{12}+\mathrm{x}^{11}+\mathrm{x}^{10}+\mathrm{x}^{8}+\mathrm{x}^{7}+\mathrm{x}^{5}+\mathrm{x}^{4}+\mathrm{x}^{2}+\mathrm{x}+1.$

## Programmable Inter Packet Gap (IPG)

The Triple Speed Ethernet MAC core supports a programmable IPG, configurable from 8 to 63 octets. The default IPG value can be set during IP generation in the IP Configuration window under **Programmable Inter Packet Gap**.

After the core is generated, the IPG can also be updated dynamically by writing to the tx\_ipg\_length register. Refer to **Control and Status Registers** on page 55 for register configuration guidelines.

Based on the configured IPG value, the MAC automatically inserts the minimum required gaps between transmitted frames. The implementation of IPG insertion is illustrated in **Figure 17: Conversion from TX AXI ST to SGMII TX** on page 24.

## TX PHY Interface

At the PHY interface, Triple Speed Ethernet MAC core schedules transmit packets based on the following priority (highest to lowest):

**1.** Pause mechanism triggered by a received pause frame.

**2.** Request to transmit a pause frame (xon\_gen/ xoff\_gen)

**3.** User data from TX AXI4-stream interface (tx\_axis\_mac\_tvalid, tx\_axis\_mac\_tlast, tx\_axis\_mac\_tstrb, tx\_axis\_mac\_tdata, and tx\_axis\_mac\_tuser)

User data transfer from the tx\_axis\_mac signals interface always has the lowest priority. The Triple Speed Ethernet MAC core maps tx\_axis\_mac\_tdata directly onto the transmit data bus of the selected PHY interface. Therefore, tx\_axis\_mac\_tdata must begin with the Ethernet frame header, i.e., Destination address, source address, length / type, and optional VLAN tags. In the figures of this user guide, the header octets are shown as DATA, to focus on the conversion between the TX AXI ST interface and the selected PHY interface.

When a higher-priority event (pause mechanism or pause frame request) is asserted during an ongoing transfer, the Triple Speed Ethernet MAC core waits until the current frame transmission is completed before servicing the higher-priority request.

You can get details on the transmission priority handling in **Priority Flow Control (Duplex Mode)** on page 40.

Notes: (1) De-assertion of tx\_axis\_mac\_tready is not accurately illustrated in this diagram. (2) Latency between TX AXI ST and RGMII is not accurately illustrated in this diagram. (3) Each byte is shown as two nibbles: (L) for lower 4 bits and (U) for upper 4 bits

## RGMII TX

For the RGMII interface, the **Double Data I/O (DDIO)** option must be enabled for the transmission of clock, data, and control signals. **Table 6: Block Editor Settings for rgmii\_txc, rgmii\_txd, and rgmii\_tx\_ctl** on page 21 shows the recommended Block Editor settings for rgmii\_txc, rgmii\_txd, and rgmii\_tx\_ctl.

Table 6: Block Editor Settings for rgmii\_txc, rgmii\_txd, and rgmii\_tx\_ctl

<table><tbody><tr><td rowspan="2">Parameter</td><td colspan="3">Setting</td></tr><tr><td>rgmii_txc</td><td>rgmii_txd[3:0]</td><td>rgmii_tx_ctl</td></tr><tr><td>Mode</td><td>output</td><td>output</td><td>output</td></tr><tr><td>RegisterOption</td><td>register</td><td>register</td><td>register</td></tr><tr><td>Double Data I/O Option</td><td>resync</td><td>resync</td><td>resync</td></tr><tr><td>ClockPinName</td><td>-</td><td>-</td><td>-</td></tr><tr><td>PinName(HI)</td><td>rgmii_txc_HI</td><td>rgmii_txd_HI</td><td>rgmii_tx_ctl_HI</td></tr><tr><td>PinName(LO)</td><td>rgmii_txc_LO</td><td>rgmii_txd_LO</td><td>rgmii_tx_ctl_LO</td></tr><tr><td>Enableinvertclock</td><td>Yes(Trion) No(Titanium)</td><td>No</td><td>No</td></tr><tr><td>OutputClockPin Name</td><td>clk_125m_90deg</td><td>clk_125m(<sup>2</sup>)</td><td>clk_125m</td></tr></tbody></table>

## Note: (2) Select clk\_125m if RGMII Transmit Clock Delay is Disabled (Edge-aligned).

In the Efinity Interface Designer, use the **Create Block/ Create Bus** menu to add these signals and configure them according to **Table 6: Block Editor Settings for rgmii\_txc, rgmii\_txd, and rgmii\_tx\_ctl** on page 21.

**Figure 11: Conversion from TX AXI ST to RGMII TX at 1000 Mbps** on page 21 to **Figure 13: Conversion from TX AXI ST to RGMII TX at 100 Mbps** on page 22 illustrates the conversion from TX AXI ST to RGMII TX at different operating speeds with the recommended block editor settings in **Table 6: Block Editor Settings for rgmii\_txc, rgmii\_txd, and rgmii\_tx\_ctl** on page 21.

Figure 11: Conversion from TX AXI ST to RGMII TX at 1000 Mbps


Figure 12: Conversion from TX AXI ST to RGMII TX at 100 Mbps

with RGMII Transmit Clock Delay Enabled (Center-aligned)


Figure 13: Conversion from TX AXI ST to RGMII TX at 100 Mbps

with RGMII Transmit Clock Delay Disabled (Edge-aligned)


The RGMII specification requires a clock-to-data skew to ensure correct sampling. This skew can be introduced either by PCB trace routing or by enabling the **RGMII Transmit Clock Delay** option in the GUI. This option only applies to 10 Mbps and 100 Mbps operation.

At 1000 Mbps, the required clock-to-data skew is achived internally by selecting a clock with a 90-degree phase shift (clk\_125m\_90deg) relative to the clock used to drive the data signals as the output clock for the rgmii\_txc DDIO register. This configuration introduces an approximate 2 ns delay, aligning the rgmii\_txc edge at the center of the data valid window for the transmitted RGMII data and control signals.

At 100 Mbps, the rgmii\_txc\_HI and rgmii\_txc\_LO signals are generated by dividing tx\_mac\_aclk by 5. The transmitted data on rgmii\_txd\_HI and rgmii\_txd\_LO are duplicated 5 times.

At 10 Mbps, the behavior is similar to 100 Mbps. The difference is that rgmii\_txc\_HI and rgmii\_txc\_LO are generated by dividing tx\_mac\_aclk by 50 instead of 5. The transmitted data on rgmii\_txd\_HI and rgmii\_txd\_LO are duplicated 50 times instead of 5 times.

By default, the **RGMII Transmit Clock Delay** option is enabled, resulting in center-aligned operation.

## MII TX

**Figure 14: Conversion from TX AXI ST to MII TX** on page 23 illustrates the conversion from TX AXI ST to MII TX.

Figure 14: Conversion from TX AXI ST to MII TX


RMII TX

Figure 15: Conversion from TX AXI ST to RMII TX on page 23 illustrates the conversion from TX AXI ST to RMII TX.

Figure 15: Conversion from TX AXI ST to RMII TX


**Figure 16: Conversion from TX AXI ST to GMII TX** on page 23 illustrates the conversion from TX AXI ST to GMII TX.

Figure 16: Conversion from TX AXI ST to GMII TX


## SGMII TX

## Figure 17: Conversion from TX AXI ST to SGMII TX on page 24 illustrates the conversion from TX AXI ST to SGMII TX.

Figure 17: Conversion from TX AXI ST to SGMII TX


Notes: (1) De-assertion of tx\_axis\_mac\_tready is not accurately illustrated in this diagram. (2) Latency between TX AXI ST and GMII is not accurately illustrated in this diagram.

## RX PHY Interface

At the RX path, the Triple Speed Ethernet MAC core decodes the selected PHY interface (RGMII, MII, RMII, GMII, or SGMII) and outputs the corresponding data stream on the RX AXI ST interface. If the received Ethernet frame begins at the upper octet, the Triple Speed Ethernet MAC core realigns the streaming data so that rx\_axis\_mac\_tstrb starts with 2’b11.

Every Ethernet Frame received by the Triple Speed Ethernet MAC core is checked against the following criteria:

• Frame Length—Verification of minimum and maximum frame size.

• FCS Check—Validation of the frame check sequence.

• Error Frame Detection—Identification of corrupted or invalid frames.

• Pause Frame Recognition—Detection and processing of PAUSE control frames.

• Address or Broadcast Filtering—Filtering based on programmed Triple Speed Ethernet MAC core addresses and broadcast rules.


**Note:** Frame Length and FCS Check are performed only for non-error frames received from the PHY. If the PHY reports an error frame (e.g., via gm\_rx\_err), the Triple Speed Ethernet MAC core bypasses Frame Length and FCS checking for that frame. Consequently the aRxFrameMismatchedLength and aRxFrameCheckSequenceErrors statistic counters do not increment even if the frame exhibits length mismatch or FCS errors.

More details on the RX frame handling are provided in **Erroneous RX Frame** on page 35, **Address Filtering and Broadcast Filtering at RX** on page 37, and **Decoding Pause Frame at RX** on page 41.

## RGMII RX

For the RGMII interface, the **Double Data I/O (DDIO)** option must be enabled for the receive data and control signals. **Table 7: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Trion Devices** on page 26 and **Table 8: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Titanium/ Topaz Devices** on page 26 show the recommended Block Editor settings for rgmii\_rxd and rgmii\_rx\_ctl.

**Table 7: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Trion Devices**

With First Sampling of RGMII Receive Data Option Set to Rising Edge

<table><tbody><tr><td rowspan="2">Parameter</td><td colspan="2">Setting</td></tr><tr><td>rgmii_rxd[3:0]</td><td>rgmii_rx_ctl</td></tr><tr><td>Mode</td><td>Input</td><td>Input</td></tr><tr><td>RegisterOption</td><td>Register</td><td>Register</td></tr><tr><td>Double Data I/O Option</td><td>Resync</td><td>Resync</td></tr><tr><td>ClockPinName</td><td>rgmii_rxc</td><td>rgmii_rxc</td></tr><tr><td>PinName(HI)</td><td>rgmii_rxd_HI</td><td>rgmii_rx_ctl_HI</td></tr><tr><td>PinName(LO)</td><td>rgmii_rxd_LO</td><td>rgmii_rx_ctl_LO</td></tr></tbody></table>


**Note:** Due to the limited availability of GPIO pins with capability on the Trion T120 BGA324 development board, the example design with external PHY targeting this device cannot assign the RGMII control signals (rgmii\_tx\_ctl and rgmii\_rx\_ctl) to a standard DDIO block.

To accommodate for this specific hardware limitation, the following workaround is implemented in tsemac\_ex.v:

```txt
assign rgmii_tx_ctl = rgmii_tx_ctl_HI | rgmii_tx_ctl_LO;
assign rgmii_rx_ctl_HI = rgmii_rx_ctl;
assign rgmii_rx_ctl_LO = rgmii_rx_ctl;
```

**Table 8: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Titanium/ Topaz Devices**

With First Sampling of RGMII Receive Data Option Set to Falling Edge

<table><tbody><tr><td rowspan="2">Parameter</td><td colspan="2">Setting</td></tr><tr><td>rgmii_rxd[3:0]</td><td>rgmii_rx_ctl</td></tr><tr><td>Mode</td><td>Input</td><td>Input</td></tr><tr><td>RegisterOption</td><td>Register</td><td>Register</td></tr><tr><td>Double Data I/O Option</td><td>Pipeline</td><td>Pipeline</td></tr><tr><td>ClockPinName</td><td>rgmii_rxc</td><td>rgmii_rxc</td></tr><tr><td>PinName(HI)</td><td>rgmii_rxd_LO</td><td>rgmii_rx_ctl_LO</td></tr><tr><td>PinName(LO)</td><td>rgmii_rxd_HI</td><td>rgmii_rx_ctl_HI</td></tr></tbody></table>

In the Efinity Interface Designer, use the **Create Block/ Create Bus** menu to add these signals and configure them according to **Table 7: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Trion Devices** on page 26 and **Table 8: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Titanium/ Topaz Devices** on page 26.

**Figure 18: Conversion from RGMII RX to RX AXI ST at 1000 Mbps (Trion Block Editor Settings)** on page 27 and **Figure 19: Conversion from RGMII RX to RX AXI ST at 1000 Mbps (Titanium/ Topaz Block Editor Settings** on page 27 illustrate the conversion from RGMII RX to RX AXI ST at 1000 Mbps with the recommended block editor settings in **Table 7: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Trion Devices** on page 26 and **Table 8: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Titanium/ Topaz Devices** on page 26.

Figure 18: Conversion from RGMII RX to RX AXI ST at 1000 Mbps (Trion Block Editor Settings) Based on Table 7: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Trion Devices on page 26


Figure 19: Conversion from RGMII RX to RX AXI ST at 1000 Mbps (Titanium/ Topaz Block Editor Settings

Based on Table 8: Block Editor Settings for rgmii\_rxd, and rgmii\_rx\_ctl Targeting Titanium/ Topaz Devices on page 26


Figure 20: Conversion from MII RX to RX AXI ST on page 27 illustrates the conversion from MII RX to RX AXI ST.

Figure 20: Conversion from MII RX to RX AXI ST


## RMII RX

## Figure 21: Conversion from RMII RX to RX AXI ST on page 28 illustrates the conversion from RMII RX to RX AXI ST.

Figure 21: Conversion from RMII RX to RX AXI ST


## GMII RX

Figure 22: Conversion from GMII RX to RX AXI ST on page 28 illustrates the conversion from GMII RX to RX AXI ST.

Figure 22: Conversion from GMII RX to RX AXI ST


## SGMII RX

Figure 23: Conversion from SGMII RX to RX AXI ST on page 28 illustrates the conversion from SGMII RX to RX AXI ST.

Figure 23: Conversion from SGMII RX to RX AXI ST


## Data Streaming Modes for Transmission

In Triple Speed Ethernet MAC core, 3 data streaming modes are available for the TX channel:

• **Cut Through** mode

• **Cut Through** with width-adaptation

**Store Forward** mode

## Cut Through Mode

During **Cut Through** mode, the Triple Speed Ethernet MAC core starts transmitting an Ethernet frame before the entire packet has been received on the AXI4-stream interface. This reduces latency compared to **Store Forward** mode.

Cut-Through Mode is available when the AXI data width matches the PHY data width and the transmit FIFO is disabled:

AXI4 Data Width = 8, PHY Interface = 8-bit GMII

AXI4 Data Width = 16, PHY Interface = 16-bit GMII (SGMII)

If an error occurs during transmission in this mode, the MAC terminates the frame as an error frame. See **Terminating Bad TX Frames** on page 32 for details.

Figure 24: Cut Through Mode


## Cut Through Mode with Width Adaptation

This mode behaves like **Cut Through** mode, but is used when the AXI data width does not match the PHY data width and the transmit FIFO is disabled. In this case, a shallow FIFO is inserted to perform width adaptation between the AXI4-stream interface and the PHY interface.

• Transmission still starts before the end of the frame is received, minimizing latency

• The shallow FIFO is only used for width conversion and does not buffer the entire frame.

Error handling follows the same rules as in **Cut Through** mode.

## Store Forward Mode

In **Store Forward** mode, the MAC buffers the entire frame in the transmit FIFO before initiating transmission on the PHY interface. The TXFIFO must be large enough to accommodate the complete frame, including Ethernet headers and optional VLAN tags. Transmission begins only after the entire frame has been received (tx\_axis\_mac\_tlast asserted), subject to the transmit priority rules described in **TX PHY Interface** on page 20.

The minimum TXFIFO depth required is calculated as follows:

• Without VLAN tag:

$$
\mathrm{TXFFO}\ \mathrm{Depth} \geq \frac{14\ \mathrm{Hender}\ \mathrm{Byters}+\mathrm{Maximum}\ \mathrm{Payload}\ \mathrm{Size}}{(\frac{\mathrm{AXI}\ \mathrm{Data}\ \mathrm{Width}}{8})}
$$

• With VLAN tag:

$$
\mathrm{TXFFO}\ \mathrm{Depth} \geq \frac{18\ \mathrm{Hender}\ \mathrm{Byters} + \mathrm{Maximum}\ \mathrm{Payload}\ \mathrm{Size}}{(\frac{\mathrm{AXI}\ \mathrm{Data}\ \mathrm{Width}}{8})}
$$

If the TXFIFO overflows before the entire frame is stored, the incomplete frame is discarded and is not transmitted.

During operation, when tx\_axis\_mac\_tvalid = 1, the MAC stores the corresponding tx\_axis\_mac\_tdata, tx\_axis\_mac\_tstrb, and tx\_axis\_mac\_tlast. When tx\_axis\_mac\_tvalid = 0, no data is stored for that cycle. The frame is not terminated, and transmission still proceeds once the complete frame is received.

However, if tx\_axis\_mac\_tstrb deasserts before tx\_axis\_mac\_tlast (i.e., dropped bytes within the middle of a frame), the MAC treats the frame as invalid. In this case, the frame is flagged as an error frame and terminated. See **Terminating Bad TX Frames** on page 32 for more details.

Figure 25: Store Forward Mode


## Data Streaming Modes for Reception

The Triple Speed Ethernet MAC core supports 2 data streaming modes on the RX channel, depending on the configuration of the receive FIFO and AXI interface width:

• **Cut Through** mode

• **FIFO** mode

In both modes, the Triple Speed Ethernet MAC core begins forwarding received data to the RX AXI4-Stream interface as soon as the frame starts arriving from the PHY interface.

The key difference lies in latency and buffering behavior. The **Cut Through** mode provides minimum latency, while **FIFO** mode introduces additional delay due to buffering and potential clock domain crossing.

## Cut Through Mode

During **Cut Through** mode, the Triple Speed Ethernet MAC core streams data directly from the PHY interface to the RX AXI4-Stream interface without intermediate buffering.

This mode offers the lowest latency and is available when the AXI data width matches the PHY data width and the RX FIFO is disabled:

• AXI4 Data Width = 8, PHY Interface = 8-bit GMII

AXI4 Data Width = 16, PHY Interface = 16-bit GMII (SGMII)

## FIFO Mode

During **FIFO** mode, the Triple Speed Ethernet MAC core begins forwarding data as the frame is received but includes an internal FIFO to provide elasticity and safe clock domain crossing between the PHY and AXI clock domains.

This mode is required when the two clocks are asynchronous or operate at different frequencies.

Because data is written into and read out from FIFO, this mode introduces slightly higher latency compared to **Cut Through** mode.

The minimum RX FIFO depth depends on the PHY interface types and maximum frame size:

• For SGMII Interface:

Without VLAN tag: RXFIFO Depth ≥ (14 Header Bytes + Maximum Payload Size) / 2

— With VLAN tag: RXFIFO Depth ≥ (18 Header Bytes + Maximum Payload Size) / 2

• For other interfaces (RGMII, MII, RMII, GMII)

— Without VLAN tag: RXFIFO Depth ≥ (14 Header Bytes + Maximum Payload Size)

— With VLAN tag: RXFIFO Depth ≥ (18 Header Bytes + Maximum Payload Size)

## Automatic Padding for Short TX Frames

To conform to the Ethernet format, the minimum payload size is 46 for non-VLAN tagged and 42 for VLAN tagged frames. In the event of short TX packets, the Triple Speed Ethernet MAC core automatically pads with zeros to fulfill the minimum payload size.

## Terminating Bad TX Frames

The following conditions are the causes of a frame being terminated as a bad frame at TX channels:

• Non-Compliant tx\_axis\_mac\_tlast

• Assertion of tx\_axis\_mac\_tuser

• Non-streaming TX data

• Dropped tx\_axis\_mac\_tvalid (**Cut Through** mode only)

TXFIFO overflow (**Store Forward** mode only)

## Non-Compliant tx\_axis\_mac\_tlast

An Ethernet frame should consist minimally of the Ethernet header, which includes the following:

• Destination address

• Source address

Optional VLAN tag

• Ethernet type/length

If tx\_axis\_mac\_tlast is asserted within the Ethernet header, it is known as a non-compliant tx\_axis\_mac\_tlast.

When tx\_axis\_mac\_tlast is asserted at the first cycle for the following configurations:

• AXI Data Width = 8 (all supported PHY interfaces)

• AXI Data Width = 16 (SGMII mode)

The frame is dropped silently, and there is no indicator of the dropped frame. No statistic counter is incremented in this case.

However, if tx\_axis\_mac\_tlast is asserted from the 2<sup>nd</sup> cycle onwards but still within the header, the header is considered incomplete. In this condition, the Triple Speed Ethernet MACcore terminates the frame and asserts the corresponding PHY error signal (e.g., gm\_tx\_err for SGMII or GMII interface).

## Assertion of tx\_axis\_mac\_tuser

The assertion of tx\_axis\_mac\_tuser indicates that there is an error in the data streaming transmission. Upon the assertion of tx\_axis\_mac\_tuser and tx\_axis\_mac\_tvalid, the Triple Speed Ethernet MAC core terminates the frame with an error indication and discards the remaining portion of the frame.

When tx\_axis\_mac\_tuser is asserted at the first cycle, the frame is dropped silently, and there is no indicator of the dropped frame. No statistic counter is incremented in this case.

However, if tx\_axis\_mac\_tuser is asserted while tx\_axis\_mac\_tlast remains low from the 2n cycle onwards but still within the Ethernet header, the header is considered incomplete. In this condition, the Triple Speed Ethernet MAC core terminates the frame, discards the remaining portion, and asserts the corresponding PHY error signal (e.g., gm\_tx\_err for SGMII or GMII interface).

When tx\_axis\_mac\_tvalid is low, all tx\_axis\_mac signals (tdata, tstrb, tlast, tuser) interface are considered invalid, as described in **TX AXI ST Interface** on page 16. Therefore, an assertion of tx\_axis\_mac\_tuser during a cycle where tx\_axis\_mac\_tvalid is deasserted does not indicate an error condition.

However, in **Cut Through** mode, if tx\_axis\_mac\_tvalid is deasserted prematurely (before the end of frame), the Triple Speed Ethernet MAC core terminates the transmission as a bad frame, as described in **Dropped tx\_axis\_mac\_tvalid Before End of Frame** on page 34.

## Non-Streaming TX Data

For Ethernet applications, tx\_axis\_mac\_tdata must be streaming and continuous throughout a frame. This requires that tx\_axis\_mac\_tstrb be fully asserted (all 1’s) on every cycle, except the final cycle of the frame indicated by tx\_axis\_mac\_tlast.

• 8-bit AXI data width;

— tx\_axis\_mac\_tstrb is always 1’b1 until the tx\_axis\_mac\_tlast cycle.

• 16-bit AXI data width;

tx\_axis\_mac\_tstrb is 2’b11 on all cycles except the tx\_axis\_mac\_tlast cycle, where it may be 2’b01 or 2’b11 depending on whether the frame ends on an odd or even byte boundary.

• 32-bit AXI data width;

tx\_axis\_mac\_tstrb must be 4’b1111 on all cycles except the tx\_axis\_mac\_tlast cycle. On the final cycle, it must indicate the valid bytes as a contiguous sequence starting form the Least Significant Bytes (i.e., 4’b0001, 4’b0011, 4’b0111). Sparse byte enables are not supported.

If non-streaming TX data is detected (for example, if tx\_axis\_mac\_tstrb is not fully asserted during a non-tlast cycle), the Triple Speed Ethernet MAC core terminates the transmission with an error frame and discards the remaining data. This event increments the aTxIncontinuityFramesErrors counter.

## Dropped tx\_axis\_mac\_tvalid Before End of Frame

Streaming data is defined as continuous valid data bytes from the start of frame (SOF) until the end of frame (EOF). This requires that tx\_axis\_mac\_tvalid remains asserted for every cycle between SOF to EOF.

## Cut Through Mode

In **Cut Through** mode, if tx\_axis\_mac\_tvalid is deasserted before EOF, the continuity of streaming data is broken. When this occurs, the Triple Speed Ethernet MAC core terminates the transmission with an error frame and drops the remaining frame. This event increments the aTxIncontinuityFramesErrors counter.

## Cut-Through Mode with Width-Adaptation or Store-Forward Mode

In **Cut Through mode with width-adaptation** or **Store Forward** mode, a dropped tx\_axis\_mac\_tvalid simply indicates that the corresponding column of tx\_axis\_mac signals are not written into TXFIFO.

Therefore, in **Cut Through mode with width-adaptation** or **Store Forward** mode, a dropped tx\_axis\_mac\_tvalid does not result in an error frame.

## TX FIFO Overflow

In **Store Forward** mode, the TX FIFO may overflow under the following conditions:

FIFO depth insufficient for one full frame—When the write and read sides of the TX FIFO operate at equal bandwidth, the FIFO must be sized large enough to store an entire maximum-sized frame, as described in **Store Forward Mode** on page 30.

Write Bandwidth Exceeds Read Bandwidth—If the FIFO is sized to accommodate a full frame, overflow can still occur when the write side (TX AXI-ST interface) provides data at a rate higher than the read side (Triple Speed Ethernet MAC core transmit engine) can drain it. In this condition, the FIFO may fill before the Triple Speed Ethernet MAC core completes transmitting the earlier data.

For both scenarios, once a TX FIFO overflow is detected, the Triple Speed Ethernet MAC core silently drops the entire frame without transmitting it. Each overflow event increments the aTxFifoOverflowFramesErrors counter.

## Erroneous RX Frame

When an error condition is detected, the Triple Speed Ethernet MAC core validates the frame against the following precedence rules. Only the highest-priority error counter is incremented.

For any error listed below, the Triple Speed Ethernet MAC core performs the following actions:

• Asserts rx\_axis\_mac\_tuser to flag the frame as invalid.

• Increments the ifInErrors statistic counter.

Table 9: RX Statistic Counter Precedence

| Priority | Condition | StatisticCounterIncremented |
| --- | --- | --- |
| 1 (Highest) | Undersized(Receivedframeis&lt;64bytes) | etherStatsUndersizePkts |
| 2 | Oversized (Receivedframeexceedstheconfiguredfrm_length) | etherStatsOversizePkts |
| 3 | FCSError (ReceivedframehasvalidsizebutfailsCRC) | aFrameCheckSequenceErrors |
| 4(Lowest) | LengthMismatch(Receivedframehasvalidsize,butLength/Typefielddoesnotmatchactualpayload) | aRxFrameMismatchedLength |

## Undersized RX Frame

An Ethernet frame must carry a minimum payload size of 46 bytes for non-VLAN tagged frames and 42 bytes for VLAN tagged frames. If a received frame does not meet this requirement, it is flagged as an undersized and handled according to the precedence rules in **Table 9: RX Statistic Counter Precedence** on page 35.

## Oversized RX Frame

Each received frame is checked against the configured frm\_length value. If the physical frame length exceeds this configured limit, the frame is flagged as an oversized and handled according to the precedence rules in **Table 9: RX Statistic Counter Precedence** on page 35.

## Frame Check Sequence (FCS) Error

Each received frame undergoes a cyclic redundancy check (CRC) validation. If the calculated CRC does not match the received FCS field, the frame is flagged as an FCS Error. This event increments the statistic counter aFrameCheckSequenceErrors, provided that the frame is not undersized or oversized.

## Mismatched Length RX Frame

For Ethernet frame with a payload size ≤1500 bytes, the Triple Speed Ethernet MAC core compares the physical frame length against the value in the Ethernet Type/ Length field. If a difference occurs, the frame is flagged as a mismatched length frame.


**Note:** As per the precedence rules in **Table 9: RX Statistic Counter Precedence** on page 35, the aRxFrameMismatchedLength counter is incremented only if the frame has a valid size and a valid FCS.

## Non-Streaming RX Data Frame (SGMII)

A Non-Streaming RX Data Frame is a condition specific to the SGMII interface. It occurs when any of the 2-bit gm\_rx\_dv signal is deasserted before the end-of-frame.

Preamble or SFD Exception—If a non-streaming condition occurs during a preamble or a start frame delimiter (SFD), the sequence is silently discarded. No statistic counters are incremented.

Frame Termination—If a non-streaming condition occurs after an SFD is detected:

**1.** The Triple Speed Ethernet MAC core immediately terminates the frame.

**2.** The frame received up to the point of termination is validated according to the precedence rules in **Table 9: RX Statistic Counter Precedence** on page 35.

**3.** Depending on the length of data received before the break, the frame is counted as undersized, oversized or an FCS error.

## Error Frame

An Error Frame occurs when the PHY asserts the error signal during reception, which are gm\_rx\_err (GMII or SGMII), rmii\_rx\_err (RMII), mii\_rx\_err (MII) , or RGMII decoded error.

Preamble or SFD Exception—If an error signal is asserted during a preamble or a start frame delimiter (SFD), the sequence is silently discarded. No statistic counters are incremented.

Frame Termination—If an error signal is asserted after an SFD is detected:

**1.** The Triple Speed Ethernet MAC core immediately terminates the frame.

**2.** The frame received up to the point of termination is validated according to the precedence rules in **Table 9: RX Statistic Counter Precedence** on page 35.

**3.** The last 4 octets of a data received before termination are interpreted as a frame check sequence (FCS). As these octets do not represent the valid checksum for the truncated frame, the FCS validation fails. If the frame length during termination is valid (neither undersized nor oversized), this resulting FCS failure will increment the aRxFrameCheckSequenceErrors counter.


## Address Filtering and Broadcast Filtering at RX

The Triple Speed Ethernet MAC core supports unicast, multicast, and broadcast filtering on incoming RX Ethernet frames.

• **Unicast/ Multicast Filtering**

— Configure the mac\_addr\_mask register to apply bit-wise filtering.

– Bit = 1: Corresponding address bit is compared

– Bit = 0: Corresponding address bit is ignored.

See **Table 10: Examples of Unicast, Multicast, and Broadcast Filtering Operation** on page 38 for examples.

## i Note: Address filtering can be completely disabled by setting the promis\_en bit to 1.

## Broadcast Filtering

— When broadcast\_filter\_en is set, all RX frames with Destination Address = 48’hFFFF\_FFFF\_FFFF are dropped.

The default value of this control register can be configured in the IP Configuration window under broadcast filtering.

Table 10: Examples of Unicast, Multicast, and Broadcast Filtering Operation

<table><tbody><tr><td>broadcast_filter_en</td><td>mac_address_mask</td><td>mac_addr</td><td>DestinationAddress(<sup>2</sup>)</td><td>Filteredand DroaptpReXdA/XOISuTtput</td><td>Application</td></tr><tr><td colspan="6">Unicast</td></tr><tr><td>Don'tCare</td><td>48'hFFFF_FFFF_FFFF</td><td>48'hAE3A_2020_0080</td><td>48'hAE3A_2020_0080</td><td>OutputatRXAXIST</td><td>Unicast</td></tr><tr><td>Don'tCare</td><td>48'hFFFF_FFFF_FFFF</td><td>48'hAE3A_2020_0080</td><td>48'h3E3F_7A20_0080</td><td>Filtered&amp;Dropped</td><td>Unicast</td></tr><tr><td colspan="6">Multicast</td></tr><tr><td>Don'tCare</td><td>48'hFFFF_FFFF_FFFF</td><td>48'h0100_5E0A_0B0C</td><td>48'h0100_5E0A_0B0D</td><td>Filtered&amp;Dropped</td><td>Multicast</td></tr><tr><td>Don'tCare</td><td>48'hFFFF_FFFF_FFFF</td><td>48'h0100_5E0A_0B0C</td><td>48'hAE3A_2020_0080</td><td>Filtered&amp;Dropped</td><td>Multicast</td></tr><tr><td>Don'tCare</td><td>48'hFFFF_FFFF_FFFF</td><td>48'h0100_5E0A_0B0C</td><td>48'h0100_5E0A_0B0C</td><td>OutputatRXAXIST</td><td>Multicast</td></tr><tr><td>Don'tCare</td><td>48'hFFFF_FF00_0000</td><td>48'h3333_ABCD_0000</td><td>48'h3333_ABCD_1234</td><td>OutputatRXAXIST</td><td>Multicast</td></tr><tr><td colspan="6">Broadcast</td></tr><tr><td>1</td><td>Don'tCare</td><td>Don'tCare</td><td>48'hFFFF_FFFF_FFFF</td><td>Filtered&amp;Dropped</td><td>Broadcast</td></tr><tr><td>0</td><td>Don'tCare</td><td>Don'tCare</td><td>48'hFFFF_FFFF_FFFF</td><td>OutputatRXAXIST</td><td>-</td></tr><tr><td colspan="6">AddressFilteringIsNotEnabled</td></tr><tr><td>0</td><td>48'h0000_0000_0000</td><td>48'hAE3A_2020_0080</td><td>48'hAE3A_2020_0080</td><td>OutputatRXAXIST</td><td>-</td></tr></tbody></table>

When address filtering or broadcast filtering is enabled, any received frame with a mismatched destination address is subject to being filtered. The exact handling of these filtered frames depends on the crc\_fwd control bit.

When crc\_fwd = 0: Filtered RX frames are silently dropped and will not appear on the RX AXI Stream interface, as shown in **Figure 26: Silent Drop of Filtered RX Frame when crc\_fwd = 0** on page 39.

When crc\_fwd = 1: Filtered RX frames are forwarded but marked as invalid. The frame data is still presented on the RX AXI Stream interface, but it is terminated with the rx\_axis\_mac\_tuser signal asserted, as shown in **Figure 27: Filtered RX Frame when crc\_fwd = 1** on page 39.

Regardless of the crc\_fwd settings, you can monitor the aRxFilterFramesErrors statistic counter to track the total number of frames that have been filtered due to address mismatches.

<small><span class="docvortex-page-footnote" data-block-type="page_footnote" style="color:#6b7280">(2) Destination address of the incoming RX Ethernet frame.</span></small>

Figure 26: Silent Drop of Filtered RX Frame when crc\_fwd = 0

EFX\_MAC1GBE: mac\_addr = AE3A\_2020\_0080, broadcast\_filter\_en=1, crc\_fwd = 0


Notes: (1) Latency between SGMII and RX AXI ST is not accurately illustrated here. (2) Broadcast Address Filtering where RX Frames with Destination Address FFFF\_FFFF\_FFFF are filtered and do not appear at RX AXI ST Interface.

Figure 27: Filtered RX Frame when crc\_fwd = 1


## Priority Flow Control (Duplex Mode)

The Triple Speed Ethernet MAC core supports the flow control at both the TX and RX paths.

## Send Pause Frame at TX

To generate a PAUSE frame for flow control, the Triple Speed Ethernet MAC core provides two configuration bits of xoff\_gen and xon\_gen.

• Initiate Pause (XOFF)—Program the desired pause duration into the pause\_quant register, then assert the xoff\_gen bit.

• Resume Transmission (XON)—Assert the xon\_gen bit. This triggers a PAUSE frame with a quanta value of zero.

Both the xon\_gen and xoff\_gen are latched signals. After the PAUSE frame has been sent, the user must manually clear the bit by writing a 0 to prepare for subsequent operations.

## Priority and Override Behavior

A PAUSE frame requests take priority over data frame transmission. However, if a pause request is triggered during an ongoing data frame, the PAUSE frame is queued and transmitted immediately after the current frame completes.

The Triple Speed Ethernet MAC core supports dynamic updates to the pause request. If xon\_gen or xoff\_gen is asserted before the previous request’s pause quanta has been transmitted, the Triple Speed Ethernet MAC core cancels the ongoing request and transmits only the most recent request. For example, if an xon\_gen request is made when there is a pending xoff\_gen request (and before the XOFF frame’s pause quanta value is sent), the Triple Speed Ethernet MAC core discards the XOFF request, and only the XON frame will be transmitted. The mechanism ensures efficient use of bandwidth link by preventing the transmission of redundant PAUSE frames.

Figure 28: Triggering pause frame generation using xoff\_gen and the corresponding Statistic Reporting increments


Notes: (1) Latency between Register Access and gm\_tx\_ signals is not accurately illustrated in this diagram. (2) Latency between gm\_tx\_ signals and statistic counters is not accurately illustrated in this diagram.

Figure 29: Triggering pause frame generation using xon\_gen and the corresponding Statistic Reporting increments


Notes: (1) Latency between Register Access and gm\_tx\_\* is not accurately illustrated in this diagram. (2) Latency between gm\_tx\_\* and statistic counters is not accurately illustrated in this diagram.

## Decoding Pause Frame at RX

On the RX path, the Triple Speed Ethernet MAC core monitors incoming Ethernet frames to detect PAUSE frames, which are uniquely identified by the reserved destination address 01-80-C2-00-00-01. When a PAUSE frame is detected, the Triple Speed Ethernet MAC core extracts the RX\_QUANT value and forwards it to the TX logic. This value directly controls how long the transmitter pauses the data transmission. One quanta corresponds to the time required to transmit 512 bits at the current link speed.

The RX PAUSE frames are not subject to address filtering. A received frame is validated as a PAUSE frame if it meets all of the following criteria:

• Matches the reserved destination address 01-80-C2-00-00-01

Contains the correct EtherType 0x8808 and PAUSE opcode 0x0001

• Passes the CRC check

If a CRC error is detected, the RX PAUSE frame is deemed invalid, the extracted RX\_QUANT is discarded, and no PAUSE operation is triggered. The received PAUSE frame is always forwarded to the RX AXI stream interface like regular frame.

A valid RX\_QUANT from a received PAUSE frame has the highest priority over other transmitter operations, including locally generated PAUSE requests (xon\_gen or xoff\_gen) and TX AXI stream data. If a frame transmission is currently in progress, the new PAUSE command is queued and takes effect immediately after the current frame completes.

You can disable the RX PAUSE frame mechanism by setting the pause\_ignore configuration bit to 1. When set, the Triple Speed Ethernet MAC core ignores the decoded RX\_QUANT value, and no PAUSE operation occurs.


**Note:** The Triple Speed Ethernet MAC core updates the PAUSE timer whenever a new PAUSE frame is received. If another PAUSE frame arrives while a previous PAUSE is active, the new RX\_QUANT value replaces the remaining timer value – it does not accumulate or extend it. A PAUSE frame with RX\_QUANT = 0 clears the timer immediately and resumes transmission.

## Statistic Reporting

The Triple Speed Ethernet MAC core provides statistic reporting for both TX and RX operations. Each counter is 16 bits wide. When a counter reaches its maximum value (16'hFFFF), it saturates and does not roll over. To clear all counters, the user must set the cnt\_reset bit, which resets them to 0. All statistical values shown in the statistic-related diagrams are reported in hexadecimal format.

The following registers are the statistic reporting for TX:

• aFramesTransmittedOK

• aTxPAUSEMACCtrlFrames

ifOutErrors

• aTxFifoOverflowFramesErrors

• aTxIncontinuityFramesErrors

The following registers are the statistic reporting for RX:

• aFramesReceivedLen

etherStatsUndersizePkts

• etherStatsOversizePkts

• aRxFrameMismatchedLength

• aFrameCheckSequenceErrors

• aRxFilterFramesErrors

• ifInErrors

• aRxPAUSEMACCtrlFrames

• aFramesReceivedOK

• etherStatsPkts

## aFramesTransmittedOK

This counter reports the number of frames successfully transmitted on the selected PHY interface. It includes streaming TX data frames with tx\_axis\_mac\_tuser = 0, short frames with auto-padding, and TX PAUSE frames.

## aTxPAUSEMACCtrlFrames

This counter reports the number of PAUSE frames transmitted due to xon\_gen or xoff\_gen requests. The behavior of TX PAUSE frames is described in **Send Pause Frame at TX** on page 40.

## ifOutErrors

This counter reports the number of bad TX frames terminated due to errors during transmission. The termination criteria include:

• Assertion of tx\_axis\_mac\_tuser.

• Non-streaming TX data.

• Dropped tx\_axis\_mac\_tvalid before end of frame (**Cut-Through** mode only).

• Frames discarded due to TX FIFO overflow in **Store-Forward** mode.

This counter does not increment for frames that are silently dropped due to non-compliant tx\_axis\_mac\_tlast, or when tx\_axis\_mac\_tuser is asserted during the first cycle of the frame. These conditions result in the frame being discarded without an error indication or a statistic update.

## aTxFifoOverflowFramesErrors

This counter reports the number of TX frames discarded due to TX FIFO overflow in **Store Forward** mode. The counter increments whenever an overflow occurs. In **Cut Through** mode or **Cut Through** mode with width adaptation, this counter remains at 0.

## aTxIncontinuityFramesErrors

This counter reports the number of transmitted frames that exhibit non-streaming TX data behavior (invalid tx\_axis\_mac\_tstrb patterns) and dropped tx\_axis\_mac\_tvalid before end-of-frame in **Cut Through** mode.

## aFramesReceivedLen

This counter reports the length of each RX frame received at the RX AXI ST interface.

The frame length includes:

• Destination Address (6 octets)

• Source Address (6 octets)

• Optional VLAN tag (4 octets)

• Ethertype/ Length (2 octets)

• Payload

• Frame Check Sequence (4 octets)

This counter reflects the length of the received frame only if the frame is error-free as illustrated in **Figure 33: RX Statistics - aRxPAUSEMACCtrlFrames** on page 45. For a list of erroneous RX frames, refer to **Erroneous RX Frame** on page 35.

## etherStatsUndersizePkts

This counter reports the number of undersized RX frames:

• Payload < 46 bytes for non-VLAN tagged frames

Payload < 42 bytes for VLAN tagged frames

For these frames, rx\_axis\_mac\_tuser is asserted. See **Erroneous RX Frame** on page 35.

Figure 30: RX Statistic - etherStatsUndersizePkts

|  | rx_axis_clk |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
|  |  |  |  |  |  | Payload length = 28 |  |  |  |  |  |  |  |  |  | ayload length =12, co |  |  |  |  |  |  |
| rx_axis_mac_tvalid |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| rx_axis_mac_tlast |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2b11 |  |  |  |  |  |
| rx_axis_mac_tstrb rx_axis_mac_tdata[15:8] |  |  | DATA01DATA03DATA05DATA07DATA09DATA11 |  |  | 2b11 | 1C | DATA. | DATA41 | CRC | CRC |  |  |  | DATA01DATA03DATA05DATA07DATA09DATA11 |  |  | DATA. | DATA25 | xCRC |  |  |
| rx_axis_mac_tdata[7:0] |  |  | DATA00DATA02DATA04DATA06DATA08 DATA10 |  |  |  | 00 | DATA. | DATA40 | CRC | CRC |  |  | DATA00DATA02DATA04DATA06DATA08DATA10 |  |  |  | DATA | DATA24 | CRC CRC |  |  |
| rx_axis_mac_tuser |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| etherStatsPkts |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| aFramesReceivedOK |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| iflnErrors |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| etherStatsUndersizePkts etherStatsOversizePkts |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
| aFrameCheckSequenceErrors |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |
|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |

Note: Latency between RX AXI ST and Statistic Counters is not accurately illustrated here.

## etherStatsOversizePkts

This counter reports the number of oversized RX frames that have a frame length greater than the configured frm\_length value.

For these frames, rx\_axis\_mac\_tuser is asserted. See **Erroneous RX Frame** on page 35.

Figure 31: RX Statistic - etherStatsOversizePkts


Note: Latency between RX AXI ST and Statistic Counters is not accurately illustrated here.

## aRxFrameMismatchedLength

This counter reports the number of received frames where the actual physical frame length does not match the value in the Ethertype/ Length field. It increments only for valid, non-error frames. For such frames, rx\_axis\_mac\_tuser is asserted. **Figure 32: RX Statistic - Mismatched Length RX Frame** on page 44 illustrates the aRxFrameMismatchedLength statistic updates relative to the RX frames at AXI ST interface.

Figure 32: RX Statistic - Mismatched Length RX Frame


## aFrameCheckSequenceErrors

This counter reports the number of received frames that fail the CRC check. For each frame with a CRC error, the Triple Speed Ethernet MAC core asserts rx\_axis\_mac\_tuser to indicate an error condition on the RX AXI ST interface.

There is no increment for:

• Frames flagged as error frames by the PHY.

• Frames filtered due to address filtering or broadcast filtering.

## aRxFilterFramesErrors

This counter reports the number of RX frames dropped due to broadcast filtering or address filtering. See **Erroneous RX Frame** on page 35 and **Address Filtering and Broadcast Filtering at RX** on page 37 for details on broadcast and address filtering.

## aRxPAUSEMACCtrlFrames

This counter reports the number of RX frames decoded as PAUSE frames.

Figure 33: RX Statistics - aRxPAUSEMACCtrlFrames


## ifInErrors

This counter reports the total number of erroneous RX frames, see **Erroneous RX Frame** on page 35, as well as frames dropped due to broadcast or address filtering, see **Address Filtering and Broadcast Filtering at RX** on page 37. For all erroneous frames, rx\_axis\_mac\_tuser is asserted, except in the case of frames dropped due to broadcast or address filtering.

Figure 34: RX Statistic Reporting - Error Frame


Notes: (1) Latency between SGMII RX and RX AXI ST is not accurately illustrated here. (2) Latency between SGMII RX and the statistic counters is not accurately illustrated here.

## aFramesReceivedOK

This counter reports the total number of error-free RX frames received at the RX AXI ST interface. For the list and definitions of erroneous RX frames, see **Erroneous RX Frame** on page 35.

## etherStatsPkts

This counter reports the total number of RX Ethernet frames received, including frames dropped due to broadcast or address filtering.


## Latency

In **Cut Through** mode, the Triple Speed Ethernet MAC core begins transmitting an Ethernet frame before the entire packet is received on the AXI4-Stream interface. This reduces overall latency, as summarized in **Table 11: Latency of PHY Interface in Cut Through Mode** on page 46. For further details, refer to **Cut Through Mode** on page 29.

Table 11: Latency of PHY Interface in Cut Through Mode

<table><tbody><tr><td rowspan="2">PHY Interface</td><td colspan="2">Latency</td></tr><tr><td>TXPath</td><td>RXPath</td></tr><tr><td>SGMII</td><td>7 cycles</td><td>7 cycles</td></tr><tr><td>GMII</td><td>11 cycles</td><td>7 cycles</td></tr></tbody></table>

1 **Note:** Starting with IP version 7.1, an additional cycle of latency is introduced to the TX path for **Cut Through mode with width adaptation** on Trion devices. This change was implemented to improve timing performance.


## IP Manager

The Efinity® IP Manager is an interactive wizard that helps you customize and generate Efinix® IP cores. The IP Manager performs validation checks on the parameters you set to ensure that your selections are valid. When you generate the IP core, you can optionally generate an example design targeting an Efinix development board and/or a testbench. This wizard is helpful when you use several IP cores, multiple instances of an IP core with different parameters, or the same IP core across different projects.

**Note:** Not all Efinix IP cores include an example design or a testbench.

## Generating the Triple Speed Ethernet MAC Core with the IP Manager

The following steps explain how to customize an IP core with the IP Configuration wizard.

**1.** Open the IP Catalog.

**2.** Choose **Ethernet** > **Triple Speed Ethernet MAC** core and click **Next**. The **IP Configuration** wizard opens.

**3.** Enter the module name in the **Module Name** box.

**Note:** You cannot generate the core without a module name.

**4.** Customize the IP core using the options shown in the wizard. For detailed information on the options, refer to the Customizing the Triple Speed Ethernet MAC section.

**5.** (Optional) In the **Deliverables** tab, specify whether to generate an IP core example design targeting an Efinix® development board and/or testbench. These options are turned on by default.

**6.** (Optional) In the **Summary** tab, review your selections.

**7.** Click **Generate** to generate the IP core and other selected deliverables.

**8.** In the **Review configuration generation** dialog box, click **Generate**. The Console in the **Summary** tab shows the generation status.


1 **Note:** You can disable the **Review configuration generation** dialog box by turning off the **Show Confirmation Box** option in the wizard.

**9.** When generation finishes, the wizard displays the **Generation Success** dialog box. Click **OK** to close the wizard.

The wizard adds the IP to your project and displays it under **IP** in the Project pane.

## Generated Files

The IP Manager generates these files and directories:

• **&lt;module name&gt;\_define.svh**—Contains the customized parameters.

• **&lt;module name&gt;\_tmpl.sv**—Verilog HDL instantiation template.

• **&lt;module name&gt;\_tmpl.vhd**—VHDL instantiation template.

• **&lt;module name&gt;.sv**—IP source code.

• **settings.json**—Configuration file.

• **&lt;kit name&gt;\_devkit**—Has generated RTL, example design, and Efinity® project targeting a specific development board.

• **Testbench**—Contains generated RTL and testbench files.

## Customizing the Triple Speed Ethernet MAC

The core has parameters so you can customize its function. You set the parameters in the **General** tab of the core's IP Configuration window.

Table 12: Triple Speed Ethernet MAC Core Parameters

| Name | Options | Description |
| --- | --- | --- |
| TSEMACVersion | Any | TripleSpeedEthernetMACversion. Default: 16 |
| UseMACwith Transceiver | Enable, Disable | EnablesuseoftheTripleSpeedEthernetMACCorewith FPGAtransceiver(availableonlyonsupporteddevices).When checked,thefollowingoptionsareauto-configured: |
|  |  | • PHYInterfaceType:SGMII • AXI4 Data Width: 16 • TX FIFO: Disable • RX FIFO: Disable • RegisterInterface:APB Default: Disable |
| PHYInterfaceType | RGMII, MII, RMII, GMII, SGMII | Defines the PHY interface type. Default: RGMII |
| AXI4 Data Width | 8, 16, 32 | DefinesAXI4-Streamdatawidth. Default: 8 |
| TX FIFO | Enable, Disable | EnablesordisablestheTXFIFOinthecore.Mustbeenablediftx_axis_clk≠PHYclockfrequency.See StoreForwardMode on page 30. Default: Enable |
| TX FIFO Depth | 16, 32, 64, 128, 256,4501926,, 1 8012942,, 2 1064388,4 | Defines TX FIFO depth. Mfraumstebse>g1r6e3a8te4r,tThXanFIfFraOmmeulesntgbtehd.Fisoarbjluemd.bSoee StoreForwardMode on page 30 for minimum depth requirements. Default: 2048 |
| RX FIFO | Enable, Disable | EnablesordisablestheRXFIFO.Mustbeenabledifrx_axis_clk≠PHYclockfrequency. Default: Enable |
| RX FIFO Depth | 16, 32, 64, 128, 256,4501926,, 1 8012942,, 2 1064388,4 | Defines RX FIFO depth. Default: 2048 |
| Programmable InterPacketGap | 8 - 63 | Default value for tx_ipg_length. Default: 12 |
|  |  | Note: In Store-Forwardmode,theeffectiveIPGmay begovernedbythebufferingmechanism. |
| MaximumTransmission UnitFrameLength | 64 - 16018 | Default value for frm_length. Includes headers, payload, and FCS. Receivedframeslargerthanmaximumtranmissionunit(MTU)areflaggedasoversized;payloads&lt;46bytes(or&lt;42bytesforVLANTaggedframes)areflaggedasundersized. Default: 1518 |
| MACSourceAddress | Any | Default value for mac_addr.UsedwhengeneratingTXpause framesandforaddressfilteringcomparison. Default: 48'h0000_0000_0000 |
| BroadcastFiltering | Enable, Disable | Default value for broadcast_filter_en. Default: Enable |
| Enable local loopbacksupport | Enable, Disable | Enables or disables local loopback capability on the selected PHYinterface.Whenchecked,loop_ena can be toggled at run time to enable or disable loopback. Default: Disable |
| RGMIITransmit Clock Delay | Enable(Center-aligned), Disable (Edge-aligned) | DefinesalignmentofRGMIItransmitclock(rgmii_txc)withdata(rgmii_txd).Appliesto10/100Mbpsonly.RefertoFigure12:ConversionfromTXAXISTtoRGMIITXat100 Mbps on page 22 andFigure13:ConversionfromTXAXIST to RGMII TX at 100 Mbps on page 22. Default:Enabled(Center-aligned) |
| Firstsamplingof RGMIIReceiveData | FallingEdge, Rising Edge | DefinesthefirstsamplingedgeforRGMIIreceivedata.Appliesto1000Mbpsonly.Default:Fallingedge |
| RegisterInterface | AXI4-Lite, APB | Definesregisterinterfaceforaccessingthecontrolandstatus registersinControlandStatusRegisters on page 55. Default: AXI4-Lite |

The maximum capabilities of the Triple Speed Ethernet MAC core depend on the FPGA device family and speed grade.

Table 13: Triple Speed Ethernet MAC core Maximum Capabilities

| DeviceFamily | Lowerspeedgrade | Higherspeedgrade |
| --- | --- | --- |
| Trion |  | Max speed: 1 Gbps Jumbopacketsize:Upto4kBforStore-ForwardMode |
| Topaz | (Except for SGMII with AXI Data Width = 8) |  |
| Titanium |  |  |


## Note:

• Lower speed grade refers to C3 for Trion and Titanium devices, and C2 for Topaz devices.

Higher speed grade refers to C4 for Trion and Titanium devices, and C3 for Topaz devices.

## Ports

Table 14: Triple Speed Ethernet MAC Core Port Interface

<table><tbody><tr><td>PortName</td><td>Direction</td><td>Bus Width</td><td>Clock Domain</td><td>Description</td></tr><tr><td colspan="5">Clock and Reset(<sup>3</sup>)</td></tr><tr><td>init_clk</td><td>Input</td><td>1</td><td>-</td><td>Freq=50MHzorbelow</td></tr><tr><td>init_rst_n</td><td>Input</td><td>1</td><td>Async</td><td>Resetallpower-uphandshakebetween SoftIPandtheFPGAPHY.</td></tr><tr><td>tx_mac_aclk</td><td>Input</td><td>1</td><td>-</td><td>See Table4:ClockSourcesintheTriple SpeedEthernetMACCore on page 9 for moredetails.</td></tr><tr><td>rx_mac_aclk</td><td>Output</td><td>1</td><td>-</td><td></td></tr><tr><td>mac_reset</td><td>Input</td><td>1</td><td>Async</td><td>Activehighsystemglobalreset.</td></tr><tr><td>proto_reset</td><td>Input</td><td>1</td><td>Async</td><td>ActivehighprotocolresetonTXandRX path.</td></tr><tr><td colspan="5">MACAXISTInterface:TX</td></tr><tr><td>tx_axis_clk</td><td>Input</td><td>1</td><td>-</td><td rowspan="7">TXAXISTInterface.SeeTXAXIST Interface on page 16formoredetails.</td></tr><tr><td>tx_axis_mac_tdata</td><td>Input</td><td>AXI_WIDTH</td><td>tx_axis_clk</td></tr><tr><td>tx_axis_mac_tvalid</td><td>Input</td><td>AXI_WIDTH/8</td><td>tx_axis_clk</td></tr><tr><td>tx_axis_mac_tlast</td><td>Input</td><td>1</td><td>tx_axis_clk</td></tr><tr><td>tx_axis_mac_tstrb</td><td>Input</td><td>AXI_WIDTH/8</td><td>tx_axis_clk</td></tr><tr><td>tx_axis_mac_tuser</td><td>Input</td><td>1</td><td>tx_axis_clk</td></tr><tr><td>tx_axis_mac_tready</td><td>Output</td><td>1</td><td>tx_axis_clk</td></tr><tr><td colspan="5">MACAXISTInterface:RX</td></tr><tr><td>rx_axis_clk</td><td>Input</td><td>1</td><td>-</td><td rowspan="7">RXAXISTInterface.SeeRXAXIST Interface on page 18formoredetails.</td></tr><tr><td>rx_axis_mac_tdata</td><td>Output</td><td>AXI_WIDTH</td><td>rx_axis_clk</td></tr><tr><td>rx_axis_mac_tvalid</td><td>Output</td><td>1</td><td>rx_axis_clk</td></tr><tr><td>rx_axis_mac_tlast</td><td>Output</td><td>1</td><td>rx_axis_clk</td></tr><tr><td>rx_axis_mac_tstrb</td><td>Output</td><td>AXI_WIDTH/8</td><td>rx_axis_clk</td></tr><tr><td>rx_axis_mac_tuser</td><td>Output</td><td>1</td><td>rx_axis_clk</td></tr><tr><td>rx_axis_mac_tready</td><td>Input</td><td>1</td><td>rx_axis_clk</td></tr><tr><td colspan="5">GMII Interface</td></tr><tr><td>gm_tx_c</td><td>Output</td><td>1</td><td>-</td><td>Providestimingreferenceforthetransfer of gm_tx_signalstothePHY. Sourcefromtx_mac_aclk.</td></tr><tr><td>gm_tx_d</td><td>Output</td><td>GMII_WIDTH</td><td>gm_tx_c</td><td>GMIItransmitsdatabustoPHY.</td></tr><tr><td>gm_tx_en</td><td>Output</td><td>GMII_WIDTH/8</td><td>gm_tx_c</td><td>Indicatesvaliddataonthetransmitdata buswhenasserted.</td></tr><tr><td>gm_tx_err</td><td>Output</td><td>GMII_WIDTH/8</td><td>gm_tx_c</td><td>IndicatestothePHYthatthetransmitted frameisinvalidwhenasserted.</td></tr><tr><td>gm_rx_c</td><td>Input</td><td>1</td><td>-</td><td>GMIIreceivesclocksourcedfromthe PHY.</td></tr><tr><td>gm_rx_d</td><td>Input</td><td>GMII_WIDTH</td><td>gm_rx_c</td><td>GMIIreceivesdatabusfromPHY.</td></tr><tr><td>gm_rx_dv</td><td>Input</td><td>GMII_WIDTH/8</td><td>gm_rx_c</td><td>Indicatesvaliddataonthereceivedata buswhenasserted. Continuetoassertthissignalduring framereception,fromthefirstpreamble byte until the last byte of the CRC field is received.</td></tr><tr><td>gm_rx_err</td><td>Input</td><td>GMII_WIDTH/8</td><td>gm_rx_c</td><td>Indicatesthatthereceivedframe containserrorswhenasserted.</td></tr><tr><td colspan="5">RGMII Interface</td></tr><tr><td>rgmii_txc_HI</td><td>Output</td><td>1</td><td>-</td><td>MSBoftheRGMIItransmitclocksignalto thePHY. Connect to PinName(HI) if the Double Data I/O option turns on for rgmii_txc busintheInterfaceDesigner.Setthe clockpinnamereferenceto90° phase shiftoftx_mac_aclk.</td></tr><tr><td>rgmii_txc_LO</td><td>Output</td><td>1</td><td>-</td><td>LSBofRGMIItransmitclocksignaltothe PHY. Connect to PinName(LO) if the Double Data I/O option turns on for rgmii_txc businInterfaceDesigner.Settheclockpinnamereferenceto90°phaseshiftoftx_mac_aclk.</td></tr><tr><td>rgmii_txd_HI</td><td>Output</td><td>4</td><td>tx_mac_aclk</td><td>The4mostsignificantbits(MSB)transmitdatatothePHY. Connect to PinName(HI) if the Double Data I/O option turns on for rgmii_txd businInterfaceDesigner.Settheclockpinnamereferencetotx_mac_aclk.</td></tr><tr><td>rgmii_txd_LO</td><td>Output</td><td>4</td><td>tx_mac_aclk</td><td>4 least significant bit (LSB) of RGMII transmitdatatothePHY. Connect to PinName(LO) if the Double Data I/O option turns on for rgmii_txd businInterfaceDesigner.Settheclockpinnamereferencetotx_mac_aclk.</td></tr><tr><td>rgmii_tx_ctl_HI</td><td>Output</td><td>1</td><td>tx_mac_aclk</td><td>MSBofthetransmitcontrolsignaltothe PHY. Connect to PinName(HI) if the Double Data I/O option turns on for rgmii_tx_ctl bus in Interface Designer.Settheclockpinnamereferencetotx_mac_aclk.</td></tr><tr><td>rgmii_tx_ctl_LO</td><td>Output</td><td>1</td><td>tx_mac_aclk</td><td>LSBoftransmitcontrolsignaltothePHY. Connect to PinName(LO) if the Double Data I/O option turns on for rgmii_tx_ctl bus in Interface Designer.Settheclockpinnamereferencetotx_mac_aclk.</td></tr><tr><td>rgmii_rxc</td><td>Input</td><td>1</td><td>-</td><td>RXclockfromPHY.SeeTable4:ClockSourcesintheTripleSpeedEthernet MACCore on page 9forfrequency requirement.</td></tr><tr><td>rgmii_rxd_HI</td><td>Input</td><td>4</td><td>rgmii_rxc</td><td>4MSBofRGMIIreceivedatafromthePHY. Connect to PinName(HI) if the Double Data I/O option turns on for rgmii_rxd businInterfaceDesigner.Settheclockpinnamereferencetorgmii_rxc.</td></tr><tr><td>rgmii_rxd_LO</td><td>Input</td><td>4</td><td>rgmii_rxc</td><td>4LSBofRGMIIreceivedatafromthePHY. Connect to PinName(LO) if the Double Data I/O option turns on for rgmii_rxd busintheInterfaceDesigner.Settheclockpinnamereferencetorgmii_rxc.</td></tr><tr><td>rgmii_rx_ctl_HI</td><td>Input</td><td>1</td><td>rgmii_rxc</td><td>MSBofreceivecontrolsignalfromthe PHY. Connect to PinName(HI) if the Double Data I/O option turns on for rgmii_rx_ctl bus in Interface Designer.Settheclockpinnamereferencetorgmii_rxc.</td></tr><tr><td>rgmii_rx_ctl_LO</td><td>Input</td><td>1</td><td>rgmii_rxc</td><td>LSBofreceivecontrolsignalfromthe PHY. Connect to PinName(LO) if the Double Data I/O option turns on for rgmii_rx_ctl bus in Interface Designer.Settheclockpinnamereferencetorgmii_rxc.</td></tr><tr><td colspan="5">MII Interface</td></tr><tr><td>mii_txc</td><td>Input</td><td>1</td><td>-</td><td>TXclockfromPHY.SeeTable4:ClockSourcesintheTripleSpeedEthernet MACCore on page 9forfrequency requirement.</td></tr><tr><td>mii_txd</td><td>Output</td><td>4</td><td>mii_txc</td><td>TransmitdatatoPHY.</td></tr><tr><td>mii_tx_dv</td><td>Output</td><td>1</td><td>mii_txc</td><td>Transmitvaliddata.</td></tr><tr><td>mii_tx_err</td><td>Output</td><td>1</td><td>mii_txc</td><td>AnassertionindicatesthatthePHYthat theframewassentisinvalid.</td></tr><tr><td>mii_rxc</td><td>Input</td><td>1</td><td>-</td><td>RXclockfromPHY.SeeTable4:ClockSourcesintheTripleSpeedEthernet MACCore on page 9forfrequency requirement.</td></tr><tr><td>mii_rxd</td><td>Input</td><td>4</td><td>mii_rxc</td><td>ReceivedatafromPHY.</td></tr><tr><td>mii_rx_dv</td><td>Input</td><td>1</td><td>mii_rxc</td><td>Datavalid.Thissignalindicatesthat the data on mii_rxd [3:0] is valid. Thesignalstaysassertedduringframe reception,fromthefirstpreamblebyte until the last byte of the CRC field is received.</td></tr><tr><td>mii_rx_err</td><td>Input</td><td>1</td><td>mii_rxc</td><td>Assertthissignaltoindicatethatthe receivedframecontainserrors.</td></tr><tr><td colspan="5">RMII Interface</td></tr><tr><td>rmii_clk_ref</td><td>Input</td><td>1</td><td>-</td><td>See Table4:ClockSourcesintheTriple SpeedEthernetMACCore on page 9.</td></tr><tr><td>rmii_txd</td><td>Output</td><td>2</td><td>rmii_clk_ref</td><td>TransmitdatatothePHY.</td></tr><tr><td>rmii_tx_en</td><td>Output</td><td>1</td><td>rmii_clk_ref</td><td>Theassertionindicatesthatthedataon thetransmitdatabusisvalid.</td></tr><tr><td>rmii_rxd</td><td>Input</td><td>2</td><td>rmii_clk_ref</td><td>ReceivedatafromthePHY.</td></tr><tr><td>rmii_crs_dv</td><td>Input</td><td>1</td><td>rmii_clk_ref</td><td>Receivevaliddatastrobe.</td></tr><tr><td>rmii_rx_err</td><td>Input</td><td>1</td><td>rmii_clk_ref</td><td>Assertthissignaltoindicatethatthe receivedframecontainserrors.</td></tr><tr><td colspan="5">APB Interface</td></tr><tr><td>s_paddr</td><td>Input</td><td>10</td><td>s_axi_aclk</td><td>APBaddress.</td></tr><tr><td>s_pwdata</td><td>Input</td><td>32</td><td>s_axi_aclk</td><td>APB write data.</td></tr><tr><td>s_pwrite</td><td>Input</td><td>1</td><td>s_axi_aclk</td><td>APB write.</td></tr><tr><td>s_penable</td><td>Input</td><td>1</td><td>s_axi_aclk</td><td>APB enable.</td></tr><tr><td>s_psel</td><td>Input</td><td>1</td><td>s_axi_aclk</td><td>APB select.</td></tr><tr><td>s_prdata</td><td>Output</td><td>32</td><td>s_axi_aclk</td><td>APBreadydata.</td></tr><tr><td>s_pready</td><td>Output</td><td>1</td><td>s_axi_aclk</td><td>APBready.</td></tr><tr><td>s_perr</td><td>Output</td><td>1</td><td>s_axi_aclk</td><td>APBslaveerror.</td></tr><tr><td colspan="5">AXI-4 Lite Interface</td></tr><tr><td>s_axi_aclk</td><td>Input</td><td>1</td><td>-</td><td>Registerinterfaceclock.SeeTable4:ClockSourcesintheTripleSpeed EthernetMACCore on page 9 for frequencyrequirement.</td></tr><tr><td>s_axi_awaddr</td><td>Input</td><td>10</td><td>s_axi_aclk</td><td>AXI4-Litewriteaddressbus.</td></tr><tr><td>s_axi_awvalid</td><td>Input</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litewriteaddressvalidstrobe.</td></tr><tr><td>s_axi_awready</td><td>Output</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litewriteaddressreadysignal.</td></tr><tr><td>s_axi_wdata</td><td>Input</td><td>32</td><td>s_axi_aclk</td><td>AXI4-Lite write data.</td></tr><tr><td>s_axi_wvalid</td><td>Input</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litewritedatavalidstrobe.</td></tr><tr><td>s_axi_wready</td><td>Output</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litewrite-readysignal.</td></tr><tr><td>s_axi_bresp</td><td>Output</td><td>2</td><td>s_axi_aclk</td><td>AXI4-Litewriteresponse.</td></tr><tr><td>s_axi_bvalid</td><td>Output</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litewriteresponsevalidstrobe.</td></tr><tr><td>s_axi_bready</td><td>Input</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litewriteresponsereadysignal.</td></tr><tr><td>s_axi_araddr</td><td>Input</td><td>10</td><td>s_axi_aclk</td><td>AXI4-Litereadaddressbus.</td></tr><tr><td>s_axi_arvalid</td><td>Input</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litereadaddressvalidstrobe.</td></tr><tr><td>s_axi_arready</td><td>Output</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litereadaddressreadysignal.</td></tr><tr><td>s_axi_rresp</td><td>Output</td><td>2</td><td>s_axi_aclk</td><td>AXI4-Litereadresponse.</td></tr><tr><td>s_axi_rdata</td><td>Output</td><td>32</td><td>s_axi_aclk</td><td>AXI4-Litereaddata.</td></tr><tr><td>s_axi_rvalid</td><td>Output</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litereaddatavalidstrobe.</td></tr><tr><td>s_axi_rready</td><td>Input</td><td>1</td><td>s_axi_aclk</td><td>AXI4-Litereaddatareadysignal.</td></tr><tr><td colspan="5">MDIO Interface</td></tr><tr><td>Mdo</td><td>Output</td><td>1</td><td>-</td><td>Output data signal for communication withthePHY'sconfigurationandstatus registers.</td></tr><tr><td>MdoEn</td><td>Output</td><td>1</td><td>-</td><td>Output data enable signal for the MDIO bidirectionalbus. IntheInterfaceDesigner,youhaveto createanINOUTtristateport,setMdi as Input, Mdo as Output, and MdoEn as Output Enable.</td></tr><tr><td>Mdi</td><td>Input</td><td>1</td><td>-</td><td>Input data signal for communication withthePHY'sconfigurationandstatus registers.Alwayssettohighwhennotin use.</td></tr><tr><td>Mdc</td><td>Output</td><td>1</td><td>-</td><td>MDIO clock management . Derived froms_axi_aclkbasedonsuppliedconfigurationdata.</td></tr><tr><td colspan="5">PHYPowerUpSequence</td></tr><tr><td>PMA_CMN_READY</td><td>Input</td><td>1</td><td>Async</td><td>OutputfromPHYtoindicatethe readinessofPHYcalibration.</td></tr><tr><td>PMA_XCVR_PLLCLK_EN_ACK</td><td>Input</td><td>1</td><td>Async</td><td rowspan="6">RefertoPowerUpHandshakewith FPGATransceiver on page 14.</td></tr><tr><td>PMA_XCVR_POWER_STATE_ACK</td><td>Input</td><td>4</td><td>Async</td></tr><tr><td>PMA_RX_SIGNAL_DETECT</td><td>Input</td><td>1</td><td>Async</td></tr><tr><td>PMA_XCVR_PLLCLK_EN</td><td>Output</td><td>1</td><td>init_clk</td></tr><tr><td>PMA_XCVR_POWER_STATE_REQ</td><td>Output</td><td>4</td><td>init_clk</td></tr><tr><td>phy_init_done</td><td>Output</td><td>1</td><td>Async</td></tr></tbody></table>

<small><span class="docvortex-page-footnote" data-block-type="page_footnote" style="color:#6b7280">(3) For details on Clock and Reset, refer to Clock Sources and 5.3 Reset Signals.</span></small>

## Control and Status Registers

As a general guideline, control registers should be programmed only when no data traffic is in progress.

Modifying configuration settings while the transmission or receiving traffic is active may result in unpredictable behavior or data corruption.

In practice, you are recommended to program control registers only when the datapath is disabled (by clearing tx\_ena or rx\_ena), with the following exceptions that may be configured at any time:

• xon\_gen

• xoff\_gen

• pause\_quant

• tx\_ena

• rx\_ena

Additionally, the following registers may be updated safely when the TX AXI ST interface is idle:

tx\_addr\_ins

• tx\_dst\_addr\_ins

• dst\_mac\_addr

Table 15: Triple Speed Ethernet MAC Core Configuration Registers

<table><tbody><tr><td>Dword Offset</td><td>Name</td><td>R/W</td><td>Description</td></tr><tr><td>0x00</td><td>VERSION</td><td>R</td><td>IndicatestheversionoftheIPcore. Default:ThedefaultvalueisconfigurablethroughTSEMACVersion fieldintheIPConfigurationwindow.</td></tr><tr><td>0x08</td><td>Command_Config</td><td>R/W</td><td>Commandconfigurationsettings.RefertoTable16: Command_ConfigRegisterFieldDescription on page 56 for moredetails.</td></tr><tr><td>0x0C</td><td>mac_addr [31:0]</td><td>R/W</td><td rowspan="2">SourceMACaddress.Example:IftheMACaddressissetto01-1B-43-17-7B-CD:Write0x43177BCDtoregister0x0CWrite0x0000011Btoregister0x10Default:ThedefaultvalueisconfigurablethroughMACSource AddressfieldintheIPConfigurationwindow.</td></tr><tr><td>0x10</td><td>mac_addr [47:32]</td><td>R/W</td></tr><tr><td>0x14</td><td>frm_length [15:0]</td><td>R/W</td><td>Indicatesthemaximumpacketlength. Default:ThedefaultvalueisconfigurablethroughMaximum TransmissionUnitFrameLengthfieldintheIPConfiguration window.</td></tr><tr><td>0x18</td><td>pause_quant [15:0]</td><td>R/W</td><td>DefinesthepausequantavalueinsertedintothegeneratedPAUSEframetriggeredbyxoff_gen.EachPAUSEframespecifiesarequestedpausedurationinunitsofpausequanta,whereonequantaequals512bittimes. Example: If pause_quant is set to 8, the pause time equals 8 × 512- bit times. Default: 0x0</td></tr><tr><td>0x5c</td><td>tx_ipg_length [5:0]</td><td>R/W</td><td>Transmitinterpacketgapvalue. Default:Thedefaultvalueisconfigurablethroughthe ProgrammableInterPacketGapfieldintheIPConfiguration window.</td></tr></tbody></table>

Table 16: Command\_Config Register Field Description

<table><tbody><tr><td>Bit</td><td>Name</td><td>R/W</td><td colspan="2">Description</td></tr><tr><td>0</td><td>tx_ena</td><td>R/W</td><td colspan="2">Enablesthetransmissionpath. Default: 1</td></tr><tr><td>1</td><td>rx_ena</td><td>R/W</td><td colspan="2">Enablesthereceivepath. Default: 1</td></tr><tr><td>2</td><td>xon_gen</td><td>R/W</td><td colspan="2">Pauseframegeneration.Asserthightotriggerapauseframewith0pausequantatoresume transmission.SeeSendPauseFrameatTX on page 40formore details. Default: 0</td></tr><tr><td>3</td><td colspan="4">Reserved</td></tr><tr><td>4</td><td>promis_en</td><td>R/W</td><td colspan="2">Promiscuousmode.AsserthightodisableMACaddressfiltering. Default: 0</td></tr><tr><td>5</td><td colspan="4">Reserved</td></tr><tr><td>6</td><td>crc_fwd</td><td>R/W</td><td colspan="2">AsserthightoforwardtheCRCvaluetotheAXI4-StreamRXdatarx_axis_mac_tdata. Default: 0</td></tr><tr><td>7</td><td colspan="4">Reserved</td></tr><tr><td>8</td><td>pause_ignore</td><td>R/W</td><td colspan="2">Asserthightodisablepauseframecontrol. Default: 0</td></tr><tr><td>9</td><td>tx_addr_ins</td><td>R/W</td><td colspan="2">Asserthightoinsertthetransmitpacket'ssourceMACaddresswiththevalueinregisters0xCand0x10. Default: 0</td></tr><tr><td>10 -14</td><td colspan="4">Reserved</td></tr><tr><td rowspan="3">15</td><td rowspan="3">loop_ena</td><td rowspan="3">R/W</td><td colspan="2" rowspan="3">ControlslocalPHYloopbackatruntime.Whenloop_ena = 1, the MAC'sTXpathisloopedbacktotheRXpathontheselectedPHY interface. Note: LocalloopbacksupportmustbeenabledintheIP Configurationwindowforthisregisterbittohaveanyeffect. Default: 0</td></tr><tr></tr><tr></tr><tr><td>16 - 18</td><td>eth_speed [2:0]</td><td>R/W</td><td colspan="2">EthernetMACtransferspeed.ForRGMIIandRMIIinterface,correctconfigurationoftheeth_speedsettingisrequiredtoensureproperclockgenerationanddatasamplingbehavior.Thesettingmustbe configuredbeforeanytrafficstarts. 3'b100: 1000 Mbps 3'b010: 100 Mbps 3'b001: 10 Mbps Default: • RGMII: 3'b100 • RMII: 3'b010 Note: ForMII,GMII,andSGMIImodes,theeth_speed settingisnotapplicableandcanbeignored.</td></tr><tr><td>19 - 21</td><td></td><td></td><td colspan="2">Reserved</td></tr><tr><td>22</td><td>xoff_gen</td><td>R/W</td><td colspan="2">Triggersthetransmissionofapauseframe.Whensetto1,theMACgeneratesapauseframeusingthequantavaluespecifiedin pause_quant (0x18). Thepauseframerequeststhelinkpartnertopausetransmissionfor pause_quant × 512 bit times. See SendPauseFrameatTX on page 40 for additional details on pauseframeoperation. Default: 0</td></tr><tr><td>23 - 30</td><td></td><td></td><td colspan="2">Reserved</td></tr><tr><td>31</td><td>cnt_reset</td><td>R/W</td><td colspan="2">Asserthightoresetallthestatisticcounterregisters. Default: 0 Note: Foraccuratecountervalues,thisresetshouldonlybe performed when the TripleSpeedEthernetMACcoreisidle (noactiveTXorRXoperations).Toensurethis,followthis sequence: 1. Disable the datapath by clearing tx_ena and rx_ena. 2. Assert cnt_reset to clear counters. 3. Re-enable tx_ena and rx_ena.</td></tr></tbody></table>

Table 17: MDIO Configuration Registers

<table><tbody><tr><td>Dword Offset</td><td>Name</td><td>R/W</td><td>Description</td></tr><tr><td rowspan="2">0x100</td><td>Bit 7:0 - Divider</td><td rowspan="2">R/W</td><td>ToderivetheMdcclockfrequency.TheMdcfrequency=s_axi_aclkfrequency/Divider. Default: 0x64</td></tr><tr><td>Bit8-NoPre</td><td>0:SendtheMDIOwithpreambledata.1:SendtheMdiowithoutpreambledata. Default: 0x0</td></tr><tr><td rowspan="2">0x104</td><td>Bit 0 - RdEn</td><td rowspan="2">System Controlled</td><td>AsserthightoreadtheMDIObus. Default: 0x0</td></tr><tr><td>Bit1-WrEn</td><td>AsserthightowritetotheMDIObus. Default: 0x0</td></tr><tr><td rowspan="3">0x108</td><td>Bit [4:0] - RegAddr</td><td rowspan="3">R/W</td><td>MDIOconfigurationregisteraddress. Default: 0x0</td></tr><tr><td>Bit [7:5] - Reserved</td><td>-</td></tr><tr><td>Bit [12:8] - PhyAddr</td><td>5-bitPHYaddress. Default: 0x0</td></tr><tr><td>0x10c</td><td>WrData[15:0]</td><td>R/W</td><td>MDIO write data. Default: 0x0</td></tr><tr><td>0x110</td><td>RdData [15:0]</td><td>R</td><td>MDIOreaddata. Default: 0x0</td></tr><tr><td rowspan="3">0x114</td><td>Bit 0 - LinkFailStatus</td><td rowspan="3">R</td><td>FailtolinkwiththePHYMDIO. Default: 0x0</td></tr><tr><td>Bit 1 - BusyStatus</td><td>PHYMDIOisbusy. Default: 0x0</td></tr><tr><td>Bit 2 - NvalidStatus</td><td>InvalidStatus(qualifierforthevalidscanresult). Default: 0x0</td></tr></tbody></table>

Table 18: Receive Supplementary Registers

<table><tbody><tr><td>Dword Offset</td><td>Name</td><td>R/W</td><td>Description</td></tr><tr><td>0x140</td><td>broadcast_filter_en</td><td>R/W</td><td>Controlsthefilteringofbroadcastpackets.Whensetto1,allreceivedpacketswiththebroadcastdestinationMACaddress (FF:FF:FF:FF:FF:FF)arediscardedbytheMAC.When0,broadcastpacketsareaccepted.SeeAddressFilteringand BroadcastFilteringatRX on page 37formoredetails. Default:ThedefaultvalueisconfigurablethroughtheBroadcast FilteringfieldintheIPConfigurationwindow.</td></tr><tr><td>0x144</td><td>mac_addr_mask[31:0]</td><td>R/W</td><td rowspan="2">SpecifiestheMACaddressmaskforaddressfiltering.Maskbitssetto1arecompared;bitssetto0areignored.Effectiveonlywhen pRDXreof omanuisl pt_:ae 0gnxe0= 307.fRoerfemrotroeAddedtareilss.sFilteringandBroadcastFilteringat</td></tr><tr><td>0x148</td><td>mac_[a4d7:d3r2_]mask</td><td>R/W</td></tr></tbody></table>

Table 19: Transmit Supplementary Registers

<table><tbody><tr><td>Dword Offset</td><td>Name</td><td>R/W</td><td>Description</td></tr><tr><td>0x180</td><td>tx_dst_addr_ins [0]</td><td>R/W</td><td>AsserthightoinsertthedestinationMACaddressvaluein0x184and0x188toTXpacketdestinationMACaddressdatabytes. Default: 0x0</td></tr><tr><td>0x184</td><td>dst_mac_addr[31:0]</td><td>R/W</td><td rowspan="2">DestinationMACaddress. Default: 0x0</td></tr><tr><td>0x188</td><td>dst_mac_addr[47:32]</td><td>R/W</td></tr></tbody></table>

Table 20: Statistic Counter Registers

For detailed information, refer to Statistic Reporting on page 42.

| Dword Offset | Name | R/W | Description |
| --- | --- | --- | --- |
| 0x68 | aFramesTransmittedOK[15:0] | R | Framessuccessfullytransmitted,includingpause frames. Default: 0x0 |
| 0x6c | aFramesReceivedOK[15:0] | R | Framessuccessfullyreceived,excludingerrorframes. Includespauseframes. Default: 0x0 |
| 0x70 | aFrameCheckSequenceErrors[15:0] | R | ReceivedframeswithCRCerrors. Default: 0x0 |
| 0x80 | aTxPAUSEMACCtrlFrames[15:0] | R | Pauseframestransmitted. Default: 0x0 |
| 0x84 | aRxPAUSEMACCtrlFrames[15:0] | R | Pauseframesreceived. Default: 0x0 |
| 0x88 | ifInErrors[15:0] | R | ErroneousRXframesandframesdroppeddueto broadcastoraddressfiltering. Default: 0x0 |
| 0x8c | ifOutErrors[15:0] | R | FramesterminatedasabadframeontheTXchannel. Default: 0x0 |
| 0x98 | aRxFrameMismatchedLength[15:0] | R | Receivedframeswithmismatchedphysicallengthvs Lengthfield. Default: 0x0 |
| 0x9c | aRxFilterFramesErrors[15:0] | R | Filteredpacketsduetoaddressmismatch. Default: 0x0 |
| 0xb4 | etherStatsPkts [15:0] | R | Totalframesreceived,includingerroneousframes. Default: 0x0 |
| 0xb8 | etherStatsUndersizePkts [15:0] | R | Frames&lt;64bytes(excludeserrorframes).Includespauseframes. Default: 0x0 |
| 0xbc | etherStatsOversizePkts [15:0] | R | Framesexceedingfrm_length(excludeserrorframes). Default: 0x0 |
| 0xc0 | aFramesReceivedLen[15:0] | R | Lengthofreceivedframe. Default: 0x0 |
| 0xc4 | aTxFifoOverflowFramesErrors[15:0] | R | TransmittedframesdiscardedduetoTXFIFO overflow in StoreForward mode. Default: 0x0 |
| 0xc8 | aTxIncontinuityFramesErrors[15:0] | R | Transmittedframeswithcontinuityerrors. Default: 0x0 |

# Triple Speed Ethernet MAC Example Design

You can choose to generate the example design when generating the core in the IP Manager Configuration window. Compile the example design project and download the **.hex** or **.bit** file to your board. To generate example design, the **Example Design Deliverables Option** signal must be enabled.

**Important:** Efinix tested the example design generated with the default parameter options only.

## Example Design with External PHY

The example design with external PHY demonstrates the functionality of the Triple Speed Ethernet MAC core running at 1000 Mbps. It includes two test modes:

Normal mode—The MAC or UDP pattern generator constructs and initiates TX packets for the TX path of the Triple Speed Ethernet MAC core.

• Linked-Partner mode—The TX packets are constructed by the other end of the network, for example a computer.

The example design consists of:

• MAC or UDP pattern generator—Generates the MAC/UDP TX packet to the Triple Speed Ethernet MAC core though AXI4-ST TX interface

RISC-V Sapphire SOC—Allows you to configure the Triple Speed Ethernet MAC core configuration register and example design configuration register. Refer to **Table 23: Configuration Registers for Example Design with External PHY** on page 74 for more details.

• Triple Speed Ethernet MAC core.

**Note:** The example design with external PHY is validated with RISC-V Sapphire core version 2.2. You are advised not to upgrade the SoC core to a newer version, as this may lead to system incompatibility or functional failure.

Figure 35: Example Design with External PHY Block Diagram


## Required Hardware

The example design with external PHY uses the following hardware from the Trion T120 BGA324 Development Kit:

• Trion T120 BGA324 development board

• Micro-USB cable

• 12 V power adapter

You also need the following hardware, which you provide yourself:

• USB-to-UART converter module

• Ethernet cable

Computer

The example design with external PHY uses the following hardware from the Titanium Ti60 F225 Development Kit:

• Titanium Ti60 F225 Development Board

• USB-C data cable

• 12 V power adapter

• Ethernet Connector Daughter Card

You also need the following hardware, which you provide yourself:

• Ethernet cable

• Computer

## Hardware Set Up for Trion® T120 BGA324 Development Board

The following figure shows the hardware setup steps for Trion T120 BGA324 Development Board example design. If you have not already done so, attach standoffs to the board.

Figure 36: Trion® T120 BGA324 Development Board Hardware Setup Note: Install standoff first.


**1.** Connect a USB cable to the board and to your computer.

**2.** Connect an Ethernet cable to the RJ-45 receptable on the board and to your computer.

**3.** Connect a USB-to-UART module to the J12 header. See **Set Up a USB-to-UART Module** on page 64.

**4.** On header J10, connect pins 2 – 3 with a jumper (default) to use the on-board oscillator.

**5.** Leave the jumper on J2 at the defaults (connecting pins 1 -2). On J3, connect pins 1 – 2.

**6.** Connect the 12 V power supply to the board connector from a power source.

**7.** Turn on the board.

## Set Up a USB-to-UART Module

The Trion T120 BGA324 Development Board does not have a USB-to-UART converter. Therefore, you need to use a separate USB-to-UART converter module. A number of modules are available from various vendors; any USB-to-UART module should work.

Figure 37: Connect the UART Module to I/O header J12


**1.** Connect the UART’s RX, TX and ground pins to the Trion T120 BGA324 Development Board using:

• RX – GPIOT\_RXP20, which is labeled as 1 on header J12

• TX – GPIOT\_RXN20, which is labeled as 7 on header J12

• Ground – Ground, connect to one of the GND pins on header J12

**2.** Plug the UART module into a USB port on your computer. The driver should install automatically if needed.


## Hardware Set Up for Titanium Ti60 F225 Development Board

The following figure shows the hardware setup steps for Titanium Ti60 F225 Development Board example design. If you have not already done so, attach standoffs to the board.

Figure 38: Titanium Ti60 F225 Development Board Hardware Setup


**1.** Connect a USB-C cable to the board and to your computer.

**2.** Attach the Ethernet Connector Daughter Card to header P1 of the development board.

**3.** Connect an Ethernet cable to the RJ-45 receptacle on the Ethernet Connector Daughter Card and to your computer.

**4.** Leave the board jumper settings to default. Refer to the development kit User Guide for information about the default jumper settings.

**5.** Connect the 12 V power supply to the board connector from a power source.

**6.** Turn on the board.

## ● Note: Ensure that you install the driver for the correct interface. Refer to the [Titanium Ti60 F225 Development Kit User Guide](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=Ti50F225-DK-UG) for information about installing the drivers.

## Set Up a USB-to-UART Module

The Titanium Ti60 F225 development board has a USB-to-UART converter connected to the

Ti60’s GPIOL\_01 and GPIOL\_02 pins. To use the UART, connect a USB cable to the FTDI USB connector on the development board and to your computer.

## 1 Note: The board has an FTDI chip to bridge communication from the USB connector. FTDI interface 2 on Ti60 communicates with the on-board UART. You do not need to install a driver for this interface because when you connect the Titanium Ti60 F225 development board to your computer, Windows automatically installs a driver for it.

## Using the Example with the RISC-V SDK

Before working with the software included with this example design, you should already be familiar with Sapphire SoC and RISC-V SDK. Specifically, you should know how to:

• Launch Eclipse using the **run\_eclipse.bat** file (Windows) or **run\_eclipse.sh file** (Linux) scripts.

• Set up global environment variables.

• Create and build a software project.

• Debug using the OpenOCD debugger.

• Open a UART terminal.


**Learn more:** Refer to the RISC-V SDK chapter of the [**Sapphire RV32 SoC User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=SAPPHIREUG) for detailed instructions on how to perform these tasks.

## Test Modes

The example design with external PHY includes software for the Sapphire SoC in the tseDemo directory. In addition to the source code, Efinix provides compile binary files using predefined settings so you can easily try out the two test modes:

• Normal Test Mode – Use the **tseDemo.elf** file in the **build\test\_mode\_0** directory.

Linked-partner Test Mode – Use the **tseDemo.elf** file in the **build\test\_mode\_1** directory.

You can also customize the test modes by changing the variables in the Sapphire SoC software driver code, **embedded\_sw\sapphire\bsp\efinix\EfxSapphireSoc\app \tseDemo.h** file. However, you must rebuild the software if you change any variable.

Figure 39: Defining Variables in tseDemo.h File

```c
/************************** Project Header File ***************************/
#define PRINTF_EN 1
#define TEST_MODE 1 //0 : Normal Mode; 1 : Link partner Test Mode;
#define PAT_NUM 100
#define PAT DLEN 100
#define PAT IPG 100
#define PAT TYPE 0 //0 : UDP Pattern; 1 : MAC Pattern;
#define DST MAC_H 0xffff
#define DST MAC _L 0xffffffff
#define SRC MAC H 0xeae8
#define SRC MAC_L 0x5e0060c8
#define SRC IP 0xc0a80164
#define DST IP 0xc0a80165
#define SRC PORT 0x0521
#define DST PORT 0x2715
```

## Normal Mode Test

In Normal mode, the MAC or UDP pattern generator constructs and initiates TX packets through the TX path of the MAC core.

Figure 40: Normal Mode Data Flow


Table 21: Normal Mode Macros

| MacroName | Description |
| --- | --- |
| PAT_NUM | Numberofpacketstotransmit.SettingPAT_NUM=0enablesunlimitedpackettransmission. |
| PAT_DLEN | LengthoftheUDP/MACpatterntransmitpacket(payloadlength). |
| PAT_IPG | Interpacketgap(IPG)betweenframes.OneIPGunitequals8ns. |
| PAT_TYPE | Typeofpacketpattern: • 0:MACpattern • 1:UDPpattern |

The following are the criteria for the test:

• If PAT\_NUM = 0, the aFramesTransmittedOK counter continues to increment until it wraps around at 0xFFFF

If PAT\_NUM is non-zero, the aFramesTransmittedOK counter matches the programmed PAT\_NUM.

• The ifOutErrors counter remains at 0.

• The captured packet in Wireshark matches the transmitted pattern.

**Figure 41: Normal Mode Sample Telnet Session Output**

```txt
Terminal ×
COM9 ×
TSEMAC Example Design in Normal Mode
Waiting Link Up...
Linked Up
Link Partner Ful1 duplex 1000 Mbps Reg26 0x0000392c
Link Speed: 1000 Mbps
switching RX clock mux...
Info : Set Mac Speed.
Info : Set Mac IPG.
Info : Assert mac reset
Info : Deassert mac reset
Info : Mac Reset Statistics Counters.
Info : Set Pattern Generator.
aFramesTransmittedoK : 0x00000064
laFramesReceivedOK : Ox00000000
ifInErrors : Ox00000000
ifOutErrors : Ox00000000
letherStatsPkts : Ox00000000
letherStatsUndersizePkts : Ox00000000
letherStatsOversizePkts : Ox00000000
aRxFilterFramesErrors : Ox00000000
aFrameChecksequenceErrors : Ox00000000
laTxPAUSEMACCtrlFrames : Ox00000000
aRxPAUSEMACCtrlFrames : Ox00000000
aRxFilterFramesErrors : Ox00000000
letherStatsUndersizePkts : Ox00000000
etherStatsOversizePkts : Ox00000000
```

## Linked Partner Test

In Linked-Partner mode, the transmit packet are constructed and sent by an external network device, such as a PC or another Ethernet-enabled system. The AXI4-Stream loop-back is enabled in this mode, allowing the core to receive and re-transmit incoming packets directly through the enabled AXI4-Stream loop-back path without using the internal MAC or a UDP pattern generator.

This mode demonstrates the MAC RX or TX datapath integration with an external Ethernet partner and verifies successful bi-directional data transfer between the FPGA and a real network device.

Figure 42: Linked Partner Mode Data Flow


The test is a 'PASS' when the following conditions are achieved:

• aFramesTransmittedOK and aFramesReceivedOK counters are equal.

• The ifInErrors counter remains at 0.

• The packets captured using Wireshark match the packets transmitted by the external device.

## Figure 43: Linked Partner Mode Sample Telnet Session Output

```csv
Terminal×
COM9 ×
TSEMAC Example Design in Linked-Partner Mode
Waiting Link Up...
BMCR: 0x00001000
ANAR: 0x000001e1
GBCR: 0x00000200
GBSR: 0x00000800
PHYCR1: 0x00002118
PHYSR: 0x0000312c
Linked Up
Link Partner Ful1 duplex 1000 Mbps Reg26 0x0000312c
Link Speed: 1000 Mbps
Switching RX clock mux...
Info : Set Mac Address.
Info : Set Mac Speed.
Info : Set Mac IPG.
Info : Assert mac reset
Info : Deassert mac reset
Info : Set Mac Address.
Info : Mac Reset Statistics Counters.
aFramesTransmittedoK : Ox00000000
aFramesReceivedOK : 0x00000000
ifInErrors : Ox00000000
ifoutErrors : Ox00000000
etherStatsPkts : 0x00000000
etherStatsUndersizePkts : 0x00000000
etherStatsOversizePkts : 0x00000000
aRxFilterFramesErrors : 0x00000000
aFrameCheckSequenceErrors : Ox00000000
aTxPAUSEMACCtrlFrames : 0x00000000
aRxPAUSEMACCtrlFrames : 0x00000000
aRxFilterFramesErrors : 0x00000000
etherStatsUndersizePkts : 0x00000000
etherStatsOversizePkts : 0x00000000
aFramesTransmittedOK : 0x00000001
aFramesReceivedOK : 0x00000001
ifInErrors : Ox00000000
ifoutErrors : 0x00000000
etherStatsPkts : 0x00000001
etherStatsUndersizePkts : 0x00000000
etherStatsOversizePkts : 0x00000000
aRxFilterFramesErrors : 0x00000000
aFrameCheckSequenceErrors : 0x00000000
aTxPAUSEMACCtrlFrames : 0x00000000
aRxPAUSEMACCtrlFrames : 0x00000000
aRxFilterFramesErrors : 0x00000000
etherStatsUndersizePkts : 0x00000000
etherStatsOversizePkts : 0x00000000
```


**Note:** You can use any terminal program (such as Putty, Termite, or the built-in Eclipse Terminal to monitor the statistic counters - aFramesTransmittedOK and ifOutErrors.

## Realigning the PHY Clock

To ensure proper transmission and reception, the PHY clock must be correctly aligned with the data signals:

There are two ways to realign the PHY clock with respect to data:

• Option 1: Use the **PHY RGMII clock-to-data delay** in the Sapphire SoC software driver function.

• Option 2: Configure the **RGMII Transmit Clock Delay** and **First Sampling of RGMII Received Data** parameter in the General tab of the IP Configuration window.

## Using the PHY RGMII Clock-to-Data Delay (Trion only)

For Trion devices, you can control the transmit and receive clock delay of the PHY through the Sapphire SoC software driver.

This is done using the PhyDlySetRXTX() function in the **main.c** file.

To adjust the TX\_delay and RX\_delay, modify the function call in: **\embedded\_sw \sapphire\software\standalone\tseDemo\src\main.c**

This method allows flexible software-level tuning of the PHY delay values to achieve optimal RGMII clock-to-data alignment for both transmit and receive paths.

**Figure 44: Defining Delay in main.c Function File**

```c
void main() {
u32 prompt=0;
u32 speed;
PhyNego(1);
bsp_init();
if(TEST_MODE == 1){
bsp_print("=== TSEMAC Example Design in Linked-Partner Mode ===");
} else {
bsp_print("=== TSEMAC Example Design in Normal Mode ===");
}
PhyDlySetRXTX(8, 0); //change PHY RX_Delay and Tx_Delay settings here
speed = PhyNormalInit();
MacNormalInit(speed);
StartRunning();
```

Table 22: RX\_delay and TX\_delay Delay Settings

| Delays | Values | Description |
| --- | --- | --- |
| RX_delay | 0 - 15 | Clock to data setup delay for RGMII RX path with 1000 Mbps. Recommendedvalues: • 0:Smallestdelayofaround0.81ns • 2:Delayofaround1.1ns • 8:Delayofaround2.17ns • 15:Largestdelayofaround2.92ns |
| TX_delay | 0 - 15 | Clock to data setup delay for RGMII TX path with 1000 Mbps. Recommendedvalues: • 0:Smallestdelayofaround0.021ns • 2:Delayofaround0.4ns • 8:Delayofaround1.7ns • 15:Largestdelayofaround3.3ns |

## RGMII Dynamic Clock Switch (Titanium only)

In RGMII interfaces, clock-to-data skew caused by PCB trace length mismatches between the clock (rgmii\_rxc) and data (rgmii\_rxd) lines is a critical factor that affects reliable data sampling. At 1000 Mbps, even a small difference in trace length can lead to a timing misalignment of several hundred ps which is significant for double data rate (DDR) sampling.

To compensate for this skew and ensure that the clock edge is properly aligned with the center of the data valid window, the example design uses a PLL with core feedback. The PLL reconstructs an internal receive clock that is phase-aligned with the incoming RGMII signals at the FPGA input pins, effectively cancelling the skew introduced by PCB routing. This ensures accurate setup and hold timing at 1000 Mbps operation.

The receive clock (rgmii\_rxc) provided by the external PHY operates at different frequencies depending on the negotiated Ethernet link speed:

• 2.5 MHz for 10 Mbps

• 25 MHz for 100 Mbps

• 125 MHz for 1000 Mbps

Because the PLL input path has a minimum input frequency requirement and cannot reliably lock at very low frequencies such as 2.5 MHz, a dynamic clock mux is implemented to support all link speeds.

The dynamic clock mux automatically switches between the PLL and the direct GPIO clock path based on the detected link speed:

• At 10/100 Mbps, the RX clock is too slow for PLL operation, so the PHY RX clock is routed directly through the GPIO input path.

• At 1000 Mbps, the faster 125 MHz RX clock is routed through the PLL, enabling phase alignment with core feedback to compensate for PCB trace mismatch and maintain timing accuracy.

This allows the same RGMII interface to dynamically support 10/100/1000 Mbps operation while maintaining clock integrity, data alignment and timing reliability across all link speeds, even when PCB trace skew between the clock and data lines exists.

Figure 45: Dynamic Clock MUX in Titanium Ti60 F225 Example Design


## Using Wireshark

Wireshark is a free, open-source network packet analyzer used to capture and inspect Ethernet traffic. Efinix recommends using Wireshark to verify packet consistency between the transmitted and received packets, especially when the FPGA design is connected to a PC or other external network partner.

Follow the following steps to use Wireshark.

**1.** Download and install Wireshark.

• Visit [**www.wireshark.org**](http://www.wireshark.org) to download and install the latest version of Wireshark.

**2.** Launch Wireshark.

• Open the Wireshark software on your computer. Under the **Capture** category, you will see a list of available network interfaces.

**3.** Select the Ethernet interface.

Choose the active Ethernet interface connection to the FPGA board. Wireshark begins capturing packets that are being transmitted and received through this interface.

Figure 46: Wireshark Sample Output (Normal Mode, UDP Pattern)

| No. | Time | Source | Destination | rIUIULUI |  |
| --- | --- | --- | --- | --- | --- |
|  | 77 0.000388 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 78 0.000388 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 79 0.000388 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 80 0.000388 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 81 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 82 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 83 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 84 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 85 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 86 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 87 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 88 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 89 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 90 0.000442 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 91 0.000498 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 92 0.000498 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 93 0.000498 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 94 0.000498 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 95 0.000498 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 96 0.000498 | 192.168.1.100 | 192.168.1.101 | UDP | 142 1313 → 10005 Len=100 |
|  | 97 0.000498 | 192.168.1.100 | 192.168.1.101 |  | 142 1313 → 10005 Len=100 |
|  | 98 0.000498 | 192.168.1.100 | 192.168.1.101 |  | 142 1313 → 10005 Len=100 |
|  | 99 0.000498 | 192.168.1.100 | 192.168.1.101 |  | 142 1313 → 10005 Len=100 |
|  | 100 0.000498 | 192.168.1.100 | 192.168.1.101 |  | 142 1313 → 10005 Len=100 |

## Example Design Configuration Registers

## Default value for all DWORD offsets are

Table 23: Configuration Registers for Example Design with External PHY

<table><tbody><tr><td>Dword Offset</td><td>Name</td><td>R/W</td><td>Description</td></tr><tr><td>0x200</td><td>mac_sw_rst</td><td>R/W</td><td>Asserthightotriggertheproto_resetsignal.Theregister output is tied to the proto_reset signal.</td></tr><tr><td rowspan="2">0x204</td><td>Bit 0 - axi4_st_mux_select</td><td>R/W</td><td>0:TransmitAXI4-StreamTXpacketfrompatterngenerator.1:LoopbackAXI4-StreamRXpathtoAXI4-StreamTXpath.</td></tr><tr><td>Bit 1 - pat_mux_select</td><td>R/W</td><td>0:SelectUDPpatterngenerator.1:SelecttheMACpatterngenerator.</td></tr><tr><td rowspan="2">0x208</td><td>Bit 0 - udp_pat_gen_en</td><td>R/W</td><td>AsserthighthenlowtotriggeraUDPpacket.</td></tr><tr><td>Bit 1 - mac_pat_gen_en</td><td>R/W</td><td>AsserthighthenlowtotriggerMACpacket.</td></tr><tr><td rowspan="2">0x20c</td><td>Bit [15:0] - pat_gen_num</td><td>R/W</td><td>Thenumberoftransmitpackettosend.Zeroindicates unlimitedpackets.</td></tr><tr><td>Bit [31:16] - pat_gen_ipg</td><td>R/W</td><td>TheUDP/MACinterpacketgap.</td></tr><tr><td>0x210</td><td>pat_dst_mac [31:0]</td><td>R/W</td><td rowspan="2">TheUDP/MACpattern'sdestinationMACaddress.</td></tr><tr><td>0x214</td><td>pat_dst_mac [47:32]</td><td>R/W</td></tr><tr><td>0x218</td><td>pat_src_mac[31:0]</td><td>R/W</td><td rowspan="2">TheUDP/MACpattern'ssourceMACaddress</td></tr><tr><td>0x21c</td><td>pat_src_mac[47:32]</td><td>R/W</td></tr><tr><td>0x220</td><td>pat_mac_dlen [15:0]</td><td>R/W</td><td>ThelengthofaMACpatternpacket.ThecompleteMAC patternpacketispat_mac_dlen + 14 bytes (excluding CRC).</td></tr><tr><td>0x224</td><td>pat_src_ip[31:0]</td><td>R/W</td><td>TheUDPpattern'ssourceIPaddress.</td></tr><tr><td>0x228</td><td>pat_dst_ip [31:0]</td><td>R/W</td><td>TheUDPpattern'sdestinationIPaddress.</td></tr><tr><td>0x22c</td><td>Bit[15:0]pat_src_port</td><td>R/W</td><td>TheUDPpattern'ssourceport.</td></tr><tr><td></td><td>Bit[31:16]pat_dst_port</td><td></td><td>TheUDPpattern'sdestinationport.</td></tr><tr><td>0x230</td><td>pat_udp_dlen [15:0]</td><td>R/W</td><td>ThelengthofaUDPpatternpacket.ThecompleteUDP patternpacketispat_udp_dlen + 45 bytes (excluding CRC).</td></tr></tbody></table>

## Example Design with FPGA Transceiver

Efinix provides the following example design. The example design targets Titanium Ti375 N1156 Development Kit.

Figure 47: Triple Speed Ethernet MAC Core's Transceiver Example Design


The example design illustrates the connectivity among the Triple Speed Ethernet MAC, FPGA PCS, and the user’s logic, as shown in **Figure 47: Triple Speed Ethernet MAC Core's Transceiver Example Design** on page 75. The user’s logic consists of 2 pattern generators and 2 checkers (denoted by efx\_mac1gbe\_exp\_pat\_gen and efx\_mac1gbe\_exp\_checker modules respectively), APB modules (denoted by efx\_mac1gbe\_exp\_apb\_master and efx\_mac1gbe\_exp\_apb\_decoder), and a virtual I/O debugger.

The APB Master translates user-driven signals from the virtual I/O debugger (usr\_apb\_start, usr\_apb\_write, usr\_apb\_addr, and usr\_apb\_pwdata) into standard APB read and write transactions. A single APB transaction is initiated on the rising edge of the usr\_apb\_start signal, requiring all address and data inputs to be stable before assertion. During APB read operations, the module captures the returned bus data and its associated address, routing them to the ram\_dout\_a\_o and ram\_dout\_d\_o ports for realtime monitoring in the virtual I/O debugger. The APB decoder decodes the APB address and routes the APB request to the corresponding APB slaves based on the address map in **Table 24: Address Map for the Transceiver Example Design** on page 76.

Table 24: Address Map for the Transceiver Example Design

<table><tbody><tr><td>StartAddress</td><td>EndAddress</td><td>Registers</td></tr><tr><td colspan="3">PCS</td></tr><tr><td>0xC0_0400</td><td>0xC0_043F</td><td>PCS(Lane0)registers</td></tr><tr><td>0xC0_04C0</td><td>0xC0_04FF</td><td>PCS(Lane3)registers</td></tr><tr><td colspan="3">MAC</td></tr><tr><td>0xE0_0000</td><td>0xE0_01FF</td><td>MAC(Lane0)ConfigurationRegisters</td></tr><tr><td>0xE0_3000</td><td>0xE0_31FF</td><td>MAC(Lane3)ConfigurationRegisters</td></tr></tbody></table>

After the assertion of IN\_USER, the example design is waiting for the PLL to lock. The assertion of PLL\_LOCK releases the resets in the Triple Speed Ethernet MAC core and the FPGA PCS. This is followed by the PHY power-up sequence handshake, resulting in the assertion of PHY\_INIT\_DONE. Upon the assertion of PHY\_INIT\_DONE, the APB modules become operational and are used to write the corresponding signal\_ok register bit to 1, enabling the RX path, as depicted in the "signal\_ok Assertion Time" section of the [**Titanium SGMII 1G and 2.5G User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=UG-TiSGMII).

After achieving synchronization status, the pattern generator starts transmitting data frames into the TX AXI ST interface of the Triple Speed Ethernet MAC core. The generated traffic is determined during compile time through the JUMBO compiler directive. By default, when JUMBO is not defined, the generator outputs standard Ethernet frames containing exactly 1,500 bytes of payload data. However, when JUMBO is defined, the generator outputs jumbo Ethernet frames containing exactly 16,384 bytes of payload data.

Throughout the operation, the checker actively checks the RX path of the Triple Speed Ethernet MAC core for data payload mismatches and erroneous frame. Test passes when ln\_data\_cnt and ln\_frame\_cnt are incremented continuously, while the error tracking counters of ln\_err\_cnt and ln\_bad\_frame\_cnt remain at 0.

## To manage the SGMII Auto-Negotiation (AN) process, the

efx\_mac1gbe\_exp\_speed\_ctrl module is instantiated for the lane operating in MAC mode. Upon the assertion of the PCS\_AN\_COMPLETE signal from the PCS, the speed controller executes the following sequence:

## 1. Read Link Partner Speed

The speed controller takes control of the APB bus and executes a read from the **Auto-Negotiation Link Partner Abilities** register to extract the link partner’s advertised speed. Refer to table "Auto-Negotiation Link Partner Abilities" of the [**Titanium SGMII 1G and 2.5G User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=UG-TiSGMII).

## 2. Speed Evaluation

● The extracted link partner speed is compared against the current local speed.

If the speeds match, the sequence terminates immediately, and the speed controller returns to idle.

• If the speeds mismatch, the speed controller proceeds with the following sequence.

## 3. Assert Reset

The speed controller asserts the reset to hold the Triple Speed Ethernet MAC core and PCS in the reset state.

## 4. Disable PCS Receiver Path

• While the PCS is held in reset, the speed controller executes an APB write to clear the signal\_ok register bit.

This strictly adheres to the [**Titanium SGMII 1G and 2.5G User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=UG-TiSGMII), which mandates that the signal\_ok must be deasserted whenever clocks are unreliable to safely reset the receiver path and flush the CTC buffers.

## 5. Clock Stabilization Delay

• To guarantee all internal clocks are stable and locked to the newly negotiated speed, a 1us wait state is enforced.

## 6. Reset Release

• The speed controller releases the reset for the Triple Speed Ethernet MAC core and PCS.

• It then executes an APB write to set the signal\_ok register bit.

• The APB bus is released, and the synchronized link is fully operational.

## Available Macros in the Transceiver Example Design

The example design includes useful macros that allow you to further customize.

• AN\_L3\_PHY\_MODE

— Configure **Lane 3** as **PHY** mode and **Lane 0** as **MAC** mode for auto negotiation.

— Pre-requisite: Enable **SGMII Auto Negotiation (AN)** in the Interface Designer with speed of 10/100/1000 Mbps.

• AN\_L0\_PHY\_MODE

— Configure **Lane 0** as **PHY** mode and **Lane 3** as **MAC** mode for auto negotiation.

— Pre-requisite: Enable **SGMII Auto Negotiation (AN)** in the Interface Designer with speed of 10/100/1000 Mbps.

• L3\_1G/ L3\_100M/ L3\_10M

— Sets **Lane 3 SGMII\_MODE** to **1G/ 100M/ 10M**, respectively.

— If none of these macros are defined, **Lane 3** is set to **2.5G** by default.

• L0\_1G/ L0\_100M/ L0\_10M

— Sets **Lane 0 SGMII\_MODE** to **1G/ 100M/ 10M**, respectively.

— If none of these macros are defined, **Lane 0** is set to **2.5G** bydefault.

• JUMBO

— Configure the pattern generator to transmit alternate normal data frames and jumbo frames.

Pre-requisite: Change the **Maximum Transmission Unit Frame Length** to **16406** in Triple Speed Ethernet MAC IP Configuration.

By default, the following macros are enabled:

• **Auto Negotiation** mode

— AN\_L3\_PHY\_MODE

— L3\_100M

— L0\_1G

• **2.5G Jumbo** mode

— JUMBO


## Enabling the Macros in the Transceiver Example Design

To enable macros for Efinity compilation.

**1.** In the active example design, go to **File** > **Edit Project**. The **Project Editor** opens.

**2.** Go to **Synthesis** tab.

**3.** At the **Verilog define Macro** section, click + to add new macros.

**4.** Type in the name of the macro and set **Value** to 1 .

0L **Note:** When enabling the macros, always set the **Value** to 1. Setting the macro to a different value does not disable the macro.

**5.** To disable a macro, you have to remove it from **Verilog define Macro** section.

**6.** To remove a macro, select the desired macro and click -.

**Figure 48: Enabling Macro in the Example Design**


## Generating the Example Design

The available example designs with FPGA transceiver share an identical architecture but are delivered as 2 separate projects, **Auto Negotiation** mode and **2.5G Jumbo** mode. Use the following steps to generate the example design from the IP Catalog.

**1.** Create a new project.

**2.** Select the Triple Speed Ethernet MAC core from the IP Catalog and set the following configurations.

• Turn on **Use MAC with Transceiver** option.

• **Maximum Transmission Unit Frame Length:**: **16402** (for 2.5G Jumbo mode only)

**3.** In the **Deliverables** tab, turn on the **Example Design (Ti375N1156\_devkit\_auto\_nego)** and **Example Design (Ti375N1156\_devkit\_2p5g\_jumbo)**.

**4.** Click **Generate**.

The **Auto Negotiation** mode example design is available in **&lt;project path&gt;\ip\&lt;ipmodule-name&gt;\Ti375N1156\_devkit\_auto\_nego** directory.

The **2.5G Jumbo** mode example design is available in **&lt;project path&gt;\ip\&lt;ip-modulename&gt;\Ti375N1156\_devkit\_2.5g\_jumbo** directory.

To run the example design in **Auto Negotiation** mode:

**1.** Open the example design at **&lt;project path&gt;\ip\&lt;ip-module-name&gt; \Ti375N1156\_devkit\_auto\_nego\efx\_ethernet\_exp\_an\_1g\_100m.xml**

**2.** Compile the design.

**3.** Download the design to the Titanium Ti375 N1156 Development Kit.

**4.** Based on the macros enabled, read the **Auto Negotiation Advertised Abilities** register. The example design address of 0xC004D0 is used for this example design. Refer to table "Auto-Negotiation Advertised Abilities Register" of the [**Titanium SGMII 1G and 2.5G User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=UG-TiSGMII).

**5.** Then, override the following bits in the **Auto Negotiation Advertised Abilities** register:

• Bit 15 = 1 (Link up)

• Bit 12 = 1'b1 (Full duplex)

Bit [11:10] = 2'b01 (100 Mbps)

**6.** Upon assertion of PHY\_INIT\_DONE, write the corresponding signal\_ok register bit to 1 to enable the RX path at address 0x600040. For this example design, set bit 11 and bit 14 to 1'b1. Refer to table "signal\_ok Program Bit" of the [**Titanium SGMII 1G and 2.5G User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=UG-TiSGMII).

**7.** The test passes when:

• ln\_data\_cnt and ln\_frame\_cnt increments.

• ln\_err\_cnt and ln\_bad\_frame\_cnt remained 0.

To run the example design in **2.5G Jumbo** mode:

**1.** Open the example design at **&lt;project path&gt;\ip\&lt;ip-module-name&gt; \Ti375N1156\_devkit\_2.5g\_jumbo\efx\_ethernet\_exp\_2p5g\_jumbo.xml**.

**2.** Compile the design.

**3.** Download the design to the Titanium Ti375 N1156 Development Kit.

**4.** Upon assertion of PHY\_INIT\_DONE, write the corresponding signal\_ok register bit to 1 to enable the RX path at address 0x600040. For this example design, set bit 11 and bit 14 to 1'b1. Refer to table "signal\_ok Program Bit" of the [**Titanium SGMII 1G and 2.5G User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=UG-TiSGMII).

**5.** The test passes when:

• ln\_data\_cnt and ln\_frame\_cnt increments.

• ln\_err\_cnt and ln\_bad\_frame\_cnt remained 0.

Table 25: Transceiver Example Design Project Files

| FileName | Description |
| --- | --- |
| efx_ethernet_1g_exp.sv | Exampledesignoftop-levelwrapper. |
| &lt;user_given_ip_name>.sv (<sup>4</sup>) | TuhseergceonnefirgauteradtiTornipilneESfpineietydIPEtMhearnnaegteMr.ACcorefileisbasedonthe |
| Timing_Ti375.sdc | Constraintfileforexampledesign. |
| efx_mac1gbe_exp_apb_master.sv(<sup>4</sup>) | APBmastercontrollermodule. |
| efx_mac1gbe_exp_apb_decoder.v | APBaddressdecodermodule. |
| efx_mac1gbe_exp_pat_gen.sv | Patterngeneratormodule. |
| efx_mac1gbe_exp_checker.sv | Checkermoduletovalidatedatareceived. |
| efx_mac1gbe_exp_speed_ctrl.sv | Auto negotiation sequence module. |
| debug_top.v | VerilogfileforEFXdebugmodule. |
| debug_profile.json | VirtualI/ODebuggercorefile.LoadthisfileintheEfinityVirtualI/O Debugger to customize the example design. See Table26:Efinity VirtualI/ODebuggerSettings on page 82. |

<small><span class="docvortex-page-footnote" data-block-type="page_footnote" style="color:#6b7280">(4) This module is encrypted.</span></small>

## Virtual I/O Debugger Settings

This example design has a Virtual I/O Debugger interface to probe and control the signals of the example design. To control the settings, refer to the Virtual I/O Debugger settings.


**Note:** In the following table, the signal names are prefixed with l0\_ and l3\_, to indicate and distingush these instances. For a detailed signal description, refer to [**Titanium SGMII 1G and 2.5G User Guide**](https://www.efinixinc.com/support/docsdl.php?s=ef&pn=UG-TiSGMII) and **Table 14: Triple Speed Ethernet MAC Core Port Interface** on page 50.

Table 26: Efinity Virtual I/O Debugger Settings

<table><tbody><tr><td>Signal Name</td><td>Width</td><td>Probe/Source</td><td>Description</td></tr><tr><td colspan="4">GeneralSignals</td></tr><tr><td>pll_locked</td><td>1</td><td>Probe</td><td>LocksignalfromPLL,indicatingthattheclocksources (INIT_CLK and APB_CLK)arestable. Thissignalkicksstarttheoperationoftheexampledesign,wheretheassertionofPLL_LOCKreleasestheresetsintheTripleSpeedEthernetMACcoreandthe FPGA PCS.</td></tr><tr><td colspan="4">PCS Interface</td></tr><tr><td colspan="3">Instance Lane 0</td><td rowspan="6">RefertothesignaldescriptionsinSignals pTietarni Quumad SG taMblIeI 1 inG th aned Si 2g.n5aGls U cshearp Gteurid oef.</td></tr><tr><td>l0_sync_status</td><td>1</td><td>Probe</td></tr><tr><td>l0_sgmii_speed</td><td>2</td><td>Probe</td></tr><tr><td colspan="3">Instance Lane 3</td></tr><tr><td>l3_sync_status</td><td>1</td><td>Probe</td></tr><tr><td>l3_sgmii_speed</td><td>2</td><td>Probe</td></tr><tr><td colspan="4">TripleSpeedEthernetMAC Interface</td></tr><tr><td>pma_cmn_ready</td><td>1</td><td>Probe</td><td rowspan="7">RefertothesignaldescriptionsinTable14:TripleSpeed EthernetMACCorePortInterface on page 50.</td></tr><tr><td colspan="3">Instance Lane 0</td></tr><tr><td>l0_init_done</td><td>1</td><td>Probe</td></tr><tr><td>l0_rx_signal_detect</td><td>1</td><td>Probe</td></tr><tr><td colspan="3">Instance Lane 3</td></tr><tr><td>l3_init_done</td><td>1</td><td>Probe</td></tr><tr><td>l3_rx_signal_detect</td><td>1</td><td>Probe</td></tr><tr><td colspan="4">APB Interface and Status</td></tr><tr><td>usr_apb_start</td><td>1</td><td>Source</td><td>ThissignalenablesyoutomanuallytriggerAPBrequests. Efinixrecommendsthatyoucontrolthissignalby selecting Active-High fromthedrop-downlistinthe controlcolumn. Thissignaloperatesbasedonitsrisingedge,i.e.,theassertionofthissignaltriggers1APBrequest.Priorassertionofthissignal,APBsignals(usr_apb_write, usr_apb_addr, and usr_apb_pwdata) need to be assigned and stable. TotriggeranotherAPBrequest,thissignalneedstoreturnto0first,thenreasserttotriggerthesubsequentAPBrequest.</td></tr><tr><td>usr_apb_write</td><td>1</td><td>Source</td><td>APBWrite.</td></tr><tr><td>usr_apb_addr</td><td>24</td><td>Source</td><td>APBAddress.</td></tr><tr><td>usr_apb_pwdata</td><td>32</td><td>Source</td><td>APBWriteData.</td></tr><tr><td>ram_dout_a</td><td>24</td><td>Probe</td><td>CapturesanddisplaystheassociatedAPBaddress duringareadoperation.</td></tr><tr><td>ram_dout_d</td><td>32</td><td>Probe</td><td>CapturesanddisplaysthereturnedAPBreaddataupon thecompletionofareadtransaction.</td></tr><tr><td colspan="4">Auto Negotiation Interface</td></tr><tr><td colspan="3">Instance Lane 0</td><td rowspan="3">Theassertionofthissignalindicatesthattheauto nalelogwoetiadt.ion sequence is ongoing and no APB access is</td></tr><tr><td>l0_speed_chg_active</td><td>1</td><td>Probe</td></tr><tr><td>l3_speed_chg_active</td><td>1</td><td>Probe</td></tr><tr><td colspan="4">Checker</td></tr><tr><td>l0_data_cnt</td><td>8</td><td>Probe</td><td rowspan="2">Data counter-Incrementsoneverycyclewhenvaliddata isreceivedontheMACRXAXISTInterface</td></tr><tr><td>l3_data_cnt</td><td>8</td><td>Probe</td></tr><tr><td>l0_err_cnt</td><td>8</td><td>Probe</td><td rowspan="2">Errorcounter-Incrementsoneverycyclewhenerroneous dataisreceivedontheMACRXAXISTInterface</td></tr><tr><td>l3_err_cnt</td><td>8</td><td>Probe</td></tr><tr><td>l0_frame_cnt</td><td>8</td><td>Probe</td><td rowspan="2">Framecounter-Incrementsforeveryframereceivedon theMACRXAXISTInterface</td></tr><tr><td>l3_frame_cnt</td><td>8</td><td>Probe</td></tr><tr><td>l0_bad_frame_cnt</td><td>8</td><td>Probe</td><td rowspan="2">Bad frame counter-Incrementsforeverybadframe receivedontheMACRXAXISTInterface</td></tr><tr><td>l3_bad_frame_cnt</td><td>8</td><td>Probe</td></tr></tbody></table>


# Triple Speed Ethernet MAC Testbench

You can choose to generate the testbench when generating the Triple Speed Ethernet MAC core in the IP Manager Configuration window.

**Note:** You must include all **.v** and **.sv** files generated in the **/testbench** directory in your simulation.

**Important:** Efinix tested the testbench generated with the default parameter options only.

Efinix provides a ready-to-use Modelsim simulation script to help you quickly run the testbench. To execute the testbench, run the following command in a terminal application: vsim -c -do modelsim.do in a terminal application. You must have Modelsim installed on your computer to use this script.

Table 27: Testbench Files

| Directory | Description |
| --- | --- |
| ../Testbench | Contains the example design and testbench files. |
| ../Testbench/aldec | ContainstheencryptedsimulationsourcecodeforAldec. |
| ../Testbench/modelsim | ContainstheencryptedsimulationsourcecodeforModelSim. |
| ../Testbench/ncsim | ContainstheencryptedsimulationsourcecodeforNCSim. |
| ../Testbench/synopsys | ContainstheencryptedsimulationsourcecodeforSynopsys VCS. |

The simulation testbench is set up in a loopback configuration, where the RGMII TX interface is directly connected to the RGMII RX interface. The test performs a Transmit MAC Packet Test, which verifies data integrity through transmit-receive loopback checking. **Packet length** is set to **100**, **Packet number** is set to **1000**, and **Packet type** is set to **MAC pattern**. You can configure the MAC speed, pattern generator type, and packet length in the testbench.

During simulation, the pattern generator sends packets and the checker verifies each received packet against the transmitted one.

If a packet matches correctly, the terminal prints a message similar to the following:

Each line indicates the simulation timestamp and the packet sequence number successfully received.

```csv
Configure TSE MAC IP register setting
9610000 - Correct MAC packet 0, received
18330000 - Correct MAC packet 1, received
27050000 Correct MAC packet 2, received
35770000 Correct MAC packet 3, received
44490000 Correct MAC packet 4, received
53210000 Correct MAC packet 5, received
61930000 Correct MAC packet 6, received
70650000 Correct MAC packet 7, received
79370000 Correct MAC packet 8, received
88090000 Correct MAC packet 9, received
96810000 Correct MAC packet 10, received
```


**Note:** The testbench supports simulation for Triple Speed Ethernet MAC core only.

**Note:** Contact Efinix support at the [**Support Center**](https://www.efinixinc.com/support) to obtain the testbench for the Triple Speed Ethernet MAC core with FPGA PCS.

## Differences with Ethernet 10G MAC Core

When crc\_fwd = 1:

Triple Speed Ethernet MAC core forward CRC octets on rx\_axis\_mac\_tdata. The signals rx\_axis\_mac\_tvalid remain asserted until the last CRC octet, with rx\_axis\_mac\_tlast asserted at the last CRC octet.

Ethernet 10G MAC core, in contrast, ends TVALID and TLAST at the final data octet. The CRC octets are driven on TDATA immediately after the last data octet.

## Revision History

Table 28: Revision History

| Date | Document Version | IPVersion | Description |
| --- | --- | --- | --- |
| June 2026 | 6.3 | 7.3 | CorrectedfigurePowerUpHandshakewiththeFPGA TransceiverPHYandPCS,andTripleSpeedEthernetMACCoreSub-Modules.(DOC-3088) |
| May 2026 | 6.2 | 7.3 | Updated Example Design with FPGATransceiver, AvailableMacrosintheTransceiverExampleDesign, EnablingtheMacrosintheTransceiverExampleDesign,GeneratingtheExampleDesign,andVirtulI/ODebuggerSettings.(DOC-3050) |
| December 2025 | 6.1 | 7.1 | RemovednoteinClocksourcesandTerminatingBadTxFrames.(DOC-2850) Added note in RGMII RX of RX PHY Interface. Updatedsub-topicsinTerminatingBadTXFramesand addednewsub-topicNon-StreamingTXData. Updated all informations in the sub-topics and added newsub-topicNon-StreamingRXDataFrame(SGMII) underErroneousRXFrame. UpdatedSendPauseFrameatTXofPriorityFlow Comtrol(DuplexMode). UpdatedinformationinaTxIncontinuityFramesErrors. Added note in Latency and Example Design with ExternalPHY. |
| December 2025 | 6.0 | 7.0 | Newdocumentreleasereplacingthecurrent document. (DOC-2710) |
| November 2024 | 5.2 | 6.3 | UpdatedIPVersioninRevisionHistory.(DOC-2185) |
| November 2024 | 5.1 | 6.4 | AddedTopazinDeviceSupport.(DOC-2176)AddedIPVersioninRevisionHistory.(DOC-2185) |
| June 2024 | 5.0 | - | UpdatedRealigningthePHYClocksection.(DOC-1888)RemovedsectionUsingtheRGMIIrgmii_rxc_edgeandrgmii_txc_dlySignals.UpdatedwaveformsforOutputSignalsWaveform withDDIOEnabledandRGMIITransmitClock DelayEnabled(Center-aligned)andOutputSignals WaveformwithDDIOEnabledandRGMIITransmit Clock Delay Disabled (Edge-aligned). AddednewwaveformsforInputSignalsWaveformwith DDIOEnabledandFirstSamplingofRGMIIReceive DataUsingFallingEdgeandInputSignalsWaveform withDDIOEnabledandFirstSamplingofRGMII ReceiveDataUsingRisingEdge. AddednewdataRGMIITransmitClockDelayandFirst SamplingofRGMIIReceiveDataintableTripleSpeed EthernetMACCoreParameters. AddedanotefortableBlockEditorSettingsforrgmii_rx_ctl.AddedimportantnoteinExampleDesignand Testbenchregardingusingdefaultparametersoptionsonly.(DOC-1781) |
| December 2023 | 4.9 | - | Updated Titaniumresourceutilization.(DOC-1601) |
| June 2023 | 4.8 | - | AddedDeviceSupportandreleasenotessections.(DOC-1234)Updatedrgmii_txcsettingsforexampledesignandto run other designs at 1000 Mbps. |
| March2023 | 4.7 | - | Added-inNormalModeandLinked-PartnerModesub-topicinUsingWireshanktopic.(DOC-1176)UpdatedprograminUsingthePHYRGMIIClock-to-DataDelay(TrionOnly). |
| February2023 | 4.6 | - | AddedTi60F225DevelopmentBoardexampledesignsupport.(DOC-1152) |
| February2023 | 4.5 | - | Addednoteabouttheresourceandperformance valuesintheresourceandutilizationtablearefor guidanceonly. |
| December 2022 | 4.4 | - | Updated example design. (DOC-1015) Added New in version section. |
| October 2022 | 4.3 | - | Updatedportswidthanddescriptionsandaddednew ports. Updatedregisterswidthandaddednewregisters.CorrectedAXI4-StreamDataWidthparameteroption.Correcteds_axi_wdatawidth.Updatedexampledesigndirectoryandfilenames. AddedDescriptionaboutrealigningPHYclockwith top-module signals. |
| September 2022 | 4.2 | - | AddedsupportforGMII,RMII,andMIIPHYinterfaces. UpdatedcoreIPmanagerparameters. |
| April 2022 | 4.1 | - | AddednoteaboutRXpacketerrorfeatureis notsupportedandusercanignorewarningsonrgmii_rx_ctl_HIsignal.(DOC-787) |
| December 2021 | 4.0 | - | AddedexampledesigninIPmanager. CorrectedPHYICdescription. Updated example design RISC-V SoC to Sapphire. UpdatedsupportedFIFOdepthto16384. |
| November 2021 | 3.3 | - | CorrectedBlockEditorSettingsforrgmii_rx_ctlandrgmii_tx_ctlsignals. |
| October 2021 | 3.2 | - | UpdatedBlockEditorSettingsforrgmii_rx_ctlandrgmii_tx_ctlsignals.(DOC-586) |
| October 2021 | 3.1 | - | Added note to state that the f<sub>MAX</sub>inResource UtilizationandPerformance,andExampleDesign Implementationtableswerebasedondefault parametersettings. |
| June 2021 | 3.0 | - | Addedmissingrgmii_txc_LOinterfacedescriptionintheportstable. AddedparameterstosetinInterfaceDesignerDDIO settings. CorrectedOutputSignalsWaveformwithDDIO Enabledfigure. Added note about including all .vgeneratedin testbenchfolderisrequiredforsimulation. |
| December 2020 | 2.0 | - | Updated user guide for Efinix® IP Manager which includes added IP Manager topics, updated parameters,anduserguidestructure. |
| October 2020 | 1.2 | - | CorrectedBit0-axi4_st_mux_selectoftheexampledesignconfigurationregistersdescription. Updated normal and link test mode descriptions. AddedaFramesReceivedLen[15:0]tostatisticcounterregister.(DOC-318)Addedinformationaboutaddingdelaytore-allignthe PHY clock in the example design. (DOC-318) AddedsettingstoenablethehardDDIOblocksin InterfaceDesignerandwaveformsafterintegratingthehardDDIOblocksintothecore.(DOC-318) |
| August 2020 | 1.1 | - | Updated the Using this Example with the RISC-V SDK topic. |
| July 2020 | 1.0 | - | Initialrelease. |