.ifndef _TIME_INC_
.equ _TIME_INC_, 1

# ==============================================================================
# 時間測量與 CPU 週期計時巨集庫 (Hardware TSC Benchmarking Utilities)
#
# 原理說明:
#   利用 x86 硬體時間戳計數器 (TSC, Time-Stamp Counter) 進行極低延遲、
#   奈秒級精度的時脈週期測量。
#
#   依據 Intel 最佳化參考手冊 (Intel 64 and IA-32 Architectures Optimization
#   Reference Manual) 推薦之黃金序列，使用雙向序列化屏障，消除現代亂序
#   超純量 CPU (Out-of-Order Execution) 的推測執行與指令重排雜訊。
# ==============================================================================

# ------------------------------------------------------------------------------
# 巨集名稱: perf_start (標準 CPU 週期測量起點)
# 參數:
#   \out_reg : 儲存起始 64-bit TSC 的暫存器 (預設為 rax)
# 說明:
#   依據 Intel 黃金序列使用 lfence + rdtsc + lfence 雙重屏障:
#   1. 第一道 lfence: 強制等待所有先前的指令全數 Retire。
#   2. rdtsc: 採樣起始時間戳至 edx:eax。
#   3. 第二道 lfence: 關鍵防線！徹底阻斷受測代碼提前推測執行 (防向前偷跑)。
#   4. 自動合成 64-bit TSC 並存入指定暫存器 out_reg。
# 破壞暫存器:
#   rax, rdx (以及 \out_reg)
# ------------------------------------------------------------------------------
.macro perf_start out_reg=rax
    lfence
    rdtsc
    lfence
    shl rdx, 32
    or rax, rdx
    .ifnc \out_reg, rax
    mov \out_reg, rax
    .endif
.endm

# ------------------------------------------------------------------------------
# 巨集名稱: perf_end (標準 CPU 週期測量終點)
# 參數:
#   \out_reg   : 儲存測量結果的暫存器 (預設為 rax)
#   \start_reg : (選填) 起始 64-bit TSC 暫存器；若提供則自動計算 Delta = End - Start
# 說明:
#   使用 rdtscp + lfence 序列化收尾:
#   1. rdtscp: 等待受測代碼所有指令全數退休後，採樣結束時間 (edx:eax) 與 Core ID (ecx)。
#   2. lfence: 阻斷後續無關代碼倒灌進受測區間。
#   3. 若有傳入 \start_reg，自動以 sub rax, \start_reg 算出耗費時脈週期 (Delta)。
# 破壞暫存器:
#   rax, rdx, ecx (以及 \out_reg)
# ------------------------------------------------------------------------------
.macro perf_end out_reg=rax, start_reg
    rdtscp
    lfence
    shl rdx, 32
    or rax, rdx
    .ifnb \start_reg
    sub rax, \start_reg
    .endif
    .ifnc \out_reg, rax
    mov \out_reg, rax
    .endif
.endm

.endif # _TIME_INC_
