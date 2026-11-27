PROJ_NAME=tseDemo

# BSP 默认值：CLI 与 Eclipse 构建均可直接 make，无需显式传参
BSP ?= efinix/EfxSapphireSoc

STANDALONE = ..


SRCS = 	$(wildcard src/*.c) \
		$(wildcard src/*.cpp) \
		$(wildcard src/*.S) \
        ${STANDALONE}/common/start.S


include ${STANDALONE}/common/bsp.mk
include ${STANDALONE}/common/riscv64-unknown-elf.mk
# app 头文件路径（tseDemo.h 等），必须在 standalone.mk 之前注入
CFLAGS_ARGS += -I${BSP_PATH}/app
include ${STANDALONE}/common/standalone.mk

