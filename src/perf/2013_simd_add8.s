.intel_syntax noprefix
.global _start

.include "system.inc"
.include "print.inc"

# -------------------------------------------------------------
# 基準測試重複次數 (1,000,000 次 / 1M iters)
# -------------------------------------------------------------
.equ ITERS, 1000000

.section .data
.align 32
vec_a: .long 1, 2, 3, 4, 5, 6, 7, 8
vec_b: .long 10, 20, 30, 40, 50, 60, 70, 80

title_msg:
    .ascii "=== 8-Integer Addition Benchmark (1M iters) ===\n"
.equ title_len, . - title_msg

msg_scalar:
    .ascii "1. Scalar (8x add):   "
.equ len_scalar, . - msg_scalar

msg_sse:
    .ascii "2. SSE (2x paddd):    "
.equ len_sse, . - msg_sse

msg_avx2:
    .ascii "3. AVX2 (1x vpaddd):  "
.equ len_avx2, . - msg_avx2

.section .text

# =============================================================
# 1. 普通純量加法 (Scalar): 8 次 32-bit add
# 每次迭代需 16 次 load (8x vec_a + 8x vec_b) 與 8 次 ALU add
# =============================================================
bench_scalar:
    mov r8, ITERS
.L_scalar_loop:
    mov eax, [vec_a]
    add eax, [vec_b]
    mov ebx, [vec_a + 4]
    add ebx, [vec_b + 4]
    mov ecx, [vec_a + 8]
    add ecx, [vec_b + 8]
    mov edx, [vec_a + 12]
    add edx, [vec_b + 12]
    mov esi, [vec_a + 16]
    add esi, [vec_b + 16]
    mov edi, [vec_a + 20]
    add edi, [vec_b + 20]
    mov r9d, [vec_a + 24]
    add r9d, [vec_b + 24]
    mov r10d, [vec_a + 28]
    add r10d, [vec_b + 28]
    dec r8
    jnz .L_scalar_loop
    ret

# =============================================================
# 2. SSE 向量加法 (128-bit): 2 次 paddd (每次算 4 個 int)
# 每次迭代需 4 次 128-bit load 與 2 次 SIMD paddd
# =============================================================
bench_sse:
    mov r8, ITERS
.L_sse_loop:
    movdqa xmm0, [vec_a]
    paddd  xmm0, [vec_b]
    movdqa xmm1, [vec_a + 16]
    paddd  xmm1, [vec_b + 16]
    dec r8
    jnz .L_sse_loop
    ret

# =============================================================
# 3. AVX2 向量加法 (256-bit): 1 次 vpaddd (一次算 8 個 int)
# 每次迭代僅需 2 次 256-bit load 與 1 次 SIMD vpaddd
# =============================================================
bench_avx2:
    mov r8, ITERS
.L_avx2_loop:
    vmovdqa ymm0, [vec_a]
    vpaddd  ymm0, ymm0, [vec_b]
    dec r8
    jnz .L_avx2_loop
    vzeroupper
    ret

# =============================================================
# 主程式進入點
# =============================================================
_start:
    # 預熱 CPU 管線與快取，穩定工作時脈
    mov r8, 50000
.L_warm:
    dec r8
    jnz .L_warm

    sys_print_str title_msg, title_len

    # --- 測量 1: 普通加法 (Scalar) ---
    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax

    call bench_scalar

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r13, rax           # r13 = Scalar 耗費週期

    # --- 測量 2: 2 次 SSE 加法 ---
    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax

    call bench_sse

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r14, rax           # r14 = SSE 耗費週期

    # --- 測量 3: 1 次 AVX2 加法 ---
    rdtscp
    shl rdx, 32
    or rax, rdx
    mov r12, rax

    call bench_avx2

    rdtscp
    shl rdx, 32
    or rax, rdx
    sub rax, r12
    mov r15, rax           # r15 = AVX2 耗費週期

    # 輸出結果
    sys_print_str msg_scalar, len_scalar
    mov rdi, r13
    call print_dec

    sys_print_str msg_sse, len_sse
    mov rdi, r14
    call print_dec

    sys_print_str msg_avx2, len_avx2
    mov rdi, r15
    call print_dec

    sys_exit 0
