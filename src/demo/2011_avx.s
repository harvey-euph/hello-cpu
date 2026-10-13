.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel AVX (Advanced Vector Extensions)
#
# 歷史背景:
#   Intel 於 Sandy Bridge 微架構 (2011) 推出 AVX 指令集。
#   這是 x86 SIMD 架構自 SSE 以來最重大的一次架構升級。
#
# 核心技術革新:
#   1. 暫存器寬度擴展至 256 位元:
#      - 引入 16 個 256-bit 暫存器 (ymm0 ~ ymm15)。
#      - ymm 的低 128 位元直接對應並重疊傳統的 xmm 暫存器。
#      - 單一 ymm 暫存器可容納:
#        * 8 個 32-bit 單精度浮點數 (Single-Precision Float, float)
#        * 4 個 64-bit 雙精度浮點數 (Double-Precision Float, double)
#
#   2. VEX 前綴編碼與非破壞性三操作數語法 (Non-Destructive 3-Operand Syntax):
#      - 傳統 SSE:  addps xmm0, xmm1       (破壞目的暫存器 xmm0 = xmm0 + xmm1)
#      - AVX (VEX): vaddps ymm2, ymm0, ymm1 (ymm2 = ymm0 + ymm1，保留 ymm0 與 ymm1 原始值)
#      - 徹底消除了繁瑣且佔用指令週期的 movaps 複製操作。
#
#   3. 記憶體對齊規範:
#      - vmovaps (Aligned Packed Single): 記憶體位址必須為 32-byte 對齊 (.align 32)。
#      - 若位址未對齊 32 bytes 則必須使用 vmovups (Unaligned)，否則將觸發一般保護錯誤 (#GP)。
#
#   4. AVX-SSE 狀態切換懲罰與 vzeroupper:
#      - 當 CPU 執行過 256-bit AVX 指令後，YMM 的高 128 位元進入髒狀態 (Dirty State)。
#      - 若隨後呼叫傳統 128-bit SSE 指令或 C 函式庫/syscall，CPU 內部需進行昂貴的微碼狀態保存與恢復。
#      - 因此在離開 AVX 函式或呼叫非 AVX 代碼前，務必執行 vzeroupper 將 YMM 高 128 位元清零。
# =============================================================

.data
header_msg: .ascii "=== Intel AVX (256-bit 浮點向量運算展示) ===\n"
.equ header_len, . - header_msg

elem0_msg:  .ascii "向量加法元素 0: 10.0 + 22.0 = "
.equ elem0_len, . - elem0_msg

elem7_msg:  .ascii "向量加法元素 7:  7.0 +  1.0 = "
.equ elem7_len, . - elem7_msg

.align 32
# 定義兩個 256-bit (8 個 float) 浮點數向量
vec_a: .float 10.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0
vec_b: .float 22.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

.text
_start:
    # 輸出標題
    sys_print_str header_msg, header_len

    # 1. 將 32-byte 對齊的記憶體資料載入 256-bit ymm 暫存器
    vmovaps ymm0, [vec_a]
    vmovaps ymm1, [vec_b]

    # 2. 執行 256-bit 向量單精度浮點加法 (8 個 float 同步相加)
    #    ymm2 = ymm0 + ymm1 (非破壞性三操作數)
    vaddps  ymm2, ymm0, ymm1

    # 3. 提取第 0 個元素 (10.0 + 22.0 = 32.0f) 並轉為整數
    #    vcvttss2si: Convert with Truncation Scalar Single to 32-bit Integer
    vcvttss2si r12d, xmm2

    # 印出第 0 元素結果
    sys_print_str elem0_msg, elem0_len
    mov edi, r12d
    call print_dec          # 印出 32

    # 4. 提取第 7 個元素 (7.0 + 1.0 = 8.0f)
    #    使用 vextractf128 提取 ymm2 的高 128 位元至 xmm3
    vextractf128 xmm3, ymm2, 1
    #    在 xmm3 中，第 7 元素位於最高 32-bit (index 3)，使用 vshufps 移至最低位
    vshufps xmm3, xmm3, xmm3, 3
    vcvttss2si r13d, xmm3

    # 印出第 7 元素結果
    sys_print_str elem7_msg, elem7_len
    mov edi, r13d
    call print_dec          # 印出 8

    # 5. 清理 YMM 高 128 位元狀態，避免 AVX/SSE 切換懲罰
    vzeroupper

    sys_exit 0
