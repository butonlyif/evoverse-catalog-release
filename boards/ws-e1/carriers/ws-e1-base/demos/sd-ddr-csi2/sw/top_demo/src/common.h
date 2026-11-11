/*
 * commom.h
 *
 *  Created on: Aug 18, 2020
 *      Author: shchung
 */

#ifndef SRC_COMMON_H_
#define SRC_COMMON_H_

#include "bsp.h"

void bsp_printf_c(int c);
void bsp_printf_s(char *p);
void bsp_printf_d(int val);
void bsp_printf(const char *format, ...);
int bsp_puts(char *s);
int putchar(int c);
void print_hex(uint32_t val, uint32_t digits);

/************************** Function File ***************************/
void Reg_Out32(u32 addr,u32 data);
u32 Reg_In32(u32 addr);


#endif /* SRC_COMMON_H_ */
