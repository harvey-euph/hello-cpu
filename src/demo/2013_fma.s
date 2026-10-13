.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel FMA3 (Fused Multiply-Add, 融合乘加指令集)
#
# 歷史背景:
#   Intel 於 Haswell 微架構 (2013) 引入 FMA3 指令集。
#   為高效能運算 (HPC)、矩陣乘法、DSP 訊號處理與深度學習推論的核心基石。
#
# 核心機制與數學優勢:
#   1. 單一步驟融合計算 (d = (a * b) + c):
#      - 傳統方式: 必須先執行 mulps (乘法)，結果進行第一次捨入 (Rounding)，
#        接著再執行 addps (加法)，進行第二次捨入。
#      - FMA 方式: 硬體在內部保留無窮精度的中間乘積，全數累積後「僅執行最後一次捨入」！
#      - 數學優勢: 徹底消除中間捨入誤差，防止災難性消去 (Catastrophic Cancellation)，
#        完全符合 IEEE 754-2008 高精度浮點規範。
#
#   2. 算力吞吐量翻倍 (Doubled Theoretical FLOPs):
#      - 單一指令週期同時完成 1 次乘法與 1 次加法 (視為 2 次浮點操作 / 2 FLOPs)。
#      - 現代 x86 CPU 每個核心通常配置 2 個 FMA 運算單元 (Port 0 與 Port 1)，
#        單週期即可輸出 2 x 8 (AVX 256-bit) x 2 = 32 個單精度浮點運算！
#
#   3. FMA3 的三操作數命名規範 (132, 213, 231 的含義):
#      - 數字代表操作數在數學公式中的角色: (第 1 乘數 * 第 2 乘數) + 累加項
#      - vfmadd132: dest = (dest * src3) + src2
#      - vfmadd213: dest = (src2 * dest) + src3
#      - vfmadd231: dest = (src2 * src3) + dest (在矩陣相乘 GEMM 中最常用)
# =============================================================

.data
header_msg: .ascii "=== Intel FMA3 (融合乘加高精度浮點展示) ===\n"
.equ header_len, . - header_msg

scalar_msg: .ascii "[純量 FMA] (3.0 * 4.0) + 5.0 = "
.equ scalar_len, . - scalar_msg

vector_msg: .ascii "[向量 FMA] (2.0 * 3.0) + 10.0 = "
.equ vector_len, . - vector_msg

# 純量測試常數
v_a: .float 3.0
v_b: .float 4.0
v_c: .float 5.0

# 256-bit 向量測試資料 (.align 32)
.align 32
vec_mul1: .float 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0
vec_mul2: .float 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0, 3.0
vec_acc:  .float 10.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 1. 測試純量 FMA (vfmadd213ss)
    #    計算: (xmm0 * xmm1) + xmm2 = (3.0 * 4.0) + 5.0 = 17.0
    # ---------------------------------------------------------
    vmovss xmm0, [v_a]      # 3.0
    vmovss xmm1, [v_b]      # 4.0
    vmovss xmm2, [v_c]      # 5.0

    # vfmadd213ss xmm0, xmm1, xmm2:
    # xmm0 = (xmm1 * xmm0) + xmm2 = (4.0 * 3.0) + 5.0 = 17.0f
    vfmadd213ss xmm0, xmm1, xmm2

    vcvttss2si r12d, xmm0   # 轉為整數 17

    sys_print_str scalar_msg, scalar_len
    mov edi, r12d
    call print_dec          # 印出 17

    # ---------------------------------------------------------
    # 2. 測試 256-bit 向量 FMA (vfmadd231ps)
    #    計算: ymm2 = (ymm0 * ymm1) + ymm2 = (2.0 * 3.0) + 10.0 = 16.0
    # ---------------------------------------------------------
    vmovaps ymm0, [vec_mul1]
    vmovaps ymm1, [vec_mul2]
    vmovaps ymm2, [vec_acc]

    # vfmadd231ps ymm2, ymm0, ymm1:
    # ymm2 = (ymm0 * ymm1) + ymm2
    vfmadd231ps ymm2, ymm0, ymm1

    # 提取第 0 元素 (16.0f)
    vcvttss2si r13d, xmm2   # 轉為整數 16

    sys_print_str vector_msg, vector_len
    mov edi, r13d
    call print_dec          # 印出 16

    vzeroupper
    sys_exit 0
