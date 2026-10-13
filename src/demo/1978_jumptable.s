.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel 間接跳躍與跳躍表 (Indirect Jump & Jump Table)
#
# 歷史背景:
#   Intel 於 8086 (1978) 引入基於暫存器與記憶體的間接跳躍指令 (jmp [reg/mem])。
#   這是所有現代編譯器將 C / C++ / Rust 的 switch-case 語句最佳化為 O(1)
#   常數時間分派 (Constant-Time Dispatch) 的最核心機制。
#
# 編譯器工程師的 Switch-Case 降級策略 (Lowering Strategies):
#   1. 稀疏分支 (Sparse Cases, 如 case 1, case 1000, case 50000):
#      - 若數值分散，編譯器生成二元搜尋決策樹 (Balanced Binary Decision Tree)，
#        透過多層 cmp + jg/jl 進行 O(log N) 比對。
#
#   2. 密集分支 (Dense Cases, 如 case 0, 1, 2, 3...):
#      - 若數值連續或緊密，編譯器會在唯讀資料段 (.rodata) 產生一個「跳躍表 (Jump Table)」。
#      - 每個表格項為 64-bit 程式標籤位址 (Quadword Address)。
#      - 執行流程只需三步:
#        步驟 1: 邊界檢查 (Range Check)
#                cmp edi, MAX_CASE
#                ja  .Ldefault_case     # 超出範圍直接跳預設分支
#        步驟 2: 計算跳躍表相對位址
#                lea rdx, [rip + .Ljump_table]
#        步驟 3: 間接跳躍 (O(1) 瞬間到達對應程式區塊)
#                jmp [rdx + rdi*8]
#
# 現代架構優勢:
#   - 消除大量級聯 if-else (Cascading Branches) 的分支預測器負擔。
#   - 配合 CPU 內部的間接分支預測器 (BTB - Branch Target Buffer)，可達成極高的預測命中率。
# =============================================================

.section .rodata
header_msg: .ascii "=== Intel Indirect JMP (編譯器 Switch-Case 跳躍表展示) ===\n"
.equ header_len, . - header_msg

case0_msg:  .ascii "[Switch 分派] 命中 Case 0 -> 執行加法 (10 + 20 = 30)\n"
.equ case0_len, . - case0_msg

case1_msg:  .ascii "[Switch 分派] 命中 Case 1 -> 執行乘法 (10 * 20 = 200)\n"
.equ case1_len, . - case1_msg

case2_msg:  .ascii "[Switch 分派] 命中 Case 2 -> 執行位元 XOR (10 ^ 20 = 30)\n"
.equ case2_len, . - case2_msg

default_msg: .ascii "[Switch 分派] 命中 Default -> 輸入超出範圍 (無效操作碼)\n"
.equ default_len, . - default_msg

# 編譯器生成的跳躍表: 存放各個 case 處理標籤的絕對位址
.align 8
jump_table:
    .quad .Lcase_0
    .quad .Lcase_1
    .quad .Lcase_2

.equ MAX_CASE, 2

.section .text
_start:
    sys_print_str header_msg, header_len

    # 模擬 switch(op): 測試 op = 1 (預期命中 Case 1 乘法)
    mov edi, 1
    call dispatch_switch

    # 模擬 switch(op): 測試 op = 2 (預期命中 Case 2 XOR)
    mov edi, 2
    call dispatch_switch

    # 模擬 switch(op): 測試 op = 99 (預期命中 Default)
    mov edi, 99
    call dispatch_switch

    sys_exit 0

# =============================================================
# 函式名稱: dispatch_switch
# 輸入: edi = switch 選擇子 (0, 1, 2...)
# =============================================================
dispatch_switch:
    # 1. 邊界檢查 (防止記憶體越界讀取 jump_table)
    cmp edi, MAX_CASE
    ja .Ldefault_handler    # 無號數比較，小於 0 (負數) 或大於 MAX_CASE 皆會跳躍

    # 2. 透過 RIP-relative 尋址取得跳躍表基底
    lea rdx, [rip + jump_table]

    # 3. 間接跳躍至目標 handler: jmp [rdx + rdi*8]
    movsxd rdi, edi         # 符號擴展至 64-bit
    jmp [rdx + rdi * 8]

.Lcase_0:
    sys_print_str case0_msg, case0_len
    ret

.Lcase_1:
    sys_print_str case1_msg, case1_len
    ret

.Lcase_2:
    sys_print_str case2_msg, case2_len
    ret

.Ldefault_handler:
    sys_print_str default_msg, default_len
    ret
