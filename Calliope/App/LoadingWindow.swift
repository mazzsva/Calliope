//
//  LoadingWindow.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 26/07/26.
//

import SwiftUI

extension View {
    func loadingWindow(isVisible: Bool, message: String?) -> some View {
        background(LoadingWindow(isVisible: isVisible, message: message))
    }
}

private struct LoadingView: View {
    let message: String?

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                if let message {
                    Text(message)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, proxy.size.height * 0.38)
            .animation(.easeInOut(duration: 0.25), value: message)
        }
        .groupedBackground()
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
    private var hostingController: UIHostingController<LoadingView>?
    private var loadingWindow: UIWindow?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        update()
    }

    private func fadeIn(_ window: UIWindow) {
        UIView.animate(withDuration: fadeDuration, delay: 0, options: .allowUserInteraction) {
            window.alpha = 1
        }
    }

    private func hideLoadingWindow() {
        guard let loadingWindow else { return }
        loadingWindow.isUserInteractionEnabled = false
        UIView.animate(withDuration: fadeDuration) {
            loadingWindow.alpha = 0
        } completion: { [weak self] _ in
            guard let self, !isLoadingVisible else { return }
            loadingWindow.isHidden = true
            self.loadingWindow = nil
            self.hostingController = nil
        }
    }

    private func showLoadingWindow() {
        if let loadingWindow {
            loadingWindow.isUserInteractionEnabled = true
            return fadeIn(loadingWindow)
        }
        guard let windowScene = window?.windowScene else { return }
        let hostingController = UIHostingController(rootView: LoadingView(message: message))
        hostingController.view.backgroundColor = .clear
        let loadingWindow = UIWindow(windowScene: windowScene)
        loadingWindow.rootViewController = hostingController
        loadingWindow.backgroundColor = .clear
        loadingWindow.windowLevel = UIWindow.Level(UIWindow.Level.normal.rawValue + 1)
        loadingWindow.alpha = 0
        loadingWindow.isHidden = false
        self.hostingController = hostingController
        self.loadingWindow = loadingWindow
        fadeIn(loadingWindow)
    }

    private func update() {
        isLoadingVisible ? showLoadingWindow() : hideLoadingWindow()
    }
}

#Preview("With Message") {
    LoadingView(message: "Signing in…")
}

#Preview("No Message") {
    LoadingView(message: nil)
}
