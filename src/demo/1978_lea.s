.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel LEA (Load Effective Address, 載入有效位址)
#
# 歷史背景:
#   Intel 於 8086 (1978) 引入 LEA 指令。
#   在現代編譯器工程（GCC, Clang, Rustc, LLVM, JIT）後端代碼生成中，
#   LEA 是被運用得最淋漓盡致、最具戰略地位的「無旗標算術引擎」。
#
# 編譯器工程師眼中的 LEA 四大神技:
#   1. 硬體定址模式折疊 (Hardware Addressing Folding):
#      - x86 定址語法: [base + index * scale + displacement]
#      - scale 僅支援硬體快速移位值: 1, 2, 4, 8。
#      - LEA 本意為計算記憶體指標位址，但可直接作為非指標純數值的算術計算！
#
#   2. 非破壞性三操作數算術 (Non-Destructive 3-Operand Math):
#      - 傳統 x86 add 指令為雙操作數（破壞來源）: add eax, ebx (eax = eax + ebx)
#      - LEA 允許三操作數計算: lea edx, [eax + ebx*4 + 10]
#        單一指令、單一週期同時完成「乘 4 + 加暫存器 + 加立即數」且保留 eax 與 ebx 原值！
#
#   3. 零旗標污染 (Zero EFLAGS Clobber):
#      - add, sub, imul, shl 都會更新 CPU 狀態旗標 (ZF, CF, SF, OF)。
#      - LEA 完全「不觸碰任何 EFLAGS 旗標」！
#      - 編譯器可將 LEA 算術安全地插入在 cmp 與 jcc 分支跳躍之間，完全不破壞比較結果。
#
#   4. 高速常數乘法合成 (Multiplication by Constants Without MUL/IMUL):
#      - 乘法器延遲較高 (imul 約 3 週期)，而 LEA 僅需 1 週期。
#      - 編譯器將常數乘法最佳化為 LEA 鏈:
#        * x * 3  -> lea eax, [rax + rax*2]
#        * x * 5  -> lea eax, [rax + rax*4]
#        * x * 9  -> lea eax, [rax + rax*8]
#        * x * 45 -> (x * 9) * 5 (僅需 2 條 LEA 指令！)
#
#   5. 位置無關代碼 (PIC / PIE) 的 RIP 相對定址:
#      - 現代 Linux 執行檔強制開啟 PIE (Position Independent Executable)。
#      - 編譯器存取全域變數或字串時，皆使用: lea rdi, [rip + label]。
# =============================================================

.data
header_msg: .ascii "=== Intel LEA (編譯器核心算術折疊與無旗標運算) ===\n"
.equ header_len, . - header_msg

test1_msg:  .ascii "[測試 1: 三操作數折疊] (10 + 20*4 + 15) = "
.equ test1_len, . - test1_msg

test2_msg:  .ascii "[測試 2: LEA 快速常數乘法] 7 * 45 = "
.equ test2_len, . - test2_msg

test3_msg:  .ascii "[測試 3: 旗標保護驗證] CMP 後執行 LEA，ZF 保持不變 (成功跳躍)!\n"
.equ test3_len, . - test3_msg

.text
_start:
    # 輸出標題 (使用 RIP 相對定址)
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 測試 1: 三操作數算術折疊 (x + y*4 + 15)
    # ---------------------------------------------------------
    mov eax, 10             # base = 10
    mov ebx, 20             # index = 20
    # edx = 10 + 20*4 + 15 = 10 + 80 + 15 = 105
    lea edx, [eax + ebx*4 + 15]
    mov r12d, edx           # 保存至 callee-saved 暫存器，避免被 syscall 覆寫

    sys_print_str test1_msg, test1_len
    mov edi, r12d
    call print_dec          # 印出 105

    # ---------------------------------------------------------
    # 測試 2: 編譯器快速合成常數乘法 (7 * 45 = 315)
    # 45 = 9 * 5
    # ---------------------------------------------------------
    mov eax, 7              # x = 7
    lea eax, [eax + eax*8]  # eax = 7 * 9 = 63
    lea eax, [eax + eax*4]  # eax = 63 * 5 = 315
    mov r13d, eax           # 保存至 callee-saved 暫存器

    sys_print_str test2_msg, test2_len
    mov edi, r13d
    call print_dec          # 印出 315

    # ---------------------------------------------------------
    # 測試 3: 驗證 LEA 不修改 EFLAGS 狀態旗標
    # ---------------------------------------------------------
    mov ecx, 50
    cmp ecx, 50             # 比較 50 與 50，此時 ZF = 1

    # 在 cmp 與條件跳躍之間插入大量 LEA 算術運算
    lea r8d, [ecx + 100]    # 運算結果 150，但完全不改變 ZF！
    lea r9d, [r8d * 2]      # 運算結果 300，ZF 依然為 1！

    # 若 LEA 破壞了 ZF，此跳躍將失敗
    je .Lflag_preserved

    sys_exit 1

.Lflag_preserved:
    sys_print_str test3_msg, test3_len
    sys_exit 0
