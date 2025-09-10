//
//  IdentityButton.swift
//  TrinsicUI
//
//  Created by Buster Townsend on 9/10/25.
//
import SwiftUI
import PassKit
#if canImport(UIKit)
import UIKit
#endif

/// A convenient SwiftUI wrapper around Apple's `PKIdentityButton` that is suggested to use
/// when verifying identity with Apple.
///
/// For more information on what styles are available for the label and style, see https://developer.apple.com/documentation/passkit/pkidentitybutton
///
@available(iOS 16.0, *)
@available(macOS, unavailable)
public struct IdentityButton: UIViewRepresentable {
  let label: PKIdentityButton.Label
  let style: PKIdentityButton.Style
  let action: () -> Void

  init(
    label: PKIdentityButton.Label = .verifyIdentity,
    style: PKIdentityButton.Style = .black,
    action: @escaping () -> Void
  ) {
    self.label = label
    self.style = style
    self.action = action
  }

  public func makeUIView(context: Context) -> PKIdentityButton {
    let button = PKIdentityButton(label: label, style: style)
    button.cornerRadius = 12.0
    button.addTarget(
      context.coordinator,
      action: #selector(Coordinator.buttonTapped),
      for: .touchUpInside)
    return button
  }

  public func updateUIView(_ uiView: PKIdentityButton, context: Context) {
    // Update view if needed
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  public class Coordinator: NSObject {
    let action: () -> Void

    init(action: @escaping () -> Void) {
      self.action = action
    }

    @objc func buttonTapped() {
      action()
    }
  }
}
