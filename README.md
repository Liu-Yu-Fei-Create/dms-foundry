# DMS Foundry

[![CI](https://github.com/Liu-Yu-Fei-Create/dms-foundry/actions/workflows/ci.yml/badge.svg)](https://github.com/Liu-Yu-Fei-Create/dms-foundry/actions/workflows/ci.yml)

**Deep mutational scanning (DMS) library design, QC and analysis — a native macOS app.**

一个 macOS 原生应用，覆盖 DMS 实验的四个环节：**文库设计 → 文库质控 → 筛选方案 → 筛选分析**。纯 Swift（SwiftUI + 无第三方依赖的 DMSEngine），黑白界面，支持深色模式。

MIT 许可，见 [LICENSE](LICENSE)。

> 命名：定名 DMS Foundry。`DMS Designer` 已被同领域 Python 工具包占用（[文档](https://jackdesmarais.github.io/DMS_Designer/index.html) / [仓库](https://github.com/jackdesmarais/DMS_Designer)），故避开。

## 下载

**➡️ [下载最新版](https://github.com/Liu-Yu-Fei-Create/dms-foundry/releases/latest)**

从 Releases 下载 `DMSFoundry-<version>.zip`，解压后把 `DMS Foundry.app` 拖进「应用程序」。

- 构建为 **ad-hoc 签名、未公证**：首次打开请右键 →「打开」，或执行
  `xattr -dr com.apple.quarantine "DMS Foundry.app"`。
- 要求 macOS 14+；Release 里的包是 Apple Silicon 构建，Intel 请从源码编译。

## 模块

| 模块 | 做什么 |
| --- | --- |
| **文库设计** | 导入质粒（.gb/.dna/.fasta）→ 标注突变 CDS 与区段 → 文库参数（氨基酸集合、同义/终止/稀有密码子、密码子策略与表）→ 四类质检变体 → Golden Gate / Gibson 组装（overhang 保真度评分、Refine）→ 子库切分与 index 配对 → 逐条 oligo 生成与 QC → 导出四件套 |
| **文库质控** | 导入 FASTQ（单端/双端 overlap merge、可选 fastp），按设计清单逐变体对账；输出总览、诊断建议、缺失清单、错误谱 |
| **筛选方案** | 定义分组（默认一子库一分组）、每个分组的重复数，供筛选分析直接读取 |
| **筛选分析** | 两种输入（FASTQ 样本表 / counts 长表）；**逐组解析**（组内结论）与**跨组归一**（WT 基线、逆方差合并、同义 null + BH-FDR、组间相关）；结构映射（PDB/mmCIF、链选择、导出 PNG） |

## 截图

![文库设计 · 参数](docs/screenshots/polish-params.png)
![文库质控](docs/screenshots/qc-module.png)
![筛选方案](docs/screenshots/screening-module.png)
![筛选分析 · 跨组归一](docs/screenshots/analysis-joint.png)

<details>
<summary>更多截图（结构映射、环形质粒图、设置）</summary>

![结构映射](docs/screenshots/structure-map.png)
![环形质粒图](docs/screenshots/polish-map.png)
![FASTQ 输入](docs/screenshots/analysis-fastq.png)
![设置](docs/screenshots/settings.png)

</details>

## 构建与测试

```bash
cd mac
swift test                    # 37 条引擎测试
CONFIG=debug ./build.sh       # 组装 "DMS Foundry.app"
open "DMS Foundry.app"

# 命令行自检（不需要窗口）
DMS_SELFTEST=1 "DMS Foundry.app/Contents/MacOS/DMSFoundry"
DMS_QC_SELFTEST=1 "DMS Foundry.app/Contents/MacOS/DMSFoundry"
DMS_ANALYSIS_SELFTEST=1 "DMS Foundry.app/Contents/MacOS/DMSFoundry"
DMS_ANALYSIS_FASTQ_SELFTEST=1 "DMS Foundry.app/Contents/MacOS/DMSFoundry"
```

快捷键：`⌘L` 载入 TEM-1 示例，`⌘1–8` 切换设计步骤，`⌥1–4` 切换模块，`⌘,` 打开设置，`⌘U` 检查更新。

## 设计流程

1. 新建项目，导入表达质粒（GenBank / SnapGene `.dna` / FASTA）；
2. 在轨道或环形图上选中突变 CDS，设定 aa 区间；
3. 设文库参数：氨基酸集合、是否含同义/终止/野生型、密码子策略与密码子表、子库步长；
4. 配置质检变体：终止密码子、同义突变、脯氨酸、随机区；
5. 选组装方式（Golden Gate Type IIS 酶或 Gibson 同源臂），查看子库接口保真度，必要时 Refine；
6. 分配子库 index（15–25 nt、两两不交叉、3′ 端唯一）；
7. 生成文库：拼装每条 oligo，逐条做长度/GC/同聚物/内部位点检查，并按位点做覆盖对账；
8. 导出四件套。

### 导出文件

| 文件 | 内容 |
| --- | --- |
| `order.csv` | pool / name / sequence，一行一条 oligo，UTF-8 BOM |
| `audit.csv` | 完整审计列：index、overhang、突变、来源、error/warning 代码 |
| `library.fasta` | 同样内容的 FASTA |
| `manifest.json` | 引擎版本、酶、步长、计数、覆盖缺口、问题清单、几何约定 |

## 文库质控

- 输入：单个 FASTQ，或样本表（`sample,sublibrary,replicate,condition,r1,r2`），支持双端 overlap merge 与可选 fastp；
- 与设计清单逐变体对账，输出观测率、零计数、中位覆盖、Gini、错误谱；
- 诊断规则给出原因与下一步（补测 reads 数、导出缺失清单等）；
- 结果写入 `runs.sqlite`，可在「最近运行」里载入。

## 筛选方案

- 分组决定哪些子库一起筛；默认一子库一分组；
- 每个分组设置重复数；
- 方案存进项目，筛选分析直接读取；空分组会提示并可清理。

## 筛选分析

- **逐组解析**：只分析单个分组及其重复，结论限定在该分组的筛选范围内；
- **跨组归一**：每组按本组 WT 对照的平均 fold-change 归一，再逆方差合并成蛋白层面数据；同义变体做 null，BH-FDR；给出组间相关矩阵；
- **结构映射**：导入 PDB 或 mmCIF，按 CA 骨架着色，自动识别相同链（同源二聚体默认只映射一条），可切换灰阶/蓝红/热度配色，导出 PNG。

## 设置

- **默认值**：新项目继承的宿主、文库参数、组装方式与酶、质检项默认数量；
- **命名预设**：保存/应用/删除参数组合；
- **外观**：跟随系统 / 浅色 / 深色；
- **外部工具**：fastp 开关、路径与参数；
- **数据存储**：可迁移到自定义目录（迁移时显示进度，完成后自动重启）。

## 数据来源

| 文件 | 内容 | 来源 |
| --- | --- | --- |
| `codons_ecoli.json` | E. coli W3110 密码子频率 | [Kazusa](http://www.kazusa.or.jp/codon/cgi-bin/showcodon.cgi?species=316407&aa=1&style=N) |
| `codons_human.json` | Human 密码子频率 | [Kazusa](http://www.kazusa.or.jp/codon/cgi-bin/showcodon.cgi?species=9606&aa=1&style=N) |
| `enzymes.json` | BsaI/BsmBI/BbsI/SapI/BspQI/AarI 几何 | REBASE 各酶页面 |
| `overhangs_t4.json` | 256 个 4-nt overhang 保真度 | Potapov et al. 2018 方法官方分析仓库（SRA PRJNA894239） |
| `indices_1024.json` | 1024 条 20 nt 子库 index | 本项目生成（seed 20261102） |
| `tem1_cds.gb` | TEM-1 成熟 CDS 示例 | UniProt P62593，E. coli 最优密码子回译 |

代码以 MIT 发布；数据表来自公开来源，重分发时请保留出处与引用。Kazusa / REBASE 数据按学术使用引用；若需商业化，建议改为构建时从原始来源获取。

## 更新机制

- `mac/release.sh <version> <build>`：构建 → zip → SHA-256 → Ed25519 签名 → 生成更新清单；
- 应用内「检查更新…」下载后做 **SHA-256 + Ed25519 双校验**，再在 Finder 中显示；
- ad-hoc 阶段不做就地替换（Gatekeeper 限制），拿到 Developer ID 后可接 Sparkle 自动安装；
- 仓库不含更新私钥，自行发布请生成自己的密钥对。

## 贡献

欢迎 issue / PR。提交前请确认 `swift test` 与 `CONFIG=debug ./build.sh` 通过；详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## License

[MIT](LICENSE) © 2026 DMS Foundry contributors
