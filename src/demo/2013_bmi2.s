.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# BMI2 (Bit Manipulation Instructions 2) 全套指令展示
#
# 核心革命性特色:
#   1. 支援三操作數 (Non-destructive: dest = src1 op src2，不破壞來源)
#   2. 絕大多數指令完全不破壞 CPU 狀態旗標 (Flag-Preserving)
#   3. 解除傳統位移只能綁定 CL 暫存器的枷鎖 (可用任意暫存器當位移量)
#   4. 引入強大的位元散播/聚集 (PEXT / PDEP)
#
# 涵蓋指令:
#   1. BZHI  - 高位歸零 (Zero High Bits)
#   2. PEXT  - 平行位元抽取 / 聚集 (Parallel Bits Extract)
#   3. PDEP  - 平行位元沉積 / 散佈 (Parallel Bits Deposit)
#   4. MULX  - 無旗標影響之高精度乘法 (Multiply Without Flags)
#   5. SHLX  - 無旗標影響之邏輯左移 (Shift Left without Flags)
#   6. RORX  - 無旗標影響之循環右移 (Rotate Right without Flags)
# =============================================================

.data
header_msg: .ascii "=== BMI2 Bit Manipulation Suite ===\n"
.equ header_len, . - header_msg

bzhi_msg:   .ascii "BZHI:    "
.equ bzhi_len, . - bzhi_msg

pext_msg:   .ascii "PEXT:    "
.equ pext_len, . - pext_msg

pdep_msg:   .ascii "PDEP:    "
.equ pdep_len, . - pdep_msg

mulx_msg:   .ascii "MULX-Hi: "
.equ mulx_len, . - mulx_msg

shlx_msg:   .ascii "SHLX:    "
.equ shlx_len, . - shlx_msg

rorx_msg:   .ascii "RORX:    "
.equ rorx_len, . - rorx_msg

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 1. BZHI (Zero High Bits)
    # 語法: bzhi dest, src, index
    # 說明: 將 index 位元以上的所有高位歸零，只保留低 index 位元。
    # 數值 0b11111111 (0xff)，index = 4:
    # 保留 bit 3..0 (0b1111)，高位全清為 0 -> 輸出 0x0f (15)。
    # ---------------------------------------------------------
    sys_print_str bzhi_msg, bzhi_len
    mov eax, 0b11111111    # 來源數值 = 0xff
    mov ecx, 4             # 截斷索引 = 4
    bzhi edi, eax, ecx     # edi = eax & ((1 << 4) - 1)
    call print_hex

    # ---------------------------------------------------------
    # 2. PEXT (Parallel Bits Extract, 位元聚集)
    # 語法: pext dest, src, mask
    # 說明: 依據 mask 中為 1 的位元位置，將 src 對應的位元抽出，
    #       並由低位向高位緊密打包。
    # 來源: 0b10110010 (0xb2)
    # 遮罩: 0b10010001 (挑選第 7, 4, 0 位)
    # 抽出的位元為: bit 7 (1), bit 4 (1), bit 0 (0) -> 打包為 0b110 = 6。
    # 預期輸出: 0x06
    # ---------------------------------------------------------
    sys_print_str pext_msg, pext_len
    mov eax, 0b10110010    # 來源
    mov edx, 0b10010001    # 遮罩
    pext edi, eax, edx     # edi = 抽取打包結果
    call print_hex

    # ---------------------------------------------------------
    # 3. PDEP (Parallel Bits Deposit, 位元散播)
    # 語法: pdep dest, src, mask
    # 說明: PEXT 的逆向操作！將 src 低位的連續位元取出，
    #       按照 mask 中為 1 的位置沉積散播進去，其餘位填 0。
    # 來源: 0b00000110 (剛才抽出的 6 = 0b110)
    # 遮罩: 0b10010001 (第 7, 4, 0 位)
    # 散播結果: 第 7 位填 1, 第 4 位填 1, 第 0 位填 0 -> 0b10010000 (0x90)。
    # 預期輸出: 0x90
    # ---------------------------------------------------------
    sys_print_str pdep_msg, pdep_len
    mov eax, 0b00000110    # 來源連續 3 個 bit: 1, 1, 0
    mov edx, 0b10010001    # 遮罩
    pdep edi, eax, edx     # 散播還原
    call print_hex

    # ---------------------------------------------------------
    # 4. MULX (Unsigned Multiply Without Affecting Flags)
    # 語法: mulx hi_dest, lo_dest, src
    # 說明: 計算 EDX * src，產出 64 位元雙倍精度乘積 (高 32 位放入 hi_dest，
    #       低 32 位放入 lo_dest)。
    # 特點: 完全不改動任何 CPU 狀態旗標 (CF, OF 等全不變)！
    # 這裡計算: 0x80000000 * 4 = 0x200000000 (高 32 位 = 2, 低 32 位 = 0)
    # 預期輸出 (Hi): 0x02
    # ---------------------------------------------------------
    sys_print_str mulx_msg, mulx_len
    mov edx, 0x80000000    # 被乘數固定在 EDX/RDX
    mov eax, 4             # 乘數
    mulx edi, ebx, eax     # edi = 高 32 位 (2), ebx = 低 32 位 (0)
    call print_hex

    # ---------------------------------------------------------
    # 5. SHLX (Shift Left Without Affecting Flags)
    # 語法: shlx dest, src, count
    # 說明: 1. 三操作數語法: dest = src << count，來源 src 保持不變。
    #       2. 位移量 count 可以放在任意暫存器 (此處用 r8d，不再強制綁定 CL)！
    #       3. 完全不改動任何 CPU 旗標。
    # 數值 0x05 左移 8 位元 -> 0x0500。
    # 預期輸出: 0x05 0x00
    # ---------------------------------------------------------
    sys_print_str shlx_msg, shlx_len
    mov eax, 0x05          # src
    mov r8d, 8             # count 在 r8d (非 CL！)
    shlx edi, eax, r8d     # edi = eax << r8d
    call print_hex

    # ---------------------------------------------------------
    # 6. RORX (Rotate Right Non-Destructive Without Flags)
    # 語法: rorx dest, src, imm8
    # 說明: 三操作數循環右移，立即數指定位移量，不影響旗標。
    # 數值 0x12345678 循環右移 8 位元 -> 0x78123456。
    # 預期輸出: 0x78 0x12 0x34 0x56
    # ---------------------------------------------------------
    sys_print_str rorx_msg, rorx_len
    mov eax, 0x12345678
    rorx edi, eax, 8
    call print_hex

    sys_exit 0
