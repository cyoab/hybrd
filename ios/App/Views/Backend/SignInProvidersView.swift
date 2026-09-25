import SwiftUI

/// Presentation-only providers. These buttons must not create a session or start OAuth.
struct SignInProvidersView: View {
  @State private var selectedProvider: Provider?

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        Rectangle().fill(HybrdStyle.line).frame(height: 1).accessibilityHidden(true)
        Text(L10n.text("More ways to sign in")).font(.caption)
          .foregroundStyle(HybrdStyle.muted).fixedSize(horizontal: false, vertical: true)
          .layoutPriority(1)
        Rectangle().fill(HybrdStyle.line).frame(height: 1).accessibilityHidden(true)
      }.padding(.bottom, 2)
      providerButton(.apple)
      providerButton(.google)
      Text(L10n.text("Apple and Google sign-in are coming soon."))
        .font(.caption).foregroundStyle(HybrdStyle.muted)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }
    .alert(item: $selectedProvider) { provider in
      Alert(title: Text(L10n.text("Coming soon")), message: Text(provider.explanation), dismissButton: .default(Text(L10n.text("OK"))))
    }
  }

  private func providerButton(_ provider: Provider) -> some View {
    Button { selectedProvider = provider } label: {
      HStack(spacing: 12) {
        Group {
          if provider == .apple {
            Image(systemName: "apple.logo").font(.system(size: 22))
          } else {
            Image("GoogleSignIn").resizable().scaledToFit()
          }
        }.frame(width: 22, height: 22).accessibilityHidden(true)
        Text(provider.title).font(.body.weight(.medium))
          .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(Color(hex: 0x1F1F1F))
      .padding(.horizontal, 16).padding(.vertical, 14)
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(hex: 0x747775), lineWidth: 1))
      .contentShape(RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
    .accessibilityHint(L10n.text("Coming soon"))
    .accessibilityIdentifier("signIn." + provider.rawValue)
  }

  private enum Provider: String, Identifiable {
    case apple, google
    var id: String { rawValue }
    var title: String {
      switch self {
      case .apple: L10n.text("Continue with Apple")
      case .google: L10n.text("Continue with Google")
      }
    }
    var explanation: String {
      switch self {
      case .apple: L10n.text("Apple sign-in is coming soon. Use email to get started today.")
      case .google: L10n.text("Google sign-in is coming soon. Use email to get started today.")
      }
    }
  }
}
