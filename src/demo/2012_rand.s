.intel_syntax noprefix
.global _start

.include "system.inc"
.include "print.inc"

# ==============================================================================
# 硬體隨機數生成指令展示: RDRAND vs RDSEED
#
# 現代 x86-64 CPU 內建了基於熱雜訊（Thermal Noise）的硬體真隨機數生成器：
#
# 1. RDRAND (2012 - Ivy Bridge, 符合 NIST SP 800-90A 規範)
#    - 機制: 硬體虛擬隨機數生成器 (Cryptographically Secure PRNG)。
#    - 架構: 核心由一個高速 AES-128 (CTR 模式) 引擎構成，定時由硬體熵源重新播種 (Re-seed)。
#    - 特點: 吞吐量極高（可達每秒數百 MB），幾乎不會耗盡，適合一般密碼學金鑰、TLS Nonce 與隨機數。
#
# 2. RDSEED (2014 - Broadwell, 符合 NIST SP 800-90B/C 規範)
#    - 機制: 物理真隨機熵源 (True Random Number Generator, TRNG)。
#    - 架構: 直接從片上熱噪聲採樣經過條件調節（Conditioner）後輸出，不經由 AES-CTR 擴展。
#    - 特點: 提供純粹的實體熵（Physical Entropy），但受限於硬體熱雜訊採集速率。
#           若呼叫頻率過快可能導致「熵池飢餓 (Underflow)」。主要用於替軟體 PRNG（如 Linux /dev/urandom）提供種子。
#
# 3. 硬體協議與 CF (Carry Flag) 狀態旗標:
#    - 兩者皆透過 CPU 旗標暫存器的 CF 位元指示是否成功：
#      - CF = 1: 硬體成功取得有效隨機數。
#      - CF = 0: 硬體尚未就緒 / 熵源枯竭，目標暫存器內容無效！
#    - 組語規範: 必須使用 jnc (Jump if Not Carry) 配合重試迴圈檢驗。
# ==============================================================================

.section .rodata
header_msg: .ascii "=== 硬體隨機數生成全集 (RDRAND vs RDSEED) ===\n"
.equ header_len, . - header_msg

msg_rdrand: .ascii "RDRAND (AES-CTR PRNG 高速隨機數): "
.equ len_rdrand, . - msg_rdrand

msg_rdseed: .ascii "RDSEED (物理熱噪聲真實熵種子):     "
.equ len_rdseed, . - msg_rdseed

.section .text
_start:
    sys_print_str header_msg, header_len

    # ==========================================================================
    # 1. RDRAND 展示
    # ==========================================================================
    sys_print_str msg_rdrand, len_rdrand

    # 嘗試生成 32-bit 隨機數 (Intel 建議最多重試 10 次)
    mov     ecx, 10             # 最大重試次數
.L_retry_rdrand:
    rdrand  ebx                 # 成功時 CF=1, ebx 填入隨機數
    jc      .L_rdrand_success   # 若 CF=1 表示成功
    pause                       # 輕微暫停降低管線功耗
    dec     ecx
    jnz     .L_retry_rdrand

.L_rdrand_success:
    mov     edi, ebx
    call    print_hex           # 印出產生的 32-bit 隨機數

    # ==========================================================================
    # 2. RDSEED 展示
    # ==========================================================================
    sys_print_str msg_rdseed, len_rdseed

    # 嘗試取得 32-bit 物理真隨機種子
    mov     ecx, 100            # RDSEED 因物理採集限制，重試次數建議設較大
.L_retry_rdseed:
    rdseed  ebx                 # 成功時 CF=1, ebx 填入真實熵種子
    jc      .L_rdseed_success
    pause
    dec     ecx
    jnz     .L_retry_rdseed

.L_rdseed_success:
    mov     edi, ebx
    call    print_hex           # 印出產生的 32-bit 熵種子

    sys_exit 0
