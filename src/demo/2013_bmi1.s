.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# ABM & BMI1 進階位元操作指令全集展示
#
# 測試基準數值: 0x0000ac38
# 二進位表示:  0000 0000 0000 0000 1010 1100 0011 1000
#
# 涵蓋指令:
#   1. LZCNT  - 前導零計數 (Leading Zero Count, ABM)
#   2. TZCNT  - 尾端零計數 (Trailing Zero Count, BMI1)
#   3. BLSR   - 清除最低位的 1 (Reset Lowest Set Bit, x & (x-1))
#   4. BLSI   - 提取最低位的 1 (Extract Lowest Set Bit, x & (-x))
#   5. BLSMSK - 最低位遮罩 (Mask Up to Lowest Set Bit, x ^ (x-1))
#   6. ANDN   - 反相及閘 (AND NOT, ~src1 & src2)
#   7. BEXTR  - 位元欄位提取 (Bit Field Extract)
# =============================================================

.data
number: .long 0x0000ac38       # 基準值: 0b00000000_00000000_10101100_00111000
mask:   .long 0x00000038       # 用於 ANDN 的遮罩

# 標題與標籤字串
header_msg: .ascii "=== ABM & BMI1 Bit Manipulation ===\n"
.equ header_len, . - header_msg

val_msg:    .ascii "Input:  "
.equ val_len, . - val_msg

lz_msg:     .ascii "LZCNT:  "
.equ lz_len, . - lz_msg

tz_msg:     .ascii "TZCNT:  "
.equ tz_len, . - tz_msg

blsr_msg:   .ascii "BLSR:   "
.equ blsr_len, . - blsr_msg

blsi_msg:   .ascii "BLSI:   "
.equ blsi_len, . - blsi_msg

blsm_msg:   .ascii "BLSMSK: "
.equ blsm_len, . - blsm_msg

andn_msg:   .ascii "ANDN:   "
.equ andn_len, . - andn_msg

bext_msg:   .ascii "BEXTR:  "
.equ bext_len, . - bext_msg

.text
_start:
    # 0. 輸出標頭與輸入基準數值
    sys_print_str header_msg, header_len

    sys_print_str val_msg, val_len
    mov edi, [number]
    call print_hex

    # ---------------------------------------------------------
    # 1. LZCNT (Leading Zero Count, ABM / Haswell)
    # 說明: 從最高位元 (MSB, bit 31) 往低位數連續的 0 個數。
    # 數值 0x0000ac38 最高位的 1 位於 bit 15，因此前方有 16 個 0。
    # 預期輸出: 0x10 (16)
    # ---------------------------------------------------------
    sys_print_str lz_msg, lz_len
    lzcnt edi, [number]
    call print_hex

    # ---------------------------------------------------------
    # 2. TZCNT (Trailing Zero Count, BMI1)
    # 說明: 從最低位元 (LSB, bit 0) 往高位數連續的 0 個數。
    # 數值 0x0000ac38 最低位的 1 位於 bit 3，因此尾端有 3 個 0。
    # 預期輸出: 0x03 (3)
    # ---------------------------------------------------------
    sys_print_str tz_msg, tz_len
    tzcnt edi, [number]
    call print_hex

    # ---------------------------------------------------------
    # 3. BLSR (Reset Lowest Set Bit, BMI1)
    # 說明: 將最低位的 1 清除為 0，數學等價於 x & (x - 1)。
    # 這是著名的 Brian Kernighan 演算法核心（O(1) 抹除最低位）。
    # 0x0000ac38 (...00111000) -> 0x0000ac30 (...00110000)
    # 預期輸出: 0xac 0x30
    # ---------------------------------------------------------
    sys_print_str blsr_msg, blsr_len
    mov eax, [number]
    blsr edi, eax
    call print_hex

    # ---------------------------------------------------------
    # 4. BLSI (Extract Lowest Set Bit, BMI1)
    # 說明: 孤立並提取最低位的 1，其餘位元全清為 0，等價於 x & (-x)。
    # 這是樹狀陣列 (Fenwick Tree / Binary Indexed Tree) 的 lowbit 核心！
    # 0x0000ac38 的最低位 1 在 bit 3 (權重 8 = 0x08)。
    # 預期輸出: 0x08
    # ---------------------------------------------------------
    sys_print_str blsi_msg, blsi_len
    mov eax, [number]
    blsi edi, eax
    call print_hex

    # ---------------------------------------------------------
    # 5. BLSMSK (Mask Up to Lowest Set Bit, BMI1)
    # 說明: 將最低位的 1 以及它右側的所有位元全部設為 1，等價於 x ^ (x - 1)。
    # 0x0000ac38 最低位為 bit 3，故 bit 3..0 全填為 1 (0b1111 = 0x0f)。
    # 預期輸出: 0x0f
    # ---------------------------------------------------------
    sys_print_str blsm_msg, blsm_len
    mov eax, [number]
    blsmsk edi, eax
    call print_hex

    # ---------------------------------------------------------
    # 6. ANDN (Logical AND NOT, BMI1)
    # 說明: 計算 ~src1 & src2，在單一微指令內完成「取反後再 AND」。
    # 語法: andn dest, src1, src2  ->  dest = (~src1) & src2
    # 這裡: (~0x00000038) & 0x0000ac38 = 0x0000ac00 (清除低位 0x38)。
    # 預期輸出: 0xac 0x00
    # ---------------------------------------------------------
    sys_print_str andn_msg, andn_len
    mov edx, [mask]        # src1 = mask (會被取反)
    mov eax, [number]      # src2 = number
    andn edi, edx, eax     # edi = (~edx) & eax
    call print_hex

    # ---------------------------------------------------------
    # 7. BEXTR (Bit Field Extract, BMI1)
    # 說明: 單指令擷取任意位置與長度的連續位元區間。
    # 控制暫存器格式 (ecx):
    #   bits 7:0  = 起始位元索引 (Start Index: 0~31)
    #   bits 15:8 = 擷取位元長度 (Length: 1~32)
    # 這裡欲從 bit 3 開始連續取出 4 個位元:
    #   ecx = (4 << 8) | 3 = 0x0403
    # 0x0000ac38 的 bit 6..3 為 0b0111 = 7 (0x07)。
    # 預期輸出: 0x07
    # ---------------------------------------------------------
    sys_print_str bext_msg, bext_len
    mov ecx, (4 << 8) | 3  # Start = 3, Length = 4
    mov eax, [number]
    bextr edi, eax, ecx
    call print_hex

    sys_exit 0
