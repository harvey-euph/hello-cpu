.intel_syntax noprefix
.global _start
.include "system.inc"

# =============================================================
# 程式說明: Linux x86_64 標準輸入輸出回顯 (Echo & POSIX Syscall)
#
# 核心機制與 Linux x86_64 系統呼叫慣例 (ABI Specification):
#   1. 系統呼叫參數暫存器傳遞規範:
#      - 系統呼叫編號 (Syscall Number): rax
#      - 第 1 參數: rdi
#      - 第 2 參數: rsi
#      - 第 3 參數: rdx
#      - 第 4 參數: r10 (注意: 使用者函式呼叫 ABI 為 rcx，但 syscall 會覆寫 rcx，故改用 r10)
#      - 第 5 參數: r8
#      - 第 6 參數: r9
#
#   2. 暫存器破壞規範 (Clobber Rule):
#      - 執行 syscall 指令時，CPU 硬體會強制破壞:
#        * rcx: 儲存系統呼叫返回時的使用者空間指令位址 (RIP)
#        * r11: 儲存進入核心前的旗標狀態 (RFLAGS)
#        * rax: 儲存系統呼叫的傳回值 (正數為成功字節數，負數為 -errno 錯誤碼)
#
#   3. 標準串流檔案描述符 (File Descriptors):
#      - 0: STDIN  (標準輸入，鍵盤輸入或管線來源)
#      - 1: STDOUT (標準輸出，終端螢幕)
#      - 2: STDERR (標準錯誤輸出)
#
#   4. EOF (End-of-File) 處理機制:
#      - 當使用者在終端按下 Ctrl+D 或輸入串流結束時，sys_read (0 號呼叫) 回傳 0。
#      - 程式應檢測 rax <= 0 並正常結束，避免無窮迴圈或未定義行為。
# =============================================================

.equ BUF_SIZE, 128

.section .bss
    .lcomm buffer, BUF_SIZE

.section .rodata
header_msg:
    .ascii "=== Linux Syscall (標準輸入讀取與回顯展示) ===\n"
.equ header_len, . - header_msg

prompt_msg:
    .ascii "[echo] 請輸入文字 (按 Enter 送出，或 Ctrl+D 結束): "
.equ prompt_len, . - prompt_msg

echo_prefix:
    .ascii "-> 接收到的內容 (Echo): "
.equ prefix_len, . - echo_prefix

eof_msg:
    .ascii "[偵測到 EOF / 空輸入，正常結束]\n"
.equ eof_msg_len, . - eof_msg

.section .text
_start:
    # 輸出標題
    sys_print_str header_msg, header_len

    # 1. 輸出提示訊息到 stdout
    sys_print_str prompt_msg, prompt_len

    # 2. 透過 sys_read (syscall 0) 從 stdin 讀取用戶輸入
    #    rax = sys_read(fd=0, buf=buffer, count=BUF_SIZE)
    sys_read buffer, BUF_SIZE

    # 3. 檢查讀取結果:
    #    rax > 0 : 成功讀取的位元組數 (包含尾隨換行符 '\n')
    #    rax == 0: 遇到 EOF (Ctrl+D)
    #    rax < 0 : 讀取發生錯誤
    cmp rax, 0
    jle .handle_eof

    # 將實際讀取的字節數存入 r12 (callee-saved)，避免被後續 syscall 覆寫
    mov r12, rax

    # 4. 輸出前綴字串
    sys_print_str echo_prefix, prefix_len

    # 5. 回顯剛剛從 stdin 讀入的內容 (含尾隨換行符號)
    sys_print_str buffer, r12

    sys_exit 0

.handle_eof:
    sys_print_str eof_msg, eof_msg_len
    sys_exit 0
