import SwiftUI

struct WelcomeView: View {
    @Environment(ViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 45, weight: .light))
                .foregroundStyle(.primary)
                .frame(width: 80, height: 80)
                .background(.background)
                .clipShape(.rect(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
                }

            Text("iTM")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .padding(.top, 16)

            Text("iOS TimeMachine")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            VStack(spacing: 12) {
                WelcomeAction(
                    symbol: "arrow.up.doc",
                    title: "Backup Device",
                    detail: "Download device data and archive to selected destination"
                ) {
                    vm.mode = .backup
                    vm.page = .findDevice
                }

                WelcomeAction(
                    symbol: "arrow.down.doc",
                    title: "Restore Device",
                    detail: "Restore device data from selected archive"
                ) {
                    vm.mode = .restore
                    vm.page = .findDevice
                }
            }
            .padding(.top, 25)
            .frame(maxWidth: 440)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { vm.resetAll() }
    }
}

private struct WelcomeAction: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 42, height: 42)
                    .background(.primary.opacity(0.06))
                    .clipShape(.rect(cornerRadius: 13))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(.primary)
            .padding(15)
            .background(.background)
            .clipShape(.rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
