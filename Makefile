# Makefile para o Rock CLI
CC ?= gcc
# Permite sobrescrever os caminhos via linha de comando para o bootstrap
LUA_CFLAGS = $(shell pkg-config --cflags lua5.4 || pkg-config --cflags lua 2>/dev/null)
LUA_LDFLAGS = $(shell pkg-config --libs lua5.4 || pkg-config --libs lua 2>/dev/null)

# Fallback para caminhos manuais se o pkg-config falhar (útil no bootstrap)
CFLAGS = -Wall -Wextra -O2 $(LUA_CFLAGS) $(INCDIR)
LDFLAGS = $(LUA_LDFLAGS) $(LIBDIR) -lm -ldl

SRC_DIR = src
BIN_DIR = bin
TARGET = $(BIN_DIR)/rock

all: $(TARGET)

$(TARGET): $(SRC_DIR)/main.c
	mkdir -p $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

clean:
	rm -rf $(BIN_DIR)

.PHONY: all clean
