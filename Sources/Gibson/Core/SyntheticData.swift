import Foundation

/// Decorative content for the panels that are pure set dressing. None of it
/// touches the host: the account table, the file vault and the intrusion log
/// are props, and they are generated from a fixed seed so they stay stable
/// while the screen is up.
enum SyntheticData {
    static let daemons = [
        "kernel_task", "launchd", "syslogd", "mDNSResponder", "cfprefsd", "distnoted",
        "loginwindow", "WindowServer", "coreaudiod", "bluetoothd", "powerd", "notifyd",
        "opendirectoryd", "securityd", "trustd", "hidd", "diskarbitrationd", "netbiosd",
        "sandboxd", "watchdogd", "usbmuxd", "airportd", "spindump", "revisiond"
    ]

    static let countries = [
        "USA", "Canada", "UK", "Japan", "Germany", "Brazil", "Australia",
        "Norway", "Singapore", "France", "Iceland", "Chile"
    ]

    static let occupations = [
        "Engineer", "Teacher", "Analyst", "Writer", "Surgeon", "Pilot", "Architect",
        "Chemist", "Auditor", "Curator", "Broker", "Machinist"
    ]

    static let accountTypes = ["Checking", "Savings", "Investment", "Escrow", "Trust"]

    static let logLines = [
        "resolving host %HOST%",
        "handshake complete, cipher AES-256-GCM",
        "authenticating as %USER%",
        "> sudo -s",
        "root access granted",
        "> cd /var/www/html",
        "> ls -la",
        "index.html  login.php  about.html",
        "injecting payload into segment 0x%HEX%",
        "bypassing firewall rule %NUM%",
        "%NUM% packets captured on %IFACE%",
        "decrypting block %NUM% of 4096",
        "checksum verified",
        "scanning subnet %NET%.0/24",
        "port %PORT% open (%SERVICE%)",
        "escalating privileges",
        "dumping memory region 0x%HEX%",
        "mounting remote volume",
        "trace route hop %NUM% (%NET%.%NUM%)",
        "signature match: %SIG%",
        "quarantine bypassed",
        "uploading beacon",
        "> exit"
    ]

    /// Rare lines, dropped into the log every so often instead of a routine one.
    static let easterEggs = [
        "mess with the best, die like the rest",
        "hack the planet",
        "> finger operator@localhost",
        "operator is idle. very idle.",
        "warning: coffee level critical",
        "RFC 1149 transport ready",
        "there is no spoon",
        "> kill -9 boredom",
        "the mainframe remembers",
        "> support --author",
        "perfecto-web.com/d"
    ]

    static let services = ["ssh", "http", "https", "mysql", "redis", "smb", "rdp", "vnc", "ftp"]

    static let signatures = ["TROJAN.GEN.2", "W32.SILENTHUNTER", "BACKDOOR.ORION", "RANSOM.HYDRA"]

    /// Fake process rows for the simulated snapshot.
    static func processes(count: Int, time: TimeInterval) -> [MetricsSnapshot.Process] {
        var rng = Seeded(seed: 0xC0FFEE)
        return (0 ..< count).map { index in
            let pid = Int32(rng.int(300, 9999))
            return MetricsSnapshot.Process(
                pid: pid,
                user: rng.chance(0.4) ? "root" : "operator",
                command: rng.pick(daemons),
                cpu: Double(noise(CGFloat(time) * 0.5 + CGFloat(index) * 3, seed: UInt64(index))) * 60,
                memory: UInt64(rng.int(8, 900)) << 20,
                threads: rng.int(1, 24),
                started: Date(timeIntervalSinceNow: -Double(rng.int(60, 400_000)))
            )
        }
    }

    /// Deterministic account row for the decorative table.
    static func account(index: Int) -> (id: String, password: String, balance: String,
                                        country: String, phone: String, occupation: String,
                                        age: String, login: String, type: String) {
        var rng = Seeded(seed: UInt64(index) &* 7919 &+ 13)
        let id = String(format: "%05d", rng.int(10000, 99999))
        let password = ["passw0rd", "letmein", "qwerty123", "hunter2", "s3cret",
                        "admin123", "welcome1", "summer2024"].randomElement(using: &rng) ?? "secret"
        let balance = String(format: "$%d,000.00", rng.int(1, 500))
        let phone = String(format: "555-%03d-%04d", rng.int(100, 999), rng.int(1000, 9999))
        let login = String(format: "2024-%02d-%02d", rng.int(1, 13), rng.int(1, 29))
        return (id, password, balance, rng.pick(countries), phone,
                rng.pick(occupations), String(rng.int(21, 68)), login, rng.pick(accountTypes))
    }
}

extension Array {
    func randomElement(using generator: inout Seeded) -> Element? {
        isEmpty ? nil : self[generator.int(0, count)]
    }
}
