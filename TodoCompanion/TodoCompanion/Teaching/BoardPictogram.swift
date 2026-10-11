import CoreGraphics
import Foundation

/// Curated sketch objects Max may place on the teaching board.
///
/// Not freeform art — a fixed vocabulary the model names and the app draws in
/// one ink weight (Pexo "one hand"). Unknown names fall back to a simple box
/// glyph so a typo still leaves *something* readable.
nonisolated enum BoardPictogram: String, Equatable, Sendable, CaseIterable {
    case person
    case people
    case car
    case truck
    case bike
    case house
    case building
    case tree
    case phone
    case laptop
    case book
    case lock
    case key
    case cloud
    case server
    case database
    case lightbulb
    case clock
    case coin
    case bag
    case mail
    case heart
    case star
    case check
    case cross
    case warning
    case package
    case door
    case bridge
    case pin
    case robot
    case brain
    case target
    case flag
    case box
    case gear
    case globe
    case search
    case chart
    case hourglass
    case shield
    case file
    case folder

    /// Resolves model synonyms (`auto` → car, `human` → person).
    static func resolve(_ raw: String?) -> BoardPictogram? {
        guard var key = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !key.isEmpty else { return nil }
        key = key.replacingOccurrences(of: " ", with: "_")
        key = key.replacingOccurrences(of: "-", with: "_")
        if let direct = BoardPictogram(rawValue: key) { return direct }
        switch key {
        case "human", "man", "woman", "user", "stick_figure": return .person
        case "humans", "users", "crowd", "group": return .people
        case "auto", "automobile", "vehicle": return .car
        case "lorry", "van": return .truck
        case "bicycle", "cycle": return .bike
        case "home": return .house
        case "office", "tower": return .building
        case "mobile", "iphone", "smartphone": return .phone
        case "computer", "pc", "notebook", "macbook": return .laptop
        case "bulb", "idea": return .lightbulb
        case "money", "cash", "dollar": return .coin
        case "email", "envelope", "letter": return .mail
        case "map_pin", "location", "marker": return .pin
        case "parcel", "carton": return .package
        case "db", "cylinder", "cache", "redis": return .database
        case "gateway", "api_gateway": return .server
        case "cdn", "balancer", "load_balancer", "lb": return .cloud
        case "tick", "ok", "yes": return .check
        case "x", "no", "reject": return .cross
        case "alert", "caution": return .warning
        case "crate": return .box
        case "cog", "settings", "config", "process": return .gear
        case "world", "internet", "earth", "web": return .globe
        case "magnifier", "magnifying_glass", "lookup", "find": return .search
        case "graph", "bar_chart", "metrics", "stats": return .chart
        case "timer", "wait", "timeout": return .hourglass
        case "security", "auth", "firewall": return .shield
        case "document", "doc", "page", "code": return .file
        case "directory", "dir": return .folder
        default: return nil
        }
    }

    /// Strokes a simple sketch of this object into `rect` (normalized drawing).
    func add(to path: inout CGMutablePath, in rect: CGRect) {
        let inset = rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08)
        switch self {
        case .person:
            let headR = inset.width * 0.18
            let head = CGPoint(x: inset.midX, y: inset.minY + headR + 2)
            path.addEllipse(in: CGRect(x: head.x - headR, y: head.y - headR,
                                       width: headR * 2, height: headR * 2))
            path.move(to: CGPoint(x: inset.midX, y: head.y + headR))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.midY + inset.height * 0.08))
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.2, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.2, y: inset.midY))
            path.move(to: CGPoint(x: inset.midX, y: inset.midY + inset.height * 0.08))
            path.addLine(to: CGPoint(x: inset.minX + inset.width * 0.25, y: inset.maxY))
            path.move(to: CGPoint(x: inset.midX, y: inset.midY + inset.height * 0.08))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.25, y: inset.maxY))

        case .people:
            let left = CGRect(x: inset.minX, y: inset.minY, width: inset.width * 0.48, height: inset.height)
            let right = CGRect(x: inset.minX + inset.width * 0.52, y: inset.minY,
                               width: inset.width * 0.48, height: inset.height)
            BoardPictogram.person.add(to: &path, in: left)
            BoardPictogram.person.add(to: &path, in: right)

        case .car, .truck:
            let body = CGRect(x: inset.minX, y: inset.midY - inset.height * 0.12,
                              width: inset.width, height: inset.height * 0.34)
            path.addRoundedRect(in: body, cornerWidth: 4, cornerHeight: 4)
            let cabinW = self == .truck ? inset.width * 0.35 : inset.width * 0.55
            let cabin = CGRect(x: inset.minX + inset.width * 0.12,
                               y: body.minY - inset.height * 0.22,
                               width: cabinW, height: inset.height * 0.24)
            path.addRoundedRect(in: cabin, cornerWidth: 3, cornerHeight: 3)
            let wheelR = inset.height * 0.1
            path.addEllipse(in: CGRect(x: inset.minX + inset.width * 0.18,
                                       y: body.maxY - wheelR * 0.3,
                                       width: wheelR * 2, height: wheelR * 2))
            path.addEllipse(in: CGRect(x: inset.maxX - inset.width * 0.18 - wheelR * 2,
                                       y: body.maxY - wheelR * 0.3,
                                       width: wheelR * 2, height: wheelR * 2))

        case .bike:
            let wheelR = inset.width * 0.16
            path.addEllipse(in: CGRect(x: inset.minX, y: inset.midY,
                                       width: wheelR * 2, height: wheelR * 2))
            path.addEllipse(in: CGRect(x: inset.maxX - wheelR * 2, y: inset.midY,
                                       width: wheelR * 2, height: wheelR * 2))
            path.move(to: CGPoint(x: inset.minX + wheelR, y: inset.midY + wheelR))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.minY + inset.height * 0.25))
            path.addLine(to: CGPoint(x: inset.maxX - wheelR, y: inset.midY + wheelR))
            path.move(to: CGPoint(x: inset.midX, y: inset.minY + inset.height * 0.25))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.minY + inset.height * 0.1))

        case .house:
            path.move(to: CGPoint(x: inset.minX, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.minY + 2))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.08, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.08, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.minX + inset.width * 0.08, y: inset.maxY))
            path.addLine(to: CGPoint(x: inset.minX + inset.width * 0.08, y: inset.midY))
            path.closeSubpath()
            let door = CGRect(x: inset.midX - inset.width * 0.08, y: inset.maxY - inset.height * 0.28,
                              width: inset.width * 0.16, height: inset.height * 0.28)
            path.addRect(door)

        case .building:
            path.addRect(inset.insetBy(dx: inset.width * 0.15, dy: 0))
            for row in 0..<3 {
                for col in 0..<2 {
                    let wx = inset.minX + inset.width * (0.28 + CGFloat(col) * 0.28)
                    let wy = inset.minY + inset.height * (0.18 + CGFloat(row) * 0.22)
                    path.addRect(CGRect(x: wx, y: wy, width: inset.width * 0.12, height: inset.height * 0.1))
                }
            }

        case .tree:
            path.addEllipse(in: CGRect(x: inset.midX - inset.width * 0.32, y: inset.minY,
                                       width: inset.width * 0.64, height: inset.height * 0.55))
            path.addRect(CGRect(x: inset.midX - inset.width * 0.06, y: inset.midY,
                                width: inset.width * 0.12, height: inset.height * 0.42))

        case .phone:
            path.addRoundedRect(in: inset.insetBy(dx: inset.width * 0.28, dy: inset.height * 0.05),
                                cornerWidth: 6, cornerHeight: 6)
            path.addEllipse(in: CGRect(x: inset.midX - 3, y: inset.maxY - inset.height * 0.14,
                                       width: 6, height: 6))

        case .laptop:
            let lid = CGRect(x: inset.minX + inset.width * 0.1, y: inset.minY + inset.height * 0.15,
                             width: inset.width * 0.8, height: inset.height * 0.45)
            path.addRoundedRect(in: lid, cornerWidth: 3, cornerHeight: 3)
            path.move(to: CGPoint(x: inset.minX, y: lid.maxY + 4))
            path.addLine(to: CGPoint(x: inset.maxX, y: lid.maxY + 4))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.08, y: inset.maxY - 4))
            path.addLine(to: CGPoint(x: inset.minX + inset.width * 0.08, y: inset.maxY - 4))
            path.closeSubpath()

        case .book:
            path.addRoundedRect(in: inset.insetBy(dx: inset.width * 0.12, dy: inset.height * 0.1),
                                cornerWidth: 2, cornerHeight: 2)
            path.move(to: CGPoint(x: inset.midX, y: inset.minY + inset.height * 0.1))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.maxY - inset.height * 0.1))

        case .lock:
            let body = CGRect(x: inset.minX + inset.width * 0.2, y: inset.midY - inset.height * 0.05,
                              width: inset.width * 0.6, height: inset.height * 0.45)
            path.addRoundedRect(in: body, cornerWidth: 4, cornerHeight: 4)
            path.addArc(center: CGPoint(x: inset.midX, y: body.minY),
                        radius: inset.width * 0.18,
                        startAngle: .pi, endAngle: 0, clockwise: false)

        case .key:
            path.addEllipse(in: CGRect(x: inset.minX, y: inset.midY - inset.height * 0.18,
                                       width: inset.width * 0.36, height: inset.height * 0.36))
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.32, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.midY))
            path.move(to: CGPoint(x: inset.maxX - inset.width * 0.12, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.12, y: inset.midY + inset.height * 0.18))

        case .cloud:
            path.addEllipse(in: CGRect(x: inset.minX, y: inset.midY - inset.height * 0.1,
                                       width: inset.width * 0.45, height: inset.height * 0.4))
            path.addEllipse(in: CGRect(x: inset.midX - inset.width * 0.2, y: inset.minY + inset.height * 0.15,
                                       width: inset.width * 0.5, height: inset.height * 0.45))
            path.addEllipse(in: CGRect(x: inset.maxX - inset.width * 0.45, y: inset.midY - inset.height * 0.1,
                                       width: inset.width * 0.45, height: inset.height * 0.4))

        case .server, .database:
            let mid = inset.insetBy(dx: inset.width * 0.15, dy: inset.height * 0.1)
            path.addEllipse(in: CGRect(x: mid.minX, y: mid.minY, width: mid.width, height: mid.height * 0.28))
            path.addRect(CGRect(x: mid.minX, y: mid.minY + mid.height * 0.14,
                                width: mid.width, height: mid.height * 0.55))
            path.addEllipse(in: CGRect(x: mid.minX, y: mid.maxY - mid.height * 0.28,
                                       width: mid.width, height: mid.height * 0.28))

        case .lightbulb:
            path.addEllipse(in: CGRect(x: inset.midX - inset.width * 0.28, y: inset.minY + 2,
                                       width: inset.width * 0.56, height: inset.height * 0.55))
            path.addRect(CGRect(x: inset.midX - inset.width * 0.12, y: inset.midY + inset.height * 0.12,
                                width: inset.width * 0.24, height: inset.height * 0.22))
            path.move(to: CGPoint(x: inset.midX - inset.width * 0.1, y: inset.maxY - 4))
            path.addLine(to: CGPoint(x: inset.midX + inset.width * 0.1, y: inset.maxY - 4))

        case .clock:
            path.addEllipse(in: inset.insetBy(dx: inset.width * 0.12, dy: inset.height * 0.12))
            path.move(to: CGPoint(x: inset.midX, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.minY + inset.height * 0.22))
            path.move(to: CGPoint(x: inset.midX, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.midX + inset.width * 0.22, y: inset.midY + 2))

        case .coin:
            path.addEllipse(in: inset.insetBy(dx: inset.width * 0.15, dy: inset.height * 0.15))
            path.addEllipse(in: inset.insetBy(dx: inset.width * 0.28, dy: inset.height * 0.28))

        case .bag:
            path.addRoundedRect(in: CGRect(x: inset.minX + inset.width * 0.15, y: inset.midY - inset.height * 0.05,
                                           width: inset.width * 0.7, height: inset.height * 0.45),
                                cornerWidth: 4, cornerHeight: 4)
            path.addArc(center: CGPoint(x: inset.midX, y: inset.midY - inset.height * 0.05),
                        radius: inset.width * 0.18,
                        startAngle: .pi, endAngle: 0, clockwise: false)

        case .mail:
            path.addRect(inset.insetBy(dx: inset.width * 0.08, dy: inset.height * 0.22))
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.08, y: inset.minY + inset.height * 0.22))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.08, y: inset.minY + inset.height * 0.22))

        case .heart:
            let w = inset.width, h = inset.height
            path.move(to: CGPoint(x: inset.midX, y: inset.maxY - h * 0.1))
            path.addCurve(to: CGPoint(x: inset.minX + w * 0.1, y: inset.minY + h * 0.35),
                          control1: CGPoint(x: inset.midX - w * 0.5, y: inset.midY),
                          control2: CGPoint(x: inset.minX, y: inset.minY + h * 0.1))
            path.addCurve(to: CGPoint(x: inset.midX, y: inset.minY + h * 0.28),
                          control1: CGPoint(x: inset.minX + w * 0.2, y: inset.minY),
                          control2: CGPoint(x: inset.midX - w * 0.1, y: inset.minY + h * 0.05))
            path.addCurve(to: CGPoint(x: inset.maxX - w * 0.1, y: inset.minY + h * 0.35),
                          control1: CGPoint(x: inset.midX + w * 0.1, y: inset.minY + h * 0.05),
                          control2: CGPoint(x: inset.maxX - w * 0.2, y: inset.minY))
            path.addCurve(to: CGPoint(x: inset.midX, y: inset.maxY - h * 0.1),
                          control1: CGPoint(x: inset.maxX, y: inset.minY + h * 0.1),
                          control2: CGPoint(x: inset.midX + w * 0.5, y: inset.midY))

        case .star:
            Self.addStar(to: &path, center: CGPoint(x: inset.midX, y: inset.midY),
                         outer: min(inset.width, inset.height) * 0.42,
                         inner: min(inset.width, inset.height) * 0.18)

        case .check:
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.15, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.midX - inset.width * 0.05, y: inset.maxY - inset.height * 0.2))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.12, y: inset.minY + inset.height * 0.2))

        case .cross:
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.2, y: inset.minY + inset.height * 0.2))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.2, y: inset.maxY - inset.height * 0.2))
            path.move(to: CGPoint(x: inset.maxX - inset.width * 0.2, y: inset.minY + inset.height * 0.2))
            path.addLine(to: CGPoint(x: inset.minX + inset.width * 0.2, y: inset.maxY - inset.height * 0.2))

        case .warning:
            path.move(to: CGPoint(x: inset.midX, y: inset.minY + 2))
            path.addLine(to: CGPoint(x: inset.maxX - 2, y: inset.maxY - 4))
            path.addLine(to: CGPoint(x: inset.minX + 2, y: inset.maxY - 4))
            path.closeSubpath()
            path.move(to: CGPoint(x: inset.midX, y: inset.midY - inset.height * 0.08))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.midY + inset.height * 0.12))
            path.addEllipse(in: CGRect(x: inset.midX - 2, y: inset.maxY - inset.height * 0.22, width: 4, height: 4))

        case .package, .box:
            path.addRect(inset.insetBy(dx: inset.width * 0.12, dy: inset.height * 0.18))
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.12, y: inset.minY + inset.height * 0.18))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.minY + inset.height * 0.05))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.12, y: inset.minY + inset.height * 0.18))
            path.move(to: CGPoint(x: inset.midX, y: inset.minY + inset.height * 0.05))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.maxY - inset.height * 0.18))

        case .door:
            path.addRoundedRect(in: inset.insetBy(dx: inset.width * 0.22, dy: inset.height * 0.05),
                                cornerWidth: 2, cornerHeight: 2)
            path.addEllipse(in: CGRect(x: inset.maxX - inset.width * 0.38, y: inset.midY,
                                       width: 6, height: 6))

        case .bridge:
            path.move(to: CGPoint(x: inset.minX, y: inset.midY + inset.height * 0.15))
            path.addQuadCurve(to: CGPoint(x: inset.maxX, y: inset.midY + inset.height * 0.15),
                              control: CGPoint(x: inset.midX, y: inset.minY))
            path.move(to: CGPoint(x: inset.minX, y: inset.maxY - 4))
            path.addLine(to: CGPoint(x: inset.maxX, y: inset.maxY - 4))
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.2, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.minX + inset.width * 0.2, y: inset.maxY - 4))
            path.move(to: CGPoint(x: inset.maxX - inset.width * 0.2, y: inset.midY))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.2, y: inset.maxY - 4))

        case .pin:
            path.addEllipse(in: CGRect(x: inset.midX - inset.width * 0.22, y: inset.minY + 2,
                                       width: inset.width * 0.44, height: inset.height * 0.4))
            path.move(to: CGPoint(x: inset.midX, y: inset.minY + inset.height * 0.4))
            path.addLine(to: CGPoint(x: inset.midX, y: inset.maxY - 2))

        case .robot:
            path.addRoundedRect(in: CGRect(x: inset.minX + inset.width * 0.2, y: inset.minY + inset.height * 0.15,
                                           width: inset.width * 0.6, height: inset.height * 0.45),
                                cornerWidth: 4, cornerHeight: 4)
            path.addEllipse(in: CGRect(x: inset.midX - inset.width * 0.16, y: inset.minY + inset.height * 0.28,
                                       width: inset.width * 0.12, height: inset.height * 0.12))
            path.addEllipse(in: CGRect(x: inset.midX + inset.width * 0.04, y: inset.minY + inset.height * 0.28,
                                       width: inset.width * 0.12, height: inset.height * 0.12))
            path.addRect(CGRect(x: inset.midX - inset.width * 0.1, y: inset.midY + inset.height * 0.15,
                                width: inset.width * 0.2, height: inset.height * 0.28))

        case .brain:
            path.addEllipse(in: CGRect(x: inset.minX + inset.width * 0.1, y: inset.minY + inset.height * 0.15,
                                       width: inset.width * 0.45, height: inset.height * 0.55))
            path.addEllipse(in: CGRect(x: inset.midX - inset.width * 0.05, y: inset.minY + inset.height * 0.15,
                                       width: inset.width * 0.45, height: inset.height * 0.55))

        case .target:
            let c = CGPoint(x: inset.midX, y: inset.midY)
            for factor: CGFloat in [0.42, 0.28, 0.14] {
                let r = min(inset.width, inset.height) * factor
                path.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            }

        case .flag:
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.2, y: inset.minY + 2))
            path.addLine(to: CGPoint(x: inset.minX + inset.width * 0.2, y: inset.maxY - 2))
            path.move(to: CGPoint(x: inset.minX + inset.width * 0.2, y: inset.minY + 2))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.1, y: inset.minY + inset.height * 0.22))
            path.addLine(to: CGPoint(x: inset.minX + inset.width * 0.2, y: inset.minY + inset.height * 0.4))

        case .gear:
            let c = CGPoint(x: inset.midX, y: inset.midY)
            let outer = min(inset.width, inset.height) * 0.44
            let inner = outer * 0.74
            for tooth in 0..<16 {
                let angle = CGFloat(tooth) * .pi / 8
                let radius = tooth.isMultiple(of: 2) ? outer : inner
                let point = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
                if tooth == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            let hub = outer * 0.3
            path.addEllipse(in: CGRect(x: c.x - hub, y: c.y - hub, width: hub * 2, height: hub * 2))

        case .globe:
            let ring = inset.insetBy(dx: inset.width * 0.1, dy: inset.height * 0.1)
            path.addEllipse(in: ring)
            path.addEllipse(in: ring.insetBy(dx: ring.width * 0.3, dy: 0))
            path.move(to: CGPoint(x: ring.minX, y: ring.midY))
            path.addLine(to: CGPoint(x: ring.maxX, y: ring.midY))
            path.move(to: CGPoint(x: ring.minX + ring.width * 0.1, y: ring.minY + ring.height * 0.28))
            path.addLine(to: CGPoint(x: ring.maxX - ring.width * 0.1, y: ring.minY + ring.height * 0.28))
            path.move(to: CGPoint(x: ring.minX + ring.width * 0.1, y: ring.maxY - ring.height * 0.28))
            path.addLine(to: CGPoint(x: ring.maxX - ring.width * 0.1, y: ring.maxY - ring.height * 0.28))

        case .search:
            let lens = CGRect(x: inset.minX + inset.width * 0.1, y: inset.minY + inset.height * 0.1,
                              width: inset.width * 0.5, height: inset.height * 0.5)
            path.addEllipse(in: lens)
            path.move(to: CGPoint(x: lens.maxX - lens.width * 0.12, y: lens.maxY - lens.height * 0.12))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.08, y: inset.maxY - inset.height * 0.08))

        case .chart:
            path.move(to: CGPoint(x: inset.minX + 2, y: inset.minY + 2))
            path.addLine(to: CGPoint(x: inset.minX + 2, y: inset.maxY - 2))
            path.addLine(to: CGPoint(x: inset.maxX - 2, y: inset.maxY - 2))
            for (index, height) in [0.35, 0.6, 0.45, 0.8].enumerated() {
                let barW = inset.width * 0.14
                let x = inset.minX + inset.width * (0.16 + CGFloat(index) * 0.2)
                let h = inset.height * CGFloat(height) * 0.85
                path.addRect(CGRect(x: x, y: inset.maxY - 2 - h, width: barW, height: h))
            }

        case .hourglass:
            let top = inset.minY + inset.height * 0.06
            let bottom = inset.maxY - inset.height * 0.06
            let left = inset.minX + inset.width * 0.25
            let right = inset.maxX - inset.width * 0.25
            path.move(to: CGPoint(x: left - 4, y: top))
            path.addLine(to: CGPoint(x: right + 4, y: top))
            path.move(to: CGPoint(x: left - 4, y: bottom))
            path.addLine(to: CGPoint(x: right + 4, y: bottom))
            path.move(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: right, y: bottom))
            path.addLine(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: right, y: top))
            path.closeSubpath()

        case .shield:
            path.move(to: CGPoint(x: inset.midX, y: inset.minY + 2))
            path.addLine(to: CGPoint(x: inset.maxX - inset.width * 0.15, y: inset.minY + inset.height * 0.18))
            path.addQuadCurve(to: CGPoint(x: inset.midX, y: inset.maxY - 2),
                              control: CGPoint(x: inset.maxX - inset.width * 0.15, y: inset.minY + inset.height * 0.78))
            path.addQuadCurve(to: CGPoint(x: inset.minX + inset.width * 0.15, y: inset.minY + inset.height * 0.18),
                              control: CGPoint(x: inset.minX + inset.width * 0.15, y: inset.minY + inset.height * 0.78))
            path.closeSubpath()

        case .file:
            let page = inset.insetBy(dx: inset.width * 0.2, dy: inset.height * 0.06)
            let fold = page.width * 0.3
            path.move(to: CGPoint(x: page.minX, y: page.minY))
            path.addLine(to: CGPoint(x: page.maxX - fold, y: page.minY))
            path.addLine(to: CGPoint(x: page.maxX, y: page.minY + fold))
            path.addLine(to: CGPoint(x: page.maxX, y: page.maxY))
            path.addLine(to: CGPoint(x: page.minX, y: page.maxY))
            path.closeSubpath()
            for line in 0..<3 {
                let y = page.minY + page.height * (0.42 + CGFloat(line) * 0.16)
                path.move(to: CGPoint(x: page.minX + page.width * 0.15, y: y))
                path.addLine(to: CGPoint(x: page.maxX - page.width * 0.15, y: y))
            }

        case .folder:
            let body = CGRect(x: inset.minX + inset.width * 0.05, y: inset.minY + inset.height * 0.3,
                              width: inset.width * 0.9, height: inset.height * 0.55)
            path.move(to: CGPoint(x: body.minX, y: body.minY))
            path.addLine(to: CGPoint(x: body.minX, y: body.minY - inset.height * 0.1))
            path.addLine(to: CGPoint(x: body.minX + body.width * 0.35, y: body.minY - inset.height * 0.1))
            path.addLine(to: CGPoint(x: body.minX + body.width * 0.45, y: body.minY))
            path.addRoundedRect(in: body, cornerWidth: 3, cornerHeight: 3)
        }
    }

    private static func addStar(to path: inout CGMutablePath, center: CGPoint,
                                outer: CGFloat, inner: CGFloat) {
        for i in 0..<10 {
            let angle = CGFloat(i) * .pi / 5 - .pi / 2
            let radius = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + cos(angle) * radius,
                                y: center.y + sin(angle) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
    }
}
