.intel_syntax noprefix
.global _start

.include "system.inc"
.include "print.inc"

# ==============================================================================
# SSE (Streaming SIMD Extensions) 系列完整指令展示與演進總覽
#
# x86 SIMD 向量架構從 1999 年至 2008 年歷經了六個主要世代：
#
# 1. SSE (SSE1, 1999 - Pentium III)
#    - 突破：擺脫 MMX 借用 x87 浮點堆疊的束縛，正式引入 128 位元獨立 XMM 暫存器 (xmm0~xmm7)。
#    - 核心：提供 128 位元「單精度浮點數 (FP32)」並行運算能力（單一週期同時算 4 個 float）。
#    - 代表指令：addps (Packed Single-precision Float Addition)。
#
# 2. SSE2 (2001 - Pentium 4)
#    - 突破：徹底取代 MMX，將整數運算擴展至 128 位元，並引入雙精度浮點數 (FP64)。
#    - 核心：支援 8/16/32/64-bit 打包整數向量運算，以及 2 個 64-bit 雙精度浮點數並行運算。
#    - 代表指令：paddd (Packed 32-bit Integer Addition)。
#
# 3. SSE3 / PNI (2004 - Pentium 4 Prescott)
#    - 突破：打破 SIMD 傳統只能垂直（Vertical，不同向量相同通道）計算的限制。
#    - 核心：引入「水平運算 (Horizontal Operations)」，允許同一個暫存器內部相鄰元素相加。
#    - 代表指令：haddps (Horizontal Add Packed Single-precision)。
#
# 4. SSSE3 (2006 - Core 微架構 / Merom & Conroe)
#    - 突破：針對多媒體、訊號處理與密碼學大幅強化整數操作。
#    - 核心：向量絕對值運算、萬用位元組任意重排 (pshufb)、位元組對齊拼接 (palignr)。
#    - 代表指令：pabsd (Packed Absolute 32-bit Integer)。
#
# 5. SSE4.1 (2007 - Penryn 45nm)
#    - 突破：引入 47 條多媒體與圖形加速指令，強化向量與通用暫存器的互動。
#    - 核心：32 位元整數取最大/最小值、向量點積 (dpps/dppd)、浮點取整 (roundps)、純量插入與提取 (pinsrd/pextrd)。
#    - 代表指令：pmaxsd (Packed Signed Maximum 32-bit Integer)。
#
# 6. SSE4.2 (2008 - Nehalem)
#    - 突破：針對文字字串加速 (STTNI) 與現代硬體通訊協議的校驗碼加速。
#    - 核心：硬體級 CRC32-C (Castagnoli 多項式) 計算，為網路、資料庫與分散式系統核心加速。
#    - 代表指令：crc32 (CRC32-C Checksum Calculation)。
# ==============================================================================

.data
.align 16
# --- SSE1 測試資料 (單精度浮點數 FP32) ---
# [10.0, 20.0, 30.0, 40.0] + [5.0, 5.0, 5.0, 5.0] => Lane 0: 15.0f (0x0f)
sse1_a: .float 10.0, 20.0, 30.0, 40.0
sse1_b: .float  5.0,  5.0,  5.0,  5.0

# --- SSE2 測試資料 (32-bit 整數) ---
# [10, 20, 30, 40] + [15, 10, 5, 0] => Lane 0: 25 (0x19)
sse2_a: .long 10, 20, 30, 40
sse2_b: .long 15, 10,  5,  0

# --- SSE3 測試資料 (水平相加浮點數) ---
# [1.0, 2.0, 3.0, 4.0] haddps => Lane 0: (1.0 + 2.0) = 3.0f (0x03)
sse3_v: .float 1.0, 2.0, 3.0, 4.0

# --- SSSE3 測試資料 (絕對值運算) ---
# [-28, 5, -100, 50] pabsd => Lane 0: |-28| = 28 (0x1c)
ssse3_v: .long -28, 5, -100, 50

# --- SSE4.1 測試資料 (有號整數取最大值) ---
# [-10, 50, 3, 99] vs [35, 20, 8, -50] pmaxsd => Lane 0: max(-10, 35) = 35 (0x23)
sse41_a: .long -10, 50, 3,  99
sse41_b: .long  35, 20, 8, -50

# --- 輸出字串標籤 ---
header_msg: .ascii "=== SSE Architecture Suite (SSE1 ~ SSE4.2) ===\n"
.equ header_len, . - header_msg

msg_sse1:  .ascii "SSE1   (addps):   "
.equ len_sse1, . - msg_sse1

msg_sse2:  .ascii "SSE2   (paddd):   "
.equ len_sse2, . - msg_sse2

msg_sse3:  .ascii "SSE3   (haddps):  "
.equ len_sse3, . - msg_sse3

msg_ssse3: .ascii "SSSE3  (pabsd):   "
.equ len_ssse3, . - msg_ssse3

msg_sse41: .ascii "SSE4.1 (pmaxsd):  "
.equ len_sse41, . - msg_sse41

msg_sse42: .ascii "SSE4.2 (crc32):   "
.equ len_sse42, . - msg_sse42

.section .text
_start:
    # 輸出總標題
    sys_print_str header_msg, header_len

    # ==========================================================================
    # 1. SSE (SSE1): 單精度浮點數平行加法 (addps)
    #
    # 行為: 將 xmm0 與 xmm1 的 4 組 float 同步相加，結果存回 xmm0。
    # 說明: 透過 cvttss2si 將第 0 通道之 15.0f 截斷取整為 32-bit 整數 15 (0x0f)。
    # ==========================================================================
    sys_print_str msg_sse1, len_sse1
    movaps   xmm0, [sse1_a]
    movaps   xmm1, [sse1_b]
    addps    xmm0, xmm1
    cvttss2si edi, xmm0        # 取出 Lane 0: 10.0 + 5.0 = 15 (0x0f)
    call     print_hex

    # ==========================================================================
    # 2. SSE2: 32-bit 整數向量平行加法 (paddd)
    #
    # 行為: 將 4 組 32-bit 有號/無號整數同步相加 (Lane 0: 10 + 15 = 25)。
    # 說明: 透過 movd 將 xmm0 最低位 32-bit 提取到通用暫存器 edi (0x19)。
    # ==========================================================================
    sys_print_str msg_sse2, len_sse2
    movdqa   xmm0, [sse2_a]
    movdqa   xmm1, [sse2_b]
    paddd    xmm0, xmm1
    movd     edi, xmm0         # 取出 Lane 0: 10 + 15 = 25 (0x19)
    call     print_hex

    # ==========================================================================
    # 3. SSE3: 水平向量浮點相加 (haddps)
    #
    # 行為: 將同一暫存器內相鄰的元素相加 (Horizontal Add)。
    #       xmm0 = [v0, v1, v2, v3]
    #       haddps xmm0, xmm0 => [v0+v1, v2+v3, v0+v1, v2+v3]
    # 說明: Lane 0 的結果為 1.0 + 2.0 = 3.0f，轉為整數 3 (0x03)。
    # ==========================================================================
    sys_print_str msg_sse3, len_sse3
    movaps   xmm0, [sse3_v]
    haddps   xmm0, xmm0
    cvttss2si edi, xmm0        # 取出 Lane 0: 1.0 + 2.0 = 3 (0x03)
    call     print_hex

    # ==========================================================================
    # 4. SSSE3: 向量絕對值運算 (pabsd)
    #
    # 行為: 針對向量內的 4 個 32-bit 有號整數，逐一求絕對值。
    # 說明: Lane 0 數值為 -28，計算後轉為正數 28 (0x1c)。
    #       過去在 SSE2 需結合 pxor 與 psubd 多步操作，SSSE3 單指令即可完成。
    # ==========================================================================
    sys_print_str msg_ssse3, len_ssse3
    movdqa   xmm0, [ssse3_v]
    pabsd    xmm0, xmm0
    movd     edi, xmm0         # 取出 Lane 0: |-28| = 28 (0x1c)
    call     print_hex

    # ==========================================================================
    # 5. SSE4.1: 向量有號整數取最大值 (pmaxsd)
    #
    # 行為: 比較兩向量對應通道的 32-bit 有號整數，取較大者存入目標暫存器。
    # 說明: Lane 0 比較 -10 與 35，取最大值為 35 (0x23)。
    #       SSE2 原本僅支援 16-bit 比較 (pmaxsw)，SSE4.1 補齊了 32-bit 整數支援。
    # ==========================================================================
    sys_print_str msg_sse41, len_sse41
    movdqa   xmm0, [sse41_a]
    movdqa   xmm1, [sse41_b]
    pmaxsd   xmm0, xmm1
    movd     edi, xmm0         # 取出 Lane 0: max(-10, 35) = 35 (0x23)
    call     print_hex

    # ==========================================================================
    # 6. SSE4.2: 硬體 CRC32-C 校驗和計算 (crc32)
    #
    # 行為: 使用硬體專屬電路累加計算 CRC-32C (Castagnoli, 多項式 0x1EDC6F41)。
    # 說明: 廣泛應用於 iSCSI, Btrfs, Ext4, Kafka, SCTP 等通訊與儲存校驗。
    #       edi 初始為 0，與 0x12345678 累加計算後產生校驗碼。
    # ==========================================================================
    sys_print_str msg_sse42, len_sse42
    xor      edi, edi
    mov      ebx, 0x12345678
    crc32    edi, ebx          # edi = 0xfa745634
    call     print_hex

    # 正常結束
    sys_exit 0
