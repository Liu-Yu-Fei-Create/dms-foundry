#!/usr/bin/env python3
"""生成软著材料：源代码文档（前30+后30页）与用户手册（docx）。

用法：python3 legal/software-copyright/make_docs.py
"""
from __future__ import annotations
import math
import re
from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / "out"
OUT.mkdir(exist_ok=True)

SOFTWARE = "DMS Foundry 深度突变扫描文库设计与分析软件"
SHORT = "DMS Foundry"
VERSION = "V0.5.3"
APPLICANT = "刘宇飞"
DATE = "2026-10-31"

LINES_PER_PAGE = 50


def set_font(run, name="Consolas", size=9, bold=False, east="宋体"):
    run.font.name = name
    run.font.size = Pt(size)
    run.bold = bold
    rPr = run._element.get_or_add_rPr()
    rFonts = rPr.find(qn("w:rFonts"))
    if rFonts is None:
        rFonts = OxmlElement("w:rFonts")
        rPr.append(rFonts)
    rFonts.set(qn("w:eastAsia"), east)


def add_page_number(paragraph):
    run = paragraph.add_run()
    set_font(run, "Times New Roman", 9)
    fld1 = OxmlElement("w:fldChar"); fld1.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText"); instr.set(qn("xml:space"), "preserve"); instr.text = "PAGE"
    fld2 = OxmlElement("w:fldChar"); fld2.set(qn("w:fldCharType"), "end")
    run._r.append(fld1); run._r.append(instr); run._r.append(fld2)


def header_footer(doc, label: str):
    section = doc.sections[0]
    section.page_width, section.page_height = Cm(21), Cm(29.7)
    section.top_margin = Cm(2.0)
    section.bottom_margin = Cm(1.8)
    section.left_margin = Cm(2.2)
    section.right_margin = Cm(2.2)

    hp = section.header.paragraphs[0]
    hp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = hp.add_run(f"{SOFTWARE} {VERSION}    {label}")
    set_font(r, "宋体", 9, east="宋体")
    r.font.color.rgb = RGBColor(0x44, 0x44, 0x44)

    fp = section.footer.paragraphs[0]
    fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_page_number(fp)


def cover(doc, kind: str):
    for _ in range(6):
        doc.add_paragraph()
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_font(p.add_run(SOFTWARE), "黑体", 22, bold=True, east="黑体")
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_font(p.add_run(f"{VERSION}  {kind}"), "黑体", 18, east="黑体")
    for _ in range(4):
        doc.add_paragraph()
    for text in [f"著作权人：{APPLICANT}", f"开发完成日期：{DATE}", f"文档日期：{DATE}"]:
        p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        set_font(p.add_run(text), "宋体", 12, east="宋体")
    doc.add_page_break()


def source_files():
    files = []
    files.append(ROOT / "mac" / "Package.swift")
    files.append(ROOT / "mac" / "build.sh")
    for pattern in ["mac/Sources/DMSEngine/**/*.swift", "mac/Sources/DMSFoundry/**/*.swift"]:
        files.extend(sorted(ROOT.glob(pattern)))
    return [f for f in files if f.exists()]


def collect_source_lines():
    lines = []
    for f in source_files():
        rel = f.relative_to(ROOT)
        lines.append(f"// ========================================================================")
        lines.append(f"// File: {rel}")
        lines.append(f"// ========================================================================")
        text = f.read_text(encoding="utf-8", errors="replace")
        lines.extend(text.splitlines())
        lines.append("")
    return lines


def build_source_doc():
    lines = collect_source_lines()
    per_page = LINES_PER_PAGE
    total_pages = math.ceil(len(lines) / per_page)
    first = min(30, total_pages)
    last = min(30, max(0, total_pages - first))
    selected = lines[: first * per_page]
    if last:
        selected += lines[(total_pages - last) * per_page :]

    doc = Document()
    header_footer(doc, "源程序")
    cover(doc, "源程序")

    text = "\n".join(selected)
    pages = [text[i : i + per_page * 120] for i in range(0, len(text), per_page * 120)]
    # 按行切页，避免字符切分
    page_lines = [selected[i : i + per_page] for i in range(0, len(selected), per_page)]

    p = doc.add_paragraph()
    set_font(p.add_run(f"源程序共 {len(lines)} 行，全文 {total_pages} 页；以下为前 {first} 页"
                       + (f"与后 {last} 页" if last else "（全文不足 60 页）") + "。"), "宋体", 9, east="宋体")
    doc.add_paragraph()

    for idx, chunk in enumerate(page_lines):
        if idx > 0:
            doc.add_page_break()
        for ln in chunk:
            para = doc.add_paragraph()
            para.paragraph_format.space_before = Pt(0)
            para.paragraph_format.space_after = Pt(0)
            para.paragraph_format.line_spacing = Pt(12.6)
            set_font(para.add_run(ln if ln else " "), "Consolas", 8.5, east="宋体")

    path = OUT / f"DMS-Foundry-源代码.docx"
    doc.save(path)
    return path, len(lines), total_pages, len(page_lines)


def heading(doc, text, level=1):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12 if level == 1 else 8)
    p.paragraph_format.space_after = Pt(6)
    set_font(p.add_run(text), "黑体", 16 if level == 1 else 13, bold=True, east="黑体")


def body(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.line_spacing = 1.4
    set_font(p.add_run(text), "宋体", 10.5, east="宋体")


def bullet(doc, text):
    p = doc.add_paragraph(style=None)
    p.paragraph_format.left_indent = Cm(0.6)
    p.paragraph_format.space_after = Pt(2)
    set_font(p.add_run("· " + text), "宋体", 10.5, east="宋体")


def table(doc, rows, widths=None):
    t = doc.add_table(rows=len(rows), cols=len(rows[0]))
    t.style = "Table Grid"
    for i, row in enumerate(rows):
        for j, cell_text in enumerate(row):
            cell = t.cell(i, j)
            cell.text = ""
            p = cell.paragraphs[0]
            set_font(p.add_run(str(cell_text)), "宋体", 9.5, bold=(i == 0), east="宋体")


def image(doc, path: Path, width_cm=15.5):
    if path.exists():
        doc.add_picture(str(path), width=Cm(width_cm))
        doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
        cap = doc.add_paragraph(); cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        set_font(cap.add_run(path.stem), "宋体", 9, east="宋体")


def build_manual():
    doc = Document()
    header_footer(doc, "用户手册")
    cover(doc, "用户手册")
    shots = ROOT / "docs" / "screenshots"

    def chapter(title):
        if doc.paragraphs:
            doc.add_page_break()
        heading(doc, title)

    chapter("1 软件概述")
    body(doc, "DMS Foundry 是运行于 macOS 的深度突变扫描（Deep Mutational Scanning，DMS）文库设计与分析软件。"
              "软件覆盖从质粒导入、文库设计、组装方案、子库 index 分配，到测序质控、筛选方案与效应分析、结构映射的完整流程。")
    body(doc, "DMS 实验的核心是构建一个“一个变体一条序列”的文库，经筛选与测序后估计每个突变的功能效应。"
              "本软件把这条链路中容易出错、依赖手工计算的部分产品化：密码子选择、组装接口、index 配对、"
              "测序计数与效应估计。")
    bullet(doc, "文库设计：导入 GenBank / SnapGene .dna / FASTA，标注突变 CDS 与氨基酸区间，生成单点突变文库。")
    bullet(doc, "组装设计：Golden Gate（Type IIS 酶）与 Gibson 两种方案，按 overhang 实测保真度评分，支持同义替换 Refine。")
    bullet(doc, "子库与 index：自动切分子库，匹配 15–25 nt index 对，生成带 index 的 oligo 序列。")
    bullet(doc, "文库质控：FASTQ 流式解析、双端 overlap merge、可选 fastp，与设计清单逐变体对账。")
    bullet(doc, "筛选方案与筛选分析：分组与重复设置；逐组解析与跨组归一；结构映射。")

    chapter("2 运行环境")
    table(doc, [
        ["项目", "要求"],
        ["操作系统", "macOS 14.0 及以上"],
        ["处理器", "Apple Silicon（Intel 需从源码编译）"],
        ["内存", "8 GB 及以上"],
        ["磁盘", "1 GB 可用空间（数据目录可迁移）"],
        ["运行时依赖", "无（纯 Swift，静态打包）"],
        ["外部工具（可选）", "fastp（FASTQ 预过滤）"],
    ])
    body(doc, "软件为 ad-hoc 签名、未公证版本时，首次打开需右键选择「打开」，或执行 "
              "xattr -dr com.apple.quarantine \"DMS Foundry.app\" 解除隔离。")

    chapter("3 安装与启动")
    bullet(doc, "下载 DMSFoundry-<version>.zip，解压后把 DMS Foundry.app 拖入「应用程序」。")
    bullet(doc, "首次启动会创建数据目录 ~/Library/Application Support/DMSFoundry。")
    bullet(doc, "可在「设置 → 默认值 → 数据存储」中把数据迁移到自定义目录。")
    bullet(doc, "卸载：把应用拖入废纸篓；如需彻底清除，再删除数据目录。")

    chapter("4 界面总览")
    body(doc, "主窗口左侧为模块导航（文库设计、文库质控、筛选方案、筛选分析），右侧为当前模块内容。"
              "文库设计模块顶部为 8 步流程条，当前步骤加粗并带下划线；已完成步骤带勾。"
              "窗口底部为状态栏，显示最近一次操作结果。")
    body(doc, "界面采用黑白灰配色，支持浅色、深色与跟随系统三种外观，可在「视图 → 外观」或设置中切换。")
    image(doc, shots / "polish-params.png")

    chapter("5 文库设计")
    heading(doc, "5.1 新建项目与导入质粒", 2)
    body(doc, "点击「新建项目」，填写项目名称与宿主。宿主会决定默认密码子表（E. coli 菌株使用 E. coli 表，"
              "哺乳动物细胞使用人表）。支持 GenBank（.gb/.gbk）、SnapGene（.dna）与 FASTA（.fasta）。"
              "导入后自动解析序列与注释，并在环形/线性轨道上显示特征。")
    body(doc, "SnapGene 文件解析文档头、DNA 块与 features XML；若导入失败，建议在 SnapGene 中另存为 GenBank 再试。")
    image(doc, shots / "polish-map.png")
    heading(doc, "5.2 标注突变目标", 2)
    body(doc, "在特征列表中选中 CDS，设置起始与结束氨基酸，软件会自动换算核苷酸范围并校验读框。"
              "反向链 CDS 会先取反向互补，再按密码子寻址；读框起点与翻译表来自注释。")
    heading(doc, "5.3 文库参数", 2)
    table(doc, [
        ["参数", "说明"],
        ["突变集合", "全部 19 种氨基酸，或指定子集"],
        ["同义突变", "是否加入同义密码子变体"],
        ["稀有密码子", "是否保留宿主稀有密码子"],
        ["终止密码子", "是否把终止作为突变类型"],
        ["野生型对照", "是否保留 WT 变体"],
        ["密码子策略", "最优 / 随机 / 避开稀有后的随机"],
        ["密码子表", "E. coli 或人，按宿主自动切换"],
        ["子库步长", "默认 150 nt，自动计算子库数与长度预算"],
    ])
    body(doc, "密码子表来自 Kazusa Codon Usage Database；稀有密码子按宿主频率判定。"
              "子库步长会影响每条 oligo 的长度，软件会实时给出预估长度与合成上限提示。")
    heading(doc, "5.4 质检项", 2)
    body(doc, "可分别配置终止密码子、同义突变、脯氨酸与随机区四类质检变体，并设定数量与氨基酸范围。"
              "这些变体用于验证文库构建与检测链路，会与设计变体统一去重编号。")
    heading(doc, "5.5 组装方式", 2)
    body(doc, "Golden Gate 需选择 Type IIS 酶，软件检查内部位点并给出 overhang 保真度评分；"
              "保真度低于 0.60 阻断，0.60–0.80 警告。也可选择 Gibson，使用 25 bp 同源臂。"
              "子库边界按密码子对齐搜索，只允许缩短，保证覆盖连续、无缺口。")
    image(doc, shots / "polish-generate.png")
    heading(doc, "5.6 index 与导出", 2)
    body(doc, "子库 index 由内置冻结表匹配，保证两两不交叉、3′ 端唯一。生成文库后逐条检查长度、GC、同聚物与内部位点，"
              "并导出 order.csv、audit.csv、library.fasta、manifest.json。")
    body(doc, "order.csv 可直接交给合成商；audit.csv 保留 index、overhang 与问题代码，便于回溯；"
              "manifest.json 记录引擎版本、酶、步长与覆盖缺口。")

    chapter("6 文库质控")
    body(doc, "选择子库与 FASTQ（支持 .gz），或导入样本表批量运行。软件用恒定区锚点定位插入片段，逐变体计数并与设计清单对账。")
    bullet(doc, "双端：先做 overlap merge（≥20 nt、≤10% 错配），失败时回退单端。")
    bullet(doc, "可选 fastp 过滤，默认开启，路径与参数在设置中修改。")
    bullet(doc, "报告包含观测率、零计数、中位覆盖、Gini、错误谱，并给出诊断与建议。")
    image(doc, shots / "qc-module.png")
    body(doc, "判定阈值：观测率 ≥95% 通过，90–95% 警告；中位覆盖 ≥100× 通过，20–100× 警告；"
              "Gini <0.3 通过；锚定率 <80% 阻断。阈值可按实验经验调整。")

    chapter("7 筛选方案")
    body(doc, "按子库分配筛选分组，默认每个子库一个分组，可合并；每个分组设置重复数。"
              "方案保存在项目内，筛选分析直接读取。空分组不参与分析，可一键清理。")
    image(doc, shots / "screening-module.png")

    chapter("8 筛选分析")
    heading(doc, "8.1 输入", 2)
    bullet(doc, "FASTQ 样本表：sample, sublibrary, replicate, condition, r1, r2。")
    bullet(doc, "counts 长表：variant_id, sample, reads, condition, replicate, sublibrary, class。")
    heading(doc, "8.2 逐组解析", 2)
    body(doc, "只分析单个分组及其重复，结论限定在该分组的筛选范围内，不跨组比较。")
    heading(doc, "8.3 跨组归一", 2)
    body(doc, "每组按本组 WT 对照的平均 fold-change 归一，再按逆方差合并为蛋白层面数据；"
              "同义变体作为 null 计算 z、p 与 BH-FDR，并给出组间相关矩阵。")
    body(doc, "富集比采用 log2(((c_sel+p)/N_sel)/((c_in+p)/N_in))，p=0.5；方差用 delta 法；"
              "合并权重为 1/SE²；低计数（<10 reads）变体标记 LOW_COUNT 并排除出合并。")
    image(doc, shots / "analysis-joint.png")
    heading(doc, "8.4 结构映射", 2)
    body(doc, "导入 PDB 或 mmCIF，按 CA 骨架着色；自动识别相同链并默认只映射每组一条；"
              "支持灰阶、蓝红、热度配色，并可导出 1600×1200 PNG。")
    image(doc, shots / "structure-map.png")

    chapter("9 设置")
    bullet(doc, "默认值：新项目继承的宿主、文库参数、组装方式与质检默认数量。")
    bullet(doc, "命名预设：保存/应用/删除参数组合。")
    bullet(doc, "外观：跟随系统 / 浅色 / 深色。")
    bullet(doc, "外部工具：fastp 开关、路径、参数。")
    bullet(doc, "数据存储：迁移数据目录，迁移时显示进度并自动重启。")
    image(doc, shots / "settings.png")

    chapter("10 文件格式")
    table(doc, [
        ["文件", "内容"],
        ["order.csv", "pool、name、sequence，UTF-8 BOM"],
        ["audit.csv", "index、overhang、突变、来源、问题代码"],
        ["library.fasta", "oligo 序列 FASTA"],
        ["manifest.json", "版本、酶、步长、计数、覆盖缺口、问题清单"],
        ["runs.sqlite", "质控与分析运行记录（应用内）"],
    ])

    chapter("11 常见问题")
    body(doc, "问：首次打开提示「无法验证开发者」？答：右键 →「打开」，或执行解除隔离命令。")
    body(doc, "问：分析时提示 fastp 不存在？答：在设置中填写 fastp 路径，或关闭 fastp。")
    body(doc, "问：载入旧结果时提示「基于旧设计」？答：设计已修改，请用当前设计重新运行。")
    body(doc, "问：Intel Mac 能否使用？答：可从源码执行 swift build 编译。")
    body(doc, "问：数据存在哪里？答：默认 ~/Library/Application Support/DMSFoundry，可在设置中迁移。")

    chapter("第二部分 设计说明")
    heading(doc, "10 总体架构", 2)
    body(doc, "软件分为引擎与应用两层。引擎 DMSEngine 只依赖 Foundation，包含序列解析、坐标换算、密码子表、"
              "突变枚举、子库切分、组装规划、index 匹配、文库生成、质控计数、分析与导出；"
              "应用层 DMSFoundry 使用 SwiftUI 构建界面，不包含业务算法。")
    body(doc, "数据流：质粒序列与注释 → 目标 CDS（编码链上下文）→ 突变枚举（Variant）→ 子库切分（SubLibrary）→ "
              "组装规划（Golden Gate/Gibson）→ index 分配 → oligo 生成（OligoRecord）→ 导出；"
              "质控输入 FASTQ 与设计清单，输出计数与对账；分析输入计数矩阵与样本元数据，输出效应。")
    body(doc, "模块边界通过纯数据类型（Codable）传递，便于测试与持久化；界面只负责状态与呈现。")

    heading(doc, "11 数据模型", 2)
    table(doc, [
        ["类型", "职责"],
        ["Project", "项目：宿主、质粒、目标、参数、组装、筛查方案"],
        ["Plasmid / Feature", "序列与注释（类型、链、子区段、密码子起点、翻译表）"],
        ["Target", "突变目标：CDS 与氨基酸区间"],
        ["LibraryParams", "氨基酸集合、同义/终止/WT、密码子策略与表、步长、随机种子"],
        ["Assembly", "组装方式、酶、同源臂长度、index 种子"],
        ["Variant", "单点突变：位置、野生型/突变氨基酸、密码子、来源"],
        ["SubLibrary", "子库：氨基酸范围、核苷酸偏移与长度"],
        ["OligoRecord", "最终 oligo：名称、序列、index、overhang、问题列表"],
    ])
    body(doc, "所有持久化对象带 schemaVersion；项目以原子写保存到数据目录，避免中断导致文件损坏。")

    heading(doc, "12 设计算法", 2)
    body(doc, "突变枚举：按目标区间逐密码子生成 19 种氨基酸替换；可选的同义、终止、脯氨酸与随机区变体单独生成，"
              "统一去重编号。密码子策略支持最优、随机与避开稀有三类，随机数使用可复现的 SplitMix64 流。")
    body(doc, "组装规划：Golden Gate 的子库边界按密码子对齐搜索，只允许缩短，保证覆盖连续、无缺口、总长不变；"
              "overhang 由野生型边界序列决定，不可自由挑选，按 T4 连接酶实测保真度评分；"
              "内部 Type IIS 位点按整条片段扫描，必要时通过同义替换 Refine 消除。")
    body(doc, "Index 匹配：从冻结表中挑选 15–25 nt 序列，要求与质粒序列无 15-mer 交叉、3′ 端唯一、"
              "两两不交叉、Tm 差不超过 2 °C；同一子库内成对使用。")

    heading(doc, "13 质控算法", 2)
    body(doc, "FASTQ 以字节流分块读取，.gz 通过系统 gzip 管道解压，内存恒定；双端先做 overlap merge，"
              "R2 反向互补后与 R1 找最长重叠（≥20 nt、≤10% 错配），失败时回退单端。")
    body(doc, "计数使用恒定区锚点定位插入片段，支持反向互补；逐密码子与参考比较，单点差异查表命中设计变体，"
              "其余归入错误谱（野生型、未知单点、多点、未锚定）。")
    body(doc, "对账输出观测率、零计数、中位覆盖、Gini 与每子库指标；诊断规则把指标翻译为阻断/警告与下一步动作。")

    heading(doc, "14 分析算法", 2)
    body(doc, "富集比：log2(((c_sel+p)/N_sel)/((c_in+p)/N_in))，伪计数 p=0.5；方差用 delta 法，"
              "合并采用逆方差加权，SE=1/√Σw；同义变体作为经验 null 计算 z 与 p，再做 BH-FDR。")
    body(doc, "跨组归一：先以各组 WT 对照的平均效应为基线平移，再合并；组间相关在共享变体上计算 Pearson r。"
              "结构映射把变体位置映射到 PDB/mmCIF 的 CA 原子，按效应着色。")

    heading(doc, "15 数据存储与迁移", 2)
    body(doc, "默认数据目录为 ~/Library/Application Support/DMSFoundry，包含 projects、runs.sqlite 与 presets.json。"
              "设置中可迁移到自定义目录：复制 → 校验 → 删除旧数据，迁移时显示进度，完成后自动重启。")

    heading(doc, "16 测试与验证", 2)
    body(doc, "引擎包含 37 条单元测试，覆盖坐标换算、GenBank/FASTA/SnapGene 解析、密码子表、突变枚举、子库切分、"
              "长度预算、随机数、酶扫描、overhang 评分、组装规划、质控、Refine、index 分配、生成与导出、"
              "双端合并、样本表校验与联合分析。")
    body(doc, "另有命令行自检：DMS_SELFTEST、DMS_QC_SELFTEST、DMS_ANALYSIS_SELFTEST、DMS_ANALYSIS_FASTQ_SELFTEST，"
              "用于验证打包后的资源加载与端到端流程。")

    chapter("附录 A 快捷键")
    table(doc, [
        ["快捷键", "功能"],
        ["⌘L", "载入 TEM-1 示例"],
        ["⌘1–8", "切换设计步骤"],
        ["⌥1–4", "切换模块"],
        ["⌘,", "打开设置"],
        ["⌘U", "检查更新"],
    ])

    chapter("附录 B 术语")
    body(doc, "DMS：深度突变扫描。Golden Gate：Type IIS 酶介导的一锅法组装。"
              "Overhang：酶切产生的 4 nt 黏性末端。CPM：每百万 reads 计数。"
              "BH-FDR：Benjamini–Hochberg 错误发现率校正。WT：野生型。")

    chapter("附录 C 示例输出")
    body(doc, "order.csv 前三行：")
    body(doc, "pool,name,sequence,length,gc,enzyme,overhang5,overhang3")
    body(doc, "SL01,SL01-H1A,TTGCTTGTGCTGGGTCTGTC…,216,0.52,BsaI,GGCA,GGAT")
    body(doc, "manifest.json 片段：")
    body(doc, "{\"engineVersion\":\"0.4.5\",\"enzyme\":\"BsaI\",\"stepNt\":150,\"counts\":{\"oligos\":4997,\"errors\":15,\"coverageGaps\":0}}")

    chapter("附录 D 数据来源与许可")
    body(doc, "密码子频率：Kazusa Codon Usage Database（E. coli W3110 / human）。"
              "酶几何：REBASE。Overhang 保真度：Potapov et al. 2018 方法官方分析仓库（SRA PRJNA894239）。"
              "Index 冻结表由本软件生成。示例质粒为 TEM-1 公共序列。")
    body(doc, "软件代码以 MIT 许可发布；数据表重分发时请保留出处与引用。")

    chapter("附录 E 技术支持")
    body(doc, "问题反馈：GitHub Issues。提交时请附 macOS 版本、软件版本（设置页底部）与复现步骤；"
              "涉及数据的请提供脱敏后的最小样例。")

    chapter("附录 F 质控与分析规格（节选）")
    spec = ROOT / "docs" / "qc-analysis-spec.md"
    if spec.exists():
        for raw in spec.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("![") or line.startswith("|"):
                continue
            if line.startswith("###"):
                heading(doc, line.lstrip("# ").strip(), 2)
            elif line.startswith("##"):
                heading(doc, line.lstrip("# ").strip(), 2)
            elif line.startswith("#"):
                heading(doc, line.lstrip("# ").strip(), 2)
            elif line.startswith(("- ", "* ")):
                bullet(doc, line[2:].strip())
            elif line.startswith("```"):
                continue
            else:
                body(doc, line.replace("**", "").replace("`", ""))

    chapter("附录 G 工程与构建")
    body(doc, "源码结构：mac/Package.swift 定义 DMSEngine 与 DMSFoundry 两个目标；"
              "mac/Sources/DMSEngine 为纯 Swift 引擎；mac/Sources/DMSFoundry 为 SwiftUI 应用；"
              "Tests/DMSEngineTests 为引擎测试；tools 为离线数据校验脚本。")
    body(doc, "构建命令：cd mac && swift test；CONFIG=debug ./build.sh 生成 DMS Foundry.app；"
              "发布使用 release.sh 打包、签名并生成更新清单。")
    body(doc, "持续集成：GitHub Actions 在 macos-14 上执行 swift test 与 build.sh。")

    chapter("附录 H 问题代码")
    table(doc, [
        ["代码", "含义"],
        ["oligo.internal-site", "oligo 内出现 Type IIS 酶切位点"],
        ["oligo.homopolymer", "同聚物长度超阈值"],
        ["oligo.length", "oligo 长度超出合成上限"],
        ["oligo.gc", "GC 含量异常"],
        ["qc.stop", "终止密码子质检变体相关问题"],
        ["qc.synonymous", "同义突变质检变体相关问题"],
        ["qc.proline", "脯氨酸质检变体相关问题"],
        ["qc.random", "随机区质检变体相关问题"],
        ["overhang.low-fidelity", "overhang 保真度低于阈值"],
        ["overhang.palindromic", "回文 overhang，禁止使用"],
    ])

    chapter("附录 I 术语表")
    table(doc, [
        ["术语", "说明"],
        ["DMS", "深度突变扫描"],
        ["CDS", "编码序列"],
        ["Type IIS", "在识别位点外侧切割的限制性内切酶"],
        ["Golden Gate", "利用 Type IIS 酶的一锅法组装"],
        ["Gibson", "利用同源臂与连接酶的组装方法"],
        ["Overhang", "酶切后产生的黏性末端"],
        ["Index", "子库扩增/拆分的短序列标签"],
        ["CPM", "每百万 reads 的计数"],
        ["BH-FDR", "Benjamini–Hochberg 错误发现率"],
        ["WT", "野生型"],
        ["Sublibrary", "按区段切分后的子库"],
        ["Refine", "用同义替换消除内部酶切位点"],
    ])

    path = OUT / "DMS-Foundry-用户手册.docx"
    doc.save(path)
    return path


def main():
    src, line_count, total_pages, submitted = build_source_doc()
    manual = build_manual()
    meta = OUT / "metadata.txt"
    meta.write_text(
        f"software={SOFTWARE}\nversion={VERSION}\napplicant={APPLICANT}\n"
        f"source_lines={line_count}\ntotal_pages={total_pages}\nsubmitted_pages={submitted}\n",
        encoding="utf-8",
    )
    print(f"source: {src}  ({line_count} lines, {total_pages} pages, submit {submitted})")
    print(f"manual: {manual}")
    print(f"meta:   {meta}")


if __name__ == "__main__":
    main()
