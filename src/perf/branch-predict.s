.intel_syntax noprefix
.global _start

.include "system.inc"
.include "print.inc"
.include "time.inc"

# ==============================================================================
# 效能評測: 分支預測效能基準測試 (Branch Prediction Benchmark)
#
# 評測原理:
#   現代高效能 CPU 具備深層管線 (Pipeline, 14~20+ 階) 與亂序執行引擎。
#   遇到條件分支 (Conditional Branch) 時，CPU 必須在取指 (Fetch) 階段就預測
#   分支是否跳轉 (Taken vs Not-Taken)。
#
#   - 預測成功 (Hit): 管線持續滿載運作，指令無縫執行 (約 1~2 cycles/元素)。
#   - 預測失敗 (Misprediction): 必須沖刷管線 (Pipeline Flush) 並撤銷投機指令，
#     在現代 x86 核心上伴隨極高的懲罰代價 (Misprediction Penalty, 約 15~20 cycles)。
#
# 評測設計:
#   1. 建立包含 1,024 個 32-bit 整數的陣列 (4 KB, 完全容納於 32 KB L1D 快取中，
#      徹底排除記憶體/快取 Miss 延遲干擾)。
#   2. 陣列填入 0~255 的隨機數值 (約 50% < 128, 約 50% >= 128)。
#   3. 對比三種情境 (重複 20,000 次，總計 20,480,000 次條件判斷):
#      [1] 已排序陣列 + 分支 (Sorted Array + Branch):
#          前半段全小於 128，後半段全大於等於 128。分支預測器命中率趨近 100%。
#      [2] 未排序陣列 + 分支 (Unsorted Array + Branch):
#          數值隨機交錯，分支方向不可預測，預測失誤率高達 ~50%，曝露巨大的 Penalty！
#      [3] 未排序陣列 + 無分支 (Unsorted Array + CMOVcc):
#          使用條件搬移指令 cmovge 替代條件跳轉，消除分支，時間不受資料分佈影響。
# ==============================================================================

.equ ARRAY_SIZE, 32768      # 陣列長度: 32,768 個元素 (128 KB, 完全容納於 256 KB L2 快取中)
.equ ITERS,      2000       # 迴圈重複次數: 2,000 次 (共 65,536,000 次條件操作)

.section .bss
.align 64
arr_unsorted:
    .space ARRAY_SIZE * 4   # 未排序陣列 (128 KB)

.align 64
arr_sorted:
    .space ARRAY_SIZE * 4   # 已排序陣列 (128 KB)

.align 64
count_table:
    .space 256 * 4          # 計數排序 (Counting Sort) 頻率表 (1 KB)

.section .data
title_msg:
    .ascii "=== Branch Prediction Performance Benchmark ===\n"
    .ascii "陣列大小: 32,768 個 32-bit 整數 (128 KB, 命中 L2 Cache，超出 BHT 記憶容量)\n"
    .ascii "重複次數: 2,000 次 (共 65,536,000 次條件判斷)\n\n"
.equ title_len, . - title_msg

msg_sorted:
    .ascii "[1] 已排序陣列 (Sorted Array + Branch):\n"
    .ascii "    時脈週期 (Cycles):   "
.equ len_sorted, . - msg_sorted

msg_unsorted:
    .ascii "[2] 未排序陣列 (Unsorted Array + Branch):\n"
    .ascii "    時脈週期 (Cycles):   "
.equ len_unsorted, . - msg_unsorted

msg_cmov:
    .ascii "[3] 未排序陣列 + 無分支 (Unsorted Array + CMOVcc):\n"
    .ascii "    時脈週期 (Cycles):   "
.equ len_cmov, . - msg_cmov

msg_verify:
    .ascii "    結果累加驗證 (Sum):  "
.equ len_verify, . - msg_verify

newline:
    .ascii "\n"

msg_penalty:
    .ascii "--- 效能分析總結 ---\n"
    .ascii "分支預測失敗懲罰 (Penalty Overhead): "
.equ len_penalty, . - msg_penalty

.section .text

# =============================================================
# 1. 條件分支版本 (Branch: cmp + jl)
# 輸入: rdi = 陣列位址
# 輸出: rax = 累加總和 (Sum)
# =============================================================
bench_branch:
    xor rax, rax            # sum = 0
    mov r8, ITERS
.L_bb_outer:
    xor edx, edx            # i = 0
.L_bb_inner:
    mov ecx, [rdi + rdx*4]  # 載入 arr[i] (自動零擴展至 rcx)
    cmp ecx, 128            # 判斷元素是否小於 128
    jl .L_bb_skip           # 條件分支: 若 < 128 則跳過累加 (此分支受預測器影響)
    add rax, rcx            # 若 >= 128 則累加
.L_bb_skip:
    inc edx
    cmp edx, ARRAY_SIZE
    jne .L_bb_inner

    dec r8
    jnz .L_bb_outer
    ret

# =============================================================
# 2. 無分支版本 (Branchless: cmp + cmovge)
# 輸入: rdi = 陣列位址
# 輸出: rax = 累加總和 (Sum)
# =============================================================
bench_cmov:
    xor rax, rax            # sum = 0
    mov r8, ITERS
.L_bc_outer:
    xor edx, edx            # i = 0
.L_bc_inner:
    mov ecx, [rdi + rdx*4]  # 載入 arr[i]
    xor r10d, r10d          # r10d = 0 (預設加 0)
    cmp ecx, 128
    cmovge r10d, ecx        # 若 ecx >= 128 則選取 ecx，否則保持 0
    add rax, r10            # 累加選取的數值 (無任何條件跳轉)

    inc edx
    cmp edx, ARRAY_SIZE
    jne .L_bc_inner

    dec r8
    jnz .L_bc_outer
    ret

# =============================================================
# 陣列初始化子常式:
# 使用線性同餘產生器 (LCG) 生成 32,768 個 0~255 的擬隨機數，
# 並透過計數排序 (Counting Sort) 在 O(N) 極速建立已排序陣列。
# =============================================================
init_arrays:
    push rbx                # 保存 Callee-saved 暫存器
    cld                     # 確保字串指令遞增

    # 步驟 1: 生成 32,768 個 0~255 的隨機數填入 arr_unsorted
    lea rdi, [arr_unsorted]
    mov rcx, ARRAY_SIZE
    mov eax, 123456789      # 初始種子 (固定種子保證每次執行結果一致)
    mov r8d, 1103515245     # LCG 乘數
    mov r9d, 12345          # LCG 增量
.L_gen_loop:
    imul eax, r8d
    add eax, r9d
    mov edx, eax
    shr edx, 16
    and edx, 0xff           # 取值範圍: 0 ~ 255
    mov [rdi], edx
    add rdi, 4
    dec rcx
    jnz .L_gen_loop

    # 步驟 2: 清空 count_table (256 個 dword)
    lea rdi, [count_table]
    xor eax, eax
    mov ecx, 256
    rep stosd

    # 步驟 3: 統計各數值出現頻率 (Histogram)
    lea rsi, [arr_unsorted]
    lea rdi, [count_table]
    mov rcx, ARRAY_SIZE
.L_hist_loop:
    mov edx, [rsi]
    inc dword ptr [rdi + rdx*4]
    add rsi, 4
    dec rcx
    jnz .L_hist_loop

    # 步驟 4: 依序重建有序數列至 arr_sorted (Counting Sort)
    lea rdi, [arr_sorted]
    xor ebx, ebx            # val = 0..255
.L_rebuild_val:
    cmp ebx, 256
    jge .L_sort_done
    mov ecx, [count_table + rbx*4]
    test ecx, ecx
    jz .L_rebuild_next
.L_rebuild_item:
    mov [rdi], ebx
    add rdi, 4
    dec ecx
    jnz .L_rebuild_item
.L_rebuild_next:
    inc ebx
    jmp .L_rebuild_val

.L_sort_done:
    pop rbx
    ret

# =============================================================
# 主程式進入點
# =============================================================
_start:
    # 1. 初始化資料集並排序
    call init_arrays

    # 2. 印出標頭說明
    sys_print_str title_msg, title_len

    # 3. 預熱管線與快取
    mov r8, 50000
.L_warmup:
    dec r8
    jnz .L_warmup

    # =========================================================
    # [測試 1] 已排序陣列 + 分支 (Sorted Array + Branch)
    # =========================================================
    perf_start r12

    lea rdi, [arr_sorted]
    call bench_branch

    mov r15, rax            # r15 = 排序版累加總和 (Sum)
    perf_end r13, r12       # r13 = 排序版耗費週期

    # 輸出測試 1 結果
    sys_print_str msg_sorted, len_sorted
    mov rdi, r13
    call print_dec
    sys_print_str msg_verify, len_verify
    mov rdi, r15
    call print_dec
    sys_print_str newline, 1

    # =========================================================
    # [測試 2] 未排序陣列 + 分支 (Unsorted Array + Branch)
    # =========================================================
    perf_start r12

    lea rdi, [arr_unsorted]
    call bench_branch

    mov r15, rax            # r15 = 未排序版累加總和 (Sum)
    perf_end r14, r12       # r14 = 未排序版耗費週期

    # 輸出測試 2 結果
    sys_print_str msg_unsorted, len_unsorted
    mov rdi, r14
    call print_dec
    sys_print_str msg_verify, len_verify
    mov rdi, r15
    call print_dec
    sys_print_str newline, 1

    # =========================================================
    # [測試 3] 未排序陣列 + 無分支 (Unsorted Array + CMOVcc)
    # =========================================================
    perf_start r12

    lea rdi, [arr_unsorted]
    call bench_cmov

    mov r15, rax            # r15 = CMOV 版累加總和 (Sum)
    perf_end r12, r12       # r12 = CMOV 版耗費週期

    # 輸出測試 3 結果
    sys_print_str msg_cmov, len_cmov
    mov rdi, r12
    call print_dec
    sys_print_str msg_verify, len_verify
    mov rdi, r15
    call print_dec
    sys_print_str newline, 1

    # =========================================================
    # [總結] 印出分支預測失敗懲罰 (Unsorted Cycles - Sorted Cycles)
    # =========================================================
    sys_print_str msg_penalty, len_penalty
    mov rax, r14
    sub rax, r13
    mov rdi, rax
    call print_dec
    sys_print_str newline, 1

    sys_exit 0
