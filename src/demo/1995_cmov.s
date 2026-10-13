.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel CMOVcc (Conditional Move, 條件搬移指令)
#
# 歷史背景:
#   Intel 於 Pentium Pro 架構 (1995, P6 微架構) 首次引入 CMOVcc 指令族。
#
# 核心痛點: 分支預測失敗的昂貴代價 (Branch Misprediction Penalty):
#   現代高效能超純量 CPU 具備深度管線 (Pipeline Depth 達 14~20 級以上)。
#   使用傳統條件跳躍 (如 je, jne, jg, jl) 時:
#     - CPU 的分支預測器 (Branch Predictor) 必須猜測執行路徑並進行投機執行 (Speculative Execution)。
#     - 若分支規律隨機或難以預測 (例如快速排序 quicksort 分割、二分搜尋 binary search)，
#       一旦預測失敗，CPU 必須清空整條管線 (Pipeline Flush) 並重新載入正確路徑，
#       每次懲罰高達 15 ~ 20 個時脈週期！
#
# CMOVcc 的架構革新:
#   - 無分支無跳躍 (Branchless): 指令順序流動，管線永遠不會中斷。
#   - 依據 EFLAGS 狀態旗標 (ZF, CF, SF, OF 等) 條件式地決定是否覆寫目的暫存器。
#   - 常見指令族:
#     * CMOVA / CMOVBE : 無號大於 / 無號小於等於 (依賴 CF, ZF)
#     * CMOVE / CMOVNE : 等於 / 不等於 (依賴 ZF)
#     * CMOVG / CMOVLE : 有號大於 / 有號小於等於 (依賴 SF, OF, ZF)
#     * CMOVS / CMOVNS : 負數 / 非負數 (依賴 SF)
#
# 權衡與最佳實踐:
#   - 適合: 難以預測的隨機資料比較、MIN/MAX 算子、無分支演算法。
#   - 不適合: 預測成功率極高 (如 99% 以上) 的迴圈終止判斷，或計算來源代價昂貴的運算。
# =============================================================

.data
header_msg: .ascii "=== Intel CMOVcc (無分支條件搬移展示) ===\n"
.equ header_len, . - header_msg

test1_msg:  .ascii "[測試 1] 條件成立 (10 == 10)，CMOVE 成功覆寫目標: "
.equ test1_len, . - test1_msg

test2_msg:  .ascii "[測試 2] 條件不成立 (10 != 20)，CMOVE 保持原值不變: "
.equ test2_len, . - test2_msg

test3_msg:  .ascii "[測試 3] 有號數大於比較 (85 > 50)，CMOVG 選取最大值 (MAX): "
.equ test3_len, . - test3_msg

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 測試 1: 條件成立的情況 (Equal, ZF = 1)
    # ---------------------------------------------------------
    mov eax, 10             # 目標暫存器初始值 = 10
    mov edx, 42             # 待搬移來源候選值 = 42
    cmp eax, 10             # 比較 10 與 10，結果相等，ZF = 1
    cmove eax, edx          # 條件成立: eax 被賦值為 edx (42)
    mov r12d, eax           # 保存

    sys_print_str test1_msg, test1_len
    mov edi, r12d
    call print_dec          # 印出 42

    # ---------------------------------------------------------
    # 測試 2: 條件不成立的情況 (Not Equal, ZF = 0)
    # ---------------------------------------------------------
    mov ebx, 100            # 目標暫存器初始值 = 100
    mov ecx, 999            # 待搬移來源候選值 = 999
    cmp ebx, 20             # 比較 100 與 20，不相等，ZF = 0
    cmove ebx, ecx         # 條件不成立: ebx 保持原值 100
    mov r13d, ebx           # 保存

    sys_print_str test2_msg, test2_len
    mov edi, r13d
    call print_dec          # 印出 100

    # ---------------------------------------------------------
    # 測試 3: 實現 Branchless MAX(a, b) 運算 (使用 CMOVG)
    # ---------------------------------------------------------
    mov r8d, 50             # a = 50
    mov r9d, 85             # b = 85
    mov eax, r8d            # 預設 max = a (50)
    cmp r9d, r8d            # 比較 b 與 a (85 > 50)
    cmovg eax, r9d          # 若 b > a，則 max = b (85)
    mov r14d, eax           # 保存

    sys_print_str test3_msg, test3_len
    mov edi, r14d
    call print_dec          # 印出 85

    sys_exit 0
