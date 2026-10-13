.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel AVX2 (Advanced Vector Extensions 2)
#
# 歷史背景:
#   Intel 於 Haswell 微架構 (2013) 推出 AVX2 指令集。
#
# 核心架構演進:
#   1. 整數向量運算全面擴展至 256 位元:
#      - AVX (2011) 雖然引入了 256-bit YMM 暫存器，但絕大多數整數 SIMD 仍被限制在 128-bit XMM。
#      - AVX2 將整數 SIMD 全面擴展至 256 位元，支援:
#        * 32 個 8-bit 整數 (Byte) 平行運算 (如 vpaddb, vpsubb)
#        * 16 個 16-bit 整數 (Word) 平行運算 (如 vpaddw, vpmullw)
#        * 8 個 32-bit 整數 (Doubleword) 平行運算 (如 vpaddd, vpmulld)
#        * 4 個 64-bit 整數 (Quadword) 平行運算 (如 vpaddq)
#
#   2. 跨 Lane 排列與廣播 (Cross-Lane Permute & Broadcast):
#      - 引入跨 128-bit lane 的任意元素置換指令 (如 vpermd, vpermps)。
#      - 引入向量常數廣播 (如 vpbroadcastb/w/d/q)，快速將純量複製填滿整個向量。
#
#   3. 向量聚集讀取 (Vector Gather):
#      - 引入 vpgatherdd / vpgatherqd，支援非連續記憶體位址 (Non-contiguous memory)
#        的平行載入，大幅加速稀疏矩陣與資料庫查表運算。
#
#   4. 向量位元邏輯運算:
#      - 提供 256-bit 的 vpand, vpor, vpxor, vpandn 等超寬位元邏輯操作。
# =============================================================

.data
header_msg: .ascii "=== Intel AVX2 (256-bit 整數向量運算展示) ===\n"
.equ header_len, . - header_msg

elem0_msg:  .ascii "整數加法元素 0: 20 + 22 = "
.equ elem0_len, . - elem0_msg

elem7_msg:  .ascii "整數加法元素 7:  8 +  1 = "
.equ elem7_len, . - elem7_msg

xor_msg:    .ascii "整數異或元素 0: 0xaa ^ 0x55 = "
.equ xor_len, . - xor_msg

.align 32
# 定義兩個 256-bit (8 個 32-bit 整數) 向量
vec_a: .long 20, 2, 3, 4, 5, 6, 7, 8
vec_b: .long 22, 1, 1, 1, 1, 1, 1, 1

vec_x: .long 0xaa, 0, 0, 0, 0, 0, 0, 0
vec_y: .long 0x55, 0, 0, 0, 0, 0, 0, 0

.text
_start:
    # 輸出標題
    sys_print_str header_msg, header_len

    # 1. 載入對齊的 256-bit 整數資料 (vmovdqa)
    vmovdqa ymm0, [vec_a]
    vmovdqa ymm1, [vec_b]

    # 2. 執行 256-bit 向量 32-bit 整數加法 (8 組 int32 同時相加)
    #    ymm2 = ymm0 + ymm1
    vpaddd  ymm2, ymm0, ymm1

    # 3. 提取第 0 個元素 (20 + 22 = 42)
    #    vmovd: 將向量最低 32-bit 提取至一般通用暫存器
    vmovd   r12d, xmm2

    # 印出第 0 元素結果
    sys_print_str elem0_msg, elem0_len
    mov edi, r12d
    call print_dec          # 印出 42

    # 4. 提取第 7 個元素 (8 + 1 = 9)
    #    使用 vextracti128 提取 ymm2 的高 128 位元整數至 xmm3
    vextracti128 xmm3, ymm2, 1
    #    在 xmm3 中，第 7 元素位於最高 32-bit (index 3)，使用 vpshufd 移至最低位
    vpshufd xmm3, xmm3, 3
    vmovd   r13d, xmm3

    # 印出第 7 元素結果
    sys_print_str elem7_msg, elem7_len
    mov edi, r13d
    call print_dec          # 印出 9

    # 5. 測試 256-bit 向量位元異或 (vpxor)
    vmovdqa ymm4, [vec_x]
    vmovdqa ymm5, [vec_y]
    vpxor   ymm6, ymm4, ymm5
    vmovd   r14d, xmm6      # 0xaa ^ 0x55 = 0xff (255)

    sys_print_str xor_msg, xor_len
    mov edi, r14d
    call print_hex          # 印出 0xff

    # 6. 清理 YMM 高位狀態
    vzeroupper

    sys_exit 0
