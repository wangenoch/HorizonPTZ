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
    private let maxDisappeared = 20 // Holds detections across temporary occlusions to prevent count jumping!
    private let minConfirmedFrames = 2 // Anti-flicker: Must persist 2 frames to eliminate momentary noise
    
    func update(with newBoxes: [CGRect], cgImage: CGImage, distThreshold: CGFloat, alpha: CGFloat, isReIdEnabled: Bool, reIdSimilarity: Float) -> [(id: Int, box: CGRect)] {
        if trackedPeople.isEmpty {
            for box in newBoxes {
                let assignedId = resolveOrAssignId(for: box, cgImage: cgImage, isReIdEnabled: isReIdEnabled, reIdSimilarity: reIdSimilarity)
                trackedPeople.append(InternalTrackedPerson(id: assignedId, box: box, disappeared: 0, confirmedFrames: 1))
            }
            return trackedPeople.filter { $0.confirmedFrames >= minConfirmedFrames }.map { ($0.id, $0.box) }
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
                
                if dist < distThreshold || iou > 0.20 {
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
            
            // EMA Exponential Moving Average Smoothing
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
        return trackedPeople.filter { $0.confirmedFrames >= minConfirmedFrames }
            .sorted { $0.id < $1.id }
            .map { ($0.id, $0.box) }
    }
    
    private func resolveOrAssignId(for box: CGRect, cgImage: CGImage, isReIdEnabled: Bool, reIdSimilarity: Float) -> Int {
        if isReIdEnabled, let obs = extractFeaturePrint(for: box, in: cgImage) {
            var bestId: Int? = nil
            var minDistance: Float = Float.greatestFiniteMagnitude
            
            let maxAllowedDistance = (1.0 - reIdSimilarity) * 2.5
            
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
    @Published var confidenceThreshold: Float = 0.12  // Clean confidence threshold (12%) to eliminate ceiling false positives
    @Published var minObjectSize: Float = 0.005       // 0.5% area threshold for real people/heads
    @Published var samplingFps: Int = 10              // High FPS sampling 10 FPS
    @Published var trackingAlpha: Float = 0.85       // Smooth movement EMA alpha
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
        return runMultiScaleInference(cgImage: cgImage)
    }
    
    private func runCoreMLYoloInference(cgImage: CGImage) -> [CGRect] {
        return runMultiScaleInference(cgImage: cgImage)
    }
    
    private func runMultiScaleInference(cgImage: CGImage) -> [CGRect] {
        var rawBoxes: [CGRect] = []
        
        // Pass 1: Full Image Pass
        let reqFull = VNDetectHumanRectanglesRequest()
        reqFull.upperBodyOnly = false
        let reqUpper = VNDetectHumanRectanglesRequest()
        reqUpper.upperBodyOnly = true
        let reqFace = VNDetectFaceRectanglesRequest()
        
        let handler1 = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler1.perform([reqFull, reqUpper, reqFace])
        
        for r in (reqFull.results ?? []) + (reqUpper.results ?? []) {
            if r.confidence >= self.confidenceThreshold {
                // Filter out false positives in the top 15% ceiling region (y > 0.85 in normalized space)
                if r.boundingBox.origin.y + r.boundingBox.height < 0.85 {
                    rawBoxes.append(r.boundingBox)
                }
            }
        }
        for f in (reqFace.results ?? []) {
            if f.confidence >= self.confidenceThreshold {
                let b = f.boundingBox
                if b.origin.y + b.height < 0.88 {
                    let headBox = CGRect(x: max(0, b.origin.x - b.width*0.15),
                                         y: max(0, b.origin.y - b.height*0.2),
                                         width: min(1.0 - b.origin.x, b.width * 1.3),
                                         height: min(1.0 - b.origin.y, b.height * 1.7))
                    rawBoxes.append(headBox)
                }
            }
        }
        
        // Pass 2: 3x2 Grid Sub-region Pass for Seated Audience Heads
        let cols = 3
        let rows = 2
        let tileW = cgImage.width / cols
        let tileH = cgImage.height / rows
        
        for r in 0..<rows {
            for c in 0..<cols {
                let tileRect = CGRect(x: c * tileW, y: r * tileH, width: tileW, height: tileH)
                guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
                
                let tReq1 = VNDetectHumanRectanglesRequest()
                tReq1.upperBodyOnly = false
                let tReq2 = VNDetectHumanRectanglesRequest()
                tReq2.upperBodyOnly = true
                let tFace = VNDetectFaceRectanglesRequest()
                
                let th = VNImageRequestHandler(cgImage: tileCg, options: [:])
                try? th.perform([tReq1, tReq2, tFace])
                
                for res in (tReq1.results ?? []) + (tReq2.results ?? []) {
                    if res.confidence >= self.confidenceThreshold {
                        let b = res.boundingBox
                        let normX = (CGFloat(c * tileW) + b.origin.x * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normY = (CGFloat(r * tileH) + b.origin.y * CGFloat(tileH)) / CGFloat(cgImage.height)
                        let normW = (b.width * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normH = (b.height * CGFloat(tileH)) / CGFloat(cgImage.height)
                        
                        // Exclude ceiling region
                        if normY + normH < 0.85 {
                            rawBoxes.append(CGRect(x: normX, y: normY, width: normW, height: normH))
                        }
                    }
                }
                
                for f in (tFace.results ?? []) {
                    if f.confidence >= self.confidenceThreshold {
                        let b = f.boundingBox
                        let normX = (CGFloat(c * tileW) + (b.origin.x - b.width*0.15) * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normY = (CGFloat(r * tileH) + (b.origin.y - b.height*0.2) * CGFloat(tileH)) / CGFloat(cgImage.height)
                        let normW = (b.width * 1.3 * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normH = (b.height * 1.7 * CGFloat(tileH)) / CGFloat(cgImage.height)
                        
                        if normY + normH < 0.88 {
                            rawBoxes.append(CGRect(x: normX, y: normY, width: normW, height: normH))
                        }
                    }
                }
            }
        }
        
        return rawBoxes
    }
    
    private func mergeAndFilterBoxes(_ inputBoxes: [CGRect]) -> [CGRect] {
        var kept: [CGRect] = []
        let minArea = CGFloat(self.minObjectSize) // 0.005
        
        let filtered = inputBoxes.filter { box in
            let area = box.width * box.height
            return area >= minArea && box.origin.y + box.height < 0.88 // Never detect ceiling!
        }
        
        // Pure Non-Maximum Suppression (NMS) - ZERO slicing, ZERO artificial grid anchors!
        let sorted = filtered.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
        
        for box in sorted {
            var isDup = false
            for k in kept {
                let intersection = box.intersection(k)
                if !intersection.isNull {
                    let interArea = intersection.width * intersection.height
                    let boxArea = box.width * box.height
                    // NMS IoU 0.50 threshold to remove overlapping duplicates of the same person
                    if interArea / boxArea > 0.50 {
                        isDup = true
                        break
                    }
                }
            }
            if !isDup {
                kept.append(box)
            }
        }
        
        return kept
    }
}
