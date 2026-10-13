.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel PCLMULQDQ (Carry-Less Multiplication, 無進位乘法)
#
# 歷史背景:
#   Intel 於 Westmere 微架構 (2010) 與 AES-NI 同期引入 PCLMULQDQ 指令。
#
# 核心機制與有限體數學 (Galois Field GF(2) Polynomials):
#   1. 普通乘法 vs 無進位乘法:
#      - 普通整數乘法: 當二進位 1 + 1 時會產生向高位的進位 (Carry, 1 + 1 = 10_2)。
#      - 無進位乘法 (Carry-Less): 加法採用 XOR (異或運算, 1 ^ 1 = 0)，「永遠不產生進位」！
#
#   2. 多項式乘法原理解析 (以 3 CLMUL 3 為例):
#      - 數值 3 的二進位為 0011_2，對應 GF(2) 多項式: (x + 1)
#      - (x + 1) * (x + 1) = x^2 + 2x + 1
#      - 由於係數在 GF(2) 體下模 2 (2x mod 2 = 0):
#        結果多項式簡化為: x^2 + 1
#      - 將 x^2 + 1 轉回二進位: 0101_2 = 5！
#      - 故普通乘法 3 * 3 = 9，而無進位乘法 3 CLMUL 3 = 5！
#
#   3. 操作數選擇機制 (Immediate Byte Selector):
#      - pclmulqdq xmm1, xmm2, imm8
#      - imm8 bit 0: 選擇 xmm1 的低 64 位 (0) 或高 64 位 (1)
#      - imm8 bit 4: 選擇 xmm2 的低 64 位 (0) 或高 64 位 (1)
#      - 輸出: 產生 128 位元的完整無進位乘積，存入 xmm1
#
# 應用領域:
#   - 現代網際網路 TLS 1.3 / HTTPS 的標準加密模式 AES-GCM (GHASH 演算法核心)。
#   - 萬兆網路封包與檔案系統 (Btrfs, ext4, gzip) 的極速硬體 CRC32 / CRC64 計算。
# =============================================================

.data
header_msg: .ascii "=== Intel PCLMULQDQ (GF(2) 無進位乘法指令展示) ===\n"
.equ header_len, . - header_msg

test1_msg:  .ascii "[測試 1] (x+1)*(x+1) -> 3 CLMUL 3 (預期 = 5): "
.equ test1_len, . - test1_msg

test2_msg:  .ascii "[測試 2] 0x80000000 CLMUL 2 (多項式左移 1 位): "
.equ test2_len, . - test2_msg

.align 16
# 測試向量 1 (低 64 位為 3)
v1: .quad 3, 0
v2: .quad 3, 0

# 測試向量 2 (低 64 位為 0x80000000 與 2)
v3: .quad 0x80000000, 0
v4: .quad 2, 0

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 測試 1: 3 CLMUL 3
    # ---------------------------------------------------------
    movdqa xmm0, [v1]
    movdqa xmm1, [v2]

    # imm = 0x00: 選擇 xmm0 的低 64-bit 與 xmm1 的低 64-bit
    pclmulqdq xmm0, xmm1, 0x00

    movd r12d, xmm0         # 提取低 32 位結果 (5)

    sys_print_str test1_msg, test1_len
    mov edi, r12d
    call print_dec          # 印出 5

    # ---------------------------------------------------------
    # 測試 2: 0x80000000 CLMUL 2
    # 乘 2 相當於多項式乘以 x (左移 1 位，無進位): 0x80000000 << 1 = 0x100000000
    # ---------------------------------------------------------
    movdqa xmm2, [v3]
    movdqa xmm3, [v4]

    pclmulqdq xmm2, xmm3, 0x00

    movq r13, xmm2          # 提取 64 位結果 (0x100000000)

    sys_print_str test2_msg, test2_len
    mov rdi, r13
    call print_hex          # 印出 0x01 0x00 0x00 0x00 0x00

    sys_exit 0
