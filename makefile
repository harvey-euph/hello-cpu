# 1. 指定編譯器
CC = gcc

# 2. 目錄定義
SRC_DIR = src
INC_DIR = include
BIN_DIR = bin

DEMO_SRC = $(SRC_DIR)/demo
PERF_SRC = $(SRC_DIR)/perf
DEMO_BIN = $(BIN_DIR)/demo
PERF_BIN = $(BIN_DIR)/perf

# 3. 編譯旗標
# -nostdlib: 不連結 C 標準庫，由 _start 作為進入點
# -march=native: 解鎖本機支援的所有硬體擴展指令集
# -g: 加入除錯資訊
# -no-pie: 產生非位置無關執行檔
# -Wa,-I...: 傳遞 include 搜尋路徑給組譯器，使 .include "system.inc" 能正確定位
CFLAGS = -nostdlib -march=native -g -no-pie -Wa,-I$(CURDIR)/$(INC_DIR) -Wa,-I$(INC_DIR)

# 4. 自動搜尋來源檔案
DEMO_SRCS = $(wildcard $(DEMO_SRC)/*.s)
PERF_SRCS = $(wildcard $(PERF_SRC)/*.s)

# 5. 生成對應的目標二進位路徑 (bin/demo/% 與 bin/perf/%)
DEMO_TARGETS = $(patsubst $(DEMO_SRC)/%.s,$(DEMO_BIN)/%,$(DEMO_SRCS))
PERF_TARGETS = $(patsubst $(PERF_SRC)/%.s,$(PERF_BIN)/%,$(PERF_SRCS))

TARGETS = $(DEMO_TARGETS) $(PERF_TARGETS)

# 預設目標：編譯所有 demo 與 perf 程式
all: demo perf

# 分類編譯目標
demo: $(DEMO_TARGETS)
perf: $(PERF_TARGETS)

# 6. 編譯規則：如何從 src/demo/%.s 生成 bin/demo/%
$(DEMO_BIN)/%: $(DEMO_SRC)/%.s | $(DEMO_BIN)
	$(CC) $(CFLAGS) $< -o $@

# 7. 編譯規則：如何從 src/perf/%.s 生成 bin/perf/%
$(PERF_BIN)/%: $(PERF_SRC)/%.s | $(PERF_BIN)
	$(CC) $(CFLAGS) $< -o $@

# 建立輸出目錄
$(DEMO_BIN):
	mkdir -p $(DEMO_BIN)

$(PERF_BIN):
	mkdir -p $(PERF_BIN)

# 一鍵執行所有程式
run: all
	@echo "=== [1/2] 執行 Demo 範例 ==="
	@for prog in $(DEMO_TARGETS); do \
		printf "%-28s -> " "$$prog"; \
		./$$prog; \
	done
	@echo ""
	@echo "=== [2/2] 執行 Performance 基準測試 ==="
	@for prog in $(PERF_TARGETS); do \
		printf "%-28s -> " "$$prog"; \
		./$$prog; \
	done

# 獨立執行 Demo
run-demo: demo
	@for prog in $(DEMO_TARGETS); do \
		printf "%-28s -> " "$$prog"; \
		./$$prog; \
	done

# 獨立執行 Perf 測試
run-perf: perf
	@for prog in $(PERF_TARGETS); do \
		printf "%-28s -> " "$$prog"; \
		./$$prog; \
	done

# 清除編譯結果
clean:
	rm -rf $(BIN_DIR)

.PHONY: all demo perf run run-demo run-perf clean
