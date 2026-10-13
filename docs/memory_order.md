# 記憶體模型全解：從 x86 TSO、C++11 記憶體序到跨架構微架構硬體實作

在多執行緒與併發程式設計中，**記憶體模型（Memory Model）** 與 **記憶體定序（Memory Ordering）** 是最深奧、最容易引發幽靈 Bug（Heisenbugs）的領域。

很多工程師寫了一輩子 x86 多執行緒代碼，自認對併發瞭如指掌；然而一旦將代碼移植到 ARM64（如 Apple Silicon M 系列、AWS Graviton 或 Android 手機）上，系統便瞬間出現隨機的資料競爭（Data Race）與死當。

這背後的原因是：**x86 硬體極度「縱容」工程師，它擁有全世界最強的硬體記憶體模型之一（TSO）**；而 ARM64 / RISC-V 則是「弱記憶體模型（Weak Memory Model）」。

本文將從 CPU 矽晶片微架構（Store Buffer、快取一致性）、Intel 手冊 8 大黃金法則、C++11 六大記憶體序，到編譯器後端如何將抽象的 `acquire / release` 降級為真實機器碼，進行徹底的解剖。

---

## 目錄
1. [問題的根源：為什麼記憶體會被「重排序」？](#一問題的根源為什麼記憶體會被重排序)
2. [硬體光譜：從順序一致性（SC）到弱記憶體模型（Weak）](#二硬體光譜從順序一致性sc到弱記憶體模型weak)
3. [x86-64 的統治級法則：Intel 官方 TSO 記憶體模型（8 大定序契約）](#三x86-64-的統治級法則intel-官方-tso-記憶體模型8-大定序契約)
4. [唯一允許的叛逆：Store-Load 重排序與經典 Dekker 演算法失效](#四唯一允許的叛逆store-load-重排序與經典-dekker-演算法失效)
5. [微架構真相：Store Buffer、快取一致性與重排序發生的物理機制](#五微架構真相store-buffer快取一致性與重排序發生的物理機制)
6. [C++11 六大記憶體序在 x86-64 上的「免費午餐」](#六c11-六大記憶體序在-x86-64-上的免費午餐)
7. [硬體屏障三劍客：SFENCE、LFENCE、MFENCE 與 LOCK 前綴](#七硬體屏障三劍客sfence-lfence-mfence-與-lock-前綴)
8. [跨架構震撼對比：x86 (TSO) vs. ARM64 (Weak Ordering)](#八跨架構震撼對比x86-tso-vs-arm64-weak-ordering)
9. [經典併發模型實戰：訊息傳遞與雙重檢查鎖定（DCLP）](#九經典併發模型實戰訊息傳遞與雙重檢查鎖定dclp)
10. [記憶體模型終極速查表](#十記憶體模型終極速查表)

---

## 一、問題的根源：為什麼記憶體會被「重排序」？

當你在高階語言寫下這兩行看似簡單的賦值：

```c
a = 1;
b = 2;
```

在單執行緒視角下，你堅信 `a` 一定先變成 1，然後 `b` 才會變成 2。但在多核心系統中，另一個執行緒看到的執行順序**完全可能是 `b = 2` 先發生，然後 `a = 1` 才出現**！

這種**重排序（Memory Reordering）** 來自兩個不同層次的協同「作弊」：

1. **軟體層（編譯器最佳化重排）**：  
   GCC、Clang 或 MSVC 發現調整指令順序可以讓運算元常駐在暫存器中、減少管線停頓（Pipeline Stall），編譯器會在產生組合語言時主動調整指令順序。
2. **硬體層（CPU 微架構動態重排）**：  
   即使編譯器產生的指令嚴格保持順序，CPU 晶片內部的**超純量亂序執行引擎（Out-of-Order Engine）**、**儲存緩衝區（Store Buffer）** 與**非同步快取刷新（Cache Invalidation）**，依然會在執行時將記憶體請求的實際完成順序對調！

> [!IMPORTANT]
> **硬體的唯一承諾：As-if 原則**  
> CPU 與編譯器只向你保證：**「在『單一執行緒』內部，最終結果就像從未重排序過一樣（As-if sequential）」**。  
> 但只要跨越到多執行緒，未同步的記憶體存取便會直接墜入混沌！

---

## 二、硬體光譜：從順序一致性（SC）到弱記憶體模型（Weak）

計算機科學界將硬體的記憶體模型依照「限制由嚴格到寬鬆」劃分為一個光譜：

```text
記憶體模型嚴格程度光譜:
[ 最嚴格 / 最慢 ]                                                           [ 最寬鬆 / 最快 ]
┌──────────────────────────┬──────────────────────────┬─────────────────────────────┐
│ 順序一致性 (SC)           │ 完全儲存定序 (TSO)       │ 弱記憶體模型 (Weak Ordering) │
│ (Sequential Consistency) │ (Total Store Order)      │                             │
├──────────────────────────┼──────────────────────────┼─────────────────────────────┤
│ • 理論理想模型            │ • x86-64 / AMD64         │ • ARM64 (AArch64)           │
│ • 所有核心看到全域一致順序 │ • SPARC TSO              │ • RISC-V                    │
│ • 硬體成本過高，無現代晶片採納│ • 唯一允許 Store-Load 重排 │ • POWER / Alpha             │
│                          │ • 絕大多數操作原生保證順序 │ • 讀讀/讀寫/寫寫/寫讀 皆可重排│
└──────────────────────────┴──────────────────────────┴─────────────────────────────┘
```

---

## 三、x86-64 的統治級法則：Intel 官方 TSO 記憶體模型（8 大定序契約）

在《**Intel SDM Vol 3A Chapter 8（Multiple-Processor Management）**》中，Intel 寫下了 x86-64 處理器對程式設計師立下的 **8 大記憶體定序鐵律（TSO 模型）**：

1. **讀操作（Loads）之間不允許重排序**：  
   `Load A` 之後緊跟 `Load B`，在硬體匯流排上，`Load A` 保證先於 `Load B` 完成。
2. **寫操作（Stores）之間不允許重排序**：  
   `Store A` 之後緊跟 `Store B`，所有其他 CPU 核心保證先看到 A 被修改，再看到 B 被修改。
3. **寫操作不會被重排到先前的讀操作之前（No Load-Store Reordering）**：  
   先讀取 `Load A`，再寫入 `Store B`，硬體絕不會先把 B 寫入而把 A 延後。
4. **⚠️ 唯一允許的硬體重排序：讀操作可以超前於更早的寫操作（Store-Load Reordering）**！  
   若先發動 `Store A`，緊接著發動讀取不同位址的 `Load B`，硬體允許 `Load B` 在 `Store A` 真正落入快取之前就完成讀取！
5. **同一記憶體位址的操作嚴格保持程式順序（Coherence）**：  
   若針對同一位址先寫再讀，讀取必會立即讀到剛剛寫入的新值（透過 Store Forwarding）。
6. **寫操作具有全域一致順序（Total Store Order）**：  
   在多核心系統中，所有核心觀察到其他核心發出的寫入操作先後順序是一致的。
7. **鎖定指令具備完全雙向屏障特性（LOCK is a full fence）**：  
   凡帶有 `LOCK` 前綴的指令（如 `lock cmpxchg`、`xchg`），其前後所有的讀寫操作皆絕對禁止跨越該邊界。
8. **例外情況**：  
   弱記憶體序的非暫態寫入指令（Non-Temporal Stores，如 `movntdq`）、快速字串指令（`rep movsb`）以及 WC（Write-Combining）記憶體類型不遵守上述 TSO 規則。

---

## 四、唯一允許的叛逆：Store-Load 重排序與經典 Dekker 演算法失效

既然 x86 的讀-讀、寫-寫、讀-寫都禁止重排序，那 **「唯一允許的 Store-Load 重排序」** 究竟會造成什麼後果？

這就是計算機系統中最著名的 **Dekker / Peterson 互斥演算法失效問題**：

### 經典程式碼場景（初值 `x = 0, y = 0`）

```c
// 執行緒 1 (運行在 CPU 核心 0)
x = 1;         // Store X
r1 = y;        // Load Y

// 執行緒 2 (運行在 CPU 核心 1)
y = 1;         // Store Y
r2 = x;        // Load X
```

### 驚人的執行結果：
在直覺的順序執行思維下，最後的 `(r1, r2)` 組合可能是：
* `(0, 1)`：執行緒 1 先跑完，執行緒 2 後跑完。
* `(1, 0)`：執行緒 2 先跑完，執行緒 1 後跑完。
* `(1, 1)`：兩邊的 `x=1` 與 `y=1` 都先執行完了才讀取。

**但是在 x86-64 實體 CPU 上，出現 `r1 == 0 且 r2 == 0` 是完全合法的物理現象！**

```text
Dekker 演算法在 x86 上的時空穿梭:
       核心 0                              核心 1
┌──────────────────┐               ┌──────────────────┐
│ x = 1 (進 SB)    │               │ y = 1 (進 SB)    │
│ r1 = y (讀到 0!) │               │ r2 = x (讀到 0!) │
└────────┬─────────┘               └────────┬─────────┘
         │ (稍後才非同步刷入快取)            │ (稍後才非同步刷入快取)
         ▼                                  ▼
      [ X = 1 ]                          [ Y = 1 ]
```

---

## 五、微架構真相：Store Buffer、快取一致性與重排序發生的物理機制

為什麼 x86 硬體晶片一定要允許 Store-Load 重排序？為什麼寫入不能立刻生效？

### 1. 儲存緩衝區（Store Buffer）的必要性
* CPU 執行算術指令只要 **0.2 奈秒（1 cycle）**，但如果發起一個寫入操作，即便 L1 快取命中，也需要經過 MESI 快取一致性協定的握手檢查。如果快取未命中，等待匯流排 RFO（Read For Ownership）需要 **10 ~ 50 奈秒**。
* CPU 如果每次寫入都要傻傻等待快取確認，整個高效能管線將直接凍結！
* **解法**：CPU 在核心內部放了一個高速硬體佇列——**Store Buffer（儲存緩衝區）**。寫入時，CPU 只要把 `位址 + 數值` 往 Store Buffer 一丟，就立刻宣布寫入完成，繼續往下執行後續指令！

### 2. 為什麼導致了 Store-Load 重排？
* 回到上面的 Dekker 範例：
  * 核心 0 執行 `x = 1`：資料進了核心 0 自己的 Store Buffer，**此時尚未落入 L1 快取，外界根本看不到**！
  * 緊接著核心 0 執行 `r1 = y`：它去讀取 `y`。因為 `y` 不在自己的 Store Buffer 裡，它直接從 L1/L2 快取讀取，此時核心 1 還沒把 `y = 1` 刷進快取，因此核心 0 讀到了舊值 `0`！
  * 核心 1 也經歷一模一樣的過程，讀到了 `x = 0`。
  * 之後，兩顆核心的 Store Buffer 才慢慢把資料排入快取，但大錯已經鑄成。

> [!TIP]
> **快取一致性（Cache Coherence, MESI）≠ 記憶體一致性（Memory Consistency）**！  
> MESI 協定只能保證「一旦資料進了快取，所有核心看到的一定同步」；但 **Store Buffer 位於快取之前**，它脫離了 MESI 協定的管轄範圍！

---

## 六、C++11 六大記憶體序在 x86-64 上的「免費午餐」

C++11 正式引入了標準多執行緒記憶體模型（`std::memory_order`）。但在不同的硬體架構上，這些記憶體序編譯出來的機器碼開銷天差地遠！

### C++11 六大記憶體序概念定義

1. **`memory_order_relaxed`**：無任何同步與順序保證，僅保證單一變數的原子性（修改順序一致）。
2. **`memory_order_consume`**：針對資料相依鏈的獲取操作（因實作難度極高，C++20 已正式棄用/修訂中）。
3. **`memory_order_acquire`（獲取）**：本指令後方的任何讀寫操作，**不得被重排到本指令之前**（常用於 Mutex Lock、讀取 ready 旗標）。
4. **`memory_order_release`（釋放）**：本指令前方的任何讀寫操作，**不得被重排到本指令之後**（常用於 Mutex Unlock、發布資料完成）。
5. **`memory_order_acq_rel`**：同時具備 Acquire 與 Release 語意（用於 RMW 操作如 `fetch_add`）。
6. **`memory_order_seq_cst`（順序一致性，預設）**：全域總順序（Total Globally Consistent Order）。所有執行緒看到所有 `seq_cst` 操作的順序完全一致。

---

### x86-64 的「免費午餐」（The x86 Free Lunch）

因為 x86 硬體本來就禁止了「讀-讀」、「寫-寫」、「讀-寫」重排序，這意味著：  
**在 x86-64 上，Acquire 與 Release 語意是硬體天然自帶的！完全不需要發射任何額外的屏障指令！**

#### GCC / Clang 在 x86-64 與 ARM64 上的編譯結果對比：

| C++11 操作 | x86-64 產出機器碼 | ARM64 (AArch64) 產出機器碼 | 開銷評估 |
| :--- | :--- | :--- | :---: |
| **`load(relaxed)`** | `mov eax, [ptr]` | `ldr w0, [x1]` | 零開銷 |
| **`load(acquire)`** | **`mov eax, [ptr]`** *(免費！)* | **`ldar w0, [x1]`** *(需硬體載入獲取指令)* | x86 免費 |
| **`store(relaxed)`**| `mov [ptr], eax` | `str w0, [x1]` | 零開銷 |
| **`store(release)`**| **`mov [ptr], eax`** *(免費！)* | **`stlr w0, [x1]`** *(需硬體儲存釋放指令)* | x86 免費 |
| **`fetch_add(acq_rel)`**| `lock xadd [ptr], eax` | `ldaxr` + `stlxr` 迴圈 | 均需原子操作 |
| **`store(seq_cst)`**| **`mov + mfence`** 或 **`xchg`** | **`stlr w0, [x1]`** + 額外屏障 | x86 需付出代價 |

> [!CAUTION]
> **跨平台巨坑**：  
> 許多 C++ 工程師在 x86 上誤用了 `relaxed`，但因為 x86 硬體底層把 `relaxed` 自動升級成了 `acquire/release` 表現，程式碼跑了幾年都沒事；一旦這段程式碼移到 ARM64 伺服器上，由於 ARM64 真的會肆無忌憚地重排 `ldr` 與 `str`，系統立刻爆出資料錯亂！

---

## 七、硬體屏障三劍客：SFENCE、LFENCE、MFENCE 與 LOCK 前綴

當我們確實需要阻止硬體重排序時，x86 提供了以下手段：

```text
x86 屏障家族阻斷方向圖:
                Load A           Store A
                  │                 │
────────── 🛑 LFENCE ───────────────┼────────── (阻止所有後續指令分派與弱序 Load)
                  │                 │
──────────────────┼────────── 🛑 SFENCE ─────── (將 Store Buffer / WC 刷入快取)
                  │                 │
══════════ 🛑 MFENCE / LOCK ═══════════════════ (全面封死！解決唯一允許的 Store-Load 重排)
                  │                 │
                Load B           Store B
```

### 1. `SFENCE`（Store Fence）
* 針對寫操作。強制等待之前發起的所有 Store（包括非暫態 `MOVNT` 寫入）完全刷入快取，保證後方的 Store 不會超越先前的 Store。

### 2. `LFENCE`（Load Fence）
* 如 [`docs/latency.md`](docs/latency.md) 所詳解，除了保證弱記憶體序（如 WC 記憶體讀取）不被重排，它最重要的現代用途是作為**推測執行屏障（Speculation Barrier）** 與指令序列化工具，防禦 Spectre 攻擊。

### 3. `MFENCE`（Memory Fence）
* **全能全雙工屏障**。它是 x86 上**專門用來擊碎「Store-Load 重排序」的終極武器**！
* 它會強制 CPU 將內部的 Store Buffer 完全清空、刷入 L1 快取，直到先前所有的讀寫操作全數在匯流排上落定，後續的讀寫才准開始。

### 4. 編譯器秘傳：為什麼 `xchg` 比 `mfence` 更常見？
在實現 `store(seq_cst)` 時，編譯器有兩種選擇：
1. `mov [ptr], val; mfence`
2. **`xchg [ptr], val`**（因為 `xchg` 自動自帶隱式 `LOCK` 前綴，LOCK 是天然的完全屏障！）

在很多舊款 Intel 微架構中，執行一條 `xchg` 指令的開銷（約 15~20 cycles）竟然**顯著低於**執行 `mov + mfence`（`mfence` 可能耗時 30~50 cycles）！因此 GCC 和 Clang 至今在 64 位元模式下生成 `seq_cst` 寫入時，依然偏好直接發射 `xchg` 指令。

---

## 八、跨架構震撼對比：x86 (TSO) vs. ARM64 (Weak Ordering)

這張表是所有現代跨平台系統工程師必備的思維地圖：

| 重排序可能性 | x86-64 (Intel / AMD) | ARM64 (Apple Silicon / Neoverse) |
| :--- | :---: | :---: |
| **讀 - 讀 重排 (Load-Load)** | ❌ **嚴格禁止** | ✅ **完全允許**（除非加 `ldar` 或 `dmb`） |
| **寫 - 寫 重排 (Store-Store)** | ❌ **嚴格禁止** | ✅ **完全允許**（除非加 `stlr` 或 `dmb`） |
| **讀 - 寫 重排 (Load-Store)** | ❌ **嚴格禁止** | ✅ **完全允許** |
| **寫 - 讀 重排 (Store-Load)** | ✅ **唯一允許**（因 Store Buffer） | ✅ **完全允許** |
| **資料相依讀取重排** | ❌ 嚴格禁止 | ❌ 禁止（遵守 Address/Data Dependency） |
| **預設指標載入安全性** | 天生安全（天然自帶 Acquire） | 需明確使用 Acquire 語意保護 |
| **硬體模型歸類** | **TSO（強記憶體模型）** | **Weak Memory Model（弱記憶體模型）** |

---

## 九、經典併發模型實戰：訊息傳遞與雙重檢查鎖定（DCLP）

### 1. 訊息傳遞模型（Producer-Consumer Flag）

這是在無鎖程式設計中最基本的模式：生產者準備好資料後，立起一個 `ready` 旗標。

```cpp
// 共享變數：
int data = 0;
std::atomic<bool> ready{false};

// 生產者執行緒 (Producer)
void producer() {
    data = 42;                                          // (1) 普通寫入
    ready.store(true, std::memory_order_release);       // (2) Release 寫入
}

// 消費者執行緒 (Consumer)
void consumer() {
    while (!ready.load(std::memory_order_acquire)) {}   // (3) Acquire 讀取
    assert(data == 42);                                 // (4) 絕對不會觸發斷言！
}
```

#### 為什麼這個模式能保證正確？
* **Release 屏障** 保證：`(1)` 絕對不會被重排到 `(2)` 之後！`data = 42` 必先對所有核心可見，`ready = true` 才會發布。
* **Acquire 屏障** 保證：`(4)` 絕對不會被超前重排到 `(3)` 之前！消費者絕對不會在還沒看見 `ready == true` 時，就偷跑去讀 `data` 的舊值。
* **在 x86-64 上**：這兩處在組合語言層次編譯出來**就只是兩條最平淡無奇的 `mov` 指令**，硬體自動以零開銷完成這場完美的併發接力！

---

### 2. 雙重檢查鎖定模式（Double-Checked Locking Pattern, DCLP）

單例模式（Singleton）中最著名的反面教材：

```cpp
// ❌ 經典錯誤實作 (在 C++98 中必崩潰，在弱架構下引發半初始化物件讀取)：
Singleton* instance = nullptr;
std::mutex mtx;

Singleton* getInstance() {
    if (instance == nullptr) {                  // 第一次檢查 (無鎖)
        std::lock_guard<std::mutex> lock(mtx);
        if (instance == nullptr) {              // 第二次檢查 (有鎖)
            instance = new Singleton();         // ⚠️ 致命的地雷行！
        }
    }
    return instance;
}
```

#### 為什麼沒有記憶體模型會崩潰？
`instance = new Singleton()` 在微架構底層會被拆解為 3 步：
1. `void* mem = malloc(sizeof(Singleton));`（配置記憶體）
2. `new (mem) Singleton();`（在記憶體上執行建構子）
3. `instance = (Singleton*)mem;`（將位址賦值給全域指標）

若無屏障限制，編譯器或 CPU 允許將執行順序重排為 **1 $\to$ 3 $\to$ 2**！  
此時另一個執行緒剛好跑到第一次檢查 `if (instance != nullptr)`，發現指標非空，欣喜若狂地拿著這個「**記憶體已配置、但建構子根本還沒執行完畢**」的半殘物件去存取成員變數，當場產生未定義行為與崩潰！

#### C++11 正確修復解法（使用 Acquire/Release）：
```cpp
std::atomic<Singleton*> instance{nullptr};
// 寫入端使用 instance.store(temp, std::memory_order_release);
// 讀取端使用 instance.load(std::memory_order_acquire);
```

---

## 十、記憶體模型終極速查表

| 記憶體定序操作 | 代表意涵 | 在 x86-64 產生的機器碼開銷 | 核心防護之重排序類型 |
| :--- | :--- | :---: | :--- |
| **`memory_order_relaxed`** | 僅保證原子性，無前後依賴 | **0 週期（一般 `mov`）** | 不防任何重排 |
| **`memory_order_acquire`** | 獲取語意：後續讀寫不准跑到本指令前 | **0 週期（一般 `mov`）** | 防 Load-Load, Load-Store 重排 |
| **`memory_order_release`** | 釋放語意：先前讀寫不准跑到本指令後 | **0 週期（一般 `mov`）** | 防 Store-Store, Load-Store 重排 |
| **`memory_order_acq_rel`** | 同時具備獲取與釋放（如 RMW） | **依賴 `lock` 前綴（~15 cycles）** | 雙向邊界完全鎖定 |
| **`memory_order_seq_cst`** | 全域單一執行順序（完全順序一致性） | **寫操作需 `xchg` 或 `mfence`** | 防包括 Store-Load 在內的一切重排 |
| **`MFENCE` / `LOCK`** | 硬體完全記憶體屏障 | **清空 Store Buffer（~20-40 cycles）** | 解決 x86 唯一的 Store-Load 弱點 |
