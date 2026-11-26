/*
 * userDef.h - compatibility stub for Efinity TSE driver headers.
 * Provides DEBUG_PRINTF_EN used by efx_tse_mac.h / efx_tse_phy.h.
 * Must be included AFTER the application header that defines PRINTF_EN.
 */
#ifndef USER_DEF_H_
#define USER_DEF_H_

#include "bsp.h"

#ifndef DEBUG_PRINTF_EN
#ifdef PRINTF_EN
#define DEBUG_PRINTF_EN PRINTF_EN
#else
#define DEBUG_PRINTF_EN 0
#endif
#endif

#endif /* USER_DEF_H_ */
