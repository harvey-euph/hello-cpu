.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel FSGSBASE (使用者態快速段基底讀寫指令集)
#
# 歷史背景:
#   Intel 於 Ivy Bridge 微架構 (2012) 引入 FSGSBASE 指令集。
#   包含四條核心指令: RDFSBASE, RDGSBASE, WRFSBASE, WRGSBASE。
#
# 核心機制與架構痛點:
#   1. x86_64 段基底暫存器 (Segment Bases):
#      - 在 64 位元長模式 (Long Mode) 下，絕大多數段基底 (CS, DS, SS, ES) 被硬體強制為 0。
#      - 僅有 FS 與 GS 保留了完整的 64 位元線性基底位址 (透過 MSR 暫存器儲存)。
#      - 作業系統與 C 語言執行時期標準庫 (glibc / musl) 將 FS 基底位址專門用作:
#        * 執行緒本地儲存區 (Thread-Local Storage, TLS)
#        * 執行緒控制區塊 (Thread Control Block, TCB, 如 pthread 結構)
#
#   2. 傳統架構的效能瓶頸 (Syscall Overhead):
#      - 過去使用者空間 (Ring 3) 無法直接讀寫 MSR，若要切換 TLS 基底，
#        必須發起昂貴的作業系統系統呼叫 (Linux arch_prctl 系統呼叫)。
#      - 每次系統呼叫耗費數百個時脈週期，涉及 Ring 3 -> Ring 0 特權級切換。
#
#   3. FSGSBASE 的架構突破:
#      - 允許使用者態 (Ring 3) 在僅 1 ~ 3 個時脈週期內直接讀寫 FS/GS 基底！
#      - 徹底消除了核心切換負擔，為現代微執行緒 / 協程 (User-Level Green Threads / Fibers，
#        如 Go goroutine 排程器、Rust Tokio、Java Project Loom 虛擬執行緒)
#        提供了極致迅速的上下文切換 (Context Switch) 基礎。
# =============================================================

.data
header_msg: .ascii "=== Intel FSGSBASE (使用者空間段基底存取展示) ===\n"
.equ header_len, . - header_msg

fs_msg:     .ascii "當前執行緒 FS Base (TLS 指標位址): "
.equ fs_len, . - fs_msg

gs_msg:     .ascii "當前執行緒 GS Base (系統擴展位址): "
.equ gs_len, . - gs_msg

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 1. 讀取 FS 段基底 (RDFSBASE)
    #    在純獨立組合語言執行環境中 (無 glibc 初始化)，FS Base 預設通常為 0
    # ---------------------------------------------------------
    rdfsbase r12

    sys_print_str fs_msg, fs_len
    mov rdi, r12
    call print_hex

    # ---------------------------------------------------------
    # 2. 讀取 GS 段基底 (RDGSBASE)
    # ---------------------------------------------------------
    rdgsbase r13

    sys_print_str gs_msg, gs_len
    mov rdi, r13
    call print_hex

    sys_exit 0
