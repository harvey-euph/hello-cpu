.ifndef _SYSTEM_INC_
.equ _SYSTEM_INC_, 1

# -------------------------------------------------------------
# Linux x86_64 常用系統呼叫號碼 (Syscall Numbers)
# -------------------------------------------------------------
.equ SYS_READ,      0
.equ SYS_WRITE,     1
.equ SYS_IOCTL,     16
.equ SYS_NANOSLEEP, 35
.equ SYS_EXIT,      60

# 常用檔案描述符 (File Descriptors)
.equ STDIN,     0
.equ STDOUT,    1
.equ STDERR,    2

# 終端機相關 ioctl 請求代碼 (Terminal ioctl requests)
.equ TIOCGWINSZ, 0x5413

# -------------------------------------------------------------
# 巨集名稱: sys_ioctl
# 參數:
#   \fd  : 檔案描述符 (如 STDOUT)
#   \cmd : 請求代碼 (如 TIOCGWINSZ)
#   \arg : 參數指標或位址標籤
# 說明: 
#   使用 Linux sys_ioctl (16) 系統呼叫對裝置或檔案進行 I/O 控制。
#   回傳值儲存於 rax (0 表示成功，負數表示錯誤碼)。
# -------------------------------------------------------------
.macro sys_ioctl fd, cmd, arg
    mov edi, \fd
    mov esi, \cmd
    lea rdx, \arg
    mov eax, SYS_IOCTL
    syscall
.endm

# -------------------------------------------------------------
# 巨集名稱: sys_read
# 參數:
#   \buf_ptr : 接收輸入資料的緩衝區標籤或記憶體位址
#   \buf_len : 欲讀取的最大位元組數 (count)
# 說明: 
#   使用 Linux sys_read (0) 系統呼叫從標準輸入 (stdin) 讀取資料。
#   執行完成後，rax 會回傳實際讀取的位元組數 (bytes read)；
#   若 rax == 0 表示遇到 EOF (如 Ctrl+D)；若 rax < 0 表示錯誤。
# -------------------------------------------------------------
.macro sys_read buf_ptr, buf_len
    lea rsi, \buf_ptr      # rsi: 指向接收緩衝區
    mov rdx, \buf_len      # rdx: 最大讀取位元組數 (count)
    mov edi, STDIN         # rdi: 檔案描述符 (0 = stdin)
    mov eax, SYS_READ      # rax: 系統呼叫編號 (0 = sys_read)
    syscall                # 發起系統呼叫
.endm

# -------------------------------------------------------------
# 巨集名稱: sys_print_str
# 參數:
#   \str_ptr : 字串標籤或記憶體位址
#   \str_len : 字串長度（位元組數）
# 說明: 向標準輸出 (stdout) 印出指定長度之字串
# -------------------------------------------------------------
.macro sys_print_str str_ptr, str_len
    lea rsi, \str_ptr      # rsi: 指向字串資料緩衝區
    mov rdx, \str_len      # rdx: 寫入的位元組數 (count)
    mov edi, STDOUT        # rdi: 檔案描述符 (1 = stdout)
    mov eax, SYS_WRITE     # rax: 系統呼叫編號 (1 = sys_write)
    syscall                # 發起系統呼叫
.endm

# -------------------------------------------------------------
# 巨集名稱: sys_sleep_ms
# 參數:
#   \ms : 欲暫停的毫秒數 (整數立即數或暫存器)
# 說明: 封裝 sleep_ms 函數呼叫，符合 x86_64 ABI 規範
# -------------------------------------------------------------
.macro sys_sleep_ms ms
    mov edi, \ms           # 將毫秒參數填入第 1 參數暫存器 edi
    call sleep_ms          # 呼叫 sleep_ms 函數
.endm

# -------------------------------------------------------------
# 巨集名稱: sys_exit
# 參數:
#   \exit_code : 欲傳回作業系統的狀態碼 (數字或暫存器)
# 說明: 呼叫 Linux 60 號系統呼叫結束程式
# -------------------------------------------------------------
.macro sys_exit exit_code
    mov edi, \exit_code    # 先將傳入的參數放進 edi 暫存器（引數前要加反斜線 \）
    mov eax, SYS_EXIT      # 載入 Linux 離開功能碼 (60)
    syscall                # 執行系統呼叫
.endm

.text
# =============================================================
# 函數名稱: sleep_ms
# 輸入: edi = 欲暫停的毫秒數 (ms)
# 說明:
#   使用 Linux sys_nanosleep (35) 系統呼叫暫停行程。
#   依據 System V AMD64 ABI 規範，caller-saved 暫存器 (rax, rcx, rdx, rsi, rdi, r11)
#   由呼叫端自行處理，函數內部在堆疊配置 struct timespec 並於結束後自動還原。
# =============================================================
sleep_ms:
    sub rsp, 16            # 配置 timespec (tv_sec: 8 bytes, tv_nsec: 8 bytes)
    mov eax, edi           # 載入毫秒數
    xor edx, edx
    mov ecx, 1000
    div ecx                # eax = 秒數 (tv_sec), edx = 剩餘毫秒數
    mov [rsp], rax         # 存入 tv_sec
    imul rdx, rdx, 1000000 # 轉為奈秒數 (1 ms = 1,000,000 ns)
    mov [rsp + 8], rdx     # 存入 tv_nsec
    lea rdi, [rsp]         # rdi: 指向 req struct timespec
    xor esi, esi           # rsi: rem = NULL
    mov eax, SYS_NANOSLEEP # rax: 35
    syscall                # 發起系統呼叫
    add rsp, 16            # 還原堆疊
    ret

.endif # _SYSTEM_INC_
