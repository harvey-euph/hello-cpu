.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel F16C (Half-Precision Floating-Point Conversion)
#
# 歷史背景:
#   Intel 於 Ivy Bridge 微架構 (2012) 引入 F16C 指令集擴展。
#
# IEEE 754-2008 半精度浮點數 (FP16 / binary16) 結構:
#   - 總長度: 16 位元 (2 Bytes)
#   - 位元分佈:
#     * Bit 15    : 符號位 (Sign, 1 bit)
#     * Bits 14-10: 指數位 (Exponent, 5 bits, 指數偏移量 Bias = 15)
#     * Bits 9-0  : 尾數位 (Fraction / Mantissa, 10 bits, 隱含前導 1)
#   - 相較於 32-bit 單精度 (FP32) 的優勢:
#     * 記憶體頻寬與儲存空間直接節省 50%！
#     * 動態範圍達 ~65504，非常適合深度學習與神經網路權重運算。
#
# F16C 核心指令:
#   1. VCVTPH2PS (Convert Packed Half-Precision to Packed Single-Precision):
#      - 將 16-bit 浮點數轉換擴展為 32-bit 單精度浮點數 (硬體在 XMM/YMM 暫存器中直接解碼)。
#   2. VCVTPS2PH (Convert Packed Single-Precision to Packed Half-Precision):
#      - 將 32-bit 單精度浮點數壓縮截斷為 16-bit 半精度浮點數。
#      - 支援第 3 操作數指定 IEEE 捨入模式 (Rounding Mode):
#        * 0: Round to Nearest Even (就近捨入)
#        * 1: Round Down / Floor (朝負無限大捨入)
#        * 2: Round Up / Ceil (朝正無限大捨入)
#        * 3: Round Toward Zero / Truncate (朝零截斷)
#
# 應用領域:
#   - 現代人工智慧與大語言模型 (LLM Inference / Weights / KV-Cache)。
#   - 3D 繪圖著色器 (HDR 紋理、色彩緩衝區)。
# =============================================================

.data
header_msg: .ascii "=== Intel F16C (半精度浮點數轉換指令展示) ===\n"
.equ header_len, . - header_msg

test1_msg:  .ascii "[測試 1: FP16 -> FP32] 半精度 0x4200 (3.0f) 轉換為整數: "
.equ test1_len, . - test1_msg

test2_msg:  .ascii "[測試 2: FP32 -> FP16] 單精度 5.0f 壓縮為 16-bit 半精度: "
.equ test2_len, . - test2_msg

# 16-bit 半精度浮點數 3.0f:
# S=0, E=16 (16-15 = 2^1), M=0.5 -> 1.5 * 2^1 = 3.0
# 二進位: 0_10000_1000000000 = 0x4200
half_val: .word 0x4200

# 32-bit 單精度浮點數 5.0f
single_val: .float 5.0

.bss
half_out: .space 8

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 測試 1: VCVTPH2PS (FP16 -> FP32)
    # ---------------------------------------------------------
    # 載入 16-bit 半精度數值，硬體擴展轉換至 xmm0 (32-bit float = 3.0f)
    vcvtph2ps xmm0, [half_val]

    # 將 32-bit 浮點數轉換為 32-bit 整數 (截斷)
    vcvttss2si r12d, xmm0   # r12d = 3

    sys_print_str test1_msg, test1_len
    mov edi, r12d
    call print_dec          # 印出 3

    # ---------------------------------------------------------
    # 測試 2: VCVTPS2PH (FP32 -> FP16)
    # ---------------------------------------------------------
    # 載入 32-bit 單精度 5.0f
    vmovss xmm1, [single_val]

    # 壓縮轉換為 16-bit 半精度，捨入模式使用 0 (Nearest Even)
    # 輸出至記憶體 half_out (5.0f 的 FP16 為 0x4500)
    vcvtps2ph [half_out], xmm1, 0

    movzx r13d, word ptr [half_out]

    sys_print_str test2_msg, test2_len
    mov edi, r13d
    call print_hex          # 印出 0x45 0x00

    vzeroupper
    sys_exit 0
