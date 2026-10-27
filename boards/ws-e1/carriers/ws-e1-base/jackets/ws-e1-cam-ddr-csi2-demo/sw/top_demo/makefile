PROJ_NAME=top_demo
STANDALONE = ../bsp


SRCS = 	$(wildcard src/*.c) \
		$(wildcard src/*.cpp) \
		$(wildcard src/*.S) \
		${STANDALONE}/start.S \
		${STANDALONE}/trap.S

CFLAGS += -Isrc

include ${STANDALONE}/bsp.mk
include ${STANDALONE}/riscv64-unknown-elf.mk
include ${STANDALONE}/standalone.mk

LDSCRIPT =  ${BSP_PATH}/linker/default.ld
