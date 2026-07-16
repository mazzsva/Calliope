//
//  View+OnScenePhaseActive.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 17/07/26.
//

import SwiftUI

extension View {
    func onScenePhaseActive(perform action: @escaping () -> Void) -> some View {
        modifier(OnScenePhaseActive(action: action))
    }
}

private struct OnScenePhaseActive: ViewModifier {
    let action: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            action()
        }
    }
}
