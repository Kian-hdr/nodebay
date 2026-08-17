//
//  AboutView.swift
//  Nodebay
//

import AppKit
import Sparkle
import SwiftUI

struct About: View {
    let updaterController: SPUStandardUpdaterController

    private var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Unknown"
        #endif
    }

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 18) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 84, height: 84)
                        .accessibilityLabel("Nodebay app icon")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(NodebayBrand.name)
                            .font(.largeTitle.weight(.semibold))
                        Text(NodebayBrand.tagline)
                            .foregroundStyle(.secondary)
                        Text("Version \(Bundle.main.releaseVersionNumber ?? "Unknown") (\(Bundle.main.buildVersionNumber ?? "Unknown"))")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(architecture)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Project") {
                LabeledContent("Creator", value: NodebayBrand.creator)
                LabeledContent("Foundation", value: NodebayBrand.foundationLabel)
                LabeledContent("License", value: "GPL-3.0")
                Text("Based on Boring Notch. Nodebay is an independent project and is not endorsed by Boring Notch or any processing-engine provider.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Links") {
                aboutLink("Nodebay source", systemImage: "chevron.left.forwardslash.chevron.right", url: NodebayBrand.sourceURL)
                aboutLink("GitHub releases", systemImage: "shippingbox", url: NodebayBrand.releasesURL)
                aboutLink("Report an issue", systemImage: "exclamationmark.bubble", url: NodebayBrand.issuesURL)
                aboutLink("Boring Notch upstream", systemImage: "arrow.up.right.square", url: NodebayBrand.upstreamURL)
                aboutLink("GPL-3.0 license", systemImage: "doc.text", url: NodebayBrand.licenseURL)
                aboutLink("Acknowledgements", systemImage: "person.3", url: NodebayBrand.acknowledgementsURL)
                aboutLink("Third-party notices", systemImage: "doc.on.doc", url: NodebayBrand.thirdPartyNoticesURL)
                aboutLink("Privacy", systemImage: "hand.raised", url: NodebayBrand.privacyURL)
                aboutLink("Security policy", systemImage: "lock.shield", url: NodebayBrand.securityURL)
            }

            Section {
                Text(NodebayBrand.copyright)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About Nodebay")
    }

    private func aboutLink(_ title: String, systemImage: String, url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
