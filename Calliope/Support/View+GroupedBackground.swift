//
//  View+GroupedBackground.swift
//  Calliope
//
//  Created by Lorenzo Mazzarotto on 17/07/26.
//

import SwiftUI

extension View {
    func groupedBackground() -> some View {
        background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
