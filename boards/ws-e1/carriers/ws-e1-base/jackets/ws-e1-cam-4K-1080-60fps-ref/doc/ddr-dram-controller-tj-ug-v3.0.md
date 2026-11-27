# TJ-Series DDR DRAM Block User Guide

**UG-DDR-DRAM-TI-v3.0**

**May 2026**

[**www.elitestek.com**](http://www.elitestek.com)

![](images/page_0_image_5.jpg)

## Contents

- Introduction... 3
- Features.... 3
- DDR Comparison.. 4
- TJ-Series FPGAs with LPDDR4/LPDDR4x DRAM Support.. 5
- Supported Frequencies and Configurations... 6
- Functional Description... ......... 8
- DDR PHY. 9
- DDR Controller. 9
- AXI Interface. 10
- Interface Mappings.. 11
- AXI Signals.. 12
- Narrow Transfers. 14
- Arbiter.... 14
- Configuration Register.. 15
- Configuration Controller. 15
- Address Mapping......... .16
- Clocking............... 17
- AXI Clock Speed.. 17
- LPDDR4 Controller Pin State... .. 18
- Reset and Calibration.... ..19
- DDR Interface Designer Settings... ... 20
- Supported DDR DRAM Devices... .. 22
- Revision History.. ..23

## Introduction

The TJ-Series DDR DRAM hardened memory controller and PHY provides a robust and complete solution to implement an external memory interface to a LPDDR4/LPDDR4x DRAM device. When the block is hardened, it provides a power and area-efficient solution.

Figure 1: DDR DRAM Interface Hard IP Block Diagram

![](images/page_2_image_4.jpg)

## Features

Supports LPDDR4 and LPDDR4x protocols

DDR PHY supports data rates up to 3,300 Mbps

Programmable termination with calibration to compensate for variations across power, voltage, and temperature (PVT)

● Supports various hardware calibrations for optimal performance

● User configurable data width support: x16 or x32 depending on the FPGA and package

User configurable timing parameters

● Supports up to 2 AXI interfaces with multiple accesses:

Data width up to 512 bits to allow a flexible system interconnect to the FPGA core

Includes a built-in arbiter to manage memory read and write requests from multiple sources

## DDR Comparison

Elitestek® strongly recommends you design with LPDDR4x for better performance and reduced power consumption.

Table 1: TJ-Series DDR Features

| Feature | LPDDR4 | LPDDR4x |
| --- | --- | --- |
| VDD (mV) | 850 | 850 |
| VDDQ (mV) | 1100 | 620 |
| V<sub>REF</sub> DQ (mV) | 0.167 x VDDQ(<sup>1</sup>) | 0.167 x VDDQ(<sup>1</sup>) |
| Maximum frequency (DDR controller) | 1.65 GHz(<sup>2</sup>) | 1.65 GHz(<sup>2</sup>) |
| Burst lengths | 16/32 | 16/32 |
| Configuration | x16, x32 | x16, x32 |
| Address commands signals | 6 Pins | 6 Pins |
| CA bus data rate | Single | Single |
| DQ bus data rate | Double | Double |
| Output drive strength (Ω) | Programmable(<sup>1</sup>) | Programmable(<sup>1</sup>) |
| CA training |  |  |
| DQ Read Training |  |  |
| DQ Write Training |  |  |
| V<sub>REF</sub> DQ Training |  |  |
| DQS Interval Oscillator |  |  |
| ZQ Calibration |  |  |
| Write leveling |  |  |
| Read leveling |  |  |
| Pre-bank refresh |  |  |
| Interface | LVSTL | LVSTL |
| On-Die Termination (ODT) | (1) | (1) |
| Package option | Discrete | Discrete |

<small><span class="docvortex-page-footnote" data-block-type="page_footnote" style="color:#6b7280">(1) Refer to your DRAM data sheet.</span></small>

<small><span class="docvortex-page-footnote" data-block-type="page_footnote" style="color:#6b7280">(2) Refer to the device data sheet in the [Elitestek website](https://www.elitestek.com) for the maximum data rate supported by package.</span></small>

## TJ-Series FPGAs with LPDDR4/LPDDR4x DRAM Support

Table 2: DDR DRAM Widths Supported for TJ-Series FPGAs

| FPGA | Package | LPDDR4/4x PHY with Memory Controller | DQ Widths |
| --- | --- | --- | --- |
| Ti180 | M484, A484S | 1 block | x16 |
| Ti90, Ti120, and Ti180 | J361 | 1 block | x16 |
| Ti90, Ti120, and Ti180 | J484, G529 | 1 block | x16 or x32 |
| TJ85 and TJ135 | N441X | 1 block | x16 |
| TJ85 and TJ135 | N576X | 1 block | x16 or x32 |
| TJ135 | N576XD2F4 | 1 block | x16 |
| TJ85 and TJ135 | N676X | 1 block | x16 or x32 |
| TJ85, TJ135, TJ165, TJ240, and TJ375 | N484X | 1 block | x16 or x32 |
| TJ165, TJ240, and TJ375 | N529 | 1 block | x16 or x32 |
| TJ165, TJ240, and TJ375 | N900X, N1156X | 2 blocks | x16 or x32 |

## Supported Frequencies and Configurations

Refer to device data sheet for the LPDDR4/LPDDR4x DRAM interface maximum data rate. You need to validate the actual data rate supported by your system.

Elitestek® recommends LPDDR4x for lower power and better performance.

The following LPDDR4 and LPDDR4x configurations are supported. The figures show the connections between the FPGA and the DRAM device.

Single-Rank, x16 Interface

![](images/page_5_image_6.jpg)

**Note:** Dual rank only supports a single package. A single package may consist of multiple dies (as in the DRAM device).

![](images/page_5_image_8.jpg)

Dual-Rank, x16 Interface

![](images/page_5_image_10.jpg)

Single-Rank, x32 Interface

![](images/page_6_image_2.jpg)

Dual-Rank, x32 Interface

![](images/page_6_image_4.jpg)

## Functional Description

The DDR DRAM block includes the elements shown in the following figure:

Figure 2: DDR DRAM Interface Hard IP Block Diagram

![](images/page_7_image_4.jpg)

## DDR PHY

The DDR PHY is a physical layer that interfaces with the external DRAM device. It is fully compliant with the LPDDR4 and LPDDR4x electrical specifications. DDR PHY has a built-in data training circuit to enable in-system calibration, which helps optimize the system timing for high performance.

The PHY connects to the DRAM device using the signals in the following table.

Table 3: DDR DRAM Pads

These pads are not available in the D576SX package because the memory device is inside the package.

<table><tbody><tr><td>Signal</td><td>Direction</td><td>Description</td></tr><tr><td>DDR_A[5:0]</td><td>Output</td><td>Address signals to the DRAM.</td></tr><tr><td>DDR_CS_N[3:0]</td><td>Output</td><td>Chip select to the DRAM.</td></tr><tr><td>DDR_CKE[1:0]</td><td>Output</td><td>Active-high clock enable signals to the DRAM.</td></tr><tr><td>DDR_RST_N</td><td>Output</td><td>Active-low reset signal to the DRAM.</td></tr><tr><td>DDR_CK</td><td>Output</td><td rowspan="2">Differential clock signals to the DRAM.</td></tr><tr><td>DDR_CK_N</td><td>Output</td></tr><tr><td>DDR_DQ[n:0]</td><td>Bidirectional</td><td>Data bus to/from the memories. For writes, the FPGA drives these signals. For reads, the memory drives these signals. These signals are connected to the DQ pins on the memories. n is 15 or 31 depending on the Data Width setting. If unused, can be left floating on the board.</td></tr><tr><td>DDR_DQS_N[m:0]</td><td>Bidirectional</td><td rowspan="2">Differential data strobes to/from the memories. Forwrites, the FPGA drives these signals. For reads, the memory drives these signals. These signals are connected to the DQS pins on the memories. m is 1or 3 depending on the DQ width. If unused, can be left floating on the board.</td></tr><tr><td>DDR_DQS[m:0]</td><td>Bidirectional</td></tr><tr><td>DDR_DM[m:0]</td><td>Bidirectional</td><td>Signals used as active-high data-mask and data bus inversion indicator. m is 1 or 3 depending on the DQ width. If data bus inversion is enabled for a write operation, the DDR controller will drive the signal high ifthe write data byte is inverted. Similarly, ifdata bus inversion is enabled for a read operation, the memory device will drive the signal high if the read data byte is inverted. If unused, can be left floating on the board.</td></tr></tbody></table>

![](images/page_8_image_7.jpg)

Note: Unused DDR\_DQ/DDR\_DQS and DDR\_DQS\_N/DDR\_DM can be left floating on the board.

## DDR Controller

The DDR controller block handles all of the protocols and handshaking between the DRAM device and the DDR PHY. It reduces the latency of the DRAM device interface and minimizes core logic consumption.

## AXI Interface

The DDR DRAM interface hard IP block has two AXI interfaces (target 0 and target 1) that provide an easy and efficient way to access the DRAM device. All AXI signals and operations comply with the AMBA AXI4 specification.

The AXI interface supports:

A clock frequency that is asynchronous to the controller clock frequency; a FIFO handles the synchronization between the AXI clock domain and the DDR controller clock domain

● Burst sizes of 1 – 64 bytes

Burst lengths of 1 – 256 for data transfer

Read and write strobes (data masking)

● Incrementing and wrapping burst types

● Narrow bus transfers

The following figures are examples of the read and write operations.

Figure 3: Read Operation Example

![](images/page_9_chart_12.jpg)

Figure 4: Write Operation Example

![](images/page_9_image_14.jpg)

Note: AWREADY is asserted after both AWVALID and WVALID are asserted.

## Interface Mappings

The AXI data width, AXI burst size, DRAM DQ width, and burst length determine the AXI-to-DQ data mapping. The following example shows the mapping based on these settings:

● AXI data width: 512

● AXI burst size (ASIZE) (number of bytes): 64

● DQ width: 32

DRAM Burst Length: 16

Table 4: AXI Data to DRAM Device DQ Mapping Example

<table><tbody><tr><td>AXI Data</td><td>[511:504]</td><td>[503:496]</td><td>[495:488]</td><td>[487:480]</td><td>...</td><td>[31:24]</td><td>[23:16]</td><td>[15:8]</td><td>[7:0]</td></tr><tr><td>AXI Beat</td><td>64</td><td>63</td><td>62</td><td>61</td><td>...</td><td>4</td><td>3</td><td>2</td><td>1</td></tr><tr><td>DQ</td><td>[31:24]</td><td>[23:16]</td><td>[15:8]</td><td>[7:0]</td><td>...</td><td>[31:24]</td><td>[23:16]</td><td>[15:8]</td><td>[7:0]</td></tr><tr><td>DRAM Burst</td><td colspan="4">16</td><td>...</td><td colspan="4">1</td></tr></tbody></table>

Table 5: Maximum Burst Length

| AWSIZE/ARSIZE | AWLEN/ARLEN |
| --- | --- |
| 6 | ≤ 63 |
| 5 | ≤ 127 |
| 4 | ≤ 255 |

![](images/page_10_image_11.jpg)

## Note: A burst must not cross a 4KB address boundary.

## AXI Signals

The following tables describe the read and write AXI interfaces signals.

Table 6: AXI4 Global Signals (Interface to FPGA Core Logic)

| Signal | Direction | Clock Domain | Description |
| --- | --- | --- | --- |
| ACLK_x | Input | N/A | AXI4 clock inputs. |
| ARSTN_x | Input | ACLK_x | Active-low reset signal to the AXI interface. |

Table 7: AXI4 Write Address Signals (Interface to FPGA Core Logic)

| Signal x is 0 or 1 | Direction | Clock Domain | Description |
| --- | --- | --- | --- |
| AWADDR_x[32:0] | Input | ACLK_x | Write address. It gives the address ofthe first transferin a burst transaction. |
| AWBURST_x[1:0] | Input | ACLK_x | Burst type. The burst type and the size determine how the address for each transfer within the burst is calculated. |
| AWID_x[5:0] | Input | ACLK_x | Address ID. This signal identifies the group of address signals. |
| AWLEN_x[7:0] | Input | ACLK_x | Burst length. This signal indicates the number of transfers in a burst. |
| AWREADY_x | Output | ACLK_x | Address ready. This signal indicates that the slave is ready to accept an address and associated control signals. |
| AWSIZE_x[2:0] | Input | ACLK_x | Burst size. This signal indicates the size of each transfer in the burst. |
| AWVALID_x | Input | ACLK_x | Address valid. This signal indicates that the channel is signaling valid address and control information. |
| AWLOCK_x | Input | ACLK_x | Lock type. This signal provides additional information about the atomic characteristics ofthe transfer. |
| AWAPCMD_x | Input | ACLK_x | Write auto-precharge. |
| AWQOS_x | Input | ACLK_x | QoS identifier for write transaction. |
| AWCACHE_x[3:0] | Input | ACLK_x | Memory type. This signal indicates how transactions are required to progress through a system. |
| AWALLSTRB_x | Input | ACLK_x | Write all strobes asserted. The DDR controlleronly supports a maximum of16 AXI beats for write commands using this signal. |
| AWCOBUF_x | Input | ACLK_x | Write coherent bufferable selection. AWCACHE_xmust be set to 'b1111 for AWCOBUF_x when: ● 'b0 = Bvalid Response is returned when both command and data have been received by the port. ● 'b1 = Bvalid Response is returned when command is accepted into the controller command queue. When AWCACHE_x is set to 'b0000: ● Bvalid Response is returned when command is issued to PHY. |

Table 8: AXI4 Write Data Channel Signals (Interface to FPGA Core Logic)

| Signal x is 0 or 1 | Direction | Clock Domain | Description |
| --- | --- | --- | --- |
| WDATA_x[511:0] | Input | ACLK_x | Write data. |
| WLAST_x | Input | ACLK_x | Write last. This signal indicates the last transferin a write burst. |
| WREADY_x | Output | ACLK_x | Write ready. This signal indicates that the slave can accept the write data. |
| WSTRB_x[63:0] | Input | ACLK_x | Write strobes. This signal indicates which byte lanes hold valid data. There is one write strobe bit for each eight bits of the write data bus. |
| WVALID_x | Input | ACLK_x | Write valid. This signal indicates that valid write data and strobes are available. |

Table 9: AXI4 Write Response Channel Signals (Interface to FPGA Core Logic)

| Signal x is 0 or 1 | Direction | Clock Domain | Description |
| --- | --- | --- | --- |
| BID_x[5:0] | Output | ACLK_x | Response ID tag. This signal is the ID tag of the write response. |
| BREADY_x | Input | ACLK_x | Response ready. This signal indicates that the mastercan accept a write response. |
| BRESP_x[1:0] | Output | ACLK_x | Read response. This signal indicates the status ofthe read transfer. |
| BVALID_x | Output | ACLK_x | Write response valid. This signal indicates that the channel is signaling a valid write response. |

Table 10: AXI4 Read Address Signals (Interface to FPGA Core Logic)

| Signal x is 0 or 1 | Direction | Clock Domain | Description |
| --- | --- | --- | --- |
| ARADDR_x[32:0] | Input | ACLK_x | Read address. It gives the address of the first transfer in a burst transaction. |
| ARBURST_x[1:0] | Input | ACLK_x | Burst type. The burst type and the size determine how the address for each transfer within the burst is calculated. 'b01 = INCR 'b10 = WRAP |
| ARID_x[5:0] | Input | ACLK_x | Address ID. This signal identifies the group of address signals. |
| ARLEN_x[7:0] | Input | ACLK_x | Burst length. This signal indicates the number of transfers in a burst. |
| ARREADY_x | Output | ACLK_x | Address ready. This signal indicates that the slave is ready to accept an address and associated control signals. |
| ARSIZE_x[2:0] | Input | ACLK_x | Burst size. This signal indicates the size of each transfer in the burst. |
| ARVALID_x | Input | ACLK_x | Address valid. This signal indicates that the channel is signaling valid address and control information. |
| ARLOCK_x | Input | ACLK_x | Lock type. This signal provides additional information about the atomic characteristics ofthe transfer. |
| ARAPCMD_x | Input | ACLK_x | Read auto-precharge. |
| ARQOS_x | Input | ACLK_x | QoS identifier for read transaction. |

Table 11: AXI4 Read Data Channel Signals (Interface to FPGA Core Logic)

| Signal x is 0 or 1 | Direction | Clock Domain | Description |
| --- | --- | --- | --- |
| RDATA_x[511:0] | Output | ACLK_x | Read data. |
| RID_x[5:0] | Output | ACLK_x | Read ID tag. This signal is the identification tag for the read data group of signals generated by the slave. |
| RLAST_x | Output | ACLK_x | Read last. This signal indicates the last transfer in a read burst. |
| RREADY_x | Input | ACLK_x | Read ready. This signal indicates that the mastercan accept the read data and response information. |
| RRESP_x[1:0] | Output | ACLK_x | Read response. This signal indicates the status ofthe read transfer. |
| RVALID_x | Output | ACLK_x | Read valid. This signal indicates that the channel is signaling the required read data. |

## Narrow Transfers

The AXI DDR implementation supports narrow transfers. It is important to set the WSTRB\_x[n:0] signals correctly when performing narrow transfers. There is one write strobe for every eight bits of the write data bus. A master must ensure that the write strobes are set to logic high for byte lanes that contain valid data.

The following figure illustrates an example of five incremental bursts of an 8-bit transfer on a 32- bit bus with a starting address of 0.

$$
\mathsf { W S T R B } = 0 0 1 0
$$

$$
\mathsf { W S T R B } = 1 0 0 0
$$

$$
\mathsf { W S T R B } = 0 0 0 1
$$

Figure 5: 8-bit Transfer on a 32-bit Bus Example

<table><tr><td rowspan=3>31    242</td><td></td><td></td><td></td><td></td><td></td><td></td></tr><tr><td rowspan=2>3    16</td><td rowspan=2>15     8</td><td></td><td></td><td></td><td></td></tr><tr><td>7       0</td><td rowspan=5 colspan=3>1st Transfer2nd Transfer3rd Transfer4th Transfer</td></tr><tr><td></td><td></td><td></td><td>D[7:0]</td></tr><tr><td></td><td></td><td>D[15:8]</td><td></td></tr><tr><td></td><td>D[23:16]</td><td></td><td></td></tr><tr><td>D[31:24]</td><td></td><td></td><td></td><td colspan=2>4th Tra</td></tr><tr><td rowspan=2></td><td rowspan=2></td><td rowspan=2></td><td rowspan=2>D[7:0]</td><td rowspan=2 colspan=2>5th</td><td>5th Tre</td></tr><tr><td></td><td></td></tr><tr><td colspan=7></td></tr></table>

WDATA[31:0]

The following figure illustrates an example of a three incremental burst of a 32-bit transfer on a 64-bit bus with a starting address of 4.

Figure 6: 32-bit Transfer on a 64-bit Bus Example

<table><tr><td rowspan=8>WSTRB = 11110000WSTRB = 00001111WSTRB = 11110000</td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr><tr><td rowspan=4>63</td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr><tr><td rowspan=3 colspan=7>4847    4039    3231    2423    1615     87      o</td><td></td></tr><tr><td rowspan=2>5548</td><td></td></tr><tr><td rowspan=4>1st Transfer2nd Transfer3rd Transfer</td></tr><tr><td>D[63:56]</td><td>D[55:48]</td><td>D[47:40]</td><td>D[39:32]</td><td></td><td></td><td></td><td></td></tr><tr><td></td><td></td><td></td><td></td><td>D[31:24]</td><td>D[23:16]</td><td>D[15:8]</td><td>D[7:0]</td></tr><tr><td>D[63:56]</td><td>D[55:48]</td><td>D[47:40]</td><td>D[39:32]</td><td></td><td></td><td></td><td></td></tr></table>

WDATA[63:0]

![](images/page_13_image_14.jpg)

**Learn more:** Refer to the AMBA AXI and ACE Protocol Specification for more information about narrow transfer transaction structure.

## Arbiter

The arbiter handles simultaneous read and write requests from the AXI 0 and 1 interfaces. It decides which request from the two interfaces to send to the DDR controller based on roundrobin arbitration.

The arbiter rotates between the interface numbers. The request of an interface will be sent to the DDR controller when it is its turn if it fulfils the following conditions:

**1.** That particular interface must have an active request.

**2.** The DDR controller's command queue is not full.

If an interface’s turn comes but there is no active request from that interface, then that interface will be skipped. This is followed by checking on the other interface. Round-robin operation ensures that each interface’s requests can be successfully arbitrated into the controller core every two cycles and no interface will be locked out. Any interface can have its requests serviced at every cycle if the other interface is quiet and the command queue is not full.

## Configuration Register

The configuration register stores the settings required for the DDR DRAM interface hard IP block and external memory device to operate properly. During FPGA configuration, this configuration register is programmed automatically by the configuration controller.

## Configuration Controller

The configuration controller facilitates the operations required to start the DDR DRAM interface hard IP block and performs the following tasks:

**1.** Configures the correct settings into the DDR PHY and the controller.

**2.** Initializes the DRAM device by programming the correct instruction sequence into the controller.

**3.** Configures the DRAM device **Mode Registers Settings (MRS)**.

**4.** Works with the DDR PHY to perform calibration and trainings.

The following table shows the list of signals for the configuration controller.

Table 12: Configuration Controller Signals

| Signal | Direction | Description |
| --- | --- | --- |
| CFG_RESET | Input | Active-high startup sequencer reset. |
| CFG_START | Input | Start the startup sequencer. |
| CFG_DONE | Output | Indicates the startup sequencer is done. |
| CFG_SEL | Input | Tie this input to low to enable the configuration controller. |

The following figure shows the configuration controller signal waveform.

**Figure 7: Configuration Controller Signal Waveform**

| CFG_RESET |  |
| --- | --- |
| CFG_SEL |  |
| CFG_START | Configuration Controller Tasks Start |
| CFG_DONE | Configuration Controller Tasks Completed |

![](images/page_14_image_15.jpg)

## Note:

● CFG\_START must stay high even after CFG\_DONE goes high.

CFG\_RESET must stay high for at least 5 cycles of the controller clock.

## Address Mapping

From the user perspective, the AXI address space is one continuous byte address space starting from byte 0 up to the size limit of the memory device. Behind the scenes, the DDR controller accesses the memory device using bank, column, and row addresses. The data width accessed by each address space is dependent on the DDR controller data width. For example, an x32 data width controller accesses 4 bytes of memory data for each address.

The relationship between the user AXI address and DDR controller address is as follows:

| DQ Data Width | DDR Controller &amp; AXI Address Mapping |
| --- | --- |
| x32 data width | DDR controller address = AXI address >> 2 |
| x16 data width | DDR controller address = AXI address >> 1 |

where >> is a Verilog HDL operator that denotes a bit-wise right shift.

Hence, for x32, the least significant bit (LSB) of the DDR controller address is bit 2 (starting from 0) of the AXI address. For x16, the LSB of the controller address is bit 1 of the AXI address.

The AXI address contains 5 fields. The following example shows the AXI address bit numbers for the maximum allowable address space.

| 32 | 31:15 | 14:12 | 11:2 | 1:0 |
| --- | --- | --- | --- | --- |
| Chip select | Row address | Bank address | Column address | Datapath |

For accessing lower density memories (with smaller row and column address range), drive the MSBs that are not used with 0s. The following example shows a mapping with MSBs that are not used:

| 32:28 | 27 | 26:12 | 11:9 | 8:2 | 1:0 |
| --- | --- | --- | --- | --- | --- |
| Not used | Chip select | Row address | Bank address | Column address | Datapath |

The chip select, row, bank, and column address fields are used to address an entire memory word, and the datapath bits are used to address individual bytes within that user word. For example, for a read starting at byte address 0x2, the datapath bits must be defined as ’b010 to address this byte directly. Read and write operations are memory word-aligned if all the datapath bits are 0.

## Clocking

Depending on the TJ-Series FPGA package, the DDR DRAM interface hard IP block may require one or two clocks that must be driven directly from the PLL.

## DDR DRAM Interface Input Clocks

For most of the packages, you only need one clock from the PLL to drive the DDR DRAM interface block. You can choose **CLKIN 0**, **CLKIN 1**, or **CLKIN 2** as the **Clock Source** in the Interface Designer, this will select CLKOUT3 (or CLKOUT4 for some devices) from the respective PLL to drive the DDR DRAM interface block. The clock runs at a quarter of the PHY data rate (for example, 2,000 Mbps requires a 500 MHz clock). You need to instantiate the selected PLL in the Interface Designer and configure the PLL's CLKOUT to the required frequency. The Efinity software then connects the PLL's CLKOUT signal to the DDR DRAM interface block automatically.

![](images/page_16_image_5.jpg)

**Note:** Refer to the Interface Floorplan in the device data sheet for information on the DDR DRAM interface blocks that are available in your package.

![](images/page_16_image_7.jpg)

**Note:** Refer to the DDR DRAM Interface section in the device data sheet for information on the PLLs and CLKOUTs for the DDR DRAM interface blocks.

For the M484 package, two clocks from the PLL are required to drive the DDR DRAM interface block. The PLL TL2 CLKOUT3 and CLKOUT4 are clocks to drive the DDR PHY and controller respectively. The CLKOUT3 drives the DDR PHY and must run at half of the PHY data rate (for example, 2,000 Mbps requires a 1,000 MHz clock). CLKOUT4 drives the DDR controller and must run at a quarter of the PHY data rate (for example, 2,000 Mbps requires a 500 MHz clock). You only need to instantiate PLL TL2 with CLKOUT3 and CLKOUT4 enabled with the required frequencies.

## AXI Clock Speed

In TJ-Series FPGA, the maximum data rate is up to 3.3 Gbps, user can calculate the data rate of AXI clock speed to achieve the data rate of LPDDR4/4x for your requirement.

The ideal case equation is as follows:

DDR data rate x DDR DQ width = AXI clock speed x AXI data width

```txt
DDR data rate = 2,666 Mbps
DDR DQ width = 32
AXI data width = 512
So, AXI clock speed = (2,666 Mbps x 32) / 512 = 166.6 MHz
```

![](images/page_16_image_15.jpg)

**Note:** The efficiency of the AXI bus is not factored into the calculation of the ideal case equation.

## LPDDR4 Controller Pin State

Refer to the following table for the state of the LPDDR4 controller pins in reset or non-user mode.

Table 13: LPDDR4 Controller Pin State

| Condition | DDR_RST_N | DDR_CS Pins | DDR_CKE | DDR_CK | DDR_CA Pins | DDR_DQDDR_DMDDR_DQSDDR_DQSnPins |
| --- | --- | --- | --- | --- | --- | --- |
| Power Group 1 Ramp Up (VDD_PHY,VDDPLL_MCB_TOP_PHY) | 0 | 0 | 0 | 0 | Z | Z |
| Power Group 2 Ramp Up (VDDQ_PHY, VDDQX_PHY, VDDQ_CK_PHY) | 0 | 0 | 0 | 0 | Z | Z |
| FPGA creset_n = 0 | 0 | 0 | 0 | 0 | Z | Z |
| FPGA Configuration (SPI active, SPI passive, orJTAG) | 0 | 0 | 0 | 0 | Z | Z |
| User Mode Without DDR Enabled | 0 | 0 | 0 | 0 | Z | Z |
| User Mode With DDR Enabled | 0 | 0 | 0 | 0 | Z | Z |
| ddr_inst_CFG_RESET = 1 | 0 | 0 | 0 | 0 | Z | Z |
| ddr_inst_CFG_RESET = 0 | 0 | 0 | 0 | 0 | Z | Z |
| ddr_inst_CFG_START = 1 and ddr_inst_CFG_START = 0 (+CFG_RESET=0) | 1 | Toggle | Toggle | Toggle | Toggle | Toggle |
| ddr_inst_CFG_DONE = 1 | 1 | Toggle | Toggle | Toggle | Toggle | Toggle |

# Reset and Calibration

The DDR DRAM interface hard IP block has reset inputs that allow you to reset the AXI interfaces, DDR controller, DDR PHY, and DRAM device. The following table summarizes the available resets.

**Table 14: Resets**

| Signal | Description |
| --- | --- |
| CFG_RESET | Active-high reset to the Configuration Controller. Asserting this reset will also reset the DDR controller, PHY and the DRAM device. |
| ARST_X | Active-high reset for the AXI interface. |

![](images/page_18_image_5.jpg)

**Note:** Elitestek recommends that you assert all the resets together after the power supplies are stable.

Asserting CFG\_RESET resets the DDR controller, DDR PHY, and the DRAM device. After asserting CFG\_RESET, you should start the Configuration Controller to configure the correct settings into the Configuration Register. Next, initialize the DRAM. The Configuration Controller also works with the DDR PHY to perform the following operations:

I/O calibration—Adjusting the I/O delay for process, voltage, and temperature compensation.

CA/CS training—Aligning the center of the address, command, and chip select to the rising edge of the memory clock.

Write leveling—Aligning the write DQS to the memory clock.

Read DQS gate training—Tuning the read DQS enable for DQS preamble.

Read data eye training—Aligning the read DQS to the center of the DQ eye for read operations.

Write data eye training—Aligning the center of the DQ eye to the DQS edge for write operations.

# DDR Interface Designer Settings

The following tables describe the settings for the TJ-Series DDR block in the Interface Designer. The settings should match the DRAM device that you are using.

Table 15: Base Tab

| Parameter | Choices | Notes |
| --- | --- | --- |
| Instance Name | User defined | Indicate the DDR instance name. This name is the prefix for all DDR signals. |
| DDR Resource | None, DDR_0, DDR_1 | Indicate the resources available. |
| Data Width | 16, 32 | Choose the DQ width. Default: 32 (16 for J361 and M484 packages) |
| Memory Density | 2G, 3G, 4G, 6G, 8G, 12G, 16G | Choose the memory density per channel. Default: 4G |
| Physical Rank | 1, 2 | Default: 1 |
| Memory Type | LPDDR4, LPDDR4x | Default: LPDDR4 |
| Clock | CLKIN 0, CLKIN 1, CLKIN 2 | Choose which PLL resource to use as the DDR clock. Refer to Clocking on page 17. |

Table 16: Advanced Options Tab (FPGA Settings)

| Option | Choices | Notes |
| --- | --- | --- |
| Auto Low Power Mode | Enable, Disable | Default: Disable The LPDDR4 memory can automatically enter into a self-refresh power-down mode when the DDR controller is idle, and exit if it issues a write or read command. |
| DQ Pull-Down Drive Strength (Ohm) | 34.3, 40, 48, 60, 80, 120, 240 | Default: 48 |
| DQ Pull-Down ODT (Ohm) | 34.3, 40, 48, 60, 80, 120, 240, High-Z | Default: 60 |
| DQ Pull-Up Drive Strength (Ohm) | 34.3, 40, 48, 60, 80, 120, 240 | Default: 48 |
| DQ Pull-Up ODT (Ohm) | 34.3, 40, 48, 60, 80, 120, 240, High-Z | Default: High-Z |
| VREF Range Selection | Range 0, Range 1 | Default: Range 0 |
| VREF Setting (% of VDDQ) | LPDDR4, Range 0: 5.40 - 38.42 (step: 0.26) LPDDR4, Range 1: 11.90 - 48.222 (step: 0.286) LPDDR4x, Range 0: 11.60 - 49.70 (step: 0.3) LPDDR4x, Range 1: 21.20 - 59.30 (step: 0.3) | Default: LPDDR4, Range 0: 21.78 LPDDR4, Range 1: 29.918 LPDDR4x, Range 0: 30.5 LPDDR4x, Range 1: 40.1 |

Table 17: Advanced Options Tab (Memory Mode Register Settings)

| Option | Choices | Notes |
| --- | --- | --- |
| Burst Length | BL = 16 Sequential, BL = 16 or 32 Sequential, BL = 32 Sequential | Default: 16 Sequential |
| CA Bus ReceiverOn-Die-Termination for CS0/CS1 | Disable, RZQ/1, RZQ/2, RZQ/3, RZQ/4, RZQ/5, RZQ/6 | Default: Disable |
| DQ Bus ReceiverOn-Die-Termination for CS0/CS1 | Disable, RZQ/1, RZQ/2, RZQ/3, RZQ/4, RZQ/5, RZQ/6 | Default: Disable |
| Pull-Down Drive Strength (PDDS) for CS0/ CS1 | RFU, RZQ/1, RZQ/2, RZQ/3, RZQ/4, RZQ/5, RZQ/6 | Default: RZQ/6 |
| CA VREF Setting Range Selection | RANGE [0], RANGE [1] | Default: RANGE [1] |
| CA VREF Settings (% of VDD2) | RANGE [0]: 10 - 30 (step: 0.4) RANGE [1]: 22 - 42 (step: 0.4) | Default: RANGE [0]: 27.2 RANGE [1]: 27.2 |
| DQ VREF Setting Range Selection | RANGE [0], RANGE [1] | Default: RANGE [1] |
| DQ VREF Settings (% of VDDQ) | RANGE [0]: 10 - 30 (step: 0.4) RANGE [1]: 22 - 42 (step: 0.4) | Default: RANGE [0]: 27.2 RANGE [1]: 27.2 |
| Enable DBI Write | On oroff | Enable data bus inversion (DBI) for write operation. When enabled, the controller automatically inverts the write data byte if there are 5 or more '1's in the data bus, and indicates the data is inverted by driving the DDR_DM signal high. Default: On |
| Enable DBI Read | On oroff | Enable data bus inversion (DBI) for read operation. When enabled, the controller automatically inverts the read data byte if the DDR_DM signal is high. Default: On |
| CK ODT CS0/CS1 Enabled for Non-terminating Rank | Override Disabled, Override Enabled | Default: Override Disabled |
| CS ODT CS/CS1 Enabled for Non-terminating Rank | Override Disabled, Override Enabled | Default: Override Disabled |
| CA ODT CS/CS1 Termination Disable | Obeys ODT_CA Bond Pad, Disabled | Default: Override Obeys ODT_CA Bond Pad |

Table 18: Advanced Options Tab (Memory Timing Settings)

| Option | Choices | Notes |
| --- | --- | --- |
| tCCD, CAS-to-CAS Delay (cycles) | 8 - 31 | Default: 8 |
| tCCDMW, CAS-to-CAS Delay Masked Write (cycles) | 32 - 63 | Default: 32 |
| tFAW, Four-Bank Activate Window (ns) | 40 - 100 | Default: 40 |
| tPPD, Precharge to Precharge Delay (cycles) | 4 - 7 | Default: 4 |
| tRAS, Row Active Time (ns) | 42 - 100 | Default: 42 |
| tRCD, RAS-to-CAS Delay (ns) | 18 - 100 | Default: 18 |
| tRPab, Row Precharge Time (All Banks) (ns) | 21 - 100 | Default: 21 |
| tRPpb, Row Precharge Time (Single Bank) (ns) | 18 - 100 | Default: 18 |
| tRRD, Active Bank-A to Active Bank-B (ns) | 10 - 100 | Default: 10 |
| tRTP, Internal Read To Precharge Delay (ns) | 7.5 - 100 | Default: 7.5 |
| tSR, Minimum SelfRefresh Time (ns) | 15 - 100 | Default: 15 |
| tWR, Write Recovery Time (ns) | 18 - 60 | Default: 18 |
| tWTR, Write-To-Read Delay (ns) | 10 - 60 | Default: 10 |

Table 19: Config Controller Tab

| Option | Choices | Notes |
| --- | --- | --- |
| &lt;description> Pin Name | User defined | Configuration and control pins. You can use the default names orspecify yourown. |

Table 20: AXI 0 and AXI 1 Tabs

| Parameter | Choices | Notes |
| --- | --- | --- |
| Enable Target 0 Enable Target 1 | On oroff | Turn on to enable the AXI 0 interface. Turn on to enable the AXI 1 interface. |
| AXI Clock Input Pin Name | User defined | Specify the name of the AXI input clock pin. |
| Invert AXI Clock Input | On oroff | Turn on to invert the AXI clock. |
| AXI Reset Pin Name | User defined | Specify the name of the AXI reset clock pin or use the default. |
| Read Address Channel tab Write Address Channel tab Write Response Channel tab Read Data Channel tab Write Data Channel tab | User defined | These tabs defines the AXI signal names for the channels. Elitestek recommends that you use the default names. |

Table 21: Controller Status Tab

| Option | Choices | Notes |
| --- | --- | --- |
| Invert Controller Status Clock Pin | On oroff | Turn on ifyou want to invert the clock. Default: off |
| &lt;description> Pin Name | User defined | Controllerstatus pins. You can use the default names orspecify yourown. |

Table 22: Pin Swizzling Tab

| Option | Choices | Notes |
| --- | --- | --- |
| Enable Package Pin Swapping | On oroff | Turn on ifyou want to swap package pins. Default: off |
| DQ/DM Pin Swizzle Groupn | - | Drag and drop pins in the DRAM column to swap DQ/DM pins. DQ Width = 16 : n is 0 and 1 DQ Width = 32 : n is 0, 1, 2 and 3 |
| Address Pin Swizzle | - | Drag and drop pins in the DRAM column to swap address pins. |

## Supported DDR DRAM Devices

TJ-Series FPGAs support all JEDEC-compliant DDR DRAM devices (LPDDR4, LPDDR4x). The following table lists devices that Elitestek® have verified with TJ-Series FPGAs.

Table 23: DDR DRAM Devices Verified with TJ-Series FPGAs

<table><tbody><tr><td>Memory Type</td><td>Manufacturer</td><td>Part Number</td></tr><tr><td rowspan="3">LPDDR4/LPDDR4x</td><td>Micron</td><td>MT53E256M32D2</td></tr><tr><td>Samsung</td><td>K4F6E3S4HM-MGCJ</td></tr><tr><td>Winbond</td><td>W66DP2RQQAFJ</td></tr></tbody></table>

## Revision History

Table 24: Revision History

| Date | Version | Description |
| --- | --- | --- |
| May 2026 | 3.0 | Added decription for the Auto Low Power Mode option in Table 16: Advanced Options Tab (FPGA Settings) on page 20. (DOC-2969) |
| February 2026 | 2.9 | Added a note and updated diagram on the dual-rank support forsingle package only. (DOC-2905) |
| August 2025 | 2.8 | Added AWCOBUF_xdescription in table AXI4 Write Address Signals (Interface to FPGA Core Logic). (DOC-2659) |
| July 2025 | 2.7 | Added Winbond W66DP2RQQAFJ into table DDR DRAM Devices Verified with TJ-Series FPGAs. (DOC-2521) Added in A484S, N441X, N576XD2F4, and N576X packages in Table 2: DDR DRAM Widths Supported forTJ-Series FPGAs on page 5. |
| March 2025 | 2.6 | Added TJ85/TJ135 N484 package in Table 2: DDR DRAM Widths Supported forTJ-Series FPGAs on page 5. (DOC-2413) |
| March 2025 | 2.5 | Added N900 package in Table 2: DDR DRAM Widths Supported forTJ-Series FPGAs on page 5. (DOC-2370) |
| January 2025 | 2.4 | Added sub-topic Throughput of AXI Clock Speed. (DOC-2330) |
| October 2024 | 2.3 | Added statement on &lt;DDR_DQ/DDR_DQS &amp; DDR_DQS_N/DDR_DM> can be left floating on the board in table DDR DRAM Pads in DDR PHY topic. (DOC-1764) Removed unsupported packages M361 and F529, and M484 is only applicable to Ti180 in table DDR DRAM Widths Supported forTitanium FPGAs. Removed MIPI D-PHY from table LPDDR4/4x Interface Performance. (DOC-1796) Included and N484 &amp; N1156 in table DDR DRAM Widths Supported forTitanium FPGAs. (DOC-1823 &amp; DOC-1852) Added N484 package forTi375 in table DDR DRAM Widths Supported forTJ-Series FPGAs. Updated waveform in figure Write Operation Example. (DOC-1948) Added new topic Pins State ofthe LPDDR4 Controller. (DOC-1968) Updated sub-topic DDR DRAM Interface Input Clocks. Updated packages for Clocking topic. Updated LPDDR4/4x burst lengths to 16/32 from 8/16. (DOC-2186) |
| February 2024 | 2.2 | Updated Maximum Burst Length table in AXI section. (DOC-1689) Added in note regarding the number of clock cycles for the CFG_RESET to stay high in the figure Configuration ControllerSignal Waveform. (DOC-1720) |
| February 2024 | 2.1 | Added Maximum Burst Length table in AXI section. (DOC-1689) Updated Ti135, Ti240, and Ti375 in table TJ-Series FPGAs with LPDDR4/LPDDR4x DRAM Support. |
| October 2023 | 2.0 | Added note forFigure: Configuration ControllerSignal Waveform. (DOC-1374) Added Pins Swizzling settings in the Efinity Interface Designer Settings. (DOC-1470) |
| July 2023 | 1.9 | Corrected Maximum frequency (DDR controller) in TJ-Series DDR Features table. (DOC-1360) Corrected Read and Write operation example waveforms. (DOC-1366) |
| June 2023 | 1.8 | Updated DDR_DM signal description and added Enable DBI options. (DOC-1322) |
| May 2023 | 1.7 | Updated DDR PHY supported data rates. (DOC-1249) |
| April 2023 | 1.6 | Updated DDR DRAM interface input clock to include description for J361, J484, and G529 packages. (DOC-1209) Removed DDR DRAM interface AXI width option and removed AXI Data to DRAM Device DQ Mapping Example with 256 bit AXI data width. (DOC-1210) Added verified DDR DRAM devices table. (DOC-1220) |
| February 2023 | 1.5 | Updated LPDDR4 interface maximum data rate for M361, M484, and F529 packages. (DOC-1107) |
| January 2023 | 1.4 | Updated J361 to DQ widths of x16, removed M484 and F529 from DQ widths x16 or x32 in topic TJ-Series FPGAs with LPDDR4/LPDDR4x DRAM Support. (DOC-1104) |
| December 2022 | 1.3 | Updated DDR PHY support data rates in Features. (DOC-1025) Updated package information in DDR DRAM Widths Supported for TJ-Series FPGAs table of topic TJ-Series FPGAs with LPDDR4/LPDDR4x DRAM Support. Updated DDR DRAM Interface Performance table in Supported Frequencies and Configurations topic. Updated Base Tab table in DDR Interface DesignerSettings. Updated title of the figures that show the connection between FPGA and DRAM device. Added in new figure Dual-Rank, x16 Interface. Added in new topic DDR Comparison. Updated Resets table. (DOC-1051) |
| November 2022 | 1.2 | Updated Dual-Channel, Dual-Rank, x32 interface in the topic Supported Frequencies and Configurations. (DOC-979) |
| October 2022 | 1.1 | Updated Dual-Channel, Single-Rank, x32 interface and Dual-Channel, Dual-Rank, x32 interface in the topic Supported Frequencies and Configurations. (DOC-964) Topic title changed from Supported DDR DRAM Modules to Supported DDR DRAM Devices. Changed the word module to device. Updated the word module to device in document. |
| October 2022 | 1.0 | Initial release. |