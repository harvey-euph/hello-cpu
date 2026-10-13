.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 效能評測: x86_64 乘法指令依賴鏈延遲評測 (Multiplication Latency Benchmark)
#
# 評測目的:
#   精確測量本機 CPU (Intel Core i5-8250U, Kaby Lake-R) 在不同乘法指令
#   與運算元配置 (暫存器 reg vs 記憶體 mem) 下的「依賴鏈延遲 (RAW Dependency Latency)」。
#
# 延遲 (Latency) vs 吞吐量 (Throughput) 的微架構測量原理:
#   現代超純量亂序 CPU 具備多個執行通道 (Execution Ports)。
#   - 吞吐量 (Throughput): 多個獨立無相依的乘法可被平行分派至多個 Port，同時執行。
#   - 延遲 (Latency): 下一條指令的輸入「必須嚴格依賴上一條指令的輸出 (RAW 依賴鏈)」，
#     強制 CPU 亂序引擎無法平行重疊，從而曝露出硬體運算單元真實的「時脈週期 (Cycles)」！
#
# 評測對比項目 (共 1,000,000 次乘法，每次乘 3):
#   1. LEA 暫存器算術合成乘 3:  lea rax, [rax + rax*2]      (預期 ~1 cycle, ALU Port 0/1)
#   2. IMUL 暫存器乘法:          imul rax, rbx               (預期 ~3 cycles, 乘法器 Port 1)
#   3. IMUL 唯讀快取記憶體:      imul rax, [mem_val]         (快取重疊, 瓶頸仍在 3-cycle 乘法器)
#   4. IMUL Store-Forwarding:   mov [mem_val], rax; imul... (強制記憶體真實相依, ~7-8 cycles)
#   5. MUL  傳統無號暫存器乘法:   mul rbx                     (預期 ~3-4 cycles, 產出 128-bit)
#   6. MULX (BMI2) 暫存器乘法:   mulx r8, rdx, rbx           (預期 ~3-4 cycles, 無旗標)
#   7. MULX (BMI2) 唯讀記憶體:   mulx r8, rdx, [mem_val]     (快取重疊, ~3-4 cycles)
#
# 測試規模: 100,000 迴圈 * 展開 10 次 = 1,000,000 次相依乘法
# =============================================================

.equ ITERS, 100000          # 100,000 次迴圈，每次展開 10 次相依乘法

.data
header_msg:
    .ascii "=== x86_64 乘法指令依賴鏈延遲評測 (1,000,000 次相依乘法) ===\n"
.equ header_len, . - header_msg

lea_msg:
    .ascii "1. LEA  reg          (移位相加乘 3, ALU):         "
.equ lea_len, . - lea_msg

imul_reg_msg:
    .ascii "2. IMUL reg          (暫存器相乘, 乘法器):       "
.equ imul_reg_len, . - imul_reg_msg

imul_mem_msg:
    .ascii "3. IMUL [mem]        (唯讀快取記憶體相乘):       "
.equ imul_mem_len, . - imul_mem_msg

imul_fwd_msg:
    .ascii "4. IMUL Store-Fwd    (Store-to-Load 記憶體相依): "
.equ imul_fwd_len, . - imul_fwd_msg

mul_reg_msg:
    .ascii "5. MUL  reg          (傳統無號暫存器乘法):       "
.equ mul_reg_len, . - mul_reg_msg

mulx_reg_msg:
    .ascii "6. MULX reg          (BMI2 無旗標暫存器乘法):    "
.equ mulx_reg_len, . - mulx_reg_msg

mulx_mem_msg:
    .ascii "7. MULX [mem]        (BMI2 唯讀快取記憶體乘法):  "
.equ mulx_mem_len, . - mulx_mem_msg

.align 64
mem_val:
    .quad 3                 # 乘數 3 (奇數保證 modulo 2^64 永不歸零)
mem_fwd:
    .quad 3

.text
_start:
    sys_print_str header_msg, header_len

    # =========================================================
    # 測試 1: LEA 暫存器算術合成乘 3 (lea rax, [rax + rax*2])
    # =========================================================
    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax            # r12 = 開始 TSC

    mov rax, 1              # 初始值 = 1
    mov ecx, ITERS          # 迴圈計數器 (必須在 rdtscp 之後設定!)
.Lloop_lea:
    .rept 10
    lea rax, [rax + rax*2]
    .endr
    dec ecx
    jnz .Lloop_lea

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r14, rax            # r14 = 總週期

    sys_print_str lea_msg, lea_len
    mov rdi, r14
    call print_dec

    # =========================================================
    # 測試 2: IMUL 暫存器相乘 (imul rax, rbx)
    # =========================================================
    mov rbx, 3              # 乘數 = 3

    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax

    mov rax, 1
    mov ecx, ITERS
.Lloop_imul_reg:
    .rept 10
    imul rax, rbx
    .endr
    dec ecx
    jnz .Lloop_imul_reg

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r14, rax

    sys_print_str imul_reg_msg, imul_reg_len
    mov rdi, r14
    call print_dec

    # =========================================================
    # 測試 3: IMUL 唯讀記憶體相乘 (imul rax, [mem_val])
    # 記憶體位址為獨立常數，快取載入與乘法器管線重疊
    # =========================================================
    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax

    mov rax, 1
    mov ecx, ITERS
.Lloop_imul_mem:
    .rept 10
    imul rax, [mem_val]
    .endr
    dec ecx
    jnz .Lloop_imul_mem

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r14, rax

    sys_print_str imul_mem_msg, imul_mem_len
    mov rdi, r14
    call print_dec

    # =========================================================
    # 測試 4: IMUL Store-to-Load Forwarding 記憶體真實相依
    # 強制將上一輪的 rax 寫入記憶體，再由 IMUL 讀回，測量 Store Forwarding 懲罰
    # =========================================================
    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax

    mov rax, 3
    mov ecx, ITERS
.Lloop_imul_fwd:
    .rept 10
    mov [mem_fwd], rax
    imul rax, [mem_fwd]
    add rax, 2              # 保證持續為奇數，永不歸零
    .endr
    dec ecx
    jnz .Lloop_imul_fwd

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r14, rax

    sys_print_str imul_fwd_msg, imul_fwd_len
    mov rdi, r14
    call print_dec

    # =========================================================
    # 測試 5: MUL 傳統無號暫存器相乘 (mul rbx)
    # =========================================================
    mov rbx, 3

    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax

    mov rax, 1
    mov ecx, ITERS
.Lloop_mul_reg:
    .rept 10
    mul rbx                 # rax = rax * 3 (rdx 存高位)
    .endr
    dec ecx
    jnz .Lloop_mul_reg

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r14, rax

    sys_print_str mul_reg_msg, mul_reg_len
    mov rdi, r14
    call print_dec

    # =========================================================
    # 測試 6: MULX (BMI2) 暫存器相乘 (mulx r8, rdx, rbx)
    # 隱含輸入為 rdx，低 64 位輸出至 rdx 以維持相依鏈
    # =========================================================
    mov rbx, 3

    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax

    mov rdx, 1              # rdx = 初始值
    mov ecx, ITERS
.Lloop_mulx_reg:
    .rept 10
    mulx r8, rdx, rbx       # rdx = (rdx * rbx) 的低 64 位元
    .endr
    dec ecx
    jnz .Lloop_mulx_reg

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r14, rax

    sys_print_str mulx_reg_msg, mulx_reg_len
    mov rdi, r14
    call print_dec

    # =========================================================
    # 測試 7: MULX (BMI2) 唯讀記憶體相乘 (mulx r8, rdx, [mem_val])
    # =========================================================
    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax

    mov rdx, 1
    mov ecx, ITERS
.Lloop_mulx_mem:
    .rept 10
    mulx r8, rdx, [mem_val]
    .endr
    dec ecx
    jnz .Lloop_mulx_mem

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r14, rax

    sys_print_str mulx_mem_msg, mulx_mem_len
    mov rdi, r14
    call print_dec

    sys_exit 0
