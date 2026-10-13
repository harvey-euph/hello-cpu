.intel_syntax noprefix
.global _start

.include "system.inc"
.include "print.inc"

# ==============================================================================
# 輸出格式化函式庫完整展示 (Decimal & Hexadecimal Formatting Suite)
#
# 在純組合語言環境（-nostdlib，不依賴 printf/libc）中，數值輸出需自行處理字元編碼：
#
# 1. 十進位格式化 (print_dec - 32-bit 無號整數):
#    - 核心演算法: 連續除以 10 (div ecx, 其中 ecx=10)。
#    - 餘數轉換: 每次除法產生的餘數 (edx, 範圍 0~9) 加上 ASCII '0' (0x30)，即為該位數字元。
#    - 緩衝區填充: 由堆疊緩衝區的末端「由後往前 (Right-to-Left)」填入，商為 0 時停止。
#    - 特點: 自動在字串尾端補上換行符 '\n'，直接呼叫 sys_write 輸出。
#
# 2. 十六進位格式化 (print_hex - 64-bit 動態長度十六進位):
#    - 核心演算法:
#      a. 最高位掃描 (BSR 指令): 使用 Bit Scan Reverse 找出最高位的 1，動態算出有效 Byte 數 (1~8 bytes)。
#      b. 零值特判: 若數值本身為 0，則輸出 0x00。
#      c. 循環左移 (ROL 指令): 依序將各個 Byte 轉入最低位，並拆解為高 4 位 (High Nibble) 與低 4 位 (Low Nibble)。
#      d. 查表轉換: 透過 hex_digits ("0123456789abcdef") 查表轉為 ASCII。
#    - 特點: 自動去除高位無效前綴 0 (例如 0x1234 不會印成 0x0000000000001234)，每 byte 前綴 0x 並以空白分隔。
# ==============================================================================

.section .rodata
header_dec: .ascii "=== 1. 十進位格式化展示 (print_dec) ===\n"
.equ len_hdec, . - header_dec

msg_d0: .ascii "零值測試 (0):          "
.equ len_d0, . - msg_d0

msg_d42: .ascii "小數測試 (42):         "
.equ len_d42, . - msg_d42

msg_dmid: .ascii "中型整數 (180393310):  "
.equ len_dmid, . - msg_dmid

msg_dmax: .ascii "最大無號 (4294967295): "
.equ len_dmax, . - msg_dmax

header_hex: .ascii "\n=== 2. 十六進位格式化展示 (print_hex) ===\n"
.equ len_hhex, . - header_hex

msg_h1: .ascii "1 Byte  (0x7f):        "
.equ len_h1, . - msg_h1

msg_h2: .ascii "2 Bytes (0x1234):      "
.equ len_h2, . - msg_h2

msg_h3: .ascii "3 Bytes (0xaabbcc):    "
.equ len_h3, . - msg_h3

msg_h4: .ascii "4 Bytes (0xdeadbeef):  "
.equ len_h4, . - msg_h4

msg_h8: .ascii "8 Bytes (64-bit 全長):  "
.equ len_h8, . - msg_h8

msg_hz: .ascii "零值輸出 (0 -> 0x00):   "
.equ len_hz, . - msg_hz

.section .text
_start:
    # --------------------------------------------------------------------------
    # 1. 測試十進位輸出 (print_dec)
    # --------------------------------------------------------------------------
    sys_print_str header_dec, len_hdec

    sys_print_str msg_d0, len_d0
    mov edi, 0
    call print_dec

    sys_print_str msg_d42, len_d42
    mov edi, 42
    call print_dec

    sys_print_str msg_dmid, len_dmid
    mov edi, 180393310
    call print_dec

    sys_print_str msg_dmax, len_dmax
    mov edi, 0xffffffff
    call print_dec

    # --------------------------------------------------------------------------
    # 2. 測試十六進位輸出 (print_hex)
    # --------------------------------------------------------------------------
    sys_print_str header_hex, len_hhex

    # 單一 Byte (0x7f)
    sys_print_str msg_h1, len_h1
    mov rdi, 0x7f
    call print_hex

    # 雙 Byte (0x12 0x34)
    sys_print_str msg_h2, len_h2
    mov rdi, 0x1234
    call print_hex

    # 三 Byte (自動截斷高位 0，印出 0xaa 0xbb 0xcc)
    sys_print_str msg_h3, len_h3
    mov rdi, 0xaabbcc
    call print_hex

    # 四 Byte (0xde 0xad 0xbe 0xef)
    sys_print_str msg_h4, len_h4
    mov rdi, 0xdeadbeef
    call print_hex

    # 八 Byte (完整 64 位元暫存器)
    sys_print_str msg_h8, len_h8
    mov rdi, 0x0123456789abcdef
    call print_hex

    # 零值測試 (輸出 0x00)
    sys_print_str msg_hz, len_hz
    mov rdi, 0
    call print_hex

    sys_exit 0
