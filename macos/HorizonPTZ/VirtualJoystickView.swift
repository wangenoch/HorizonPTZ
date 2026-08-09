import SwiftUI

struct VirtualJoystickView: View {
    let title: String
    var onJoystickMove: (CGFloat, CGFloat) -> Void // reports normalized offset (-1.0 to 1.0)
    var onJoystickRelease: () -> Void
    
    @State private var dragOffset: CGSize = .zero
    private let joystickSize: CGFloat = 110
    private let knobSize: CGFloat = 36
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            
            ZStack {
                // Outer ring
                Circle()
                    .fill(Color.black.opacity(0.15))
                    .frame(width: joystickSize, height: joystickSize)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1.5)
                    )
                
                // Cross guides
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: joystickSize - 20, height: 1)
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 1, height: joystickSize - 20)
                
                // Inner Knob
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.9), Color.accentColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: knobSize, height: knobSize)
                    .offset(dragOffset)
                    .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let maxDistance = (joystickSize - knobSize) / 2
                                let width = value.translation.width
                                let height = value.translation.height
                                let distance = sqrt(width * width + height * height)
                                
                                if distance <= maxDistance {
                                    dragOffset = value.translation
                                } else {
                                    let angle = atan2(height, width)
                                    dragOffset = CGSize(
                                        width: cos(angle) * maxDistance,
                                        height: sin(angle) * maxDistance
                                    )
                                }
                                
                                // Normalize between -1.0 and 1.0 (invert Y axis for standard cartesian coordinate)
                                let normX = dragOffset.width / maxDistance
                                let normY = -dragOffset.height / maxDistance
                                onJoystickMove(normX, normY)
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    dragOffset = .zero
                                }
                                onJoystickRelease()
                            }
                    )
            }
            .frame(width: joystickSize, height: joystickSize)
        }
    }
}
