import CoreGraphics
import Foundation

/// Live process table. PID, command, CPU, memory, thread count and start time
/// come from the host. The PORTS and STATUS columns are set dressing, kept
/// stable per PID so they do not flicker between refreshes.
final class ProcessTablePanel: Panel {
    let title: String? = "process monitor"
    let redrawInterval: TimeInterval = 1.0

    func contentKey(_ context: RenderContext) -> Int? {
        context.metrics.timestamp.hashValue
    }

    private static let columns: [Table.Column] = [
        .init(title: "PID", chars: 6, alignRight: true),
        .init(title: "COMMAND", chars: 18, accent: true),
        .init(title: "%CPU", chars: 6, alignRight: true),
        .init(title: "START", chars: 8),
        .init(title: "PORTS", chars: 10),
        .init(title: "THR", chars: 4, alignRight: true),
        .init(title: "USER", chars: 10),
        .init(title: "MEMORY", chars: 8, alignRight: true),
        .init(title: "STATUS", chars: 8)
    ]

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let processes = context.metrics.processes
        guard !processes.isEmpty else {
            canvas.text("waiting for sample...", at: CGPoint(x: body.minX, y: body.minY + 12),
                        font: Fonts.mono(10), color: context.theme.dim)
            return
        }

        let rows = processes.map { row -> [String] in
            let seed = UInt64(bitPattern: Int64(row.pid))
            var rng = Seeded(seed: seed)
            let port = rng.int(1, 100) > 70 ? "\(rng.int(1024, 65535))/tcp" : "-"
            let status = rng.int(0, 20) == 0 ? "Sleeping" : "Running"
            return [
                String(row.pid),
                row.command,
                String(format: "%.1f", row.cpu),
                Format.shortTimeFormatter.string(from: row.started),
                port,
                String(row.threads),
                context.maskSensitiveInfo ? Format.mask(row.user) : row.user,
                Format.bytes(row.memory),
                status
            ]
        }

        var table = Table(columns: Self.columns, rows: rows)
        table.rowTint = { index in
            let cpu = processes[min(index, processes.count - 1)].cpu
            return (0.45 + CGFloat(cpu) / 60).clamped(0.45, 1)
        }
        table.draw(canvas, in: body, theme: context.theme, fontSize: fontSize(for: body))
    }

    private func fontSize(for rect: CGRect) -> CGFloat {
        (rect.height / 17).clamped(6, 13)
    }
}

/// Decorative account dump modelled on the tables in the reference stills.
/// Everything here is generated, no personal data is read from the machine.
final class AccountsPanel: Panel {
    let title: String? = "user account information"
    let redrawInterval: TimeInterval = 1.5

    private var scroll = 0
    private var frame = 0

    private static let columns: [Table.Column] = [
        .init(title: "USER ID", chars: 7, accent: true),
        .init(title: "PASSWORD", chars: 11),
        .init(title: "BALANCE", chars: 11, alignRight: true),
        .init(title: "COUNTRY", chars: 10),
        .init(title: "PHONE", chars: 12),
        .init(title: "OCCUPATION", chars: 11),
        .init(title: "AGE", chars: 3, alignRight: true),
        .init(title: "LAST LOGIN", chars: 10),
        .init(title: "TYPE", chars: 10)
    ]

    func update(_ context: RenderContext) {
        frame += 1
        if frame % 8 == 0 { scroll += 1 }
    }

    func draw(_ canvas: Canvas, _ context: RenderContext) {
        let body = PanelChrome.draw(canvas, context, title: title)
        let rows = (0 ..< 40).map { offset -> [String] in
            let account = SyntheticData.account(index: scroll + offset)
            return [account.id, account.password, account.balance, account.country,
                    account.phone, account.occupation, account.age, account.login, account.type]
        }

        var table = Table(columns: Self.columns, rows: rows)
        table.rowTint = { index in index % 4 == 0 ? 0.85 : 0.55 }
        table.draw(canvas, in: body, theme: context.theme,
                   fontSize: (body.height / 17).clamped(6, 12))
    }
}
