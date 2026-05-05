import SwiftUI
import MapKit

struct SearchBarView: View {
    @Binding var coordinate: CLLocationCoordinate2D?
    @Binding var region: MKCoordinateRegion
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var showDropdown = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search location…", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { runSearch() }
                    .onChange(of: query) { _, v in
                        if v.isEmpty { results = []; showDropdown = false }
                    }
                if searching {
                    ProgressView().scaleEffect(0.6)
                } else if !query.isEmpty {
                    Button { query = ""; results = []; showDropdown = false }
                    label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))

            if showDropdown && !results.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(results.prefix(6), id: \.self) { item in
                        Button {
                            selectItem(item)
                        } label: {
                            HStack {
                                Image(systemName: "mappin")
                                    .foregroundColor(.cyan)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name ?? "")
                                        .font(.callout)
                                        .foregroundColor(.primary)
                                    Text(item.placemark.title ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.001))
                        .onHover { over in
                            // hover highlight handled by buttonStyle
                        }
                        if item != results.prefix(6).last {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }

    private func runSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        searching = true
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = region
        MKLocalSearch(request: req).start { resp, _ in
            DispatchQueue.main.async {
                searching = false
                results = resp?.mapItems ?? []
                showDropdown = !results.isEmpty
            }
        }
    }

    private func selectItem(_ item: MKMapItem) {
        guard let loc = item.placemark.location else { return }
        coordinate = loc.coordinate
        region = MKCoordinateRegion(
            center: loc.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        )
        query = item.name ?? ""
        showDropdown = false
        results = []
    }
}
