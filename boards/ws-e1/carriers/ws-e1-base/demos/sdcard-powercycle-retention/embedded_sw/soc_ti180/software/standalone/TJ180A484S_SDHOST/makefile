PROJ_NAME=TJ180A484S_SDHOST
STANDALONE = ..


SRCS = 	$(wildcard src/*.c) \
		$(wildcard src/*.cpp) \
		$(wildcard src/*.S) \
		${STANDALONE}/common/start.S \
		${STANDALONE}/common/trap.S

CFLAGS += -Isrc

include ${STANDALONE}/common/bsp.mk
include ${STANDALONE}/common/riscv64-unknown-elf.mk
include ${STANDALONE}/common/standalone.mk

LDSCRIPT =  ${BSP_PATH}/linker/default.ld

