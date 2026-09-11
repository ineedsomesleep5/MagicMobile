import SwiftUI
import MagicMobileOnDevice

/** Generic inspection controls, not a claim of polished/parity-complete gameplay UI. */
struct PromptInspector: View {
    let prompt: EnginePrompt
    let disabled: Bool
    let enginePlayerID: String?
    let send: (String, JSONValue) -> Void
    @State private var text = ""
    @State private var integer = "0"
    @State private var amounts: [String] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(prompt.kind.replacingOccurrences(of: "_", with: " ")).font(.headline)
            Text(plain(prompt.payload["message"]?.string ?? "Choose an action"))
            if prompt.submitted { Text("Answer queued; waiting for XMage.").font(.footnote) }
            if let choices = prompt.payload["choices"]?.object {
                ForEach(choices.keys.sorted(), id: \.self) { key in
                    Button(plain(choices[key]?.string ?? key)) {
                        send(prompt.responseTypes.contains("uuid") ? "uuid" : "string", .string(key))
                    }.buttonStyle(.bordered)
                }
            }
            if let abilities = prompt.payload["abilities"]?.array {
                ForEach(Array(abilities.enumerated()), id: \.offset) { _, ability in
                    if let id = ability["id"]?.string {
                        Button(plain(ability["label"]?.string ?? id)) { send("uuid", .string(id)) }
                    }
                }
            }
            if let ids = prompt.payload["candidates"]?.array {
                ForEach(Array(ids.enumerated()), id: \.offset) { _, candidate in
                    if let id = candidate.string { Button(id) { send("uuid", .string(id)) }.font(.caption.monospaced()) }
                }
            }
            if prompt.responseTypes.contains("boolean") {
                HStack {
                    Button(plain(prompt.payload["options"]?["UI.left.btn.text"]?.string ?? "Yes / Done")) { send("boolean", .bool(true)) }
                    Button(plain(prompt.payload["options"]?["UI.right.btn.text"]?.string ?? "No / Cancel")) { send("boolean", .bool(false)) }
                }.buttonStyle(.bordered)
            }
            if prompt.responseTypes.contains("integer") {
                Text("Amount: \(prompt.minimum)…\(prompt.maximum)").font(.caption)
                HStack {
                    TextField("Integer", text: $integer).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    Button("Submit amount") {
                        if let value = Int64(integer), value >= prompt.minimum, value <= prompt.maximum { send("integer", .integer(value)) }
                    }
                }
            }
            if prompt.responseTypes.contains("integers"), let rows = prompt.payload["allocations"]?.array {
                Text("Allocation total must be \(prompt.minimum)…\(prompt.maximum)").font(.caption)
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    TextField(plain(row["message"]?.string ?? "Amount \(index + 1)"), text: Binding(
                        get: { amounts.indices.contains(index) ? amounts[index] : String(row["defaultValue"]?.integer ?? 0) },
                        set: { value in
                            while amounts.count < rows.count { amounts.append("0") }; amounts[index] = value
                        })).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                }
                Button("Submit allocation") {
                    let values = rows.enumerated().compactMap { index, row -> Int64? in
                        Int64(amounts.indices.contains(index) ? amounts[index] : String(row["defaultValue"]?.integer ?? 0))
                    }
                    if values.count == rows.count { send("integers", .array(values.map(JSONValue.integer))) }
                }
            }
            if prompt.responseTypes.contains("uuid") || prompt.responseTypes.contains("string") {
                TextField("Object UUID or exact choice key (developer input)", text: $text).textFieldStyle(.roundedBorder)
                HStack {
                    if prompt.responseTypes.contains("uuid") {
                        Button("Select object") { if let id = UUID(uuidString: text) { send("uuid", .string(id.uuidString.lowercased())) } }
                    }
                    if prompt.responseTypes.contains("string") { Button("Send exact key") { send("string", .string(text)) } }
                }
            }
            if prompt.responseTypes.contains("mana") {
                if let playerID = enginePlayerID {
                    Text("Spend mana already in your pool").font(.caption)
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(["WHITE", "BLUE", "BLACK", "RED", "GREEN", "COLORLESS"], id: \.self) { type in
                                Button(type) { send("mana", .object(["playerId": .string(playerID), "manaType": .string(type)])) }
                            }
                        }
                    }
                }
            }
            DisclosureGroup("Complete prompt metadata") { JSONInspector(value: prompt.payload) }
        }
        .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .disabled(disabled || prompt.submitted)
    }
    private func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
