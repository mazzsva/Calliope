//
//  LoadingWindow.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 26/07/26.
//

import SwiftUI

extension View {
    func loadingWindow(isVisible: Bool, message: String? = nil) -> some View {
        background(LoadingWindow(isVisible: isVisible, message: message))
    }
}

private struct LoadingView: View {
    let message: String?

    @State private var showsMessage = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                ZStack {
                    // Reserve a line of height so the message fades in without resizing the layout
                    Text(" ")
                        .hidden()
                    if showsMessage, let message {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            // Anchor the content near the optical center, slightly above the true middle
            .padding(.top, proxy.size.height * 0.38)
            .animation(.easeInOut(duration: 0.25), value: showsMessage)
            .animation(.easeInOut(duration: 0.25), value: message)
        }
        .groupedBackground()
        .task {
            // Delay the message so quick loads never flash text
            try? await Task.sleep(for: .seconds(0.5))
            showsMessage = true
        }
    }
}

private struct LoadingWindow: UIViewRepresentable {
    let isVisible: Bool
    let message: String?

    func makeUIView(context: Context) -> LoadingWindowAnchor {
        LoadingWindowAnchor()
    }

    func updateUIView(_ anchor: LoadingWindowAnchor, context: Context) {
        anchor.message = message
        anchor.isLoadingVisible = isVisible
    }
}

// Reach the active window scene from the view hierarchy so the overlay can open its own window
private final class LoadingWindowAnchor: UIView {
    var isLoadingVisible = false {
        didSet {
            guard isLoadingVisible != oldValue else { return }
            update()
        }
    }

    var message: String? {
        didSet { hostingController?.rootView = LoadingView(message: message) }
    }

    private let fadeDuration: TimeInterval = 0.25
    private var loadingWindow: UIWindow?
    private var hostingController: UIHostingController<LoadingView>?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        update()
    }

    private func update() {
        if isLoadingVisible {
            // Showing again mid fade-out reuses the window and fades it back in
            if let loadingWindow {
                loadingWindow.isUserInteractionEnabled = true
                UIView.animate(withDuration: fadeDuration, delay: 0, options: .allowUserInteraction) {
                    loadingWindow.alpha = 1
                }
                return
            }
            guard let windowScene = window?.windowScene else { return }
            let hostingController = UIHostingController(rootView: LoadingView(message: message))
            hostingController.view.backgroundColor = .clear
            // A dedicated window above the app keeps the overlay on top of sheets and alerts
            let loadingWindow = UIWindow(windowScene: windowScene)
            loadingWindow.rootViewController = hostingController
            loadingWindow.backgroundColor = .clear
            loadingWindow.windowLevel = UIWindow.Level(UIWindow.Level.normal.rawValue + 1)
            loadingWindow.alpha = 0
            loadingWindow.isHidden = false
            self.hostingController = hostingController
            self.loadingWindow = loadingWindow
            // Keep blocking touches while the fade-in runs
            UIView.animate(withDuration: fadeDuration, delay: 0, options: .allowUserInteraction) {
                loadingWindow.alpha = 1
            }
        } else {
            guard let loadingWindow else { return }
            // Give touches back to the app as soon as the dismissal starts
            loadingWindow.isUserInteractionEnabled = false
            UIView.animate(withDuration: fadeDuration) {
                loadingWindow.alpha = 0
            } completion: { [weak self] _ in
                // Loading may have restarted mid fade-out; the window is being reused then
                guard let self, !isLoadingVisible else { return }
                loadingWindow.isHidden = true
                self.loadingWindow = nil
                self.hostingController = nil
            }
        }
    }
}

#Preview("With Message") {
    LoadingView(message: "Signing in…")
}

#Preview("No Message") {
    LoadingView(message: nil)
}
