.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel CLFLUSHOPT (Cache Line Flush Optimized)
#
# 歷史背景:
#   Intel 於 Skylake 微架構 (2015) 推出 CLFLUSHOPT 指令。
#
# 核心機制與快取架構:
#   1. 快取行 (Cache Line):
#      - 現代 x86 CPU 快取 (L1, L2, L3）以 64 位元組 (64 bytes) 為基本搬移單位。
#      - 當寫入資料時，資料通常先駐留在 CPU 快取中 (Write-Back 策略)，尚未真正寫入主記憶體 (RAM/NVDIMM)。
#
#   2. CLFLUSH vs CLFLUSHOPT 關鍵差異:
#      - 傳統 CLFLUSH (Pentium 4 引入):
#        * 強序 (Strictly Ordered): 與前後所有記憶體讀寫完全串行化 (Serialized)。
#        * 每次執行 CLFLUSH 都會阻塞管線，直到快取行被驅逐回記憶體。
#        * 若要刷寫一大段記憶體區塊 (例如 4KB 分頁)，會造成嚴重的 CPU 管線停頓。
#      - 優化版 CLFLUSHOPT (Skylake 引入):
#        * 弱序 (Weakly Ordered): 僅對同一快取行的 store 或明確的記憶體屏障 (SFENCE/MFENCE) 保證順序。
#        * 允許 CPU 同時並行處理多條不同快取行的刷寫請求 (Concurrent Flushes)。
#        * 刷寫大區塊陣列時，吞吐量可提升數倍以上！
#
#   3. 應用場景:
#      - 非揮發性記憶體 (NVDIMM / Persistent Memory / PMEM) 的持久化寫入保證 (Crash Consistency)。
#      - 裝置驅動程式 (DMA 緩衝區同步)。
#      - 資安防禦與微架構旁道攻擊研究 (如 Flush+Reload 快取計時分析)。
# =============================================================

.data
header_msg: .ascii "=== Intel CLFLUSHOPT (快取行優化刷寫指令展示) ===\n"
.equ header_len, . - header_msg

status1_msg: .ascii "[1] 資料已寫入記憶體/快取，數值: "
.equ status1_len, . - status1_msg

status2_msg: .ascii "[2] 執行 CLFLUSHOPT + MFENCE 完成快取行刷回。\n"
.equ status2_len, . - status2_msg

status3_msg: .ascii "[3] 重新讀取驗證資料一致，數值: "
.equ status3_len, . - status3_msg

# 64-byte 對齊的測試緩衝區 (剛好佔據一個標準 Cache Line)
.align 64
cache_buffer:
    .quad 0x12345678abcdef00

.text
_start:
    sys_print_str header_msg, header_len

    # 1. 寫入並讀取測試資料
    mov rax, [cache_buffer]
    mov r12, rax

    sys_print_str status1_msg, status1_len
    mov rdi, r12
    call print_hex

    # 2. 針對該位址所屬的 64-byte 快取行發起優化刷寫
    #    clflushopt 指令會將包含該位址的整條 Cache Line 寫回主記憶體並標記為無效
    clflushopt [cache_buffer]

    # 3. 由於 CLFLUSHOPT 為弱序指令，需透過記憶體屏障 (MFENCE/SFENCE)
    #    確保刷寫操作在屏障之後的指令執行前全數完成持久化
    mfence

    sys_print_str status2_msg, status2_len

    # 4. 再次讀取記憶體（此時 CPU 必須重新從主記憶體/L3 載入快取行）
    mov rbx, [cache_buffer]
    mov r13, rbx

    sys_print_str status3_msg, status3_len
    mov rdi, r13
    call print_hex

    sys_exit 0
