.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel CX16 (CMPXCHG16B - 128-bit 原子比較並交換)
#
# 歷史背景:
#   Intel 於 64-bit 時代 (Prescott / Nocona 架構) 引入 CMPXCHG16B 指令 (CPUID 特徵旗標 cx16)。
#
# 核心機制 (128-bit Atomic Compare-and-Swap, 128-bit CAS):
#   - 運算元規範:
#     * 期望值 (Expected): rdx:rax (rax 為低 64 位元，rdx 為高 64 位元)
#     * 新數值 (New):      rcx:rbx (rbx 為低 64 位元，rcx 為高 64 位元)
#     * 目標記憶體:        [m128] (必須為 16-byte 對齊)
#   - 運作邏輯:
#     1. CPU 比較記憶體 [m128] 與 rdx:rax:
#     2. 若相等 (Match):
#        - 設定 ZF = 1
#        - 將 rcx:rbx 原子寫入 [m128]
#     3. 若不相等 (Mismatch):
#        - 設定 ZF = 0
#        - 將 [m128] 當前的 128 位元實際值載入回 rdx:rax
#
# lock 前綴與快取一致性:
#   - 搭配 lock 前綴 (lock cmpxchg16b) 確保在多核心多處理器環境下，
#     利用 MESI 快取一致性協定或匯流排鎖定，保證「讀取-比較-寫入」為不可分割的原子操作。
#   - 記憶體位址必須 16 位元組對齊 (.align 16)，否則將觸發一般保護錯誤 (#GP)。
#
# 解決無鎖結構 (Lock-Free Data Structure) 的 ABA 問題:
#   - 傳統單一指標 64-bit CAS 容易遭受 ABA 問題 (節點被釋放又重新分配至同位址)。
#   - 使用 CMPXCHG16B 可將「64-bit 記憶體指標」與「64-bit 遞增版本計數器 (Tag)」
#     打包成 128 位元聯合體進行原子更新，徹底杜絕 ABA 問題！
# =============================================================

.data
header_msg: .ascii "=== Intel CX16 (128-bit 原子 CMPXCHG16B 展示) ===\n"
.equ header_len, . - header_msg

test1_msg:  .ascii "[測試 1: 期望值匹配] 128-bit CAS 成功寫入新值 (ZF = 1)\n"
.equ test1_len, . - test1_msg

val_low_msg:  .ascii "  -> 記憶體低 64 位元 (新值 = 99):  "
.equ val_low_len, . - val_low_msg

val_high_msg: .ascii "  -> 記憶體高 64 位元 (新值 = 100): "
.equ val_high_len, . - val_high_msg

test2_msg:  .ascii "[測試 2: 期望值不符] 128-bit CAS 寫入失敗 (ZF = 0)，自動載回目前值: "
.equ test2_len, . - test2_msg

.align 16
# 128-bit 測試目標: [0..7] = 10, [8..15] = 20
target_data:
    .quad 10    # 低 64-bit
    .quad 20    # 高 64-bit

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 測試 1: 期望值匹配的情況 (Expected = 10, 20)
    # ---------------------------------------------------------
    mov rax, 10             # Expected Low
    mov rdx, 20             # Expected High
    mov rbx, 99             # New Low
    mov rcx, 100            # New High

    lock cmpxchg16b [target_data]
    jnz .Lfailed_test1

    sys_print_str test1_msg, test1_len

    # 印出寫入後的新值
    sys_print_str val_low_msg, val_low_len
    mov rdi, [target_data]
    call print_dec          # 印出 99

    sys_print_str val_high_msg, val_high_len
    mov rdi, [target_data + 8]
    call print_dec          # 印出 100

    # ---------------------------------------------------------
    # 測試 2: 期望值不匹配的情況 (刻意傳入錯誤的 Expected = 0, 0)
    # ---------------------------------------------------------
    mov rax, 0              # 錯誤的 Expected Low (實際值目前為 99)
    mov rdx, 0              # 錯誤的 Expected High (實際值目前為 100)
    mov rbx, 888            # 欲寫入的新值
    mov rcx, 999

    lock cmpxchg16b [target_data]
    jz .Lfailed_test2       # 若 ZF = 1 則表示意外成功

    # 由於匹配失敗，硬體會將記憶體當前值載入 rdx:rax
    mov r12, rax            # r12 = 記憶體目前的低 64 位元 (99)

    sys_print_str test2_msg, test2_len
    mov rdi, r12
    call print_dec          # 印出 99

    sys_exit 0

.Lfailed_test1:
.Lfailed_test2:
    sys_exit 1
