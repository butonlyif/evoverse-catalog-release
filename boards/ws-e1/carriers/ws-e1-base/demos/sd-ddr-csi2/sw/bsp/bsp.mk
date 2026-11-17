BSP_PATH ?= ${STANDALONE}
CFLAGS += -I${BSP_PATH}/include


include ${BSP_PATH}/include/soc.mk

LDSCRIPT ?= ${BSP_PATH}/linker/default.ld
