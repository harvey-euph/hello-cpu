.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"
.include "time.inc"

# =============================================================
# 指令集說明: Intel/AMD RDTSCP (Read Time-Stamp Counter and Processor ID)
#
# 歷史背景:
#   AMD 於 2006 (Pacifico 核心) 首次引入，隨後 Intel 於 Nehalem (2008) 納入標準架構。
#   為現代高效能基準測試 (Microbenchmarking) 與超低延遲系統 (Low-Latency Trading)
#   必備的高精度計時指令。
#
# 核心機制與亂序執行陷阱 (Out-of-Order Execution Pitfalls):
#   1. 不變的時間戳計數器 (Invariant TSC):
#      - 現代 CPU 的 TSC 以恆定基準頻率遞增，不受動態節能調頻 (DVFS / SpeedStep)
#        或超頻 (Turbo Boost) 影響，提供精確的絕對時間測量基準。
#
#   2. RDTSC vs RDTSCP 關鍵差異:
#      - 傳統 RDTSC:
#        * 非串行化 (Non-Serializing): 現代 CPU 具備亂序執行 (Out-of-Order) 能力，
#          CPU 可能在被測程式碼尚未執行完畢前就「提前投機執行」RDTSC，導致測量誤差極大！
#        * 過去必須在前後插入肥重的 CPUID 指令強制管線清空。
#      - 優化版 RDTSCP:
#        * 具備半串行化保證 (Partially Serializing): 保證在 RDTSCP 之前的所有指令
#          全數退休 (Retired) 並提交至架構狀態後，才會讀取 TSC 計數器。
#
#   3. IA32_TSC_AUX 與核心遷移檢測 (Core Migration Detection):
#      - RDTSCP 在將 64-bit 計時數值寫入 EDX:EAX 的同時，會將 MSR IA32_TSC_AUX 寫入 ECX。
#      - Linux 核心會在此 MSR 填入 NUMA Node 與 CPU Core ID。
#      - 程式可藉此檢查兩次測量期間 thread 是否被作業系統排程器遷移至不同核心 (Cross-core Migration)，
#        確保時鐘測量的同步性與嚴謹度。
# =============================================================

.data
msg_title:  .ascii "=== RDTSCP 100ms 基準測試 (高精度時間戳與核心識別) ===\n"
.equ len_title, . - msg_title

msg_before: .ascii "測量前 TSC (Before): "
.equ len_before, . - msg_before

msg_after:  .ascii "測量後 TSC (After):  "
.equ len_after, . - msg_after

msg_diff:   .ascii "時脈週期增量 (Delta): "
.equ len_diff, . - msg_diff

msg_core:   .ascii "目前運行的 CPU Core:  "
.equ len_core, . - msg_core

.text
_start:
    sys_print_str msg_title, len_title

    # 1. 第一次讀取 TSC (使用標準 perf_start 巨集)
    perf_start r12

    # 2. 暫停 100 毫秒 (使用 sys_sleep_ms 巨集)
    sys_sleep_ms 100

    # 3. 第二次讀取 TSC 與 Core ID (使用標準 perf_end 巨集)
    perf_end r13
    mov r14d, ecx          # r14d = Core ID (IA32_TSC_AUX 來自 perf_end 中的 rdtscp)

    # 4. 印出 TSC Before
    sys_print_str msg_before, len_before
    mov rdi, r12
    call print_hex

    # 5. 印出 TSC After
    sys_print_str msg_after, len_after
    mov rdi, r13
    call print_hex

    # 6. 計算差距 (r13 - r12) 並印出
    sub r13, r12
    sys_print_str msg_diff, len_diff
    mov rdi, r13
    call print_hex

    # 7. 印出執行時的 Core ID (十進位)
    sys_print_str msg_core, len_core
    mov edi, r14d
    call print_dec

    sys_exit 0
