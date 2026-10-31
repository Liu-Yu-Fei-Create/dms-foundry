import Foundation

public struct QCFinding: Codable, Sendable {
    public enum Severity: String, Codable, Sendable { case block, warn, info, pass }
    public var severity: Severity
    public var title: String
    public var detail: String
    public var action: String
    public init(severity: Severity, title: String, detail: String, action: String) {
        self.severity = severity; self.title = title; self.detail = detail; self.action = action
    }
}

/// 把指标翻译成“为什么重要 + 怎么办”。
public enum QCDiagnosis {

    /// 支撑 100× 中位覆盖所需的 reads 估算
    public static func readsFor100x(designed: Int, anchoredRate: Double) -> Int {
        let rate = max(anchoredRate, 0.05)
        return Int((Double(designed) * 100 / rate).rounded(.up))
    }

    public static func headline(_ s: QCSummary) -> String {
        switch s.verdict {
        case "pass":
            return "文库完整、分布均一，可以进入筛选实验。"
        case "warn":
            return "文库基本可用，但有风险项：建议先处理，再投入筛选。"
        default:
            return "不建议直接进入筛选：这份文库可能让下游实验白做。"
        }
    }

    public static func findings(_ s: QCSummary, spectrum: QCErrorSpectrum) -> [QCFinding] {
        var out: [QCFinding] = []
        let observed = s.observedRate
        let zeroPct = s.designedVariants == 0 ? 0 : Double(s.zeroCount) / Double(s.designedVariants)
        let needs = readsFor100x(designed: s.designedVariants, anchoredRate: s.anchoredRate)

        if observed < 0.90 {
            out.append(.init(severity: .block, title: "文库完整性不足",
                             detail: "只有 \(pct(observed)) 的设计变体被测到（\(s.observedVariants)/\(s.designedVariants)），低于 90% 的底线。常见原因：合成池缺失、克隆/转化丢失，或测序量不足。",
                             action: "先导出「缺失变体清单」与合成订单核对；确认池里有，再补测序；仍缺失则补合成该子库。"))
        } else if observed < 0.95 {
            out.append(.init(severity: .warn, title: "有 \(s.zeroCount) 个变体没被测到",
                             detail: "观测率 \(pct(observed))，低于 95% 的推荐线。这些变体在下游筛选里会被当成“无数据”，影响覆盖度。",
                             action: "导出缺失清单，核对合成/克隆；如果只是测序深度不够，按建议补测。"))
        }

        if s.medianCoverage < 20 {
            out.append(.init(severity: .block, title: "测序深度严重不足",
                             detail: "中位覆盖只有 \(fmt(s.medianCoverage))×，远低于 100×。低计数会让效应估计方差爆炸，弱效应变体基本测不出来。",
                             action: "补测到约 \(needs) 条 reads（当前 \(s.totalReads) 条）；或减少单次测序的样本数。"))
        } else if s.medianCoverage < 100 {
            out.append(.init(severity: .warn, title: "测序深度偏低",
                             detail: "中位覆盖 \(fmt(s.medianCoverage))×，推荐 ≥100×。低丰度变体的读数会很少，效应置信区间变宽。",
                             action: "补测到约 \(needs) 条 reads，或合并更多测序数据。"))
        }

        if s.gini > 0.5 {
            out.append(.init(severity: .block, title: "文库分布极不均一",
                             detail: "Gini \(fmt(s.gini))，说明少数变体占了大部分 reads。常见原因：PCR 偏差、转化效率差异、混池不均。",
                             action: "检查 PCR 循环数与模板量；重新混池/重新转化，再测一次。"))
        } else if s.gini > 0.3 {
            out.append(.init(severity: .warn, title: "文库均一性一般",
                             detail: "Gini \(fmt(s.gini))，超过 0.3 的经验线，部分变体可能被系统性低估。",
                             action: "复核 PCR 与混池步骤；下游分析时对低覆盖变体保持谨慎。"))
        }

        if s.anchoredRate < 0.80 {
            out.append(.init(severity: .block, title: "锚定率过低",
                             detail: "只有 \(pct(s.anchoredRate)) 的 reads 能定位到设计插入片段。多半是引物/接头不匹配、参考选错，或文库方向不对。",
                             action: "核对测序引物与插入片段两端序列；确认 sample sheet 里的子库与参考对应；必要时换锚点重跑。"))
        }

        let total = max(s.totalReads, 1)
        let unknownPct = Double(spectrum.unknownSingle) / Double(total)
        if unknownPct > 0.05 {
            out.append(.init(severity: .warn, title: "非设计序列比例偏高",
                             detail: String(format: "%.1f%% 的 reads 是设计外单点变异，提示合成错误或 PCR 突变偏高。", unknownPct * 100),
                             action: "看错误谱与原始 reads；必要时提高合成质量或降低 PCR 循环数。"))
        }

        if out.isEmpty {
            out.append(.init(severity: .pass, title: "全部规则通过",
                             detail: "观测率、深度、均一性与锚定率都在推荐线内。",
                             action: "可以进入筛选实验；保留本次报告作为批次基线。"))
        }
        return out
    }

    /// 每个指标“意味着什么”
    public static let metricMeaning: [(String, String)] = [
        ("锚定率", "能定位到设计插入片段的 reads 比例；低 = 引物/接头或参考有问题。"),
        ("观测率", "设计变体里至少被测到 1 条 read 的比例；直接决定文库“全不全”。"),
        ("零计数", "一条 read 都没有的设计变体数量；这些变体在下游没有数据。"),
        ("中位覆盖", "每个变体的 reads 中位数；决定效应估计的精度。"),
        ("Gini", "变体间 reads 分布的不均一程度；越高说明少数变体垄断了测序量。"),
        ("判定", "以上规则里最差的一项，用来决定能不能进筛选。"),
    ]

    private static func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }
    private static func fmt(_ x: Double) -> String { String(format: "%.2f", x) }
}
