import SwiftUI

/// Choosing the artwork of one card in a deck: every printing Scryfall lists for the card, as sleeves on
/// the binder's page, newest first. The choice belongs to the deck row. It shows in the deck, on the board
/// and in exports ("1 Sol Ring (CMM) 400"), and it never changes the card's rules or the deck's check.
/// Android: studio/DeckStudioArtworkPicker.kt.
struct DeckStudioArtworkPicker: View {
    let name: String
    let current: CardPrinting?
    /// nil returns the card to its default artwork.
    let choose: (CardPrinting?) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NativeArtworkPreference.key) private var remoteArtwork = false
    @State private var printings: [DeckStudioScryfallPrinting] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if !remoteArtwork {
                        BinderNote(title: "Online card images are off",
                                   message: "Choosing artwork asks Scryfall for this card's printings. It receives the card name and your IP address, and nothing else. Saved images keep working offline.",
                                   icon: "photo.on.rectangle.angled")
                        Button("Turn on") { remoteArtwork = true }
                            .buttonStyle(BinderPlaqueButtonStyle()).fixedSize(horizontal: true, vertical: false)
                            .accessibilityIdentifier("deckStudio.artwork.enable")
                    } else {
                        gallery
                    }
                }.padding(20)
            }
            .background(GrimoirePaper())
            .binderLeaf("Choose artwork", trailing: BinderLeafAction(title: "Done", identifier: "deckStudio.artwork.done") { dismiss() })
        }
        .foregroundStyle(DeckStudioPalette.ink).preferredColorScheme(.light).grimoirePage(.loose)
        .task(id: remoteArtwork) { if remoteArtwork, !loaded { await load(next: 1) } }
        .accessibilityIdentifier("deckStudio.artwork.picker")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.system(size: 22, weight: .bold, design: .serif)).fixedSize(horizontal: false, vertical: true)
            Text(current.map { "Showing \($0.label)" } ?? "Showing the default artwork")
                .font(.system(size: 14, weight: .semibold, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
                .accessibilityIdentifier("deckStudio.artwork.current")
            Text("The art you pick is saved with this card in this deck. It shows in the deck, on the board and in exports, and never changes the card's rules.")
                .font(.system(size: 13, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk).fixedSize(horizontal: false, vertical: true)
            if current != nil {
                Button("Use the default artwork") { choose(nil); dismiss() }
                    .buttonStyle(BinderPlaqueButtonStyle()).fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier("deckStudio.artwork.default")
            }
        }
    }

    @ViewBuilder private var gallery: some View {
        if let error {
            BinderNote(title: "Printings unavailable", message: error, icon: "exclamationmark.triangle")
            Button("Try again") { Task { await load(next: max(1, page + (printings.isEmpty ? 0 : 1))) } }
                .buttonStyle(BinderPlaqueButtonStyle()).fixedSize(horizontal: true, vertical: false)
        }
        if printings.isEmpty, busy {
            Text("Looking up printings…").font(.system(size: 14, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
        }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)], alignment: .leading, spacing: 14) {
            ForEach(printings) { tile($0) }
        }
        if hasMore {
            Button(busy ? "Loading…" : "More printings") { Task { await load(next: page + 1) } }
                .buttonStyle(BinderPlaqueButtonStyle()).fixedSize(horizontal: true, vertical: false)
                .disabled(busy).accessibilityIdentifier("deckStudio.artwork.more")
        } else if loaded, error == nil, !printings.isEmpty {
            Text("\(printings.count) printing\(printings.count == 1 ? "" : "s")").font(.caption2)
                .foregroundStyle(DeckStudioPalette.secondaryInk).frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func tile(_ item: DeckStudioScryfallPrinting) -> some View {
        let printing = item.printing
        let selected = printing != nil && printing == current
        let shape = RoundedRectangle(cornerRadius: DeckStudioMetrics.cardRadius)
        return Button {
            guard let printing else { return }
            choose(printing); dismiss()
        } label: {
            VStack(spacing: 5) {
                PrintingThumbnail(url: item.thumbnailURL)
                    .aspectRatio(63.0 / 88.0, contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(selected ? DeckStudioPalette.accent : DeckStudioPalette.separator, lineWidth: selected ? 3 : 1))
                    .overlay(alignment: .topTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(DeckStudioPalette.accent)
                                .background(Circle().fill(DeckStudioPalette.surfaceElevated)).padding(5)
                        }
                    }
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
                Text(printing?.label ?? item.set.uppercased()).font(.system(size: 12, weight: .heavy, design: .serif))
                Text(item.caption).font(.system(size: 10, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain).disabled(printing == nil)
        .accessibilityLabel("\(item.setName), \(printing?.label ?? item.collectorNumber)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func load(next: Int) async {
        guard !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            guard let result = try await DeckStudioScryfallClient.shared.printings(of: name, page: next, allowNetwork: true) else { return }
            try Task.checkCancellation()
            let known = Set(printings.map(\.id))
            printings = next == 1 ? result.printings : printings + result.printings.filter { !known.contains($0.id) }
            page = result.page; hasMore = result.hasMore && result.page < 10; loaded = true
        } catch is CancellationError {
        } catch DeckStudioScryfallError.invalidInput {
            error = "This card's name can't be searched for printings. It keeps its default artwork."; loaded = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// A printing's small picture from Scryfall's image host; a plain brass-edged blank while it loads.
private struct PrintingThumbnail: View {
    let url: URL?
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            DeckStudioPalette.surfaceElevated
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: failed ? "photo" : "rectangle.portrait").font(.title3).foregroundStyle(DeckStudioPalette.secondaryInk.opacity(0.5))
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            image = nil; failed = false
            guard let url else { failed = true; return }
            do {
                guard let data = try await NativeDeckArtwork.shared.thumbnailData(url: url, allowNetwork: true),
                      let decoded = await NativeArtworkDecoding.image(data, variant: .compact, illustration: false) else { failed = true; return }
                try Task.checkCancellation()
                image = decoded
            } catch is CancellationError { } catch { failed = true }
        }
    }
}
