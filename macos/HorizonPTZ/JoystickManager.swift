import Foundation
import GameController

class JoystickManager: ObservableObject {
    static let shared = JoystickManager()
    
    @Published var isControllerConnected = false
    @Published var controllerName = "No controller"
    
    var onPanTiltUpdate: ((Float, Float) -> Void)?
    var onZoomUpdate: ((Int, Int) -> Void)? // mode: 0 stop, 1 in, 2 out; speed: 0-7
    
    private var activeController: GCController?
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidConnect),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDidDisconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        
        // Setup initial controller if available
        if let controller = GCController.controllers().first {
            setupController(controller)
        }
    }
    
    @objc private func controllerDidConnect(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            setupController(controller)
        }
    }
    
    @objc private func controllerDidDisconnect(_ notification: Notification) {
        if let controller = notification.object as? GCController, controller == activeController {
            DispatchQueue.main.async {
                self.isControllerConnected = false
                self.controllerName = "No controller"
            }
            activeController = nil
        }
    }
    
    private func setupController(_ controller: GCController) {
        activeController = controller
        DispatchQueue.main.async {
            self.isControllerConnected = true
            self.controllerName = controller.vendorName ?? "USB Controller"
        }
        
        controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, element in
            guard let self = self else { return }
            
            // Left stick handles pan/tilt
            let pan = gamepad.leftThumbstick.xAxis.value  // -1.0 to 1.0
            let tilt = gamepad.leftThumbstick.yAxis.value // -1.0 to 1.0
            self.onPanTiltUpdate?(pan, tilt)
            
            // Triggers handle zoom
            let zoomOut = gamepad.leftTrigger.value  // 0.0 to 1.0
            let zoomIn = gamepad.rightTrigger.value   // 0.0 to 1.0
            
            if zoomIn > 0.1 {
                let speed = Int(zoomIn * 7)
                self.onZoomUpdate?(1, speed)
            } else if zoomOut > 0.1 {
                let speed = Int(zoomOut * 7)
                self.onZoomUpdate?(2, speed)
            } else {
                self.onZoomUpdate?(0, 0)
            }
        }
    }
}
