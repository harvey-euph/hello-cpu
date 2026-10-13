.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel 符號擴展與零擴展 (MOVSX / MOVZX / MOVSXD)
#
# 歷史背景:
#   Intel 於 80386 (1985) 引入 MOVSX (Move with Sign-Extend) 與 MOVZX (Move with Zero-Extend)。
#   AMD64 / x86_64 (2003) 進一步引入 MOVSXD (Move Doubleword with Sign-Extend to Quadword)。
#
# 編譯器工程師型別轉換與定址核心法則 (Type Casting & Array Indexing):
#   1. 型別提升 (Type Promotion):
#      - C/C++/Rust 中將窄型別 (uint8_t, int16_t) 提升為寬型別 (uint64_t, int64_t):
#        * 無號提升: 使用 MOVZX 將高位全部補 0。
#        * 有號提升: 使用 MOVSX / MOVSXD 複製最高符號位元 (Sign Bit) 填滿高位。
#
#   2. 陣列索引定址陷阱 (Array Subscript Lowering):
#      - 在 64 位元架構下，記憶體位址運算強制為 64 位元: [base + index*scale]
#      - 當 C 語言寫: int i; array[i]
#      - i 屬於 32-bit 有號整數 (int)。若 i 為負數 (如指標倒退)，編譯器若未做符號擴展，
#        硬體會將 32-bit 視為巨大正數 (4GB 偏移)，引發 Segmentation Fault！
#      - 因此編譯器在陣列定址前必插入: movsxd rdi, edi。
#
#   3. x86_64 黃金零擴展特徵 (The 32-bit Auto-Zero-Extension Rule):
#      - 寫入 8-bit (al) 或 16-bit (ax) 暫存器時: 高位保持不變 (可能造成局部暫存器停頓 Partial Register Stall)。
#      - 寫入 32-bit (eax) 暫存器時: 硬體「自動將高 32 位元清零」！
#      - 因此編譯器將 uint32_t 轉 uint64_t 時，從不發出多餘指令，mov eax, edx 就已天然完成 64 位元零擴展！
# =============================================================

.data
header_msg: .ascii "=== Intel MOVSX / MOVZX (型別提升與陣列定址擴展展示) ===\n"
.equ header_len, . - header_msg

test1_msg:  .ascii "[測試 1: MOVZX 無號零擴展] uint8 0x80 -> 64-bit (128): "
.equ test1_len, . - test1_msg

test2_msg:  .ascii "[測試 2: MOVSX 有號符號擴展] int8 0x80 (-128) 擴展為 64-bit: "
.equ test2_len, . - test2_msg

test3_msg:  .ascii "[測試 3: MOVSXD 32至64位元] int32 -42 符號擴展為 64-bit 十六進位: "
.equ test3_len, . - test3_msg

byte_val: .byte 0x80        # 若視為無號數 = 128；若視為有號數 = -128
int_neg:  .long -42         # 32-bit 有號負數

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 測試 1: MOVZX (Zero-Extend, 無號數擴展)
    # 0x80 (1000_0000) 零擴展後高位全補 0 -> 0x0000000000000080 (128)
    # ---------------------------------------------------------
    movzx r12, byte ptr [byte_val]

    sys_print_str test1_msg, test1_len
    mov rdi, r12
    call print_dec          # 印出 128

    # ---------------------------------------------------------
    # 測試 2: MOVSX (Sign-Extend, 有號數擴展)
    # 0x80 符號位為 1，符號擴展後高位全補 1 -> 0xffffffffffffff80 (-128)
    # ---------------------------------------------------------
    movsx r13, byte ptr [byte_val]

    sys_print_str test2_msg, test2_len
    mov rdi, r13
    call print_hex          # 印出 0xff 0xff 0xff 0xff 0xff 0xff 0xff 0x80

    # ---------------------------------------------------------
    # 測試 3: MOVSXD (32-bit to 64-bit Sign-Extend)
    # 編譯器降級 int32 陣列索引至 64 位元暫存器之核心指令
    # -42 (0xffffffd6) -> 64-bit (0xffffffffffffffd6)
    # ---------------------------------------------------------
    movsxd r14, dword ptr [int_neg]

    sys_print_str test3_msg, test3_len
    mov rdi, r14
    call print_hex          # 印出 0xff 0xff 0xff 0xff 0xff 0xff 0xff 0xd6

    sys_exit 0
