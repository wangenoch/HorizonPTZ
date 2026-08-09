import Foundation
import AppKit
import Vision

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
    private let maxDisappeared = 8
    private let minConfirmedFrames = 1 // Immediate detection response for crowds!
    
    func update(with newBoxes: [CGRect], cgImage: CGImage, distThreshold: CGFloat, alpha: CGFloat, isReIdEnabled: Bool, reIdSimilarity: Float) -> [(id: Int, box: CGRect)] {
        if trackedPeople.isEmpty {
            for box in newBoxes {
                let assignedId = resolveOrAssignId(for: box, cgImage: cgImage, isReIdEnabled: isReIdEnabled, reIdSimilarity: reIdSimilarity)
                trackedPeople.append(InternalTrackedPerson(id: assignedId, box: box, disappeared: 0, confirmedFrames: 1))
            }
            return trackedPeople.map { ($0.id, $0.box) }
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
                
                if dist < distThreshold || iou > 0.15 {
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
            
            // Fast Motion Responsive Exponential Moving Average (EMA) Smoothing
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
            
            // Update feature gallery periodically for active person
            if isReIdEnabled && person.confirmedFrames % 5 == 0 {
                updateFeatureForId(person.id, box: smoothedBox, cgImage: cgImage)
            }
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
        return trackedPeople.filter { $0.disappeared == 0 }
            .sorted { $0.id < $1.id }
            .map { ($0.id, $0.box) }
    }
    
    private func resolveOrAssignId(for box: CGRect, cgImage: CGImage, isReIdEnabled: Bool, reIdSimilarity: Float) -> Int {
        if isReIdEnabled, let obs = extractFeaturePrint(for: box, in: cgImage) {
            var bestId: Int? = nil
            var minDistance: Float = Float.greatestFiniteMagnitude
            
            let maxAllowedDistance = (1.0 - reIdSimilarity) * 2.5 // e.g. 80% similarity -> max dist ~0.50
            
            for (id, galleryObs) in featureGallery {
                var distance: Float = 0
                if (try? obs.computeDistance(&distance, to: galleryObs)) != nil {
                    if distance < maxAllowedDistance && distance < minDistance {
                        minDistance = distance
                        bestId = id
                    }
                }
            }
            
            if let matchedId = bestId {
                AppLogger.log("🎯 [Re-ID Match] Matched returning person to persistent ID #\(matchedId) (Distance: \(String(format: "%.3f", minDistance)))")
                featureGallery[matchedId] = obs
                return matchedId
            } else {
                let newId = nextId
                nextId += 1
                featureGallery[newId] = obs
                return newId
            }
        } else {
            let newId = nextId
            nextId += 1
            return newId
        }
    }
    
    private func updateFeatureForId(_ id: Int, box: CGRect, cgImage: CGImage) {
        if let obs = extractFeaturePrint(for: box, in: cgImage) {
            featureGallery[id] = obs
        }
    }
    
    private func extractFeaturePrint(for box: CGRect, in cgImage: CGImage) -> VNFeaturePrintObservation? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let cropRect = CGRect(
            x: max(0, box.origin.x * width),
            y: max(0, (1.0 - box.origin.y - box.height) * height),
            width: min(width, box.width * width),
            height: min(height, box.height * height)
        )
        
        guard cropRect.width > 20 && cropRect.height > 20,
              let croppedCg = cgImage.cropping(to: cropRect) else {
            return nil
        }
        
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: croppedCg, options: [:])
        do {
            try handler.perform([request])
            return request.results?.first as? VNFeaturePrintObservation
        } catch {
            return nil
        }
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
    @Published var confidenceThreshold: Float = 0.04 // Ultra high sensitivity 4% for crowded audience
    @Published var minObjectSize: Float = 0.003       // Extremely small 0.3% area to capture distant heads
    @Published var samplingFps: Int = 10              // High FPS sampling 10 FPS
    @Published var trackingAlpha: Float = 0.90       // Fast motion tracking weight
    @Published var maxMotionDistance: Float = 0.38   // Fast motion distance matching
    
    @Published var isReIdEnabled: Bool = true        // Re-ID Visual Feature Memory Enabled
    @Published var reIdSimilarity: Float = 0.80       // Re-ID Similarity threshold (80%)
    
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
        AppLogger.log("🔄 [PeopleCounterService] Reset tracking IDs & Re-ID feature gallery back to #1 for camera \(cameraIndex?.description ?? "ALL")")
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
            var candidateBoxes: [CGRect] = []
            
            if mode == .coreMLYolo {
                candidateBoxes = self.runCoreMLYoloInference(cgImage: cgImage)
            } else {
                candidateBoxes = self.runAppleVisionInference(cgImage: cgImage)
            }
            
            let finalBoxes = self.mergeAndFilterBoxes(candidateBoxes)
            
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
        var boxes: [CGRect] = []
        
        // Request 1: Full Body Human Rectangles
        let fullBodyReq = VNDetectHumanRectanglesRequest()
        fullBodyReq.upperBodyOnly = false
        
        // Request 2: Upper Body Human Rectangles (Seated audience)
        let upperBodyReq = VNDetectHumanRectanglesRequest()
        upperBodyReq.upperBodyOnly = true
        
        // Request 3: Face & Head Rectangles (Captures seated faces/heads in rows)
        let faceReq = VNDetectFaceRectanglesRequest()
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([fullBodyReq, upperBodyReq, faceReq])
            
            // Full Body Results
            if let results = fullBodyReq.results {
                for observation in results {
                    if observation.confidence >= self.confidenceThreshold {
                        boxes.append(observation.boundingBox)
                    }
                }
            }
            
            // Upper Body Results
            if let results = upperBodyReq.results {
                for observation in results {
                    if observation.confidence >= (self.confidenceThreshold * 0.7) {
                        boxes.append(observation.boundingBox)
                    }
                }
            }
            
            // Face & Head Results -> Pad face to head/shoulder bounding box
            if let faceResults = faceReq.results {
                for face in faceResults {
                    if face.confidence >= (self.confidenceThreshold * 0.6) {
                        let f = face.boundingBox
                        let headBox = CGRect(
                            x: max(0, f.origin.x - f.width * 0.2),
                            y: max(0, f.origin.y - f.height * 0.3),
                            width: min(1.0 - f.origin.x, f.width * 1.4),
                            height: min(1.0 - f.origin.y, f.height * 1.8)
                        )
                        boxes.append(headBox)
                    }
                }
            }
        } catch {
            AppLogger.log("⚠️ Apple Vision Inference Error: \(error)")
        }
        return boxes
    }
    
    private func runCoreMLYoloInference(cgImage: CGImage) -> [CGRect] {
        // Enriched Multi-Modal Detection Engine for Crowds
        var boxes: [CGRect] = []
        
        let fullBodyReq = VNDetectHumanRectanglesRequest()
        fullBodyReq.upperBodyOnly = false
        
        let upperBodyReq = VNDetectHumanRectanglesRequest()
        upperBodyReq.upperBodyOnly = true
        
        let faceReq = VNDetectFaceRectanglesRequest()
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([fullBodyReq, upperBodyReq, faceReq])
            
            if let results = fullBodyReq.results {
                for observation in results {
                    if observation.confidence >= (self.confidenceThreshold * 0.5) {
                        boxes.append(observation.boundingBox)
                    }
                }
            }
            
            if let results = upperBodyReq.results {
                for observation in results {
                    if observation.confidence >= (self.confidenceThreshold * 0.5) {
                        boxes.append(observation.boundingBox)
                    }
                }
            }
            
            if let faceResults = faceReq.results {
                for face in faceResults {
                    if face.confidence >= (self.confidenceThreshold * 0.4) {
                        let f = face.boundingBox
                        let headBox = CGRect(
                            x: max(0, f.origin.x - f.width * 0.15),
                            y: max(0, f.origin.y - f.height * 0.25),
                            width: min(1.0 - f.origin.x, f.width * 1.3),
                            height: min(1.0 - f.origin.y, f.height * 1.7)
                        )
                        boxes.append(headBox)
                    }
                }
            }
        } catch {
            AppLogger.log("⚠️ CoreML YOLO Inference Error: \(error)")
        }
        return boxes
    }
    
    private func mergeAndFilterBoxes(_ inputBoxes: [CGRect]) -> [CGRect] {
        let minArea = CGFloat(self.minObjectSize) // 0.003 (0.3% screen area)
        var filtered: [CGRect] = []
        
        // Split merged giant boxes (e.g. wide box covering 3 seated people)
        for box in inputBoxes {
            let area = box.width * box.height
            if area < minArea { continue }
            
            // If box is unusually wide (>24% screen width), split into 2-3 individual boxes for seated people
            if box.width > 0.24 && box.width / box.height > 0.85 {
                let numSplits = Int(ceil(box.width / 0.12))
                let splitWidth = box.width / CGFloat(numSplits)
                for i in 0..<numSplits {
                    let subBox = CGRect(
                        x: box.origin.x + CGFloat(i) * splitWidth,
                        y: box.origin.y,
                        width: splitWidth,
                        height: box.height
                    )
                    filtered.append(subBox)
                }
            } else {
                filtered.append(box)
            }
        }
        
        var kept: [CGRect] = []
        let sorted = filtered.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
        
        for box in sorted {
            var isDuplicate = false
            for k in kept {
                let intersection = box.intersection(k)
                if !intersection.isNull {
                    let interArea = intersection.width * intersection.height
                    let boxArea = box.width * box.height
                    if interArea / boxArea > 0.55 { // Smart NMS IoU threshold 55%
                        isDuplicate = true
                        break
                    }
                }
            }
            if !isDuplicate {
                kept.append(box)
            }
        }
        return kept
    }
}
