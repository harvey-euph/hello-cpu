.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel XADD (Exchange and Add, 交換並相加與原子 Fetch-Add)
#
# 歷史背景:
#   Intel 於 80486 (1989) 引入 XADD 指令。
#   這是現代並行程式設計與編譯器後端生成 C++11 std::atomic::fetch_add
#   與 Rust Atomic::fetch_add 的最核心專屬硬體指令。
#
# 核心機制 (Exchange and Add):
#   - 語法: xadd dest, src  (通常 dest 為記憶體 [mem]，src 為暫存器 reg)
#   - 執行邏輯:
#     1. 暫存器 reg 取得 dest 原本的「舊數值 (Old Value)」。
#     2. 記憶體 dest 被寫入「舊數值 + 增量 (New Value = Old + Increment)」。
#
# lock 前綴與快取一致性 (Atomic Fetch-Add):
#   - 當搭配 lock 前綴時: lock xadd [counter], rax
#   - CPU 透過 MESI 快取一致性協定鎖定該快取行 (Cache Line Lock)，保證:
#     1. 記憶體讀取、數值相加、舊值傳回、新值寫入為「完全不可分割的原子操作 (Atomic RMW)」。
#     2. 自帶完整記憶體屏障 (Full Memory Barrier / Sequentially Consistent)，防止指令重排。
#
# 編譯器熱點應用:
#   - 智慧指標原子引用計數 (Thread-Safe Reference Counting, 如 std::shared_ptr, Rust Arc::clone)。
#   - 無鎖佇列 (Lock-Free Work-Stealing Queue) 與 票券自旋鎖 (Ticket Spinlock)。
#   - 高效能並行記憶體分配器 (jemalloc / tcmalloc 執行緒快取統計)。
# =============================================================

.data
header_msg: .ascii "=== Intel XADD (原子 Fetch-and-Add / std::atomic 核心) ===\n"
.equ header_len, . - header_msg

old_msg:    .ascii "[原子 Fetch-Add] 暫存器取得舊值 (Old Value = 100): "
.equ old_msg_len, . - old_msg

new_msg:    .ascii "[原子 Fetch-Add] 記憶體更新為新值 (New Value = 115): "
.equ new_msg_len, . - new_msg

.align 8
atomic_counter:
    .quad 100               # 共享計數器初始值 = 100

.text
_start:
    sys_print_str header_msg, header_len

    # 模擬 C++11: counter.fetch_add(15);
    # 預期: 回傳舊值 100，記憶體更新為 115
    mov rax, 15             # 欲累加的步進值 (Delta = 15)

    # 執行原子交換並累加
    lock xadd [atomic_counter], rax

    # 此時: rax 存放累加前的舊值 (100)，記憶體存放 100 + 15 = 115
    mov r12, rax            # 保存舊值至 callee-saved 暫存器
    mov r13, [atomic_counter] # 取出記憶體新值

    # 印出舊值
    sys_print_str old_msg, old_msg_len
    mov rdi, r12
    call print_dec          # 印出 100

    # 印出新值
    sys_print_str new_msg, new_msg_len
    mov rdi, r13
    call print_dec          # 印出 115

    sys_exit 0
