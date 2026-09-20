import Foundation
import AppKit
import Vision
import CoreML

final class CoreMLYoloDetector {
    static let shared = CoreMLYoloDetector()
    private var headModel: VNCoreMLModel?
    private var bodyModel: VNCoreMLModel?
    
    private init() {
        // 1. Load Head Model (yolov8n-head)
        let headCandidatePaths = [
            Bundle.main.url(forResource: "yolov8n-head", withExtension: "mlmodelc"),
            Bundle.main.url(forResource: "yolov8n_head", withExtension: "mlmodelc"),
            URL(fileURLWithPath: "/Users/enoch/Desktop/HorizonPTZ.app/Contents/Resources/yolov8n-head.mlmodelc"),
            URL(fileURLWithPath: "/Users/enoch/Desktop/HorizonPTZ.app/Contents/Resources/yolov8n_head.mlmodelc"),
            URL(fileURLWithPath: "/Users/enoch/AndroidStudioProjects/HorizonPTZ/macos/HorizonPTZ/yolov8n-head.mlmodelc"),
            URL(fileURLWithPath: "/Users/enoch/AndroidStudioProjects/HorizonPTZ/macos/HorizonPTZ/yolov8n_head.mlmodelc"),
            URL(fileURLWithPath: "/tmp/yolov8n_head.mlmodelc")
        ]
        
        for path in headCandidatePaths {
            if let url = path, FileManager.default.fileExists(atPath: url.path) {
                if let mlModel = try? MLModel(contentsOf: url),
                   let vModel = try? VNCoreMLModel(for: mlModel) {
                    self.headModel = vModel
                    print("🚀 [CoreMLYoloDetector] Head Model loaded successfully from: \(url.path)")
                    break
                }
            }
        }
        
        // 2. Load Body Model (yolov8n - COCO Person)
        let bodyCandidatePaths = [
            Bundle.main.url(forResource: "yolov8n", withExtension: "mlmodelc"),
            URL(fileURLWithPath: "/Users/enoch/Desktop/HorizonPTZ.app/Contents/Resources/yolov8n.mlmodelc"),
            URL(fileURLWithPath: "/Users/enoch/AndroidStudioProjects/HorizonPTZ/macos/HorizonPTZ/yolov8n.mlmodelc"),
            URL(fileURLWithPath: "/tmp/yolov8n.mlmodelc")
        ]
        
        for path in bodyCandidatePaths {
            if let url = path, FileManager.default.fileExists(atPath: url.path) {
                if let mlModel = try? MLModel(contentsOf: url),
                   let vModel = try? VNCoreMLModel(for: mlModel) {
                    self.bodyModel = vModel
                    print("🚀 [CoreMLYoloDetector] Body (Person) Model loaded successfully from: \(url.path)")
                    break
                }
            }
        }
    }
    
    func detect(cgImage: CGImage, minConfidence: Float = 0.20, isAudienceView: Bool = false) -> [CGRect] {
        var bodyBoxes: [CGRect] = []
        var headBoxes: [CGRect] = []
        var requests: [VNRequest] = []
        
        if let bodyModel = bodyModel {
            let bodyReq = VNCoreMLRequest(model: bodyModel) { [weak self] req, _ in
                guard let self = self,
                      let obs = (req.results as? [VNCoreMLFeatureValueObservation])?.first,
                      let multi = obs.featureValue.multiArrayValue else { return }
                bodyBoxes = self.parseYoloTensorBody(multiArray: multi, minConfidence: 0.32)
            }
            bodyReq.imageCropAndScaleOption = .scaleFill
            requests.append(bodyReq)
        }
        
        if let headModel = headModel {
            let headReq = VNCoreMLRequest(model: headModel) { [weak self] req, _ in
                guard let self = self,
                      let obs = (req.results as? [VNCoreMLFeatureValueObservation])?.first,
                      let multi = obs.featureValue.multiArrayValue else { return }
                headBoxes = self.parseYoloTensorHead(multiArray: multi, minConfidence: minConfidence, isAudienceView: isAudienceView)
            }
            headReq.imageCropAndScaleOption = .scaleFill
            requests.append(headReq)
        }
        
        guard !requests.isEmpty else { return [] }
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform(requests)
        
        // SAHI: Slicing Aided Hyper Inference (Double pixel resolution for small targets in audience view)
        if isAudienceView, let headModel = headModel {
            let fullW = cgImage.width
            let fullH = cgImage.height
            let sliceW = Int(Double(fullW) * 0.60)
            
            // Left 60% slice
            let leftRect = CGRect(x: 0, y: 0, width: sliceW, height: fullH)
            if let leftCg = cgImage.cropping(to: leftRect) {
                var sliceHeads: [CGRect] = []
                let sReq = VNCoreMLRequest(model: headModel) { [weak self] req, _ in
                    guard let self = self,
                          let obs = (req.results as? [VNCoreMLFeatureValueObservation])?.first,
                          let multi = obs.featureValue.multiArrayValue else { return }
                    sliceHeads = self.parseYoloTensorHead(multiArray: multi, minConfidence: minConfidence, isAudienceView: true)
                }
                sReq.imageCropAndScaleOption = .scaleFill
                let sHandler = VNImageRequestHandler(cgImage: leftCg, options: [:])
                try? sHandler.perform([sReq])
                
                for b in sliceHeads {
                    let mapped = CGRect(x: b.origin.x * 0.60, y: b.origin.y, width: b.width * 0.60, height: b.height)
                    headBoxes.append(mapped)
                }
            }
            
            // Right 60% slice
            let rightRect = CGRect(x: fullW - sliceW, y: 0, width: sliceW, height: fullH)
            if let rightCg = cgImage.cropping(to: rightRect) {
                var sliceHeads: [CGRect] = []
                let sReq = VNCoreMLRequest(model: headModel) { [weak self] req, _ in
                    guard let self = self,
                          let obs = (req.results as? [VNCoreMLFeatureValueObservation])?.first,
                          let multi = obs.featureValue.multiArrayValue else { return }
                    sliceHeads = self.parseYoloTensorHead(multiArray: multi, minConfidence: minConfidence, isAudienceView: true)
                }
                sReq.imageCropAndScaleOption = .scaleFill
                let sHandler = VNImageRequestHandler(cgImage: rightCg, options: [:])
                try? sHandler.perform([sReq])
                
                let startX = CGFloat(fullW - sliceW) / CGFloat(fullW)
                for b in sliceHeads {
                    let mapped = CGRect(x: startX + b.origin.x * 0.60, y: b.origin.y, width: b.width * 0.60, height: b.height)
                    headBoxes.append(mapped)
                }
            }
            
            // Unified NMS on headBoxes after SAHI
            var nmsHeads: [CGRect] = []
            let sortedHeads = headBoxes.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
            for b in sortedHeads {
                var keep = true
                for k in nmsHeads {
                    let inter = b.intersection(k)
                    if !inter.isNull {
                        let interArea = inter.width * inter.height
                        let unionArea = (b.width * b.height) + (k.width * k.height) - interArea
                        if interArea / unionArea > 0.35 {
                            keep = false
                            break
                        }
                    }
                }
                if keep { nmsHeads.append(b) }
            }
            headBoxes = nmsHeads
        }
        
        // Head-First Hierarchical Fusion:
        // 1. In congregation/auditorium settings, every detected head represents a confirmed individual.
        var finalBoxes: [CGRect] = headBoxes
        var headlessBodiesCount = 0
        
        // 2. Add detected bodies that do not have an associated head (e.g. head occluded, looking down)
        for body in bodyBoxes {
            let hasAssociatedHead = headBoxes.contains { head in
                let upperBody = CGRect(
                    x: body.minX - 0.04,
                    y: body.minY + body.height * 0.35,
                    width: body.width + 0.08,
                    height: body.height * 0.80
                )
                return upperBody.contains(CGPoint(x: head.midX, y: head.midY))
            }
            if !hasAssociatedHead {
                finalBoxes.append(body)
                headlessBodiesCount += 1
            }
        }
        
        AppLogger.log("🎯 [Head-First Fusion] Heads: \(headBoxes.count), Bodies: \(bodyBoxes.count) (HeadlessBodies: \(headlessBodiesCount)) -> Total: \(finalBoxes.count)")
        return finalBoxes
    }
    
    private func parseYoloTensorBody(multiArray: MLMultiArray, minConfidence: Float = 0.32) -> [CGRect] {
        var rawBoxes: [(box: CGRect, score: Float)] = []
        let strides = multiArray.strides.map { $0.intValue }
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
        
        let shape = multiArray.shape.map { $0.intValue }
        let numAnchors = shape.count > 2 ? shape[2] : 8400
        let strideChannel = strides.count > 1 ? strides[1] : numAnchors
        let strideAnchor = strides.count > 2 ? strides[2] : 1
        
        for i in 0..<numAnchors {
            let score = ptr[4 * strideChannel + i * strideAnchor] // class 0 is 'person'
            if score >= minConfidence {
                let cx = ptr[0 * strideChannel + i * strideAnchor] / 640.0
                let cy = ptr[1 * strideChannel + i * strideAnchor] / 640.0
                let w  = ptr[2 * strideChannel + i * strideAnchor] / 640.0
                let h  = ptr[3 * strideChannel + i * strideAnchor] / 640.0
                
                let normW = CGFloat(w)
                let normH = CGFloat(h)
                let normX = max(CGFloat(0), CGFloat(cx) - normW / 2.0)
                let normY = max(CGFloat(0), CGFloat(1.0 - cy) - normH / 2.0)
                
                if normH >= 0.08 && normW <= 0.85 && (normW / normH) <= 1.50 {
                    rawBoxes.append((box: CGRect(x: normX, y: normY, width: normW, height: normH), score: score))
                }
            }
        }
        
        var finalBoxes: [CGRect] = []
        let sorted = rawBoxes.sorted { $0.score > $1.score }
        for item in sorted {
            let b = item.box
            var keep = true
            for k in finalBoxes {
                let inter = b.intersection(k)
                if !inter.isNull {
                    let interArea = inter.width * inter.height
                    let unionArea = (b.width * b.height) + (k.width * k.height) - interArea
                    let iou = interArea / unionArea
                    if iou > 0.40 {
                        keep = false
                        break
                    }
                }
            }
            if keep {
                finalBoxes.append(b)
            }
        }
        return finalBoxes
    }
    
    private func parseYoloTensorHead(multiArray: MLMultiArray, minConfidence: Float = 0.20, isAudienceView: Bool = false) -> [CGRect] {
        var rawBoxes: [(box: CGRect, score: Float)] = []
        let strides = multiArray.strides.map { $0.intValue }
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
        
        let shape = multiArray.shape.map { $0.intValue }
        let numAnchors = shape.count > 2 ? shape[2] : 8400
        let strideChannel = strides.count > 1 ? strides[1] : numAnchors
        let strideAnchor = strides.count > 2 ? strides[2] : 1
        
        for i in 0..<numAnchors {
            let score = ptr[4 * strideChannel + i * strideAnchor]
            let cx = ptr[0 * strideChannel + i * strideAnchor] / 640.0
            let cy = ptr[1 * strideChannel + i * strideAnchor] / 640.0
            let w  = ptr[2 * strideChannel + i * strideAnchor] / 640.0
            let h  = ptr[3 * strideChannel + i * strideAnchor] / 640.0
            
            let normW = CGFloat(w)
            let normH = CGFloat(h)
            let normX = max(CGFloat(0), CGFloat(cx) - normW / 2.0)
            let normY = max(CGFloat(0), CGFloat(1.0 - cy) - normH / 2.0)
            
            // Adaptive noise suppression:
            // Microphone stands on stage (non-audience view, high up, narrow width) require high confidence
            let isStageMic = (!isAudienceView && normW < 0.065 && (normY + normH / 2.0) > 0.45)
            let requiredConf = isStageMic ? 0.45 : minConfidence
            
            if score >= requiredConf {
                let aspect = normW / normH
                if normW <= 0.35 && normH <= 0.40 && (normW * normH) >= 0.0004 && aspect >= 0.35 && aspect <= 1.60 {
                    rawBoxes.append((box: CGRect(x: normX, y: normY, width: normW, height: normH), score: score))
                }
            }
        }
        
        var finalBoxes: [CGRect] = []
        let sorted = rawBoxes.sorted { $0.score > $1.score }
        for item in sorted {
            let b = item.box
            var keep = true
            for k in finalBoxes {
                let inter = b.intersection(k)
                if !inter.isNull {
                    let interArea = inter.width * inter.height
                    let unionArea = (b.width * b.height) + (k.width * k.height) - interArea
                    let iou = interArea / unionArea
                    if iou > 0.40 {
                        keep = false
                        break
                    }
                }
            }
            if keep {
                finalBoxes.append(b)
            }
        }
        return finalBoxes
    }
}

enum AiEngineMode: String, CaseIterable, Identifiable {
    case appleVision = "Apple Vision (原生 360°)"
    case coreMLYolo = "CoreML YOLO (深度學習 NPU)"
    var id: String { rawValue }
}

struct TrackedHuman {
    let id: Int
    let box: CGRect
}

struct InternalTrackedPerson {
    let id: Int
    var box: CGRect
    var disappeared: Int
    var confirmedFrames: Int
}

class PersonTracker {
    private var trackedPeople: [InternalTrackedPerson] = []
    private var featureGallery: [Int: VNFeaturePrintObservation] = [:]
    private var nextId = 1
    private let maxDisappeared = 15 // ~1.5s grace period at 10fps
    private let minConfirmedFrames = 2
    
    func update(with newBoxes: [CGRect], cgImage: CGImage, distThreshold: CGFloat, alpha: CGFloat, isReIdEnabled: Bool, reIdSimilarity: Float) -> [(id: Int, box: CGRect)] {
        if trackedPeople.isEmpty {
            for box in newBoxes {
                let assignedId = resolveOrAssignId(for: box, cgImage: cgImage, isReIdEnabled: isReIdEnabled, reIdSimilarity: reIdSimilarity)
                trackedPeople.append(InternalTrackedPerson(id: assignedId, box: box, disappeared: 0, confirmedFrames: 1))
            }
            return trackedPeople.filter { $0.confirmedFrames >= minConfirmedFrames && $0.disappeared <= 12 }.map { ($0.id, $0.box) }
        }
        
        var matches: [(trackedIdx: Int, newBoxIdx: Int, distance: CGFloat)] = []
        
        for (tIdx, person) in trackedPeople.enumerated() {
            let centerA = CGPoint(x: person.box.midX, y: person.box.midY)
            for (nIdx, newBox) in newBoxes.enumerated() {
                let centerB = CGPoint(x: newBox.midX, y: newBox.midY)
                let dx = centerA.x - centerB.x
                let dy = centerA.y - centerB.y
                let dist = sqrt(dx*dx + dy*dy)
                
                let intersection = person.box.intersection(newBox)
                let iou = intersection.isNull ? 0 : (intersection.width * intersection.height) / (person.box.width * person.box.height)
                
                if dist < distThreshold || iou > 0.10 {
                    matches.append((tIdx, nIdx, dist))
                }
            }
        }
        
        matches.sort { $0.distance < $1.distance }
        
        var updatedTracked: [InternalTrackedPerson] = []
        var matchedTracked = Set<Int>()
        var matchedNew = Set<Int>()
        
        for match in matches {
            if matchedTracked.contains(match.trackedIdx) || matchedNew.contains(match.newBoxIdx) {
                continue
            }
            matchedTracked.insert(match.trackedIdx)
            matchedNew.insert(match.newBoxIdx)
            
            var person = trackedPeople[match.trackedIdx]
            let targetBox = newBoxes[match.newBoxIdx]
            
            let smoothedBox = CGRect(
                x: person.box.origin.x * (1 - alpha) + targetBox.origin.x * alpha,
                y: person.box.origin.y * (1 - alpha) + targetBox.origin.y * alpha,
                width: person.box.size.width * (1 - alpha) + targetBox.size.width * alpha,
                height: person.box.size.height * (1 - alpha) + targetBox.size.height * alpha
            )
            
            person.box = smoothedBox
            person.disappeared = 0
            person.confirmedFrames += 1
            updatedTracked.append(person)
        }
        
        for (tIdx, person) in trackedPeople.enumerated() {
            if !matchedTracked.contains(tIdx) {
                var p = person
                p.disappeared += 1
                if p.disappeared <= maxDisappeared {
                    updatedTracked.append(p)
                }
            }
        }
        
        for (nIdx, newBox) in newBoxes.enumerated() {
            if !matchedNew.contains(nIdx) {
                let assignedId = resolveOrAssignId(for: newBox, cgImage: cgImage, isReIdEnabled: isReIdEnabled, reIdSimilarity: reIdSimilarity)
                updatedTracked.append(InternalTrackedPerson(id: assignedId, box: newBox, disappeared: 0, confirmedFrames: 1))
            }
        }
        
        if updatedTracked.isEmpty && featureGallery.isEmpty {
            nextId = 1
        }
        
        trackedPeople = updatedTracked
        return trackedPeople.filter { $0.confirmedFrames >= minConfirmedFrames && $0.disappeared <= 12 }
            .sorted { $0.id < $1.id }
            .map { ($0.id, $0.box) }
    }
    
    private func resolveOrAssignId(for box: CGRect, cgImage: CGImage, isReIdEnabled: Bool, reIdSimilarity: Float) -> Int {
        let newId = nextId
        nextId += 1
        return newId
    }
    
    func reset() {
        trackedPeople.removeAll()
        featureGallery.removeAll()
        nextId = 1
    }
}

class PeopleCounterService: ObservableObject {
    static let shared = PeopleCounterService()
    
    @Published var currentEngineMode: AiEngineMode = .coreMLYolo
    @Published var confidenceThreshold: Float = 0.15
    @Published var minObjectSize: Float = 0.001
    @Published var samplingFps: Int = 10
    @Published var trackingAlpha: Float = 0.85
    @Published var maxMotionDistance: Float = 0.15
    
    @Published var isReIdEnabled: Bool = true
    @Published var reIdSimilarity: Float = 0.80
    
    private var tracker1 = PersonTracker()
    private var tracker2 = PersonTracker()
    
    struct AnalysisResult {
        let count: Int
        let trackedHumans: [TrackedHuman]
        let engineName: String
    }
    
    func resetTracker(cameraIndex: Int? = nil) {
        if let idx = cameraIndex {
            if idx == 1 { tracker1.reset() }
            else if idx == 2 { tracker2.reset() }
        } else {
            tracker1.reset()
            tracker2.reset()
        }
    }
    
    func analyzePeopleCount(in image: NSImage, cameraIndex: Int, completion: @escaping (AnalysisResult) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(AnalysisResult(count: 0, trackedHumans: [], engineName: currentEngineMode.rawValue))
            return
        }
        
        let mode = self.currentEngineMode
        let distThresh = CGFloat(self.maxMotionDistance)
        let alpha = CGFloat(self.trackingAlpha)
        let reIdOn = self.isReIdEnabled
        let reIdSim = self.reIdSimilarity
        
        DispatchQueue.global(qos: .userInitiated).async {
            let finalBoxes: [CGRect]
            if mode == .appleVision {
                finalBoxes = self.runAppleVisionInference(cgImage: cgImage)
            } else {
                finalBoxes = self.runCoreMLYoloInference(cgImage: cgImage, cameraIndex: cameraIndex)
            }
            
            let tracker = (cameraIndex == 1) ? self.tracker1 : self.tracker2
            let trackedTuples = tracker.update(
                with: finalBoxes,
                cgImage: cgImage,
                distThreshold: distThresh,
                alpha: alpha,
                isReIdEnabled: reIdOn,
                reIdSimilarity: reIdSim
            )
            let resultHumans = trackedTuples.map { TrackedHuman(id: $0.id, box: $0.box) }
            AppLogger.log("🔎 [Cam \(cameraIndex)] finalBoxes: \(finalBoxes.count), tracked: \(resultHumans.count)")
            
            DispatchQueue.main.async {
                completion(AnalysisResult(
                    count: resultHumans.count,
                    trackedHumans: resultHumans,
                    engineName: mode.rawValue
                ))
            }
        }
    }
    
    private func runAppleVisionInference(cgImage: CGImage) -> [CGRect] {
        return runPrecisionDetection(cgImage: cgImage)
    }
    
    private func runCoreMLYoloInference(cgImage: CGImage, cameraIndex: Int = 1) -> [CGRect] {
        return CoreMLYoloDetector.shared.detect(cgImage: cgImage, minConfidence: self.confidenceThreshold, isAudienceView: (cameraIndex == 1))
    }
    
    private func runPrecisionDetection(cgImage: CGImage, cameraIndex: Int = 1) -> [CGRect] {
        var rawBoxes: [CGRect] = []
        
        let poseReq = VNDetectHumanBodyPoseRequest()
        let reqFace = VNDetectFaceRectanglesRequest()
        let h1 = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? h1.perform([poseReq, reqFace])
        
        // 1. Pass 1: Human Body Pose Head/Neck Keypoints
        for obs in (poseReq.results ?? []) {
            if let points = try? obs.recognizedPoints(forGroupKey: .all) {
                let validPoints = points.values.filter { $0.confidence > 0.20 }
                if validPoints.count >= 2 {
                    let xs = validPoints.map { CGFloat($0.location.x) }
                    let ys = validPoints.map { CGFloat($0.location.y) }
                    let minX = xs.min()!
                    let maxX = xs.max()!
                    let minY = ys.min()!
                    let maxY = ys.max()!
                    
                    let padX: CGFloat = 0.02
                    let padY: CGFloat = 0.02
                    
                    let b = CGRect(
                        x: max(0, minX - padX),
                        y: max(0, minY - padY),
                        width: min(0.12, (maxX - minX) + padX * 2),
                        height: min(0.15, (maxY - minY) + padY * 2)
                    )
                    rawBoxes.append(b)
                }
            }
        }
        
        // 2. Pass 2: Face Detections (True Faces)
        for f in (reqFace.results ?? []) {
            if f.confidence >= 0.05 {
                let b = f.boundingBox
                let head = CGRect(x: max(0, b.origin.x - b.width*0.10),
                                  y: max(0, b.origin.y - b.height*0.10),
                                  width: min(0.12, b.width * 1.2),
                                  height: min(0.15, b.height * 1.3))
                rawBoxes.append(head)
            }
        }
        
        // 3. Pass 3: 8x8 Seated Audience Micro Grid (Face detection only, no generic upper body)
        if cameraIndex == 1 {
            let cols = 8
            let rows = 8
            let tileW = CGFloat(cgImage.width) / CGFloat(cols)
            let tileH = CGFloat(cgImage.height) / CGFloat(rows)
            let fullW = CGFloat(cgImage.width)
            let fullH = CGFloat(cgImage.height)
            
            for r in 0..<rows {
                for c in 0..<cols {
                    let tileRect = CGRect(x: CGFloat(c) * tileW, y: CGFloat(r) * tileH, width: tileW, height: tileH)
                    guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
                    
                    let tFace = VNDetectFaceRectanglesRequest()
                    let th = VNImageRequestHandler(cgImage: tileCg, options: [:])
                    try? th.perform([tFace])
                    
                    for f in (tFace.results ?? []) {
                        if f.confidence >= 0.03 {
                            let b = f.boundingBox
                            let normX = (CGFloat(c) * tileW + (b.origin.x - b.width * 0.10) * tileW) / fullW
                            let normY = 1.0 - ((CGFloat(r + 1) * tileH) - (b.origin.y - b.height * 0.10) * tileH) / fullH
                            let normW = (b.width * 1.2 * tileW) / fullW
                            let normH = (b.height * 1.3 * tileH) / fullH
                            
                            rawBoxes.append(CGRect(x: max(0, normX), y: max(0, normY), width: min(0.12, normW), height: min(0.15, normH)))
                        }
                    }
                }
            }
        }
        
        // 4. Filter out invalid background noise (Doors, Ceiling, Wall Light Beam)
        let validBoxes = rawBoxes.filter { b in
            let area = b.width * b.height
            let isDoorFrame = (b.origin.x < 0.03 && b.origin.y > 0.50) || (b.origin.x > 0.94)
            let isCeiling = (b.origin.y + b.height >= 0.92)
            
            // Exclude static wall light / projector beam zone (midX: 0.38..0.55, midY: 0.40..0.75 without human features)
            let isWallLightBeam = (b.midX > 0.38 && b.midX < 0.55 && b.midY > 0.45 && b.midY < 0.75 && b.width > 0.15)
            let isGiantCluster = (b.width > 0.14 || b.height > 0.18)
            
            return area >= 0.0005 && !isCeiling && !isDoorFrame && !isWallLightBeam && !isGiantCluster
        }
        
        // 5. Standard IoU Non-Maximum Suppression (NMS - No vertical column over-merging)
        var keptBoxes: [CGRect] = []
        let candidates = validBoxes.sorted { ($0.width * $0.height) < ($1.width * $1.height) }
        
        for b in candidates {
            var shouldKeep = true
            for existing in keptBoxes {
                let intersection = b.intersection(existing)
                if !intersection.isNull {
                    let interArea = intersection.width * intersection.height
                    let unionArea = (b.width * b.height) + (existing.width * existing.height) - interArea
                    let iou = interArea / unionArea
                    if iou > 0.30 {
                        shouldKeep = false
                        break
                    }
                }
            }
            if shouldKeep {
                keptBoxes.append(b)
            }
        }
        return keptBoxes
    }
}
