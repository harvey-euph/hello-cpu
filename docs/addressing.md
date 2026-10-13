# 深入解析 x86-64 記憶體定址與 SIB 位元組：為什麼是 [rax + rax*2] 而不是 [rax*3]？

在學習 x86-64 組合語言時，幾乎所有人都會遇到一個看似詭異的現象：
當我們想要計算一個暫存器乘上 3（例如 $3 \times rax$）時，組譯器與編譯器永遠都會寫成：

```assembly
lea rax, [rax + rax*2]
```

如果嘗試寫成看似更簡潔直觀的：
```assembly
lea rax, [rax*3]       # ❌ 編譯錯誤！Assembler Error: invalid scale factor
```
GNU Assembler (as) 會立刻毫不留情地噴出組譯錯誤：`invalid scale factor '3'`。

為什麼中括號 `[]` 明明支援乘法，卻**只能寫 `*2`, `*4`, `*8`，絕對不給寫 `*3`**？
中括號 `[]` 的內部運作機制到底是什麼？本篇教學將深入硬體機器碼底層，帶你徹底搞懂 x86 定址模式的設計哲學。

---

## 一、 中括號 `[]` 的基本意涵：指標解引用 vs. 算術求值

在 Intel 組合語言語法中，中括號 `[]` 代表**「位址計算（Address Evaluation）」**。

但根據搭配的指令不同，`[]` 具有兩種截然不同的行為：

### 1. 搭配資料傳輸指令（如 `MOV`, `ADD`, `CMP`）：記憶體解引用 (Memory Dereference)
相當於 C 語言中的指標取值運算子 `*ptr`：
```assembly
mov edx, [rax]         # 等同於 C: edx = *rax; (從記憶體位址 rax 讀取 4 個 bytes)
mov [rbx + 8], rcx     # 等同於 C: *(rbx + 1) = rcx; (寫入記憶體位址 rbx + 8)
```
此時 CPU 會啟動記憶體匯流排，依序經過 L1、L2、L3 快取或主記憶體讀寫資料。

### 2. 搭配位址載入指令（`LEA`）：純算術求值 (Math Calculation Only)
相當於 C 語言中的取位址運算子 `&`：
```assembly
lea edx, [rax + 8]     # 等同於 C: edx = (uint32_t)(rax + 8); 
```
> [!IMPORTANT]
> **關鍵差異**：`LEA` 雖然使用了中括號 `[]`，但它**完全不會去碰記憶體快取或匯流排**！它只利用 CPU 內部的定址計算電路算好括號內的數值，然後直接把「結果」送進目的暫存器。這也是編譯器拿它當「無旗標快速算術引擎」的原因。

---

## 二、 x86-64 記憶體定址的通用黃金公式

在 x86 硬體晶片中，中括號 `[]` 支援的語法並不是任意數學運算式，而是嚴格符合以下**四要素硬體定址公式**：

$$\Large [ \, \text{Base} + (\text{Index} \times \text{Scale}) + \text{Displacement} \, ]$$

| 元件名稱 | 中文意義 | 允許的暫存器與數值 | 典型程式設計用途 |
| :--- | :--- | :--- | :--- |
| **Base** | 基底暫存器 | 任意 64 位元通用暫存器（`rax`, `rbx`, `rsp`, `rbp`, `r8`~`r15` 等） | 物件基底位址、陣列起點指標、結構體指標 |
| **Index** | 索引暫存器 | 任意 64 位元通用暫存器（**唯獨 `rsp` 除外**） | 陣列索引下標（如 `i` 或 `j`） |
| **Scale** | 比例因子 | **只能是 1, 2, 4, 8 中的一個** | 陣列元素的大小（`sizeof(type)`） |
| **Displacement** | 位移立即數 | 常數整數（可為 0、8-bit、32-bit，可正可負） | 結構體成員偏移（Struct Field Offset） |

> [!NOTE]
> 另外在 64 位元長模式中，新增了專門用於位置無關代碼（PIC/PIE）的 **`[rip + Disp32]`** 相對定址模式。

---

## 三、 底層真相：為什麼 Scale 只能是 1, 2, 4, 8？

要回答「為什麼不能寫 `*3`」，我們必須拆開 CPU 機器碼的微架構二進位結構。

在 x86-64 指令編碼中，凡是需要用到複雜定址的指令，機器碼中一定會包含一個長度剛好為 **1 個 Byte（8 個位元）** 的輔助位元組：
👉 **SIB 位元組（Scale-Index-Base Byte）**。

### SIB 位元組的二進位欄位結構

```text
       ┌───────────┬───────────────┬───────────────┐
       │ Scale (SS)│  Index (3-bit)│   Base (3-bit)│
       │  Bit 7..6 │   Bit 5..3    │    Bit 2..0   │
       └─────┬─────┴───────┬───────┴───────┬───────┘
             │             │               │
             │             │               └─ 編碼 8 個通用暫存器 (RAX..RDI)
             │             └───────────────── 編碼 8 個索引暫存器 (RSP 特殊代表無 Index)
             └─────────────────────────────── 硬體僅配置 2 個位元！
```

請注意看最左邊的 **Scale 欄位（SS）**：硬體規格中它**只分配了 2 個 bits**！

2 個二進位位元，能代表的數值總共只有 4 種組合：
* `00`（二進位） $\rightarrow \text{Scale} = 1$ ($2^0$)
* `01`（二進位） $\rightarrow \text{Scale} = 2$ ($2^1$)
* `10`（二進位） $\rightarrow \text{Scale} = 4$ ($2^2$)
* `11`（二進位） $\rightarrow \text{Scale} = 8$ ($2^3$)

### 為什麼硬體工程師只給它 2 個 bits？
1. **陣列元素大小的物理映射**：
   在 C/C++ 等系統級程式語言中，基本純量型別的大小永遠是 2 的次方：
   * `sizeof(char)` / `uint8_t` = **1 byte** ($\text{Scale} = 1$)
   * `sizeof(short)` / `int16_t` = **2 bytes** ($\text{Scale} = 2$)
   * `sizeof(int)` / `float` / `int32_t` = **4 bytes** ($\text{Scale} = 4$)
   * `sizeof(long)` / `double` / 指標 = **8 bytes** ($\text{Scale} = 8$)
2. **硬體電路設計的極致精簡**：
   在 CPU 內部的定址生成單元（AGU, Address Generation Unit）中，乘以 1, 2, 4, 8 不需要塞入龐大且耗電的「硬體乘法器」，只需要放一個極低延遲的**桶形移位器（Barrel Shifter）**：
   * 乘 1 = 不移位（左移 0 位元）
   * 乘 2 = 左移 1 位元 (`<< 1`)
   * 乘 4 = 左移 2 位元 (`<< 2`)
   * 乘 8 = 左移 3 位元 (`<< 3`)
   
因為**根本沒有「乘 3」的硬體移位線路**，機器碼也根本沒有欄位可以填入數字 3，所以寫 `[rax*3]` 在語法分析階段就會被組譯器直接攔截拒絕！

---

## 四、 數學妙計：如何用 Base + Index 實現乘 3？

既然硬體不支援 `*3`，但編譯器為什麼又能用單一指令做到 $3 \times rax$ 呢？

答案就是高中代數的拆解技巧：

$$\Large 3x = x + 2x$$

現在我們回頭看硬體的定址公式：

$$\Large [ \, \text{Base} + (\text{Index} \times \text{Scale}) \, ]$$

我們只要巧妙地將同一個暫存器 `rax` 同時指定為 Base 和 Index：
* 令 $\text{Base} = rax$
* 令 $\text{Index} = rax$
* 令 $\text{Scale} = 2$（合法的硬體值！二進位 `01`）

代入公式：
$$\Large rax + rax \times 2 = 3 \times rax$$

### 它的機器碼長什麼樣子？
以指令 `lea rax, [rax + rax*2]` 為例，產出的十六進位機器碼為：
```text
48 8d 04 40
```
* `48`: REX.W 前綴（代表 64 位元運算元）
* `8d`: LEA 指令的 Opcode
* `04`: ModR/M 位元組（指示後面緊跟一個 SIB 位元組）
* `40`: **SIB 位元組！** 二進位為 `01_000_000`：
  * Scale = `01`（代表 $\times 2$）
  * Index = `000`（代表 `rax`）
  * Base  = `000`（代表 `rax`）

整條指令在 CPU 的 ALU 中只要 **1 個時脈週期** 即可完成！

---

## 五、 常見乘數的 LEA 合成速查大全

利用 Base、Index 與 Scale 的排列組合，編譯器可以不呼叫耗時的乘法器（`imul` 需 3 週期），直接在 1~2 週期內合成出絕大多數常見常數的乘法：

| 目標算式 | 組合語言寫法 | 拆解原理 | 所需週期 |
| :--- | :--- | :--- | :---: |
| **$x \times 2$** | `lea eax, [rax + rax]` 或 `[rax*2]` | $x + x$ 或 $x \times 2$ | 1 cycle |
| **$x \times 3$** | `lea eax, [rax + rax*2]` | $x + 2x$ | 1 cycle |
| **$x \times 4$** | `lea eax, [rax*4]` | $x \times 4$ | 1 cycle |
| **$x \times 5$** | `lea eax, [rax + rax*4]` | $x + 4x$ | 1 cycle |
| **$x \times 6$** | `lea eax, [rax + rax*2]; add eax, eax` | $(3x) \times 2$ | 2 cycles |
| **$x \times 8$** | `lea eax, [rax*8]` | $x \times 8$ | 1 cycle |
| **$x \times 9$** | `lea eax, [rax + rax*8]` | $x + 8x$ | 1 cycle |
| **$x \times 10$** | `lea eax, [rax + rax*4]; lea eax, [rax*2]` | $(5x) \times 2$ | 2 cycles |
| **$x \times 12$** | `lea eax, [rax + rax*2]; lea eax, [rax*4]` | $(3x) \times 4$ | 2 cycles |
| **$x \times 13$** | `lea edx, [rax + rax*2]; lea eax, [rax + rdx*4]` | $x + (3x \times 4)$ | 2 cycles |
| **$x \times 45$** | `lea eax, [rax + rax*8]; lea eax, [rax + rax*4]` | $(9x) \times 5$ | 2 cycles |

---

## 六、 語法邊界：合法 vs. 非法定址寫法對比表

很多初學者在寫中括號定址時容易隨意組合暫存器，以下是編譯器與硬體層級的嚴格限制：

| 定址寫法 | 判定 | 原因與硬體限制 |
| :--- | :---: | :--- |
| `[rax]` | ✅ 合法 | 純 Base，無 Index，無 Displacement |
| `[rax + 16]` | ✅ 合法 | Base + 8-bit/32-bit 位移常數 |
| `[rax + rbx]` | ✅ 合法 | Base + Index，預設 Scale = 1 |
| `[rax + rbx*4]` | ✅ 合法 | 標準 Base + Index * Scale |
| `[rax + rbx*4 + 32]`| ✅ 合法 | 四要素齊全：Base + Index * Scale + Disp |
| `[rbx*8 + 100]` | ✅ 合法 | 無 Base（Base=none），純 Index * Scale + Disp |
| `[rax + rax*2]` | ✅ 合法 | Base 與 Index 相同，巧妙合成乘 3 |
| `[rax*3]` | ❌ **非法** | **Scale 只能為 1, 2, 4, 8，硬體 SIB 位元組無法表示 3** |
| `[rax*5]` | ❌ **非法** | 同上，硬體無 5 比例因子（必須改寫為 `[rax + rax*4]`） |
| `[rax + rbx + rcx]` | ❌ **非法** | 硬體只有 1 個 Base 欄位與 1 個 Index 欄位，不能有第三個暫存器 |
| `[rsp*2]` | ❌ **非法** | **`rsp` 永遠不能作為 Index 暫存器！**（在 SIB 編碼中，Index 填入 `100b` 特殊代表「無 Index」，硬體電路無法以 RSP 當作索引） |
| `[rax + rsp]` | ❌ **非法** | 同上，RSP 只能放在 Base 位置，不能放在 Index 位置 |
| `[rax + 10 + 20]` | ✅ 合法 | 組譯器在預處理期會自動將常數折疊為 `[rax + 30]` |

---

## 總結

1. **`[]` 是位址生成器**：在 `MOV` 中它會解引用去讀記憶體，在 `LEA` 中它只是純粹計算數值。
2. **`*3` 在硬體上根本不存在**：因為 SIB 位元組只有 2 個 bits（只能選 $2^0, 2^1, 2^2, 2^3$），硬體移位器也只支援二進位位移。
3. **`[rax + rax*2]` 是工程上的智慧妥協**：既然沒有 $3x$，就用 Base + Index 寫成 $x + 2x$。它用最優雅的 SIB 編碼，在單一指令週期內達成了 3 倍數的運算。
