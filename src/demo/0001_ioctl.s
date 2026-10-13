.intel_syntax noprefix
.global _start

.include "system.inc"
.include "print.inc"

# =============================================================
# 程式說明: Linux sys_ioctl (I/O 控制系統呼叫與終端機視窗查詢)
#
# 核心機制與 POSIX 裝置控制 (Device Control):
#   1. 為什麼需要 ioctl?
#      - Unix/Linux 遵循「一切皆檔案 (Everything is a file)」的哲學。
#      - 然而標準的 sys_read 與 sys_write 僅能傳輸通用的位元組資料流，無法處理特定硬體
#        裝置的專屬設定（例如: 終端機解析度、網卡頻寬、音效卡取樣率、硬碟 SMART 狀態）。
#      - sys_ioctl (16 號系統呼叫) 是 Linux 核心提供給使用者空間與裝置驅動程式 (Device Driver)
#        進行硬體控制與專屬結構體交換的核心介面。
#
#   2. TIOCGWINSZ 請求碼 (Terminal I/O Get Window Size, 0x5413):
#      - 用於向 TTY / PTY (虛擬終端) 驅動程式查詢目前終端機視窗的大小。
#
#   3. Linux C 語言 struct winsize 結構體記憶體佈局:
#      struct winsize {
#          unsigned short ws_row;    // 偏移量 0..1 (2 bytes): 終端機列高 (Rows, 垂直文字行數)
#          unsigned short ws_col;    // 偏移量 2..3 (2 bytes): 終端機欄寬 (Columns, 水平字元數)
#          unsigned short ws_xpixel; // 偏移量 4..5 (2 bytes): 視窗水平像素寬度 (未使用時通常為 0)
#          unsigned short ws_ypixel; // 偏移量 6..7 (2 bytes): 視窗垂直像素高度 (未使用時通常為 0)
#      }; // 總大小: 8 位元組
#
#   4. 重定向 (Redirection) 容錯與 Fallback 機制:
#      - 當使用者執行 `./ioctl > output.txt` 或在 CI/CD 自動化環境執行時，STDOUT (fd=1)
#        會被重新指向一般磁碟檔案。對非 TTY 檔案發起 TIOCGWINSZ 會回傳 -ENOTTY (錯誤碼 -25)。
#      - 本範例實作了優雅的向下探測容錯鏈: STDOUT -> STDIN -> STDERR。
# =============================================================

.section .bss
    .lcomm win_size, 8

.section .rodata
header_msg:
    .ascii "=== Linux sys_ioctl (TIOCGWINSZ 終端機大小查詢) ===\n"
.equ header_len, . - header_msg

row_msg:
    .ascii "終端機列高 (Rows / 行數):   "
.equ row_len, . - row_msg

col_msg:
    .ascii "終端機欄寬 (Cols / 字元寬): "
.equ col_len, . - col_msg

not_tty_msg:
    .ascii "[ioctl 提示] 當前標準串流皆非 TTY (例如處於管線或重定向模式)，無法獲取視窗尺寸。\n"
.equ not_tty_len, . - not_tty_msg

.section .text
_start:
    # 1. 優先嘗試查詢 stdout (fd = 1)
    sys_ioctl STDOUT, TIOCGWINSZ, win_size
    test rax, rax
    jz .Lprint_info

    # 2. 若 stdout 被導向 (如管線 pipe)，嘗試查詢 stdin (fd = 0)
    sys_ioctl STDIN, TIOCGWINSZ, win_size
    test rax, rax
    jz .Lprint_info

    # 3. 若 stdin 也被導向，嘗試查詢 stderr (fd = 2)
    sys_ioctl STDERR, TIOCGWINSZ, win_size
    test rax, rax
    jz .Lprint_info

    # 4. 若皆非 TTY (例如測試環境中全面導向)，輸出提示並正常結束
    sys_print_str not_tty_msg, not_tty_len
    sys_exit 0

.Lprint_info:
    # 印出標題
    sys_print_str header_msg, header_len

    # 印出 Rows (行數)
    sys_print_str row_msg, row_len
    movzx edi, word ptr [rip + win_size]        # 取出 16-bit ws_row
    call print_dec                              # 印出十進位並換行

    # 印出 Cols (列數)
    sys_print_str col_msg, col_len
    movzx edi, word ptr [rip + win_size + 2]    # 取出 16-bit ws_col
    call print_dec                              # 印出十進位並換行

    sys_exit 0
