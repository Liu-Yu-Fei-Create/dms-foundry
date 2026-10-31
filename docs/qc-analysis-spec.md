# DMS Foundry — 文库质控（QC）与数据分析（Analysis）模块产品与技术规格

> 版本：v0.1 草案 · 定位：DMS Foundry（macOS 原生 SwiftUI 应用）在「设计」模块之后的两个模块。本文档基于公开的 DMS 分析工具与文献调研撰写，标注「经验值」的结论无直接文献出处，来自社区惯例与本团队判断。

## 0. 范围与定位

- **设计模块（已完成）**：产出**定义序列的 oligo 池**（每条 oligo ↔ 一个具体变体，非 NNS 简并池）与四件套：`order.csv`、`audit.csv`、`library.fasta`、`manifest.json`。
- **QC 模块（本文 §3）**：拿到 Twist 合成 → 克隆 → 转化后的**建库质控测序**（或筛选前 T0 测序）数据，回答「做出来的文库是否符合设计」。
- **Analysis 模块（本文 §4）**：拿到**筛选实验**（如竞争生长、抗性选择）的多条件/多时间点测序计数，估计每个变体的效应（enrichment / fitness / functional score）。

关键产品差异：因为文库是**定义序列**而非简并池，QC 阶段可以做严格的 **expected vs observed 对账**——这是相对 Enrich2/DiMSum 等通用工具的核心差异化能力，应作为 QC 模块的主轴。

---

## 1. 数据与流程

### 1.1 用户会拿到什么

| 数据 | 说明 |
|---|---|
| FASTQ（.fastq / .fastq.gz） | Illumina 短读长；**推荐双端 2×150**（突变区间需被完全覆盖，双端重叠可纠错）；也可能是单端长读（如 1×300，较少见） |
| 样本表 | 每行一个样本：`sample, sublibrary, replicate, condition, timepoint, index5, index3`（§3.1 给出模板） |
| 参考 | 设计模块导出的 `manifest.json` + `library.fasta` + 质粒序列（.gb/.fasta） |

文库建库通常采用**扩增子测序**（amplicon-seq）：对突变区域 PCR 扩增后直接测序。这与 dms_tools2 的 barcoded-subamplicon 设计、DiMSum 的 "constant sequence + variable region" 模型一致（见 §2）。

### 1.2 端到端流程

```
FASTQ → (1) read QC/trim → (2) index demux → (3) 定位到参考
     → (4) 在设计位点计数 → (5) 过滤 → (6) 与设计清单对账 → (7) 报告
```

1. **Read QC / trim**：Q-score 过滤（文献常用 min Q≥15–30，dms_tools2 默认 `--minq 15`）、去接头/引物（cutadapt/BBDuk 语义）。因为是扩增子，**恒定区（引物结合位点）必须精确匹配**，可作为 read 归属与方向判定的锚点（DiMSum 的 `-E/--experimentalDesign` + constant region 做法）。
2. **Index demux**：按 index5/index3 组合拆分；未匹配 reads 进 `undetermined` 桶并统计 Top-N 未知 index 组合（串扰诊断）。
3. **定位到参考**：DMS 扩增子通常 ≤600 bp 且序列已知，**不需要通用比对器**。推荐两种模式：
   - **锚点 + 直接比对（默认，纯 Swift 可实现）**：用恒定区锚定位置，对可变区做逐位比较（类似 dms2_bcsubamp 的 gapless `--alignspecs`，容忍 ≤ `--maxmuts` 个错配）。
   - **外部比对器（可选）**：BWA-MEM / minimap2 / BBMap 处理插入缺失或非预期重组，作为诊断模式而非主路径。
4. **计数**：将每条 read 翻译到设计变体（完全一致匹配 oligo 的可变区），累加到 `variant × sample` 矩阵；不一致的 read 归入「非设计序列」桶并做突变谱统计（估计合成/PCR 错误率）。
5. **过滤**：最小计数阈值（经验值：≥10 reads 才进入效应估计；QC 对账用 ≥1）、双端一致率、变异区无 N。
6. **对账**：expected（来自 `audit.csv`/`manifest.json`）vs observed，输出每个变体 `expected/observed/ratio/flag`。
7. **报告**：见 §3.3。

### 1.3 关键指标清单

| 指标 | 定义 | 用途 |
|---|---|---|
| reads 总数 / 可用率 | demux 后 + 锚定后的 read 比例 | 测序量是否够 |
| 锚定率（"比对率"） | 锚定到参考可变区的 reads / 总 reads | 建库质量 |
| 变体覆盖度 | 每个设计变体的 reads 数；中位覆盖 = 总可用 reads / 变体数 | 核心 QC 指标 |
| 零计数比例 | observed=0 的设计变体比例 | 合成/克隆缺失 |
| 均衡性 | sublibrary 内变体计数的 CV 或 Gini 系数 | 文库均一性（Gini 借自 MAGeCK-VISPR） |
| index cross-talk | 样本 A 的 reads 出现在样本 B 的 index 下的比例 | 污染 |
| 重复一致性 | replicate 间变体频率的 Spearman/Pearson；可附 ICC | 实验可重复性 |
| 突变组成 | 观测到的非同义/同义/终止比例 vs 设计预期 | 克隆/合成偏差 |
| 合成错误率估计 | 非设计 read 的单点突变频率（排除 PCR 错误的重复观测） | Twist 池质量 |
| 缺失变体清单 | expected 且 observed=0（或 <阈值） | 指导补合成/重克隆 |

---

## 2. 已有工具与算法调研

| 工具 | 输入→输出 | 统计模型 | replicate | time-series | 主要借鉴点 | 不适用点 |
|---|---|---|---|---|---|---|
| **DiMSum** (Lehner lab, [GitHub](https://github.com/lehner-lab/DiMSum), [Faure et al. 2020, Genome Biol](https://doi.org/10.1186/s13059-020-02091-3)) | FASTQ(+实验设计表 `-E`) → fitness + 诊断图 | 乘法误差模型：计数噪声 + 瓶颈/抽样过散；逐变体 SE；WT 归一 | ✅ 加权合并 | ❌（仅一轮选择 input/output） | **误差模型与"实验病理诊断"**（瓶颈检测、输入库不均匀诊断）；用同义突变做 null | R 实现、命令行；不支持多轮时间序列 |
| **Enrich2** (Fowler lab, [GitHub](https://github.com/FowlerLab/Enrich2), [Rubin et al. 2017, Genome Biol](https://doi.org/10.1186/s13059-017-1272-5)) | FASTQ/counts → enrichment score | 计数近似 Poisson，score=频率 log 比；多时间点用**加权最小二乘回归**斜率；replicate 用**随机效应**合并 | ✅ 随机效应 | ✅ WLS 回归 | counts→score 的最完整参考实现；按 SE 过滤低质量变体的先例 | 面向 barcode/简并池，无设计清单对账；Python2 遗留 |
| **mutscan** ([GitHub](https://github.com/fmicompbio/mutscan), [Soneson et al. 2023, Genome Biol](https://doi.org/10.1186/s13059-023-02967-0)) | FASTQ → variant count → 差异分析 | 直接借 edgeR / limma-voom（负二项） | ✅ | 部分 | **fastq→count 的 R 端工程范式**（digestFastqs 的常量区+可变区规格语言值得照抄其配置设计）；负二项差异检验是 MVP 显著性的低成本实现 | edgeR/limma 为 RNA-seq 设计，DMS 重复间方差结构不同（Rosace 论文 §1 的批评）；R 依赖重 |
| **dms_tools2 / dms-vep** (Bloom lab, [文档](https://jbloomlab.github.io/dms_tools2/), [GitHub](https://github.com/dms-vep)) | FASTQ(barcode-subamplicon) → codon counts → prefs/diffsel | 位点偏好（偏好值=富集归一）、fracsurvive；barcode 共识降噪 | ✅ batch 模式 | ❌（dms-vep 的 func_effects 有 log fold change） | **`--alignspecs` 无 gap 锚定算法**与 `--minq/--minreads/--minconcur` 共识参数集是双端纠错的最佳蓝本；reads-per-barcode 分布诊断 PCR 重复 | 其 barcode 范式（随机 barcode 关联变体）与定义 oligo 池不同；全读入内存（~1GB/百万 PE reads）在桌面端不可接受 |
| **Rosace** ([bioRxiv 2023](https://doi.org/10.1101/2023.10.24.562292), [GitHub](https://github.com/pimentellab/rosace)) | counts 矩阵 → 功能分数后验 | **贝叶斯层级模型**：位置均值 ϕ + 变体 β 收缩；均值-方差关系共享；lfsr 做显著性 | ✅ | ✅（生长型多时间点线性模型） | **位置信息收缩 + 均值-方差收缩**显著改善低计数/少重复（1–3 重复）下的 FDR；同义突变作 null 校准 | 需要 MCMC/优化，Swift 实现成本高；列为 v2+ |
| **FitSeq / Fit-Seq2** ([Li et al. 2018, Cell Syst](https://doi.org/10.1016/j.cels.2018.09.004)) | 多时间点 barcode 计数 → 每个 lineage 的适应度 | 似然法联合估计初始频率与生长率，EM 迭代 + 噪声模型 | 部分 | ✅（核心场景） | 竞争生长实验的**标准估计框架**：log(freq 比) 对时间线性回归即其简化版 | 需要 ≥4 个时间点才有意义；MVP 不做 |
| **MAGeCK / MAGeCK-VISPR**（CRISPR 筛选，[Li et al. 2014/2015, Genome Biol](https://doi.org/10.1186/s13059-015-0843-6)） | sgRNA counts | NB 检验 + RRA | ✅ | ❌ | **QC 指标集可直接借用**：Gini 系数、零计数率、重复相关性、read 分布直方图 | 无逐变体 DMS 语义 |

**关于 "SEstimate / BayeSweep"**：未检索到以此命名的公开 DMS 工具（截至本文调研）。"SEstimate" 按名字理解即 shrinkage estimation，其思想已由 Rosace（位置/均值-方差收缩）与 DESeq2 式 NB 收缩覆盖；"BayeSweep" 可能指群体遗传学贝叶斯选择扫描方法，对 DMS 计数不直接适用。两者均列为**思想借鉴（收缩/贝叶斯），无现成实现可抄**。

**结论（算法选型）**：MVP 用 **Enrich2 式 log 比 + Poisson 方差 + replicate 随机效应/加权平均**（实现简单、文献基础好），QC 诊断吸收 **DiMSum 的瓶颈/病理诊断**与 **MAGeCK 的指标集**；v2 引入 **Rosace 式收缩**与 **FitSeq 式时间序列**。

---

## 3. 质控模块产品设计

### 3.1 输入界面

1. **导入设计产物**：选择设计模块的 `manifest.json`（自动带出 `library.fasta`、`audit.csv`、质粒路径；用 manifest 里的引擎版本/参数哈希校验「设计-分析同源」）。
2. **导入 FASTQ**：支持拖拽多个 `.fastq(.gz)`；自动按 `_R1/_R2` 配对，单/双端混排给出警告。
3. **样本表**（提供「生成模板」按钮，导出 CSV）：

```csv
sample,sublibrary,replicate,condition,timepoint,index5,index3,r1,r2
libA_T0_rep1,libA,1,input,0,ATCACG,TAGCTT,reads/libA_T0_rep1_R1.fastq.gz,reads/libA_T0_rep1_R2.fastq.gz
```

   **校验规则**（导入即检查，全部硬失败/软警告分级）：
   - index5+index3 组合全局唯一（硬失败）；
   - 每个 index 序列只含 ACGT、长度 6–12、两两汉明距离 ≥3（软警告，提示 hopping 容错差；距离≥3 为经验值）；
   - `sublibrary` 必须能在 `audit.csv` 的 pool 列中找到（硬失败）；
   - 同一 (sublibrary, condition, timepoint) 下 replicate 编号连续（软警告）；
   - FASTQ 路径存在、R1/R2 行数一致（硬失败）。

### 3.2 运行与进度（技术路线）

- **纯 Swift 引擎，无外部二进制依赖（推荐）**。理由：扩增子场景下锚点+直接比对即可，BWA/BBMap 是过度依赖。引擎管线：
  - FASTQ 解析：流式逐行（`FileHandle` 分块读 + gzip 用 Apple `Compression` 框架或内嵌 `zlib`），绝不整文件载入；
  - 双端合并/锚定：恒定区精确匹配（Hamming ≤1）定位可变区边界 → 可变区与 oligo 词典做哈希查表（完全匹配）→ 不匹配者进入「错误谱」慢路径（k-mer 投票找最近变体，用于错误率估计）；
  - 并发：`DispatchQueue.concurrentPerform` 按 read 块并行，计数用线程局部字典再归并；内存占用 ≈ 变体词典（10⁵–10⁶ 条 × ~100 B ≈ 百 MB 内）+ 常量缓冲，**几十 GB FASTQ 以 8–64 MB 流式块处理，内存恒定**。
- **进度**：按文件字节偏移估算百分比（经验做法），阶段化展示（demux → 锚定 → 计数 → 对账）；可随时取消（`Task` 取消令牌）。
- **可选诊断模式**：对 `undetermined` 与非锚定 reads 抽样导出子集 FASTQ，引导用户在「外部工具」页指引其用 BWA-MEM/IGV 排查（不做进 MVP）。

### 3.3 报告页

- **总览卡片**：总 reads、demux 率、锚定率、设计变体观测率、零计数比例、中位覆盖、重复一致性、总体判定（✅/⚠️/❌）。
- **每 sublibrary 覆盖条形图**：变体按位置排序的 read 数（log 轴），叠加中位数线。
- **变体级表格**：`variant_id | position | wt_aa | mut_aa | expected | observed | ratio | flag`；flag ∈ {OK, LOW, ZERO, NOT_DESIGNED}。
- **重复一致性散点**：两两 replicate 的 log10(count+1) 散点 + Spearman ρ。
- **污染/串扰面板**：观测到的非本样本 index 组合 Top-N 表；UDI 双端不匹配计数。
- **导出**：`qc_report.csv`（变体级）、`qc_summary.json`（指标+判定）、PDF 报告（SwiftUI 渲染→PDF，v1.1）。

### 3.4 判定阈值（默认，均可配置）

| 规则 | 默认阈值 | 依据 |
|---|---|---|
| 设计变体观测率 | ≥ 95% ✅ / 90–95% ⚠️ | 经验值（CRISPR 文库常见要求 100% sgRNA 检出，DMS 定义池放宽） |
| 零计数变体比例 | < 5% | 经验值，与上行互补 |
| 重复间 Spearman ρ | > 0.9 ✅ / 0.8–0.9 ⚠️ | 经验值；Enrich2/DiMSum 教程中良好实验通常 >0.9 |
| sublibrary 内计数 Gini | < 0.3 ✅ / 0.3–0.5 ⚠️ | 经验值，借自 MAGeCK-VISPR 的 Gini 用法 |
| sublibrary 间 reads CV | < 0.3 | 经验值 |
| index cross-talk | < 0.5% ✅ / >1% ❌ | UDI 论文报告 patterned flow cell 上非 UDI hopping 可达 ~1–2%，UDI 可降至 <0.1%（[Illumina 白皮书 770-2017-004](https://www.illumina.com/content/dam/illumina-marketing/documents/products/whitepapers/index-hopping-white-paper-770-2017-004.pdf), [MacConaill et al. 2018](https://pmc.ncbi.nlm.nih.gov/articles/PMC5759201/)）；阈值按此取中 |
| 中位覆盖 | ≥ 100× ✅ / 20–100× ⚠️ | 经验值；低覆盖使低丰度变体效应不稳（Rosace/Enrich2 均以低计数为主要误差源） |
| 终止密码子比例 | 不超过设计预期 +1 个百分点 | 来自设计参数直接对账（确定性规则，非经验值） |

判定 = 全部规则里最差等级。

---

## 4. 分析模块产品设计

### 4.1 输入

- QC 产出的 counts 矩阵（首选），或直接导入 counts CSV（列约定见 §5.2）；
- 样本元数据：condition（input/selected/…）、replicate、timepoint、selection 强度；
- 对照定义：WT/同义变体自动从 `audit.csv` 的质检变体类识别，作为 null 分布与归一基准。

### 4.2 模型（MVP → 后续）

**MVP 实现**：
1. **归一化**：每样本 library size 归一（CPM）；可选 WT 中位数归一（Enrich2 做法）。
2. **Enrichment / log2FC**：`log2((c_sel + p)/(N_sel) ÷ (c_in + p)/(N_in))`，伪计数 p=0.5（经验值；Enrich2 用 0.5）。
3. **方差与 CI**：Poisson 方差 `var ≈ 1/c_sel + 1/c_in`（delta 法）；replicate 合并用逆方差加权平均 + 随机效应项（Enrich2）；输出 mean ± 95% CI。
4. **显著性**：以同义变体分布为经验 null，计算 z 分数与 BH-FDR（Rosace 论文用同义作 null 验证 FDR 的思路）。
5. **多时间点（v1.1）**：log(freq ratio) 对时间做 WLS 回归（Enrich2），斜率 = fitness 代理；≥4 时间点再评估 FitSeq 式联合估计。

**后续版本**：Rosace 式位置+均值-方差收缩（v2，贝叶斯或经验贝叶斯近似）；负二项 GLM（edgeR 语义，v2）；结构映射（PDB 投影，v2+）。

**明确不做**（MVP 边界）：barcode 共识（无随机 barcode）、indel 变体效应、机器学习效应预测。

### 4.3 输出与交互

- **变体表**：`variant | effect | CI_low | CI_high | z | FDR | flag`；
- **missense 热图**：position × 20 aa，色标=effect，缺失=灰，WT=对角线标注；导出 PNG/PDF（PDF 走 SwiftUI ImageRenderer/矢量）；
- **聚合视图**：按位置中位数曲线（滑动窗口，窗口=5，借鉴 Rosace 平滑）、按 aa 理化性质分组箱线（疏水性/电荷/体积，分组表内置）；
- **命中 calling**：阈值模式（|effect|>cutoff 且 FDR<0.05）+ 经验贝叶斯模式（v2）；
- **对账视图**：分析结果按设计时的 aa 覆盖清单核点（哪些设计变体无有效效应估计及原因）；
- **交互**：条件对比选择器、平滑开关、伪计数/归一方式切换（实时重算，矩阵在内存中，10⁵ 变体 × 数十样本足够快）；
- **导出**：`effects.csv`、`analysis_report.json`、图 PNG/PDF。

---

## 5. 数据模型与文件格式

### 5.1 SQLite（应用内单一项目库 `*.dmsproj`）

```sql
CREATE TABLE runs (id INTEGER PRIMARY KEY, type TEXT,            -- 'qc' | 'analysis'
                   manifest_hash TEXT, engine_version TEXT,
                   created_at TEXT, params_json TEXT, status TEXT);
CREATE TABLE samples (id INTEGER PRIMARY KEY, run_id INT, name TEXT,
                      sublibrary TEXT, replicate INT, condition TEXT,
                      timepoint REAL, index5 TEXT, index3 TEXT,
                      r1_path TEXT, r2_path TEXT);
CREATE TABLE variants (id INTEGER PRIMARY KEY, variant_id TEXT UNIQUE,  -- 与 audit.csv 一致
                       pool TEXT, position INT, wt_codon TEXT, mut_codon TEXT,
                       wt_aa TEXT, mut_aa TEXT, mut_class TEXT,         -- missense/synonymous/stop/…
                       oligo_seq TEXT);
CREATE TABLE counts (run_id INT, sample_id INT, variant_id INT,
                     reads INT, UNIQUE(run_id, sample_id, variant_id));
CREATE TABLE effects (run_id INT, variant_id INT, contrast TEXT,
                      effect REAL, se REAL, ci_low REAL, ci_high REAL,
                      z REAL, fdr REAL, flag TEXT);
```

对接设计模块：`variants` 与 `samples.sublibrary` 直接来自 `audit.csv`/`manifest.json`；`manifest_hash` 防止「设计与分析不是同一份清单」。

### 5.2 counts 矩阵 CSV 约定（对外交换格式）

长表（首选，追加友好）：
```csv
variant_id,sample,reads
libA:P0123A,libA_T0_rep1,1523
```
宽表（兼容 Enrich2 习惯）：首列 `variant_id`，其后每列一个 sample。两类均支持导入导出。

---

## 6. 风险与坑

1. **Index hopping / 串扰**：patterned flow cell（NovaSeq/HiSeq 3000/4000/X）上游离接头导致的 index 跳转，非 UDI 可达 ~1–2%，UDI（唯一双端）可压到 <0.1%（来源见 §3.4 表）。对策：样本表强制记录 index5/index3、UDI 配对检查、cross-talk 面板、阈值告警。
2. **PCR 偏差与 duplicates**：扩增子 PCR 使 read 数≠分子数；无 UMI 时无法去重。dms_tools2 的 reads-per-barcode 分布可诊断瓶颈；建议（经验值）PCR 循环 ≤20、上机量 ≥50× 变体数，报告中给出「duplicate 嫌疑」提示而非去重。
3. **参考与设计不一致**：质粒坐标 vs CDS 坐标、反向链（oligo 是否按反义链合成）、manifest 与本次实验不是同一版本——用 `manifest_hash` + 锚定率骤降做自动预警。
4. **低计数过度解读**：计数 <10 的变体 log2FC 方差爆炸；对策：默认屏蔽 effect 输出（标记 LOW_COUNT），或 v2 收缩。Rosace 论文证明收缩可显著降低此类假阳性。
5. **replicate 合并错误做法**：直接相加 counts 会放大测序深度差；应**先各自算 score 再逆方差加权/随机效应合并**（Enrich2）。
6. **大文件与内存**：严禁整文件载入（dms_tools2 约 1GB/百万 PE reads 的做法在桌面不可行）；流式 + 线程局部计数。gzip 解压与哈希查表是热点，需基准测试（目标：M 系芯片 ≥ 50 MB/s/线程，经验值）。
7. **本地算力**：Mac 上不做 MCMC；贝叶斯功能 v2 用经验贝叶斯/解析近似，或可选导出到 R/Python 脚本桥接。

---

## 7. MVP 实施方案

### 7.1 模块拆分

| 组件 | 技术 | 内容 |
|---|---|---|
| `QCEngine`（Swift package） | 纯 Swift，零外部二进制 | FASTQ 流式解析、gzip、锚定、变体查表计数、指标计算、判定规则 |
| `AnalysisEngine`（Swift package） | 纯 Swift（统计自实现：加权平均、BH-FDR、WLS） | 归一化、log2FC+CI、replicate 合并、热图数据 |
| `QCUI` / `AnalysisUI`（SwiftUI） | App 内模块 | §3.3 / §4.3 的页面；图表用 Swift Charts |
| 存储 | SQLite（GRDB 或 CoreData） | §5.1 schema |

**依赖结论：不需要 BWA/BBMap 等外部二进制；MVP 可 100% 纯 Swift 实现。** 外部比对器仅作为未来诊断模式的可选集成。

### 7.2 里程碑与工作量（人日，1 名熟悉 Swift 的开发者）

| 里程碑 | 内容 | 估时 |
|---|---|---|
| M1 QC 引擎核心 | FASTQ 流式解析 + gzip + 锚定 + 词典计数 + 对账 | 8–10 |
| M2 QC 指标与报告 | 指标集、判定规则、报告页、CSV/JSON 导出 | 6–8 |
| M3 Analysis 引擎 | 归一化、log2FC+CI、replicate 加权合并、null/FDR | 6–8 |
| M4 Analysis UI | 变体表、missense 热图（Swift Charts）、条件对比、PNG 导出 | 8–10 |
| M5 数据层与联调 | SQLite schema、设计模块对接、端到端测试（合成数据 + 1 个真实数据集） | 5–7 |
| **合计 MVP** | | **33–43 人日** |
| v1.1 | 时间序列 WLS、PDF 报告、外部比对器诊断模式 | +8–10 |
| v2 | Rosace 式收缩、结构映射、NB-GLM | 另立项评估 |

---

## 附：主要参考来源

- DiMSum: [github.com/lehner-lab/DiMSum](https://github.com/lehner-lab/DiMSum)；[Faure et al., Genome Biology 2020](https://doi.org/10.1186/s13059-020-02091-3)
- Enrich2: [github.com/FowlerLab/Enrich2](https://github.com/FowlerLab/Enrich2)；[Rubin et al., Genome Biology 2017](https://doi.org/10.1186/s13059-017-1272-5)
- mutscan: [github.com/fmicompbio/mutscan](https://github.com/fmicompbio/mutscan)；[Soneson et al., Genome Biology 2023](https://doi.org/10.1186/s13059-023-02967-0)
- dms_tools2: [jbloomlab.github.io/dms_tools2](https://jbloomlab.github.io/dms_tools2/)；dms-vep: [github.com/dms-vep](https://github.com/dms-vep)
- Rosace: [Rao et al., bioRxiv 2023](https://doi.org/10.1101/2023.10.24.562292)；[github.com/pimentellab/rosace](https://github.com/pimentellab/rosace)
- FitSeq: [Li et al., Cell Systems 2018](https://doi.org/10.1016/j.cels.2018.09.004)
- MAGeCK-VISPR: [Li et al., Genome Biology 2015](https://doi.org/10.1186/s13059-015-0843-6)
- Index hopping: [Illumina 白皮书 770-2017-004](https://www.illumina.com/content/dam/illumina-marketing/documents/products/whitepapers/index-hopping-white-paper-770-2017-004.pdf)；[MacConaill et al. 2018, UDI](https://pmc.ncbi.nlm.nih.gov/articles/PMC5759201/)
