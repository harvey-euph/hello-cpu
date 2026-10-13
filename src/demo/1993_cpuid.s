.intel_syntax noprefix
.global _start
.include "system.inc"
.include "print.inc"

# =============================================================
# 指令集說明: Intel CPUID (CPU Identification, 處理器識別指令)
#
# 歷史背景:
#   Intel 於 Pentium 處理器 (1993) 首次引入 CPUID 指令。
#   為所有現代作業系統與應用程式在執行期 (Runtime) 探索 CPU 硬體功能與擴展指令集的唯一標準。
#
# 核心機制:
#   - CPUID 可以在使用者空間 (Ring 3, User Mode) 直接執行，無須經過作業系統系統呼叫。
#   - 呼叫方式: 將欲查詢的葉節點編號 (Leaf Number) 寫入 EAX (子節點寫入 ECX)，
#     執行 CPUID 後，硬體會將查詢結果寫回 EAX, EBX, ECX, EDX。
#
# 常用查詢葉節點 (Leaves):
#   1. Leaf 0 (EAX = 0):
#      - EAX: 支援的最大基本葉節點編號。
#      - EBX:EDX:ECX: 12-byte 製造商識別字串 (Vendor ID String)。
#        * Intel: "GenuineIntel" (EBX="Genu", EDX="ineI", ECX="ntel")
#        * AMD:   "AuthenticAMD"
#   2. Leaf 1 (EAX = 1):
#      - EAX: 處理器系列 (Family)、型號 (Model)、步進 (Stepping)。
#      - EDX / ECX: 基礎功能標誌位元 (如 SSE, SSE2, SSE4.2, AES, AVX 等)。
#   3. Leaf 7 (EAX = 7, ECX = 0):
#      - EBX / ECX / EDX: 擴展功能標誌位元 (如 AVX2, BMI1, BMI2, ADX 等)。
#   4. Leaf 0x80000002 ~ 0x80000004:
#      - 擴展葉節點，連續 3 次呼叫回傳共 48 位元組的完整 CPU 商業型號名稱 (Brand String)。
# =============================================================

.data
header_msg: .ascii "=== Intel CPUID (處理器硬體能力探索全集) ===\n"
.equ header_len, . - header_msg

vendor_msg: .ascii "CPU 製造商識別碼 (Vendor):   "
.equ vendor_len, . - vendor_msg

brand_msg:  .ascii "CPU 完整商業型號 (Brand):    "
.equ brand_len, . - brand_msg

avx2_ok_msg:  .ascii "硬體能力檢測 (AVX2 支援):    [ 支援 (YES) ]\n"
.equ avx2_ok_len, . - avx2_ok_msg

avx2_no_msg:  .ascii "硬體能力檢測 (AVX2 支援):    [ 不支援 (NO) ]\n"
.equ avx2_no_len, . - avx2_no_msg

newline: .ascii "\n"

.bss
vendor_str: .space 16
brand_str:  .space 64

.text
_start:
    sys_print_str header_msg, header_len

    # ---------------------------------------------------------
    # 1. 查詢 Leaf 0: 獲取 Vendor ID String
    # ---------------------------------------------------------
    mov eax, 0
    cpuid
    # 注意 Intel 順序是 EBX, EDX, ECX
    mov dword ptr [vendor_str], ebx
    mov dword ptr [vendor_str + 4], edx
    mov dword ptr [vendor_str + 8], ecx
    mov byte ptr  [vendor_str + 12], '\n'

    sys_print_str vendor_msg, vendor_len
    sys_print_str vendor_str, 13

    # ---------------------------------------------------------
    # 2. 查詢 Leaf 0x80000002 ~ 0x80000004: 獲取 48-byte CPU 型號字串
    # ---------------------------------------------------------
    # 檢查是否支援擴展 Leaf
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000004
    jb .Lskip_brand

    # 讀取 Part 1 (0x80000002) -> 16 bytes
    mov eax, 0x80000002
    cpuid
    mov [brand_str], eax
    mov [brand_str + 4], ebx
    mov [brand_str + 8], ecx
    mov [brand_str + 12], edx

    # 讀取 Part 2 (0x80000003) -> 16 bytes
    mov eax, 0x80000003
    cpuid
    mov [brand_str + 16], eax
    mov [brand_str + 20], ebx
    mov [brand_str + 24], ecx
    mov [brand_str + 28], edx

    # 讀取 Part 3 (0x80000004) -> 16 bytes
    mov eax, 0x80000004
    cpuid
    mov [brand_str + 32], eax
    mov [brand_str + 36], ebx
    mov [brand_str + 40], ecx
    mov [brand_str + 44], edx

    # 補上換行符號
    mov byte ptr [brand_str + 48], '\n'

    sys_print_str brand_msg, brand_len
    sys_print_str brand_str, 49

.Lskip_brand:
    # ---------------------------------------------------------
    # 3. 查詢 Leaf 7, Subleaf 0: 檢測是否支援 AVX2 指令集
    #    AVX2 位於 Leaf 7 的 EBX bit 5
    # ---------------------------------------------------------
    mov eax, 7
    mov ecx, 0
    cpuid
    test ebx, (1 << 5)      # 檢查 bit 5 (AVX2)
    jnz .Lavx2_supported

    sys_print_str avx2_no_msg, avx2_no_len
    jmp .Lexit

.Lavx2_supported:
    sys_print_str avx2_ok_msg, avx2_ok_len

.Lexit:
    sys_exit 0
