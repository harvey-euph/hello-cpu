.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel POPCNT (Population Count / Hamming Weight)
#
# 歷史背景:
#   Intel 於 Nehalem 微架構 (2008, 納入 SSE4.2 指令集) 與 AMD Barcelona (2007, ABM) 引入。
#
# 核心機制與資訊理論 (Hamming Weight):
#   1. 計算位元 1 的個數 (Population Count):
#      - 輸入一個 16/32/64 位元暫存器或記憶體數值，硬體直接統計二進位中 '1' 的總位元數。
#
#   2. 軟體演算法 vs 硬體單一週期:
#      - 早期沒有 POPCNT 時，軟體必須採用:
#        * 逐位檢查迴圈: 效能極差，受分支預測影響。
#        * Brian Kernighan 演算法: 迴圈執行 x = x & (x - 1)，次數取決於 1 的個數。
#        * 平行位元樹遮罩法 (Parallel Bit-Hack): 需消耗 ~12 條算術與移位指令。
#      - POPCNT 指令直接在 CPU 內部算術邏輯閘於「1 個時脈週期」內瞬間得出結果！
#
#   3. 核心應用領域:
#      - 漢明距離計算 (Hamming Distance):
#        * 兩組資料 A 與 B 的相異位元數: d(A, B) = POPCNT(A ^ B)
#        * 廣泛應用於錯誤更正碼 (ECC)、密碼學雜湊比對、感知影像雜湊 (pHash)。
#      - 棋類 AI 與西洋棋引擎 (Bitboards):
#        * 棋盤狀態以 64-bit 點陣棋盤表示，極速評估棋子存活數與合法走步。
#      - 資料庫與搜尋引擎:
#        * 稀疏位圖索引 (Bitmap Indexing)、Bloom Filter、Roaring Bitmaps。
#      - 生物資訊學:
#        * DNA 基因序列比對 (K-mer Counting)。
# =============================================================

.data
header_msg: .ascii "=== Intel POPCNT (硬體漢明權重與位元計數展示) ===\n"
.equ header_len, . - header_msg

test1_msg:  .ascii "[測試 1] 32-bit 數值 0x000e123f 中 '1' 的個數: "
.equ test1_len, . - test1_msg

test2_msg:  .ascii "[測試 2] 漢明距離: POPCNT(0b11110000 ^ 0b10100000): "
.equ test2_len, . - test2_msg

# 0x000e123f:
# 0b00000000_00001110_00010010_00111111
# 個數: 0 + 3 + 2 + 6 = 11 個 1
test_val: .long 0x000e123f

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 測試 1: 32-bit 整數 POPCNT
    # ---------------------------------------------------------
    mov eax, [test_val]
    popcnt ebx, eax         # ebx = 11
    mov r12d, ebx

    sys_print_str test1_msg, test1_len
    mov edi, r12d
    call print_dec          # 印出 11

    # ---------------------------------------------------------
    # 測試 2: 計算兩數之間的漢明距離 (Hamming Distance)
    # 數值 A = 0xf0 (1111 0000)
    # 數值 B = 0xa0 (1010 0000)
    # A ^ B  = 0x50 (0101 0000) -> 漢明距離應為 2
    # ---------------------------------------------------------
    mov rax, 0xf0
    mov rdx, 0xa0
    xor rax, rdx            # 異或找出所有相異位元
    popcnt rcx, rax         # 計算相異位元總數
    mov r13d, ecx

    sys_print_str test2_msg, test2_len
    mov edi, r13d
    call print_dec          # 印出 2

    sys_exit 0
