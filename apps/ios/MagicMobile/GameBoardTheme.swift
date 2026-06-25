import SwiftUI

struct GameBoardTheme {
    let backgroundDeepMoss = Color(red: 0.02, green: 0.10, blue: 0.07)
    let backgroundShadow = Color(red: 0.04, green: 0.03, blue: 0.02)
    let leatherDark = Color(red: 0.11, green: 0.07, blue: 0.05)
    let leatherMid = Color(red: 0.20, green: 0.13, blue: 0.09)
    let carvedWood = Color(red: 0.29, green: 0.17, blue: 0.09)
    let agedParchment = Color(red: 0.72, green: 0.58, blue: 0.37)
    let antiqueGold = Color(red: 0.84, green: 0.65, blue: 0.25)
    let brass = Color(red: 0.66, green: 0.47, blue: 0.17)
    let iron = Color(red: 0.09, green: 0.08, blue: 0.08)
    let emeraldPriority = Color(red: 0.18, green: 0.78, blue: 0.47)
    let arcaneBlue = Color(red: 0.27, green: 0.65, blue: 0.85)
    let warningAmber = Color(red: 0.85, green: 0.54, blue: 0.17)
    let dangerOxblood = Color(red: 0.54, green: 0.17, blue: 0.15)
    let whiteReadable = Color(red: 0.97, green: 0.95, blue: 0.90)
    let mutedText = Color(red: 0.79, green: 0.74, blue: 0.65)

    static let current = GameBoardTheme()
}

struct GameBoardShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

extension GameBoardTheme {
    var panelShadow: GameBoardShadow {
        GameBoardShadow(color: .black.opacity(0.28), radius: 8, x: -3, y: 4)
    }

    var priorityGlow: GameBoardShadow {
        GameBoardShadow(color: emeraldPriority.opacity(0.34), radius: 10, x: 0, y: 0)
    }

    var stackGlow: GameBoardShadow {
        GameBoardShadow(color: arcaneBlue.opacity(0.28), radius: 10, x: 0, y: 0)
    }
}
