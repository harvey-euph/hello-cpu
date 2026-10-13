.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel MMX (MultiMedia eXtensions, 始祖級 SIMD 指令集)
#
# 歷史背景:
#   Intel 於 Pentium with MMX Technology (1997, P55C 架構) 首次引入。
#   這是 x86 處理器歷史上第一個 SIMD (單指令多資料流) 向量擴展指令集。
#
# 核心機制:
#   1. 64 位元向量暫存器 (mm0 ~ mm7):
#      - 支援 64-bit 緊縮整數 (Packed Integer) 平行運算:
#        * 8 個 8-bit  整數 (paddb, psubb)
#        * 4 個 16-bit 整數 (paddw, psubw, pmullw)
#        * 2 個 32-bit 整數 (paddd, psubd)
#
#   2. 暫存器重疊陷阱 (x87 FPU Register Aliasing):
#      - 當年為了在不修改作業系統核心 (不需要新增 context switch 暫存器儲存指令)
#        的前提下支援 MMX，Intel 做了一個極具爭議的硬體設計:
#      - 8 個 MMX 暫存器 (mm0 ~ mm7) 直接共用物理上的 x87 浮點運算器堆疊 (st0 ~ st7)！
#      - MMX 佔用 80-bit 浮點暫存器中的低 64 位元尾數部分。
#
#   3. EMMS (Empty MMX State) 指令的必要性:
#      - 當執行任何 MMX 指令時，CPU 硬體會自動將 x87 浮點狀態字 (FPU Tag Word)
#        標記為「全部有效 (Valid)」。
#      - 若未在 MMX 程式段結束時呼叫 EMMS，隨後執行的任何 x87 浮點運算都會誤認為
#        浮點堆疊已滿，從而引發浮點堆疊溢位例外 (FPU Stack Overflow) 或產生 NaN 錯誤！
#      - 因此，在離開任何 MMX 函數或呼叫外部程式碼前，必須嚴格執行 EMMS 指令清空狀態！
# =============================================================

.data
header_msg: .ascii "=== Intel MMX (64-bit 始祖 SIMD 指令集展示) ===\n"
.equ header_len, . - header_msg

elem0_msg:  .ascii "MMX 32-bit 加法元素 0: 10 +  5 = "
.equ elem0_len, . - elem0_msg

elem1_msg:  .ascii "MMX 32-bit 加法元素 1: 20 + 15 = "
.equ elem1_len, . - elem1_msg

# 64-bit 測試向量: 包含 2 個 32-bit 整數
val1: .long 10, 20
val2: .long 5,  15

.text
_start:
    sys_print_str header_msg, header_len

    # 1. 將 64-bit 資料載入 mm0 與 mm1 暫存器
    movq mm0, [val1]
    movq mm1, [val2]

    # 2. 執行 64-bit 緊縮 32-bit 整數加法 (2 組 int32 同時相加)
    #    mm0 = mm0 + mm1 (破壞性雙操作數語法)
    paddd mm0, mm1

    # 3. 提取第 0 元素 (10 + 5 = 15)
    #    movd: 提取最低 32-bit 至通用暫存器
    movd r12d, mm0

    sys_print_str elem0_msg, elem0_len
    mov edi, r12d
    call print_dec          # 印出 15

    # 4. 提取第 1 元素 (20 + 15 = 35)
    #    psrlq: 將 mm0 邏輯右移 32 位元，將高 32-bit 移至低 32-bit
    psrlq mm0, 32
    movd r13d, mm0

    sys_print_str elem1_msg, elem1_len
    mov edi, r13d
    call print_dec          # 印出 35

    # 5. 關鍵清理: 執行 EMMS 重設 FPU 狀態字，避免後續浮點程式碼崩潰
    emms

    sys_exit 0
