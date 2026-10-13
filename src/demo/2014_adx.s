.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel ADX (Multi-Precision Add-Carry Instruction Extensions)
#
# 歷史背景:
#   Intel 於 Broadwell 微架構 (2014) 引入 ADX 指令集。
#   主要針對大數運算 (Big-Integer Arithmetic)、非對稱密碼學 (RSA, ECC, Diffie-Hellman)
#   與多精度算術 (Arbitrary-Precision Arithmetic) 進行重大硬體優化。
#
# 核心痛點與架構革新:
#   傳統 x86 的 ADC (Add with Carry) 指令在運算時會同時寫入 CF (進位旗標)
#   與 OF (溢位旗標)，並破壞其他算術旗標 (SF, ZF, AF, PF)。
#   這導致 CPU 只能維護一條單一序列的進位鏈 (Carry Chain)，超純量 (Superscalar)
#   流水線無法平行處理多個進位依賴。
#
# ADX 提供的雙進位鏈架構:
#   1. ADCX (Unsigned Integer Addition of Two Operands with Carry Flag):
#      - 運算: dest = dest + src + CF
#      - 特性: 只讀取並更新 CF，完全不影響 OF 及其他旗標！
#   2. ADOX (Unsigned Integer Addition of Two Operands with Overflow Flag):
#      - 運算: dest = dest + src + OF
#      - 特性: 只讀取並更新 OF，完全不影響 CF 及其他旗標！
#
# 效益:
#   軟體程式可將兩組大數乘加運算的進位鏈交錯排列（一條走 CF、一條走 OF），
#   讓現代 CPU 內的多個 ALU 同時平行執行兩個進位鏈，使大數密碼學運算吞吐量翻倍！
# =============================================================

.data
header_msg: .ascii "=== Intel ADX (多精度平行進位指令集展示) ===\n"
.equ header_len, . - header_msg

adcx_msg:   .ascii "[ADCX] 10 + 25 + CF(1) = "
.equ adcx_len, . - adcx_msg

adox_msg:   .ascii "[ADOX] 50 + 20 + OF(1) = "
.equ adox_len, . - adox_msg

.text
_start:
    # 輸出標題
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 1. 測試 ADCX (使用 CF 進位旗標)
    # ---------------------------------------------------------
    mov eax, 10             # 第一加數
    mov edx, 25             # 第二加數
    stc                     # 設定進位旗標 CF = 1
    adcx eax, edx           # eax = 10 + 25 + CF(1) = 36 (0x24)
    mov r12d, eax           # 保存至 callee-saved 暫存器，避免 syscall 覆寫 rax

    # 輸出結果
    sys_print_str adcx_msg, adcx_len
    mov edi, r12d
    call print_dec          # 印出 36

    # ---------------------------------------------------------
    # 2. 測試 ADOX (使用 OF 溢位旗標，CF 不受影響)
    # ---------------------------------------------------------
    mov r8d, 50             # 第一加數
    mov r9d, 20             # 第二加數

    # 人為設定 OF = 1: 將 0x7fffffff (正數最大值) + 1 觸發有號數溢位 (OF=1)
    mov r10d, 0x7fffffff
    add r10d, 1             # 產生溢位，此時 OF = 1

    adox r8d, r9d           # r8d = 50 + 20 + OF(1) = 71 (0x47)

    # 輸出結果
    sys_print_str adox_msg, adox_len
    mov edi, r8d
    call print_dec          # 印出 71

    sys_exit 0
