////////////////////////////////////////////////////////////////////////////
//  imx415_init.h -- IMX415 camera I2C configuration (camera step 2)
//
//  Target: 1920x1080 @ 60fps (1944x1096 rows incl. blanking), RAW10,
//          4 MIPI lanes @ 1782 Mbps, INCK = 37.125 MHz
//  I2C:    7-bit addr 0x1A (write 0x34 / read 0x35), 50 kHz via SoC I2C0
//          (cam0) / I2C1 (cam1) -- selected by imx415_init(id)
//
//  Register map source: cam2_1080p.md (bench-verified config, R9.53/R9.54,
//  real Sony IMX415 map). Bitstream must be built with data_rate=1782.
////////////////////////////////////////////////////////////////////////////
#pragma once
#include "type.h"

int imx415_init(int id);        /* id: 0 = I2C0+gpio bit0 (cam_0),
				 *     1 = I2C1+gpio bit1 (cam_1)
				 * 0 = ok, negative = error (see .c) */
int imx415_read_reg(u16 reg, u8 *val);
int imx415_write_reg(u16 reg, u8 val);
int imx415_stream_on(void);
int imx415_stream_off(void);
