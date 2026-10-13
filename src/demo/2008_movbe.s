.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel MOVBE (Move with Byte Swap, 位元組反轉搬移指令)
#
# 歷史背景:
#   Intel 於 Haswell 微架構 (2013) 正式納入標準桌面處理器 (先前於 Atom 架構引入)。
#
# 端序衝突問題 (Endianness Conflict):
#   - x86 處理器原生為小端序 (Little-Endian, 低位元組存於低記憶體位址)。
#   - 網際網路標準協定 (TCP/IP 標頭、IPv4/IPv6、DNS) 以及大量二進位檔案格式
#     (PNG, JPEG, Java .class 檔案) 皆採用大端序 (Big-Endian / Network Byte Order)。
#
# 傳統解決方案的效能損耗:
#   - 在 MOVBE 出現之前，從記憶體讀取大端序資料必須執行兩條指令:
#     1. mov   eax, [mem]    (先將記憶體載入暫存器)
#     2. bswap eax           (再透過 BSWAP 指令反轉暫存器中的位元組順序)
#   - 寫入時亦同 (先 BSWAP 再 MOV)，額外佔用指令解碼通道與執行週期。
#
# MOVBE 的硬體革新:
#   - 單一指令、單一記憶體週期同時完成「記憶體搬移」與「位元組順序反轉」！
#   - 雙向支援:
#     * movbe reg, [mem] : 從記憶體載入大端序資料，硬體自動翻轉為小端序載入暫存器。
#     * movbe [mem], reg : 將暫存器資料翻轉為大端序後直接寫入記憶體。
#   - 支援 16-bit, 32-bit, 64-bit 運算元。
# =============================================================

.data
header_msg: .ascii "=== Intel MOVBE (大端序/網路序硬體反轉搬移展示) ===\n"
.equ header_len, . - header_msg

test1_msg:  .ascii "[測試 1: 32-bit 讀取反轉] 記憶體 [11 22 33 44] 透過 MOVBE 載入暫存器: "
.equ test1_len, . - test1_msg

test2_msg:  .ascii "[測試 2: 64-bit 寫入反轉] 暫存器 0x0102030405060708 透過 MOVBE 寫回記憶體: "
.equ test2_len, . - test2_msg

# 記憶體中的連續 Byte 陣列 (小端位址依序為 0x11, 0x22, 0x33, 0x44)
be_bytes: .byte 0x11, 0x22, 0x33, 0x44

.bss
out_buf: .space 8

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 測試 1: 32-bit MOVBE 讀取反轉
    # 記憶體位址由低至高為 0x11, 0x22, 0x33, 0x44
    # 若以一般 mov eax, [be_bytes] 載入，小端序數值為 0x44332211
    # 但以 movbe eax, [be_bytes] 載入，硬體直接反轉為 0x11223344！
    # ---------------------------------------------------------
    movbe eax, [be_bytes]
    mov r12d, eax

    sys_print_str test1_msg, test1_len
    mov edi, r12d
    call print_hex          # 印出 0x11 0x22 0x33 0x44

    # ---------------------------------------------------------
    # 測試 2: 64-bit MOVBE 寫入反轉
    # 將暫存器數值 0x0102030405060708 以大端序寫入記憶體 out_buf
    # ---------------------------------------------------------
    mov rax, 0x0102030405060708
    movbe [out_buf], rax    # 記憶體位址由低至高變為 01 02 03 04 05 06 07 08

    # 使用普通 64-bit mov 讀回以驗證記憶體真實 byte 排列
    mov r13, [out_buf]      # 小端序讀回為 0x0807060504030201

    sys_print_str test2_msg, test2_len
    mov rdi, r13
    call print_hex          # 印出 0x08 0x07 0x06 0x05 0x04 0x03 0x02 0x01

    sys_exit 0
