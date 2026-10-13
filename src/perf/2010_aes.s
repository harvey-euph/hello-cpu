.intel_syntax noprefix
.global _start

.include "system.inc"
.include "print.inc"

# ==============================================================================
# AES 加密效能基準測試: AES-NI 硬體指令 vs 純軟體演算法實作
#
# AES (Advanced Encryption Standard, Rijndael) 單輪加密由四大核心變換組成：
#
# 1. 演算法四步驟:
#    a. ShiftRows (列移位): 將 4x4 狀態矩陣的每一列進行循環位移。
#    b. SubBytes (S-Box 代換): 使用非線性代換表 (S-Box) 進行 8-bit 位元組對應。
#    c. MixColumns (行混合): 在伽羅瓦有限體 GF(2^8) 上進行矩陣多項式乘法模除。
#    d. AddRoundKey (金鑰加法): 將狀態矩陣與輪金鑰進行逐位元互斥或 (XOR)。
#
# 2. 純軟體實作的困境與資安弱點:
#    - 效能瓶頸: S-Box 查表需 16 次隨機記憶體存取，MixColumns 需數十次位移與 XOR (xtime)。
#    - 資安隱患 (側信道攻擊 / Side-Channel): S-Box 查表極度容易遭受「快取計時攻擊 (Cache Timing Attack)」，
#      攻擊者可藉由測量快取命中時間反推秘密金鑰！
#    - 耗時: 單輪約需 70 ~ 100 個 CPU 週期。
#
# 3. AES-NI 硬體加速 (2010 - Westmere 架構引入):
#    - aesenc 指令: CPU 內部配置了專屬的硬體 Galois Field 乘法器與代換電路。
#    - 單一指令: 一條 aesenc 指令在 1 個週期吞吐（~4 週期延遲）內同時完成上述四個步驟！
#    - 常數時間 (Constant Time): 完全不存取記憶體 S-Box 表，免疫任何快取計時側信道攻擊！
# ==============================================================================

.equ ITERS, 100000

.section .data
.align 16
state: .quad 0x0123456789abcdef, 0xfedcba9876543210
key:   .quad 0x1020304050607080, 0x90a0b0c0d0e0f000

# AES S-box 表 (256 bytes)
sbox:
    .byte 0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76
    .byte 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0
    .byte 0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15
    .byte 0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75
    .byte 0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84
    .byte 0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf
    .byte 0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8
    .byte 0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2
    .byte 0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73
    .byte 0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb
    .byte 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79
    .byte 0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08
    .byte 0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a
    .byte 0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e
    .byte 0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf
    .byte 0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16

.section .bss
.align 16
buf1: .space 16
buf2: .space 16

.section .rodata
title_msg:  .ascii "=== AES-NI 硬體加速 vs 純軟體實作基準測試 ===\n"
.equ len_title, . - title_msg

ver_hw_msg: .ascii "[驗證] 硬體 AES-NI 輸出: "
.equ len_ver_hw, . - ver_hw_msg

ver_sw_msg: .ascii "[驗證] 純軟體演算法 輸出: "
.equ len_ver_sw, . - ver_sw_msg

bench_title: .ascii "--- 100,000 次單輪加密效能對比 ---\n"
.equ len_btitle, . - bench_title

msg_hw:     .ascii "硬體 AES-NI (aesenc 指令): "
.equ len_hw, . - msg_hw

msg_sw:     .ascii "純軟體實作  (查表與數學):   "
.equ len_sw, . - msg_sw

.section .text

# ------------------------------------------------------------------------------
# 輔助函數: xtime (Galois Field GF(2^8) 乘以 2 模除 0x11b)
# ------------------------------------------------------------------------------
xtime:
    movzx eax, dil
    mov edx, eax
    shl eax, 1             # x << 1
    sar dl, 7              # 若最高 bit 為 1 則 dl = 0xff, 否則 0x00
    and dl, 0x1b           # 不可約多項式 x^8 + x^4 + x^3 + x + 1 的低 8 位 (0x1b)
    xor al, dl             # 條件模除 XOR
    movzx eax, al
    ret

# ------------------------------------------------------------------------------
# 純軟體單輪 AES 加密實作
# ------------------------------------------------------------------------------
aes_software_round:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16

    # 1. ShiftRows (列移位)
    mov al, byte ptr [state + 0]
    mov byte ptr [buf1 + 0], al
    mov al, byte ptr [state + 4]
    mov byte ptr [buf1 + 4], al
    mov al, byte ptr [state + 8]
    mov byte ptr [buf1 + 8], al
    mov al, byte ptr [state + 12]
    mov byte ptr [buf1 + 12], al

    mov al, byte ptr [state + 5]
    mov byte ptr [buf1 + 1], al
    mov al, byte ptr [state + 9]
    mov byte ptr [buf1 + 5], al
    mov al, byte ptr [state + 13]
    mov byte ptr [buf1 + 9], al
    mov al, byte ptr [state + 1]
    mov byte ptr [buf1 + 13], al

    mov al, byte ptr [state + 10]
    mov byte ptr [buf1 + 2], al
    mov al, byte ptr [state + 14]
    mov byte ptr [buf1 + 6], al
    mov al, byte ptr [state + 2]
    mov byte ptr [buf1 + 10], al
    mov al, byte ptr [state + 6]
    mov byte ptr [buf1 + 14], al

    mov al, byte ptr [state + 15]
    mov byte ptr [buf1 + 3], al
    mov al, byte ptr [state + 3]
    mov byte ptr [buf1 + 7], al
    mov al, byte ptr [state + 7]
    mov byte ptr [buf1 + 11], al
    mov al, byte ptr [state + 11]
    mov byte ptr [buf1 + 15], al

    # 2. SubBytes (查 S-Box 代換)
    xor ecx, ecx
.Lsub_loop:
    movzx eax, byte ptr [buf1 + rcx]
    movzx eax, byte ptr [sbox + rax]
    mov byte ptr [buf1 + rcx], al
    inc ecx
    cmp ecx, 16
    jne .Lsub_loop

    # 3. MixColumns (GF(2^8) 行混合)
    xor r12d, r12d
.Lmix_col_loop:
    lea r13, [r12 * 4]
    movzx r14d, byte ptr [buf1 + r13 + 0]
    movzx r15d, byte ptr [buf1 + r13 + 1]
    movzx ebx,  byte ptr [buf1 + r13 + 2]
    movzx esi,  byte ptr [buf1 + r13 + 3]

    mov edx, r14d
    xor edx, r15d
    xor edx, ebx
    xor edx, esi
    mov [rsp], edx         # 保存 T = s0 ^ s1 ^ s2 ^ s3

    mov edi, r14d
    xor edi, r15d
    call xtime
    xor eax, r14d
    xor eax, [rsp]
    mov byte ptr [buf2 + r13 + 0], al

    mov edi, r15d
    xor edi, ebx
    call xtime
    xor eax, r15d
    xor eax, [rsp]
    mov byte ptr [buf2 + r13 + 1], al

    mov edi, ebx
    xor edi, esi
    call xtime
    xor eax, ebx
    xor eax, [rsp]
    mov byte ptr [buf2 + r13 + 2], al

    mov edi, esi
    xor edi, r14d
    call xtime
    xor eax, esi
    xor eax, [rsp]
    mov byte ptr [buf2 + r13 + 3], al

    inc r12d
    cmp r12d, 4
    jne .Lmix_col_loop

    # 4. AddRoundKey (金鑰加法)
    mov rax, [buf2]
    xor rax, [key]
    mov [buf2], rax

    mov rax, [buf2 + 8]
    xor rax, [key + 8]
    mov [buf2 + 8], rax

    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

_start:
    sys_print_str title_msg, len_title

    # --------------------------------------------------------------------------
    # 步驟 1: 輸出數值驗證（確認硬體與軟體計算結果 100% 相同）
    # --------------------------------------------------------------------------
    # 1.1 硬體輸出
    sys_print_str ver_hw_msg, len_ver_hw
    movdqa xmm0, [state]
    movdqa xmm1, [key]
    aesenc xmm0, xmm1
    movq   rdi, xmm0
    call   print_hex

    # 1.2 軟體輸出
    sys_print_str ver_sw_msg, len_ver_sw
    call   aes_software_round
    mov    rdi, [buf2]
    call   print_hex

    # --------------------------------------------------------------------------
    # 步驟 2: 100,000 次單輪加密效能對比
    # --------------------------------------------------------------------------
    sys_print_str bench_title, len_btitle

    # 暖機 (預熱 CPU 與快取)
    mov ecx, 2000
.L_warm:
    dec ecx
    jnz .L_warm

    # 2.1 測量硬體 AES-NI (100k iters)
    rdtscp
    shl rdx, 32
    or rax, rdx
    mov rbx, rax

    mov ebp, ITERS
.L_loop_hw:
    movdqa xmm0, [state]
    movdqa xmm1, [key]
    aesenc xmm0, xmm1
    dec ebp
    jnz .L_loop_hw

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, rbx
    push rax               # [rsp] = 硬體耗費週期

    # 2.2 測量純軟體演算法 (100k iters)
    rdtscp
    shl rdx, 32
    or rax, rdx
    mov rbx, rax

    mov ebp, ITERS
.L_loop_sw:
    call aes_software_round
    dec ebp
    jnz .L_loop_sw

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, rbx
    push rax               # [rsp] = 軟體耗費週期, [rsp+8] = 硬體耗費週期

    # 印出硬體結果
    sys_print_str msg_hw, len_hw
    mov rdi, [rsp + 8]
    call print_dec

    # 印出軟體結果
    sys_print_str msg_sw, len_sw
    mov rdi, [rsp]
    call print_dec

    add rsp, 16
    sys_exit 0
