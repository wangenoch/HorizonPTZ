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
    private let maxDisappeared = 30 // Holds tracked IDs across temporary movements to keep count steady!
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
    @Published var confidenceThreshold: Float = 0.05
    @Published var minObjectSize: Float = 0.002
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
        return runMultiScaleInference(cgImage: cgImage)
    }
    
    private func runCoreMLYoloInference(cgImage: CGImage) -> [CGRect] {
        return runMultiScaleInference(cgImage: cgImage)
    }
    
    private func runMultiScaleInference(cgImage: CGImage) -> [CGRect] {
        var rawBoxes: [CGRect] = []
        
        // Pass 1: Anatomical Body Pose Request
        let poseReq = VNDetectHumanBodyPoseRequest()
        let reqFull = VNDetectHumanRectanglesRequest()
        reqFull.upperBodyOnly = false
        let reqUpper = VNDetectHumanRectanglesRequest()
        reqUpper.upperBodyOnly = true
        let reqFace = VNDetectFaceRectanglesRequest()
        
        let h1 = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? h1.perform([poseReq, reqFull, reqUpper, reqFace])
        
        for obs in (poseReq.results ?? []) {
            if let points = try? obs.recognizedPoints(forGroupKey: .all) {
                let validPoints = points.values.filter { $0.confidence > 0.15 }
                if validPoints.count >= 2 {
                    let xs = validPoints.map { CGFloat($0.location.x) }
                    let ys = validPoints.map { CGFloat($0.location.y) }
                    
                    let minX = xs.min()!
                    let maxX = xs.max()!
                    let minY = ys.min()!
                    let maxY = ys.max()!
                    
                    let padX: CGFloat = 0.04
                    let padY: CGFloat = 0.06
                    
                    let b = CGRect(
                        x: max(0, minX - padX),
                        y: max(0, minY - padY),
                        width: min(0.35, (maxX - minX) + padX * 2),
                        height: min(0.65, (maxY - minY) + padY * 2)
                    )
                    rawBoxes.append(b)
                }
            }
        }
        
        for r in (reqFull.results ?? []) + (reqUpper.results ?? []) {
            if r.confidence >= self.confidenceThreshold {
                rawBoxes.append(r.boundingBox)
            }
        }
        
        for f in (reqFace.results ?? []) {
            if f.confidence >= self.confidenceThreshold {
                let b = f.boundingBox
                let headBox = CGRect(x: max(0, b.origin.x - b.width*0.25),
                                     y: max(0, b.origin.y - b.height*0.25),
                                     width: min(0.20, b.width * 1.5),
                                     height: min(0.25, b.height * 1.9))
                rawBoxes.append(headBox)
            }
        }
        
        // Pass 2: 4x4 Multi-scale Grid Tiling (Extremely Sensitive for Seated Audience Crowd)
        let cols = 4
        let rows = 4
        let tileW = cgImage.width / cols
        let tileH = cgImage.height / rows
        
        for r in 0..<rows {
            for c in 0..<cols {
                let tileRect = CGRect(x: c * tileW, y: r * tileH, width: tileW, height: tileH)
                guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
                
                // Audience seating area is bottom 3 rows (r <= 2 in Vision y-up space)
                let isAudienceArea = (r <= 2)
                let tileThresh: Float = isAudienceArea ? 0.012 : self.confidenceThreshold
                
                let tFace = VNDetectFaceRectanglesRequest()
                let tFull = VNDetectHumanRectanglesRequest()
                tFull.upperBodyOnly = true
                
                let th = VNImageRequestHandler(cgImage: tileCg, options: [:])
                try? th.perform([tFace, tFull])
                
                for f in (tFace.results ?? []) {
                    if f.confidence >= tileThresh {
                        let b = f.boundingBox
                        let normX = (CGFloat(c * tileW) + (b.origin.x - b.width*0.25) * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normY = (CGFloat(r * tileH) + (b.origin.y - b.height*0.25) * CGFloat(tileH)) / CGFloat(cgImage.height)
                        let normW = (b.width * 1.5 * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normH = (b.height * 1.9 * CGFloat(tileH)) / CGFloat(cgImage.height)
                        rawBoxes.append(CGRect(x: normX, y: normY, width: min(0.18, normW), height: min(0.25, normH)))
                    }
                }
                
                for h in (tFull.results ?? []) {
                    if h.confidence >= tileThresh {
                        let b = h.boundingBox
                        let normX = (CGFloat(c * tileW) + b.origin.x * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normY = (CGFloat(r * tileH) + b.origin.y * CGFloat(tileH)) / CGFloat(cgImage.height)
                        let normW = (b.width * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normH = (b.height * CGFloat(tileH)) / CGFloat(cgImage.height)
                        rawBoxes.append(CGRect(x: normX, y: normY, width: min(0.18, normW), height: min(0.35, normH)))
                    }
                }
            }
        }
        
        return rawBoxes
    }
    
    private func mergeAndFilterBoxes(_ inputBoxes: [CGRect]) -> [CGRect] {
        let minArea = CGFloat(self.minObjectSize) // 0.003
        
        // Rule A: Exclude top ceiling wall area (y + height >= 0.82)
        // Rule B: Exclude door frame on left wall (x < 0.08 & y > 0.40)
        // Rule C: Exclude tripod in center space (midX between 0.44..0.54 & midY between 0.20..0.55)
        let validBoxes = inputBoxes.filter { b in
            let area = b.width * b.height
            let aspectRatio = b.width / b.height
            let isDoorFrame = (b.origin.x < 0.08 && b.origin.y > 0.40)
            let isCeiling = (b.origin.y + b.height >= 0.82)
            let isTripod = (b.midX > 0.44 && b.midX < 0.54 && b.midY > 0.20 && b.midY < 0.55)
            
            return area >= minArea && !isCeiling && !isDoorFrame && !isTripod && aspectRatio >= 0.15 && aspectRatio <= 2.2
        }
        
        // Rule D: Single Speaker Anatomical Column Fusion
        // Fuses face (#4), chest (#2), head (#3) of the SAME speaker into 1 SINGLE ENCLOSING BOX!
        var fusedBoxes: [CGRect] = []
        let sortedByArea = validBoxes.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
        
        for b in sortedByArea {
            var absorbedIdx: Int? = nil
            for (idx, existing) in fusedBoxes.enumerated() {
                let intersection = b.intersection(existing)
                let centerDx = abs(b.midX - existing.midX)
                let centerDy = abs(b.midY - existing.midY)
                let maxW = max(b.width, existing.width)
                let maxH = max(b.height, existing.height)
                
                let isSamePersonColumn = (centerDx < maxW * 0.40 && centerDy < maxH * 0.85)
                let isOverlapping = !intersection.isNull && (intersection.width * intersection.height / (b.width * b.height) > 0.25)
                
                if isSamePersonColumn || isOverlapping {
                    absorbedIdx = idx
                    break
                }
            }
            
            if let idx = absorbedIdx {
                let e = fusedBoxes[idx]
                let newMinX = min(e.minX, b.minX)
                let newMinY = min(e.minY, b.minY)
                let newMaxX = max(e.maxX, b.maxX)
                let newMaxY = max(e.maxY, b.maxY)
                fusedBoxes[idx] = CGRect(x: newMinX, y: newMinY, width: newMaxX - newMinX, height: newMaxY - newMinY)
            } else {
                fusedBoxes.append(b)
            }
        }
        
        // Rule E: Reject empty wall boxes (y + height > 0.85 or width > 0.38)
        let cleanBoxes = fusedBoxes.filter { b in
            return b.width <= 0.38 && b.height <= 0.70
        }
        
        return cleanBoxes
    }
}
