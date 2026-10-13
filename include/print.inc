.ifndef _PRINT_INC_
.equ _PRINT_INC_, 1

# -------------------------------------------------------------
# 格式化輸出函數庫 (十六進位 8/16/32/64-bit 與 十進位 32-bit)
# -------------------------------------------------------------

.include "system.inc"

.data
hex_digits:
    .ascii "0123456789abcdef"

.text
# =============================================================
# 核心通用函數: print_hex
# 輸入:
#   rdi = 欲輸出的數值 (最高 64-bit)
# 說明:
#   自動忽略高位前綴 0，只輸出有效非零 byte（由 MSB 到 LSB，格式為 0x??）。
#   若數值本身為 0，則輸出 0x00。結尾換行。
# =============================================================
print_hex:
    sub rsp, 64            # 配置 64 bytes 堆疊緩衝區 (8 bytes * 5 字元 = 40 + overhead)
    mov [rsp + 48], rbx    # 保存 Callee-saved 暫存器
    mov [rsp + 56], r12

    mov r12, rdi           # r12 保存原始數值

    # 自動判斷有效 byte 數量 (忽略高位 0，若為 0 則輸出 1 個 0x00)
    test rdi, rdi
    jnz .Lcalc_len
    mov eax, 1             # 若數值為 0，長度為 1 byte (輸出 0x00)
    jmp .Lprep_shift

.Lcalc_len:
    bsr rax, rdi           # rax = 最高有效 bit 索引 (0..63)
    shr eax, 3             # rax = 最高有效 byte 索引 (0..7)
    inc eax                # eax = 有效 byte 數量 (1..8)

.Lprep_shift:
    mov r10d, eax          # r10 保存 byte 數量

    # 計算推齊至 64-bit 最高位 (MSB) 所需左移位元數: (8 - r10d) * 8
    mov ecx, 8
    sub ecx, r10d
    shl ecx, 3
    shl r12, cl            # 將有效數值推齊至最高位 (MSB)

    lea rbx, [rsp]         # rbx 指向緩衝區寫入位置
    mov rcx, r10           # 迴圈計數器 = byte 數量

.Lhex_loop:
    rol r12, 8             # 循環左移 8 位元，最高 byte 轉入最低 byte (r12b)

    # 1. 寫入 "0x"
    mov byte ptr [rbx], '0'
    mov byte ptr [rbx + 1], 'x'

    # 2. 轉換高 4 位 (High Nibble) 為 ASCII
    movzx eax, r12b
    shr eax, 4
    mov al, [hex_digits + rax]
    mov [rbx + 2], al

    # 3. 轉換低 4 位 (Low Nibble) 為 ASCII
    movzx eax, r12b
    and eax, 0x0f
    mov al, [hex_digits + rax]
    mov [rbx + 3], al

    # 4. 寫入間隔空白 ' '
    mov byte ptr [rbx + 4], ' '
    add rbx, 5             # 緩衝區前進 5 個字元

    dec rcx
    jnz .Lhex_loop

    # 5. 將最後一個空格改為換行符號 '\n'
    mov byte ptr [rbx - 1], '\n'

    # 6. 計算總長度: rdx = byte 數量 * 5，並以 sys_print_str 巨集輸出字串
    lea edx, [r10d + r10d * 4]
    sys_print_str [rsp], rdx

    # 還原暫存器並退出
    mov rbx, [rsp + 48]
    mov r12, [rsp + 56]
    add rsp, 64
    ret

# =============================================================
# 函數名稱: print_dec (32-bit 無號整數十進位輸出)
# 輸入:
#   edi = 32-bit 無號整數 (uint32_t)
# 說明:
#   將 4-byte 整數以十進位 ASCII 格式輸出至 stdout (結尾自動換行)。
#   採用由後向前 (Backwards) 填寫緩衝區演算法，無需字串翻轉。
#   輸出範例: 42 -> "42\n", 0 -> "0\n"
# =============================================================
print_dec:
    sub rsp, 24             # 配置 24 bytes 堆疊緩衝區 (16-byte 對齊)
    mov byte ptr [rsp + 23], '\n' # 結尾填入換行符
    lea rsi, [rsp + 23]     # rsi 指向當前寫入位置 (由後向前填入)

    mov eax, edi            # eax = 被除數
    mov ecx, 10             # 除數 = 10

.Ldec_loop:
    xor edx, edx            # 清空高位以進行 32 位元除法 edx:eax / ecx
    div ecx                 # eax = 商, edx = 餘數 (0~9)
    add dl, '0'             # 餘數轉為 ASCII 字元 ('0'~'9')
    dec rsi                 # 指標向前移動
    mov [rsi], dl           # 寫入字元

    test eax, eax           # 檢查商是否為 0
    jnz .Ldec_loop          # 若商不為 0 則繼續除以 10

    # 計算輸出字串長度: (rsp + 24) - rsi
    lea rdx, [rsp + 24]
    sub rdx, rsi            # rdx = 字串長度
    sys_print_str [rsi], rdx

    add rsp, 24
    ret

.endif # _PRINT_INC_
