.intel_syntax noprefix
.global _start

.include "system.inc"
.include "print.inc"
.include "time.inc"

# -------------------------------------------------------------
# 基準測試重複次數 (100k 次)
# -------------------------------------------------------------
.equ ITERS, 100000

.section .data
.align 32
val_ymm: .long 1, 2, 3, 4, 5, 6, 7, 8
val_xmm: .long 1, 1, 1, 1

title_msg:
    .ascii "=== AVX-SSE Transition Penalty Benchmark (100k iters) ===\n"
.equ title_len, . - title_msg

msg_with:
    .ascii "WITH vzeroupper (cycles):    "
.equ len_with, . - msg_with

msg_without:
    .ascii "WITHOUT vzeroupper (cycles): "
.equ len_without, . - msg_without

msg_diff:
    .ascii "Penalty Overhead (cycles):   "
.equ len_diff, . - msg_diff

.section .text

# =============================================================
# 子模組 1: AVX2 256-bit 向量計算 (良好規範: 包含 vzeroupper)
# =============================================================
avx_clean:
    vmovaps ymm0, [val_ymm]
    vaddps  ymm0, ymm0, ymm0
    vzeroupper             # 清空 YMM 高 128 位元，重置硬體狀態為 Clean
    ret

# =============================================================
# 子模組 2: AVX2 256-bit 向量計算 (不良示範: 未清空，留下 dirty 狀態)
# =============================================================
avx_dirty:
    vmovaps ymm0, [val_ymm]
    vaddps  ymm0, ymm0, ymm0
    # 故意沒有 vzeroupper!
    ret

# =============================================================
# 子模組 3: 傳統 128-bit SSE (無 VEX 前綴) 運算
# 模擬呼叫未開啟 AVX 編譯的舊函式庫或第三方二進位程式
# =============================================================
legacy_sse_work:
    movaps  xmm1, [val_xmm]
    addps   xmm1, xmm1
    mulps   xmm1, xmm1
    addps   xmm1, xmm1
    mulps   xmm1, xmm1
    addps   xmm1, xmm1
    mulps   xmm1, xmm1
    addps   xmm1, xmm1
    ret

# =============================================================
# 函數 A: 有使用 vzeroupper 的迴圈 (呼叫 100k 次)
# =============================================================
func_with_vzero:
    mov rbx, ITERS
.L_loop_with:
    call avx_clean
    call legacy_sse_work
    dec rbx
    jnz .L_loop_with
    ret

# =============================================================
# 函數 B: 未使用 vzeroupper 的迴圈 (呼叫 100k 次)
# =============================================================
func_without_vzero:
    mov rbx, ITERS
.L_loop_without:
    call avx_dirty
    call legacy_sse_work
    dec rbx
    jnz .L_loop_without
    ret

# =============================================================
# 主程式進入點
# =============================================================
_start:
    # 1. 暖機 (Warm-up)：消除 CPU 初始降頻與冷快取干擾
    vzeroupper
    mov ecx, 30000
.L_warm:
    call avx_clean
    call legacy_sse_work
    dec ecx
    jnz .L_warm

    # 印出標題
    sys_print_str title_msg, title_len

    # ---------------------------------------------------------
    # 2. 外部計時測量：有使用 vzeroupper
    # ---------------------------------------------------------
    perf_start r12
    call func_with_vzero
    perf_end r14, r12      # r14 = 耗費 CPU cycles (WITH)

    # ---------------------------------------------------------
    # 3. 外部計時測量：未使用 vzeroupper
    # ---------------------------------------------------------
    vzeroupper             # 先清空以確保公平起跑
    perf_start r12
    call func_without_vzero
    perf_end r15, r12      # r15 = 耗費 CPU cycles (WITHOUT)

    vzeroupper             # 測量完畢清理

    # ---------------------------------------------------------
    # 4. 輸出測量數據與效能差距
    # ---------------------------------------------------------
    # 印出 WITH
    sys_print_str msg_with, len_with
    mov rdi, r14
    call print_dec

    # 印出 WITHOUT
    sys_print_str msg_without, len_without
    mov rdi, r15
    call print_dec

    # 計算並印出額外開銷 (Penalty = WITHOUT - WITH)
    sys_print_str msg_diff, len_diff
    mov rax, r15
    sub rax, r14
    mov rdi, rax
    call print_dec

    sys_exit 0
