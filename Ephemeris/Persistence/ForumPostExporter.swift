import Foundation

/// Phase 11 — generate a structured Markdown summary for the user to paste into a
/// forum, Discord channel, or chat with Claude. Includes rig profile, recent nights,
/// observations with source authority, and suggested questions per design §5.5 /
/// the throughline #12 help-prep moment.
///
/// Phase 8's MCP server is the day-to-day conversational path; this exporter is for
/// audiences that aren't using Claude — Cloudy Nights threads, PHD2 forum posts,
/// emailing a friend.
enum ForumPostExporter {

    enum Format: String, CaseIterable, Sendable {
        case markdown    // generic markdown, looks fine in GitHub / Discord / Slack
        case bbcode      // for older forum software (Cloudy Nights, vBulletin-style)
        case plainText   // strip all formatting — for email or terminals

        var displayName: String {
            switch self {
            case .markdown:  return "Markdown"
            case .bbcode:    return "BBCode (forums)"
            case .plainText: return "Plain text"
            }
        }
    }

    struct Inputs: Sendable {
        let profile: RigProfile
        let summaries: [NightSummary]
        let observations: [RecommenderObservation]
        let annotations: [Annotation]
        let format: Format
        let userQuestion: String?
    }

    static func render(_ inputs: Inputs) -> String {
        var out = ""
        out += rigHeader(inputs)
        out += "\n\n"
        out += recentNightsSection(inputs)
        out += "\n\n"
        out += observationsSection(inputs)
        if !inputs.annotations.isEmpty {
            out += "\n\n"
            out += annotationsSection(inputs)
        }
        out += "\n\n"
        out += suggestedQuestionsSection(inputs)
        out += "\n\n"
        out += footer(inputs)
        return applyFormatTransforms(out, format: inputs.format)
    }

    private static func rigHeader(_ i: Inputs) -> String {
        var out = "## Rig\n\n"
        out += "- **Profile**: \(i.profile.effectiveName)"
        if i.profile.effectiveName != i.profile.currentName {
            out += " (PHD2: `\(i.profile.currentName)`)"
        }
        out += "\n"
        out += "- **Mount class**: \(i.profile.mountClass.displayName)"
        if i.profile.hasHighPrecisionEncoders { out += " (high-precision encoders)" }
        out += "\n"
        if i.profile.imagingFocalLength > 0 {
            out += "- **OTA**: \(Int(i.profile.imagingFocalLength))mm"
            if let reducer = i.profile.reducerFactor, reducer != 1.0 {
                let effective = i.profile.imagingFocalLength * reducer
                out += " × \(reducer) reducer = \(Int(effective))mm effective"
            }
            out += "\n"
        }
        if i.profile.imagingPixelSize > 0 {
            out += "- **Imaging camera**: \(i.profile.imagingPixelSize)μm pixels"
            if i.profile.imagingBinning > 1 { out += " (binning \(i.profile.imagingBinning)×\(i.profile.imagingBinning))" }
            out += "\n"
        }
        if i.profile.isImagingScaleConfigured {
            out += "- **Imaging scale**: \(String(format: "%.2f", i.profile.imagingPixelScale))\"/px\n"
        }
        if i.profile.guideCameraPixelSize > 0 && i.profile.guideFocalLength > 0 {
            out += "- **Guiding**: \(i.profile.guideConfiguration.rawValue), \(Int(i.profile.guideFocalLength))mm × \(i.profile.guideCameraPixelSize)μm = \(String(format: "%.2f", i.profile.guidePixelScale))\"/px\n"
        }
        if let mount = i.profile.mountModel, !mount.isEmpty {
            out += "- **Mount model**: \(mount)\n"
        }
        return out
    }

    private static func recentNightsSection(_ i: Inputs) -> String {
        guard !i.summaries.isEmpty else { return "" }
        let visible = i.summaries.suffix(7).reversed()
        var out = "## Recent nights (last \(visible.count))\n\n"
        out += "| Date | Sessions | Integration | Median RMS |\n"
        out += "|---|---|---|---|\n"
        for night in visible {
            let date = night.nightDate.formatted(date: .abbreviated, time: .omitted)
            let rms = String(format: "%.2f\"", night.medianRMSArcsec)
            let mins = String(format: "%.0f min", night.totalIntegrationMinutes)
            out += "| \(date) | \(night.sessionsCount) | \(mins) | \(rms) |\n"
        }
        let rmsValues = i.summaries.map { $0.medianRMSArcsec }.filter { $0 > 0 }.sorted()
        if !rmsValues.isEmpty {
            let median = rmsValues[rmsValues.count / 2]
            let best = rmsValues.first ?? 0
            let worst = rmsValues.last ?? 0
            out += "\nAcross \(i.summaries.count) nights: median **\(String(format: "%.2f\"", median))**, best \(String(format: "%.2f\"", best)), worst \(String(format: "%.2f\"", worst))"
            if i.profile.isImagingScaleConfigured {
                let ratio = median / i.profile.imagingPixelScale
                out += " (median is \(Int((ratio * 100).rounded()))% of imaging scale)"
            }
        }
        return out
    }

    private static func observationsSection(_ i: Inputs) -> String {
        guard !i.observations.isEmpty else { return "" }
        let top = i.observations.prefix(8)
        var out = "## Active observations (\(i.observations.count))\n\n"
        for obs in top {
            out += "### \(obs.title)\n"
            out += "*Severity: \(obs.severity.displayName) · Source: \(obs.sourceAuthority.badgeLabel)*\n\n"
            out += "\(obs.summary)\n\n"
            if !obs.evidence.isEmpty {
                out += "**Evidence:**\n"
                for item in obs.evidence {
                    if let detail = item.detail {
                        out += "- \(item.label): \(item.value) — \(detail)\n"
                    } else {
                        out += "- \(item.label): \(item.value)\n"
                    }
                }
                out += "\n"
            }
            if !obs.candidateContributors.isEmpty {
                out += "**Possible contributors:**\n"
                for c in obs.candidateContributors {
                    out += "- \(c)\n"
                }
                out += "\n"
            }
            if !obs.suggestedResponse.isEmpty {
                out += "**Suggested next step:** \(obs.suggestedResponse)\n\n"
            }
            if !obs.relatedPHD2Tools.isEmpty {
                let tools = obs.relatedPHD2Tools.map { "[\($0.canonicalName)](\($0.manualURL.absoluteString))" }.joined(separator: ", ")
                out += "**PHD2 tools referenced:** \(tools)\n\n"
            }
        }
        if i.observations.count > top.count {
            out += "*(\(i.observations.count - top.count) more observations not shown.)*\n"
        }
        return out
    }

    private static func annotationsSection(_ i: Inputs) -> String {
        var out = "## Annotations\n\n"
        for ann in i.annotations.prefix(10) {
            let date = ann.eventDate.formatted(date: .abbreviated, time: .omitted)
            let cats = ann.categories.map { $0.displayName }.sorted().joined(separator: ", ")
            out += "- **\(date)** — \(ann.label)"
            if !cats.isEmpty { out += " *(\(cats))*" }
            if ann.isRigMutating { out += " ⚠ rig-mutating" }
            out += "\n"
            if !ann.detail.isEmpty {
                out += "  \(ann.detail)\n"
            }
        }
        return out
    }

    private static func suggestedQuestionsSection(_ i: Inputs) -> String {
        var out = "## Questions I'd like help with\n\n"
        if let q = i.userQuestion, !q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out += "\(q)\n\n"
        } else {
            out += "_(Add your specific questions here.)_\n\n"
        }
        out += "Possible starting points based on the data above:\n"
        if i.observations.contains(where: { $0.severity == .alert }) {
            out += "- Address the alert-severity observations first — they have the strongest evidence.\n"
        }
        if i.observations.contains(where: { $0.relatedPHD2Tools.contains(.guidingAssistant) }) {
            out += "- Has the Guiding Assistant been run recently? PHD2's own min-move and backlash measurements supersede heuristics.\n"
        }
        if i.observations.contains(where: { $0.title.localizedCaseInsensitiveContains("orthogonality") }) {
            out += "- Check the Calibration Assistant — it slews to the optimum sky position and pre-clears Dec backlash.\n"
        }
        return out
    }

    private static func footer(_ i: Inputs) -> String {
        let now = Date().formatted(date: .abbreviated, time: .shortened)
        return "---\n*Generated by Ephemeris v2.0 · \(now)*"
    }

    /// Apply per-format transforms after assembling the markdown payload.
    private static func applyFormatTransforms(_ markdown: String, format: Format) -> String {
        switch format {
        case .markdown:
            return markdown
        case .bbcode:
            return markdownToBBCode(markdown)
        case .plainText:
            return markdownToPlainText(markdown)
        }
    }

    /// Lightweight markdown → BBCode for Cloudy Nights / vBulletin forums.
    private static func markdownToBBCode(_ md: String) -> String {
        var s = md
        // Headers → [b][size]
        s = s.replacingOccurrences(of: "## ", with: "[b][size=4]")
            .replacingOccurrences(of: "### ", with: "[b][size=3]")
        // Italic *text*
        s = replace(s, regex: #"\*([^*\n]+)\*"#, with: "[i]$1[/i]")
        // Bold **text**
        s = replace(s, regex: #"\*\*([^*\n]+)\*\*"#, with: "[b]$1[/b]")
        // Links [text](url)
        s = replace(s, regex: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "[url=$2]$1[/url]")
        return s
    }

    private static func markdownToPlainText(_ md: String) -> String {
        var s = md
        s = s.replacingOccurrences(of: "## ", with: "")
            .replacingOccurrences(of: "### ", with: "")
            .replacingOccurrences(of: "---", with: "—")
        s = replace(s, regex: #"\*\*([^*\n]+)\*\*"#, with: "$1")
        s = replace(s, regex: #"\*([^*\n]+)\*"#, with: "$1")
        s = replace(s, regex: #"\[([^\]]+)\]\(([^)]+)\)"#, with: "$1 ($2)")
        return s
    }

    private static func replace(_ s: String, regex pattern: String, with template: String) -> String {
        guard let r = try? NSRegularExpression(pattern: pattern, options: []) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return r.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
    }
}
