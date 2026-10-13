# hello-cpu

一個輕量級、無 C 標準庫依賴（`-nostdlib`）的 x86_64 組合語言學習專案。透過 Linux 原生 `syscall` 與硬體指令，深度探索本機 CPU 在 `lscpu` 中所支援的各項指令集架構擴展（ISA Extensions）、編譯器熱點生成模式與微架構特徵。

---

## 本機硬體規格與 CPU 架構定義

本專案的所有二進位程式皆以 `-march=native` 針對本機硬體直接編譯與最佳化：

| 硬體規格項目 | 詳細硬體參數 |
| :--- | :--- |
| **處理器型號** | **Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz** |
| **微架構代號** | **Kaby Lake Refresh (KBL-R, 14nm FinFET, 第八代 Core 處理器)** |
| **CPU 識別碼** | Family: `6`, Model: `142` (`0x8e`), Stepping: `10` |
| **核心 / 執行緒數** | **4 實體核心 (Cores) / 8 邏輯執行緒 (Threads)**（支援 Hyper-Threading SMT） |
| **時脈頻率** | 基準時脈 1.60 GHz，最高 Turbo Boost 3.40 GHz，BogoMIPS: 3599.99 |
| **快取階層架構** | **L1d**: 32 KiB/核 (共 128 KiB) \| **L1i**: 32 KiB/核 (共 128 KiB)<br>**L2**: 256 KiB/核 (共 1 MiB) \| **L3**: 6 MiB 共享 Smart Cache |
| **硬體旗標總量** | `lscpu` 回報共 **78 個硬體 Flags**（特權/系統防禦 39 個、使用者態 ISA 39 個） |
| **使用者態覆蓋率** | 本專案已實作展示其中的 **33 個核心旗標（覆蓋率達 84.6%）** |

---

## 快速開始

### 編譯所有範例
```bash
make
```

### 一鍵編譯並依年代順序執行所有範例（make run）
```bash
make run        # 執行全部 (Demo + Perf)
make run-demo   # 僅執行 Demo 範例
make run-perf   # 僅執行 Performance 基準測試
```
所有範例皆依據**歷史年代軸（1978 ～ 2015）**依序建置與輸出：
```text
=== [1/2] 執行 Demo 範例 ===
bin/demo/0001_echo           -> === Linux Syscall (標準輸入讀取與回顯展示) === ...
bin/demo/0001_ioctl          -> === Linux sys_ioctl (TIOCGWINSZ 終端機大小查詢) === ...
bin/demo/0001_print          -> === 1. 十進位格式化展示 (print_dec) === ...
bin/demo/1978_jumptable      -> === Intel Indirect JMP (編譯器 Switch-Case 跳躍表展示) === ...
bin/demo/1978_lea            -> === Intel LEA (編譯器核心算術折疊與無旗標運算) === ...
bin/demo/1985_movsx          -> === Intel MOVSX / MOVZX (型別提升與陣列定址擴展展示) === ...
bin/demo/1989_xadd           -> === Intel XADD (原子 Fetch-and-Add / std::atomic 核心) === ...
bin/demo/1993_cpuid          -> === Intel CPUID (處理器硬體能力探索全集) === ...
bin/demo/1995_cmov           -> === Intel CMOVcc (無分支條件搬移展示) === ...
bin/demo/1997_mmx            -> === Intel MMX (64-bit 始祖 SIMD 指令集展示) === ...
...
bin/demo/2015_clflushopt     -> === Intel CLFLUSHOPT (快取行優化刷寫指令展示) === ...

=== [2/2] 執行 Performance 基準測試 ===
bin/perf/2008_rdtscp         -> === RDTSCP 100ms 基準測試 === ...
bin/perf/2010_aes            -> === AES-NI 硬體加速 vs 純軟體實作基準測試 === ...
bin/perf/2011_vzeroupper     -> === AVX-SSE Transition Penalty Benchmark === ...
bin/perf/2013_mul_lat        -> === x86_64 乘法指令依賴鏈延遲評測 === ...
bin/perf/2013_simd_add8      -> === 8-Integer Addition Benchmark === ...
```

### 清除編譯產物
```bash
make clean
```

---

## 核心特權級（Ring 0）架構與指令運作邏輯解析

在此 CPU（i5-8250U）的 `lscpu` 旗標中，約有 39 個屬於作業系統核心特權級（Ring 0）、記憶體分頁 MMU 與微架構安全防禦旗標。使用者態（Ring 3）程式若直接執行這些指令將觸發一般保護錯誤（`#GP, General Protection Exception`）。以下詳述其在 Linux 核心中的底層運作邏輯：

### 1. 記憶體分頁與 MMU 控制指令
* **`CR3` (Page Directory Base Register)**：存放當前行程的四級分頁表（PML4 / 4-Level Paging）物理基底位址。當作業系統排程器執行行程切換（Context Switch）時，寫入 `mov cr3, rax` 即可瞬間切換虛擬記憶體位址空間。
* **`CR4.PCID` 與 `invpcid` (Process-Context Identifiers)**：傳統寫入 CR3 會導致 CPU 內部的 TLB（轉譯後備緩衝區）全數失效清空，引發巨大快取未命中懲罰。PCID 允許分頁快取打上行程 ID 標籤，配合 `invpcid` 指令可精準僅刷除指定行程的 TLB，大幅降低行程切換成本。
* **`invlpg [addr]` (Invalidate TLB Entry)**：當核心呼叫 `mprotect` 或回收單一記憶體頁時，發出 `invlpg` 刷除特定虛擬位址在 CPU 內部 TLB 的快取項。
* **`CR4.SMEP` (Supervisor Mode Execution Prevention)**：核心態防禦旗標。防止 CPU 在 Ring 0 特權級下意外跳躍執行使用者態（Ring 3）記憶體中的惡意代碼（防禦 ret2usr 攻擊）。
* **`CR4.SMAP` (Supervisor Mode Access Prevention)**：防止 Ring 0 核心在未明確允許（`stac` 指令）的情況下直接讀寫使用者空間資料，杜絕核心態利用未驗證指標讀取惡意資料。

### 2. 特殊暫存器（MSR）與系統呼叫硬體分派
* **`rdmsr` / `wrmsr` (Read/Write Model-Specific Register)**：
  - 核心透過 `ecx` 傳入 32 位元 MSR 編號，並由 `edx:eax` 讀寫 64 位元數值。
  - **`IA32_LSTAR` (`0xC0000082`)**：存放使用者態發起 `syscall` 時硬體直接跳躍的 Linux 核心進入點函式（`entry_SYSCALL_64`）。
  - **`IA32_STAR` (`0xC0000081`)**：設定切換時的 CS/SS 核心與使用者段選擇子。
  - **`IA32_FMASK` (`0xC0000084`)**：定義執行 `syscall` 時自動遮罩（清除）的 RFLAGS 旗標（如硬體自動清除 IF 關閉中斷）。
  - **`IA32_FS_BASE` / `IA32_GS_BASE`**：底層存放 TLS 與 per-CPU 資料結構基底。

### 3. 中斷、異常與特權切換
* **`lidt` (Load IDTR)**：載入中斷描述符表（IDT），配置 256 個中斷與異常閘（包含除零錯誤 `#DE`、分頁錯誤 `#PF`、計時器中斷等）。
* **`cli` / `sti` (Clear/Set Interrupt Flag)**：關閉與開啟 CPU 可遮罩中斷。在核心自旋鎖（Spinlock）與臨界區執行時，關閉中斷防止死鎖與重入。
* **`swapgs`**：當使用者態透過 `syscall` 或中斷進入核心時，硬體不自動切換 GS。核心首條指令即執行 `swapgs`，原子置換使用者 GS 與核心內部的 per-CPU 結構基底指標。
* **`iretq` (Interrupt Return 64-bit)**：中斷處理結尾指令。從核心堆疊中原子彈出並還原 `RIP`, `CS`, `RFLAGS`, `RSP`, `SS` 五個暫存器，無縫返回中斷發生前的使用者行程。

### 4. 擴展向量狀態管理 (XSAVE 體系)
* **`xsetbv` / `xgetbv`**：控制擴展控制暫存器 `XCR0`。向硬體宣告作業系統已準備好支援哪些向量狀態（Bit 0: x87, Bit 1: SSE, Bit 2: AVX, Bit 5..7: AVX-512）。若核心未透過 `xsetbv` 開啟 AVX 位元，使用者態執行任何 AVX 指令將直接觸發無效操作碼錯誤（`#UD`）。
* **`xsaves` / `xrstors`**：特權級高效能狀態儲存，僅備份有被修改（Dirty）的向量暫存器以節省記憶體頻寬。

### 5. 推測執行與微架構硬體安全防禦（針對 Kaby Lake Refresh 架構）
* **KPTI (Kernel Page Table Isolation, 旗標 `pti`)**：防禦 Meltdown (CVE-2017-5754)。在使用者空間運行時完全卸載核心位址分頁，徹底阻斷推測讀取核心記憶體。
* **IBRS / IBPB (旗標 `ibrs`, `ibpb`)**：防禦 Spectre v2 (CVE-2017-5715)。核心透過寫入 `IA32_SPEC_CTRL` MSR，在特權級切換時建立間接分支預測屏障，防止惡意推測注入。
* **STIBP (旗標 `stibp`)**：單執行緒間接分支預測器，防止 Hyper-Threading 超執行緒中的兄弟執行緒竊取分支預測狀態。
* **MDS / TAA 防禦 (旗標 `md_clear`, `flush_l1d`)**：在行程切換或返回 Ring 3 前，核心執行 `verw` 指令或寫入 `IA32_FLUSH_CMD` MSR，清空 CPU 內部的 L1 Data Cache 與微架構暫存緩衝區（Line Fill Buffers）。

---

## 編譯器工程師視角：現代編譯器前 95% 熱點指令全景指南

在現代編譯器（如 **GCC, Clang/LLVM, Rustc, Go gc, V8 TurboFan, JVM JIT**）的後端代碼生成中，實際在熱點代碼中被高頻生成的並非冷門的複雜指令，而是少數具備極高語義密度、零管線停頓的高效指令。

以下為編譯器工程師必須精通的 7 大核心代碼生成模式：

```text
編譯器代碼生成前 95% 關鍵模組架構圖:
├── 1. 算術折疊與無旗標計算 ─── LEA (Load Effective Address)
├── 2. 控制流分派最佳化 ─────── Indirect JMP + Jump Table (.rodata O(1) 分派)
├── 3. 型別提升與陣列定址 ─────── MOVZX (零擴展) / MOVSXD (符號擴展) / 32-bit Auto-Zero
├── 4. 併發與原子引用計數 ─────── LOCK XADD (std::atomic::fetch_add / Rust Arc)
├── 5. 分支消除與管線保護 ─────── CMOVcc (Branchless MIN/MAX/三元運算子)
├── 6. 位元欄位與演算法加速 ───── POPCNT (漢明權重) / BMI1 / BMI2 (LZCNT, TZCNT, PEXT, PDEP)
└── 7. SIMD 向量化迴圈 ──────── AVX2 / FMA (vpaddd, vfmadd231ps, 矩陣乘法)
```

### 1. 算術折疊與無旗標計算：`LEA` ([1978_lea.s](src/demo/1978_lea.s))
* **三操作數運算**：`lea edx, [eax + ebx*4 + 15]` 單週期同時完成乘、加、加立即數，且不破壞來源暫存器。
* **保護 EFLAGS**：`lea` 算術「完全不觸碰任何狀態旗標」，編譯器可將其安全排程在 `cmp` 與 `jcc` 之間。
* **常數乘法合成**：編譯器將常數乘法替換為低延遲 LEA 鏈（如 `x * 45` 拆解為 `x * 9` 再 `* 5`，僅需 2 個時脈週期）。
* **PIE 相對定址**：生成位置無關代碼（`lea rdi, [rip + label]`）。

### 2. 控制流降級：Switch-Case 跳躍表 ([1978_jumptable.s](src/demo/1978_jumptable.s))
* **密集分支 $O(1)$ 分派**：編譯器在 `.rodata` 中建構位址陣列，經由邊界檢查後發起 `jmp [rdx + rdi*8]`。
* **分支預測器最佳化**：避免長串 `cmp + je` 級聯分支導致分支預測緩衝區（BTB）污染。

### 3. 型別系統降級與陣列索引定址 ([1985_movsx.s](src/demo/1985_movsx.s))
* **型別提升**：無號提升發出 `movzx`；有號提升發出 `movsx`。
* **64 位元陣列定址防禦**：C 語言 `array[i]`（32-bit int 索引）必須透過 `movsxd` 擴展，防止負數索引被誤判為 4GB 正向偏移。
* **32-bit 自動零擴展規則**：寫入任何 32-bit 暫存器（如 `mov eax, edx`）硬體自動將高 32 位元清零，編譯器無須發出多餘指令。

### 4. 併發與原子操作降低開銷 ([1989_xadd.s](src/demo/1989_xadd.s) & [2004_cx16.s](src/demo/2004_cx16.s))
* **原子 Fetch-and-Add**：C++ `std::atomic<int>::fetch_add` 與 Rust `AtomicI32` 在 x86 後端直接對應單一指令 `lock xadd [mem], reg`。
* **智慧指標引用計數**：`std::shared_ptr` 與 Rust `Arc::clone` / `drop` 的無鎖計數基礎。
* **無鎖 CAS**：`lock cmpxchg` 與 128-bit `lock cmpxchg16b`，用於解決 ABA 問題的無鎖佇列與堆疊。

### 5. 分支消除 (Branchless Code Generation)：`CMOVcc` ([1995_cmov.s](src/demo/1995_cmov.s))
* 編譯器將三元運算子 `a ? b : c` 或 `std::min / std::max` 轉化為條件搬移，完全杜絕 15~20 週期的分支預測失敗懲罰。

### 6. 位元操作加速：ABM / BMI1 / BMI2 ([2008_popcnt.s](src/demo/2008_popcnt.s), [2013_bmi1.s](src/demo/2013_bmi1.s), [2013_bmi2.s](src/demo/2013_bmi2.s))
* `__builtin_popcount` 降級為 `popcnt`（1 週期計算漢明權重）。
* `__builtin_clz` 降級為 `lzcnt`；`__builtin_ctz` 降級為 `tzcnt`。
* 位元遮罩與提取降級為 `bzhi`, `pext`, `pdep`。

### 7. 自動向量化 (Auto-Vectorization)：AVX2 & FMA ([2011_avx.s](src/demo/2011_avx.s), [2013_avx2.s](src/demo/2013_avx2.s), [2013_fma.s](src/demo/2013_fma.s))
* 編譯器迴圈向量化核心：256-bit 向量整數加法 `vpaddd`、高精度融合乘加 `vfmadd231ps`（矩陣相乘 GEMM 核心算子）。
* 離開向量區塊時嚴格插入 `vzeroupper` 消除切換懲罰。

---

## 支援的 ISA 範例總覽表（依年代排序）

全專案共包含 **25 個 Demo 展示專案** 與 **4 個 Perf 基準測試專案**：

| 年代 | 類別 | ISA 旗標 | 範例檔案 | 核心代表指令 | 說明 | 執行輸出內容 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **0001** | **系統與輸出** | `stdin`/`stdout` | [0001_echo.s](src/demo/0001_echo.s) | `sys_read`, `sys_write` | 標準輸入讀取與字串回顯（Linux x86_64 ABI 與 EOF 處理） | 輸入提示與回顯內容 |
| **0001** | | `ioctl` | [0001_ioctl.s](src/demo/0001_ioctl.s) | `sys_ioctl` (`TIOCGWINSZ`) | 終端機裝置控制（查詢視窗列數 Rows 與行數 Cols） | 終端機視窗尺寸 (Rows/Cols) |
| **0001** | | `print` | [0001_print.s](src/demo/0001_print.s) | `print_dec`, `print_hex` | 數值格式化全集（32-bit 十進位與 64-bit 動態十六進位輸出） | 各項十進位與十六進位格式化展示 |
| **1978** | **編譯器核心** | `base` | [1978_jumptable.s](src/demo/1978_jumptable.s) | `jmp [table + reg*8]` | 編譯器 Switch-Case 跳躍表（O(1) 常數時間分支分派） | Case 1 / Case 2 / Default 分派結果 |
| **1978** | | `base` | [1978_lea.s](src/demo/1978_lea.s) | `lea` | 編譯器無旗標算術引擎（三操作數運算、快速乘法合成、EFLAGS 保護） | 算術折疊、常數乘法與旗標保護驗證 |
| **1985** | | `base` | [1985_movsx.s](src/demo/1985_movsx.s) | `movzx`, `movsx`, `movsxd`| 型別提升與陣列定址擴展（32-bit 自動零擴展與負數索引保護） | 零擴展、符號擴展與 64-bit 數值輸出 |
| **1989** | **併發與原子** | `base` | [1989_xadd.s](src/demo/1989_xadd.s) | `lock xadd` | 原子 Fetch-and-Add（C++ std::atomic 與智慧指標引用計數核心） | 舊值傳回與新值原子累加結果 |
| **1993** | **通用架構** | `cpuid` | [1993_cpuid.s](src/demo/1993_cpuid.s) | `cpuid` | 處理器硬體能力探索（Leaf 0 Vendor、Leaf 7 AVX2 檢測、Brand 型號） | 廠商字串、型號名稱與 AVX2 支援檢測 |
| **1995** | | `cmov` | [1995_cmov.s](src/demo/1995_cmov.s) | `cmove`, `cmovg` | 條件式傳送（管線分支預測懲罰分析、無分支 MIN/MAX） | 條件成立/不成立/有號數 MAX 測試輸出 |
| **1997** | **傳統向量** | `mmx` | [1997_mmx.s](src/demo/1997_mmx.s) | `paddd`, `emms` | 64 位元始祖 SIMD 整數向量加法（x87 FPU 暫存器重疊陷阱與 EMMS 必要性） | 2 組 32-bit 元素加法計算結果 |
| **1999** | | `sse` ~ `sse4_2` | [1999_sse.s](src/demo/1999_sse.s) | `addps`, `paddd`, `crc32` 等 | SSE 全系列指令集全集（SSE1 到 SSE4.2 六大世代演進與代表指令） | 6 項向量運算輸出 |
| **2004** | **系統架構** | `cx16` | [2004_cx16.s](src/demo/2004_cx16.s) | `cmpxchg16b` | 128 位元原子比較並交換（Lock-Free 無鎖結構 ABA 問題防禦） | 期望值匹配與不匹配之 CAS 行為驗證 |
| **2008** | **整數與位元** | `movbe` | [2008_movbe.s](src/demo/2008_movbe.s) | `movbe` | 大端序/網路序硬體反轉搬移（32-bit 讀取反轉、64-bit 寫入反轉） | 反轉後暫存器數值與記憶體驗證 |
| **2008** | | `popcnt` | [2008_popcnt.s](src/demo/2008_popcnt.s) | `popcnt` | 硬體漢明權重計算 (Population Count 與漢明距離) | 1 的個數與漢明距離計算結果 |
| **2010** | **密碼與雜湊** | `pclmulqdq` | [2010_pclmulqdq.s](src/demo/2010_pclmulqdq.s) | `pclmulqdq` | GF(2) 有限體多項式無進位乘法 (AES-GCM / GHASH / CRC32 核心) | 3 CLMUL 3 多項式乘法驗證 |
| **2011** | **進階向量** | `avx` | [2011_avx.s](src/demo/2011_avx.s) | `vaddps`, `vzeroupper` | 256 位元 YMM 浮點向量運算（VEX 3 操作數非破壞性語法與狀態清理） | 向量加法元素 0 與元素 7 結果 |
| **2012** | | `f16c` | [2012_f16c.s](src/demo/2012_f16c.s) | `vcvtph2ps`, `vcvtps2ph` | 半精度浮點數 (FP16) 與單精度 (FP32) 雙向轉換 | 雙向浮點數轉換驗證輸出 |
| **2012** | **系統架構** | `fsgsbase` | [2012_fsgsbase.s](src/demo/2012_fsgsbase.s) | `rdfsbase`, `rdgsbase` | 使用者態快速段基底讀寫（TLS / 協程綠色執行緒切換優化） | 當前 FS Base 與 GS Base 十六進位位址 |
| **2012** | **隨機數** | `rand` | [2012_rand.s](src/demo/2012_rand.s) | `rdrand`, `rdseed` | 硬體隨機數全集（AES-CTR PRNG 高速隨機數 vs 物理熱噪聲真實熵種子） | 2 組 32-bit 隨機輸出 |
| **2013** | **進階向量** | `avx2` | [2013_avx2.s](src/demo/2013_avx2.s) | `vpaddd`, `vpxor` | 256 位元 YMM 整數向量運算與位元邏輯操作 | 向量整數加法與異或計算結果 |
| **2013** | **位元操作** | `abm` / `bmi1` | [2013_bmi1.s](src/demo/2013_bmi1.s) | `lzcnt`, `tzcnt`, `blsr` 等 | 進階位元操作指令全集（前導/尾隨零、最低位清除/提取/遮罩、ANDN、BEXTR） | 8 項位元運算輸出 |
| **2013** | | `bmi2` | [2013_bmi2.s](src/demo/2013_bmi2.s) | `bzhi`, `pext`, `pdep`, `mulx` 等 | 高階位元操作與無旗標運算全集（散播/聚集、無旗標乘法/位移） | 6 項位元運算輸出 |
| **2013** | **進階向量** | `fma` | [2013_fma.s](src/demo/2013_fma.s) | `vfmadd213ss`, `vfmadd231ps` | 融合乘加 $A \times B + C$（無中間捨入高精度純量/向量計算） | 純量與向量 FMA 計算結果 |
| **2014** | **整數運算** | `adx` | [2014_adx.s](src/demo/2014_adx.s) | `adcx`, `adox` | 大數密碼學雙鏈路平行進位加法（CF/OF 雙進位鏈平行運算） | ADCX 與 ADOX 平行加法計算結果 |
| **2015** | **快取架構** | `clflushopt` | [2015_clflushopt.s](src/demo/2015_clflushopt.s) | `clflushopt`, `mfence` | 快取行最佳化弱序刷寫指令 (Cache Line Flush Optimized) | 刷寫前後記憶體數值驗證與生命週期 |
| **2008** | **效能 (Perf)** | `rdtscp` | [2008_rdtscp.s](src/perf/2008_rdtscp.s) | `rdtscp` | 序列化讀取時間戳計數器 (100ms 基準測試) 與 CPU Core ID 遷移檢測 | 時脈週期增量與目前運行的 Core ID |
| **2010** | | `aes` | [2010_aes.s](src/perf/2010_aes.s) | `aesenc` vs 純軟體 | AES-NI 硬體加速 vs 純軟體實作（數值正確性驗證與 100k 次效能對比） | 軟硬體輸出完全一致驗證與 ~150x 效能差距 |
| **2011** | | AVX-SSE 懲罰 | [2011_vzeroupper.s](src/perf/2011_vzeroupper.s) | `vzeroupper` | AVX-SSE 轉換懲罰基準測試（100k 次迭代時序對比） | 有/無 vzeroupper 週期與 Penalty 差距 |
| **2013** | | SIMD 比較 | [2013_simd_add8.s](src/perf/2013_simd_add8.s) | `add`, `paddd`, `vpaddd` | 8 整數加法效能基準測試（純量 vs SSE vs AVX2） | 100 萬次迭代週期對比 |
| **2013** | | 乘法延遲 | [2013_mul_lat.s](src/perf/2013_mul_lat.s) | `lea`, `imul`, `mul`, `mulx` | x86_64 乘法指令依賴鏈延遲評測（暫存器 vs 記憶體 vs Store-Fwd） | 7 種乘法模式之實際時脈週期與延遲差距 |

---

## 專案目錄結構

- **[`src/`](src/)**
  - **[`src/demo/`](src/demo/)**：存放各項指令集特徵與編譯器模式展示源碼（共 25 個範例，依年代前綴命名）。
  - **[`src/perf/`](src/perf/)**：存放具備測量性質的微基準測試源碼（`2008_rdtscp.s`, `2010_aes.s`, `2011_vzeroupper.s`, `2013_mul_lat.s`, `2013_simd_add8.s`）。
- **`bin/`**
  - **`bin/demo/`**：編譯產出的 Demo 執行檔目錄。
  - **`bin/perf/`**：編譯產出的 Perf 執行檔目錄。
- **[`include/`](include/)**
  - 存放組合語言標頭檔、巨集與輔助函數庫（`*.inc`）：
    - [`system.inc`](include/system.inc)：
      - `sys_exit exit_code`: 安全結束行程並回傳狀態碼至作業系統。
      - `sys_read buf_ptr, buf_len`: 使用 Linux `sys_read` (0) 系統呼叫從標準輸入 (stdin) 讀取資料。
      - `sys_print_str str_ptr, str_len`: 使用 Linux `sys_write` (1) 系統呼叫直接輸出字串至標準輸出 (stdout)。
      - `sys_ioctl fd, cmd, arg`: 使用 Linux `sys_ioctl` (16) 系統呼叫對裝置進行底層控制（如終端機視窗大小）。
      - `sys_sleep_ms ms` / `sleep_ms`: 使用 Linux `sys_nanosleep` (35) 系統呼叫暫停指定毫秒數 (ms)，符合 x86_64 ABI 規範。
    - [`print.inc`](include/print.inc)：
      - `print_hex`: 核心十六進位格式化函數（自動忽略高位前綴 0，支援 0~64-bit 任意數值輸出）。
      - `print_dec`: 32-bit (4-byte) 無號整數十進位格式化輸出函數。
- **[`docs/`](docs/)**
  - 存放硬體架構與系統程式設計專題教學文件：
    - [`flags.md`](docs/flags.md)：深入解析 CPU 旗標（ZF, CF, SF, OF）與 x86-64 / ARM64 跨架構對比指南。
    - [`aes.md`](docs/aes.md)：AES（進階加密標準）完整架構、工作模式（GCM/CBC/CTR）、應用情境與硬體加速原理。
    - [`cache.md`](docs/cache.md)：CPU 快取控制（clflushopt/clwb/cldemote）、記憶體屏障（sfence/lfence/mfence）、非暫態寫入與預取指令解析指南。
    - [`args.md`](docs/args.md)：x86-64 函式呼叫與參數傳遞指南（System V AMD64 ABI、暫存器傳參順序、Caller/Callee-saved 責任劃分與堆疊對齊）。
    - [`addressing.md`](docs/addressing.md)：深入解析 x86-64 記憶體定址與 SIB 位元組：為什麼是 `[rax + rax*2]` 而不是 `[rax*3]`？
- **[`makefile`](makefile)**
  - 編譯選項：`-nostdlib -march=native -g -no-pie -Wa,-I$(CURDIR)/include -Wa,-Iinclude`。
  - 支援目標：`make all`, `make demo`, `make perf`, `make run`, `make run-demo`, `make run-perf`, `make clean`。
