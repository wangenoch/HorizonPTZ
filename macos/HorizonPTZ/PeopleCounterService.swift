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
    private let maxDisappeared = 25 // Holds detections across temporary head movements to keep count steady!
    private let minConfirmedFrames = 2 // Anti-flicker: Must persist 2 frames to eliminate noise
    
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
            
            // Exponential Moving Average (EMA) position smoothing
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
    @Published var confidenceThreshold: Float = 0.08
    @Published var minObjectSize: Float = 0.003
    @Published var samplingFps: Int = 10
    @Published var trackingAlpha: Float = 0.85
    @Published var maxMotionDistance: Float = 0.38
    
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
        return runMultiTileInference(cgImage: cgImage)
    }
    
    private func runCoreMLYoloInference(cgImage: CGImage) -> [CGRect] {
        return runMultiTileInference(cgImage: cgImage)
    }
    
    private func runMultiTileInference(cgImage: CGImage) -> [CGRect] {
        var rawBoxes: [CGRect] = []
        
        // Pass 1: Full Image Pass (Stage & Speaker Pass)
        let reqFull = VNDetectHumanRectanglesRequest()
        reqFull.upperBodyOnly = false
        let reqUpper = VNDetectHumanRectanglesRequest()
        reqUpper.upperBodyOnly = true
        let reqFace = VNDetectFaceRectanglesRequest()
        
        let h1 = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? h1.perform([reqFull, reqUpper, reqFace])
        
        for r in (reqFull.results ?? []) {
            if r.confidence >= self.confidenceThreshold { rawBoxes.append(r.boundingBox) }
        }
        for r in (reqUpper.results ?? []) {
            if r.confidence >= self.confidenceThreshold { rawBoxes.append(r.boundingBox) }
        }
        for f in (reqFace.results ?? []) {
            if f.confidence >= self.confidenceThreshold {
                let b = f.boundingBox
                let headBox = CGRect(x: max(0, b.origin.x - b.width*0.2),
                                     y: max(0, b.origin.y - b.height*0.2),
                                     width: min(1.0 - b.origin.x, b.width * 1.4),
                                     height: min(1.0 - b.origin.y, b.height * 1.8))
                rawBoxes.append(headBox)
            }
        }
        
        // Pass 2: 3x3 Grid Tiles (Zoomed-in Multi-scale Tiling for Seated Audience)
        let cols = 3
        let rows = 3
        let tileW = cgImage.width / cols
        let tileH = cgImage.height / rows
        
        for r in 0..<rows {
            for c in 0..<cols {
                let tileRect = CGRect(x: c * tileW, y: r * tileH, width: tileW, height: tileH)
                guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
                
                // In seating area (bottom 2 rows in Vision y-up space r <= 1), use higher sensitivity (0.015)
                let isSeatingArea = (r <= 1)
                let tileThresh: Float = isSeatingArea ? 0.015 : self.confidenceThreshold
                
                let tFull = VNDetectHumanRectanglesRequest()
                tFull.upperBodyOnly = false
                let tUpper = VNDetectHumanRectanglesRequest()
                tUpper.upperBodyOnly = true
                let tFace = VNDetectFaceRectanglesRequest()
                
                let th = VNImageRequestHandler(cgImage: tileCg, options: [:])
                try? th.perform([tFull, tUpper, tFace])
                
                for res in (tFull.results ?? []) {
                    if res.confidence >= tileThresh {
                        let b = res.boundingBox
                        let normX = (CGFloat(c * tileW) + b.origin.x * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normY = (CGFloat(r * tileH) + b.origin.y * CGFloat(tileH)) / CGFloat(cgImage.height)
                        let normW = (b.width * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normH = (b.height * CGFloat(tileH)) / CGFloat(cgImage.height)
                        rawBoxes.append(CGRect(x: normX, y: normY, width: normW, height: normH))
                    }
                }
                
                for res in (tUpper.results ?? []) {
                    if res.confidence >= tileThresh {
                        let b = res.boundingBox
                        let normX = (CGFloat(c * tileW) + b.origin.x * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normY = (CGFloat(r * tileH) + b.origin.y * CGFloat(tileH)) / CGFloat(cgImage.height)
                        let normW = (b.width * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normH = (b.height * CGFloat(tileH)) / CGFloat(cgImage.height)
                        rawBoxes.append(CGRect(x: normX, y: normY, width: normW, height: normH))
                    }
                }
                
                for f in (tFace.results ?? []) {
                    if f.confidence >= tileThresh {
                        let b = f.boundingBox
                        let normX = (CGFloat(c * tileW) + (b.origin.x - b.width*0.2) * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normY = (CGFloat(r * tileH) + (b.origin.y - b.height*0.2) * CGFloat(tileH)) / CGFloat(cgImage.height)
                        let normW = (b.width * 1.4 * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normH = (b.height * 1.8 * CGFloat(tileH)) / CGFloat(cgImage.height)
                        rawBoxes.append(CGRect(x: normX, y: normY, width: normW, height: normH))
                    }
                }
            }
        }
        
        return rawBoxes
    }
    
    private func mergeAndFilterBoxes(_ inputBoxes: [CGRect]) -> [CGRect] {
        let minArea = CGFloat(self.minObjectSize) // 0.003
        
        // Rule A: Exclude top ceiling wall area (y + height >= 0.82 in Vision y-up space)
        let validBoxes = inputBoxes.filter { b in
            let area = b.width * b.height
            return area >= minArea && b.origin.y + b.height < 0.82
        }
        
        // Rule B: Vertical Containment NMS (Absorbs Upper Body & Lower Body into Full Body!)
        // Prevents a single person from being sliced into upper/lower body boxes!
        var mergedBoxes: [CGRect] = []
        let sortedByArea = validBoxes.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
        
        for b in sortedByArea {
            var isSubBoxOfLarger = false
            for m in mergedBoxes {
                let intersection = b.intersection(m)
                if !intersection.isNull {
                    let interArea = intersection.width * intersection.height
                    let bArea = b.width * b.height
                    let verticalOverlap = intersection.height / b.height
                    let horizontalOverlap = intersection.width / b.width
                    
                    // If smaller box is >35% contained in larger box OR >50% vertically overlapping within same body column
                    if (interArea / bArea > 0.35) || (verticalOverlap > 0.50 && horizontalOverlap > 0.50) {
                        isSubBoxOfLarger = true
                        break
                    }
                }
            }
            if !isSubBoxOfLarger {
                mergedBoxes.append(b)
            }
        }
        
        return mergedBoxes
    }
}
