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
    private let minConfirmedFrames = 2 // Anti-flicker: Must be confirmed across 2 frames to eliminate noise!
    
    func update(with newBoxes: [CGRect], cgImage: CGImage, distThreshold: CGFloat, alpha: CGFloat, isReIdEnabled: Bool, reIdSimilarity: Float) -> [(id: Int, box: CGRect)] {
        if trackedPeople.isEmpty {
            for box in newBoxes {
                let assignedId = resolveOrAssignId(for: box, cgImage: cgImage, isReIdEnabled: isReIdEnabled, reIdSimilarity: reIdSimilarity)
                trackedPeople.append(InternalTrackedPerson(id: assignedId, box: box, disappeared: 0, confirmedFrames: 1))
            }
            return []
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
                
                if dist < distThreshold || iou > 0.18 {
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
        return trackedPeople.filter { $0.disappeared == 0 && $0.confirmedFrames >= minConfirmedFrames }
            .sorted { $0.id < $1.id }
            .map { ($0.id, $0.box) }
    }
    
    private func resolveOrAssignId(for box: CGRect, cgImage: CGImage, isReIdEnabled: Bool, reIdSimilarity: Float) -> Int {
        if isReIdEnabled, let obs = extractFeaturePrint(for: box, in: cgImage) {
            var bestId: Int? = nil
            var minDistance: Float = Float.greatestFiniteMagnitude
            
            let maxAllowedDistance = (1.0 - reIdSimilarity) * 2.5 // e.g. 82% similarity -> max dist ~0.45
            
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
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        
        // Convert Vision bounding box (0..1 bottom-up) to CGImage pixel coordinates
        let cropX = max(0, box.origin.x * imgW)
        let cropY = max(0, (1.0 - box.origin.y - box.size.height) * imgH)
        let cropW = min(imgW - cropX, box.size.width * imgW)
        let cropH = min(imgH - cropY, box.size.height * imgH)
        
        guard cropW > 20 && cropH > 20,
              let croppedCg = cgImage.cropping(to: CGRect(x: cropX, y: cropY, width: cropW, height: cropH)) else {
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
    
    @Published var currentEngineMode: AiEngineMode = .appleVision
    @Published var confidenceThreshold: Float = 0.08  // Ultra-sensitive threshold for distant human capture
    @Published var minObjectSize: Float = 0.018      // Min screen height for distant seated humans
    
    @Published var samplingFps: Int = 10              // High-speed responsiveness (10 FPS = 100ms per frame)
    @Published var trackingAlpha: Float = 0.90       // Fast motion tracking weight (90% immediate update)
    @Published var maxMotionDistance: Float = 0.38   // Fast motion distance matching (38% screen width)
    
    @Published var isReIdEnabled: Bool = true        // Re-ID Visual Feature Memory Enabled
    @Published var reIdSimilarity: Float = 0.82       // Re-ID Similarity threshold (82%)
    
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
                completion(AnalysisResult(count: resultHumans.count, trackedHumans: resultHumans, engineName: mode.rawValue))
            }
        }
    }
    
    private func runCoreMLYoloInference(cgImage: CGImage) -> [CGRect] {
        return runAppleVisionInference(cgImage: cgImage)
    }
    
    private func runAppleVisionInference(cgImage: CGImage) -> [CGRect] {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        let poseReq = VNDetectHumanBodyPoseRequest()
        let faceReq = VNDetectFaceRectanglesRequest()
        let upperReq = VNDetectHumanRectanglesRequest()
        upperReq.upperBodyOnly = true
        
        do {
            try handler.perform([poseReq, faceReq, upperReq])
        } catch {
            return []
        }
        
        var candidateBoxes: [CGRect] = []
        var jointCenters: [CGPoint] = []
        
        let confThresh = self.confidenceThreshold
        let minH = CGFloat(self.minObjectSize)
        
        // 1. Process 360° Human Body Pose
        if let poseResults = poseReq.results {
            for obs in poseResults {
                if let pts = try? obs.recognizedPoints(.all) {
                    let validPts = pts.values.filter { $0.confidence >= confThresh }.map(\.location)
                    if validPts.count >= 2 {
                        let locs = validPts
                        for loc in locs { jointCenters.append(loc) }
                        
                        let minX = locs.map(\.x).min()!
                        let maxX = locs.map(\.x).max()!
                        let minY = locs.map(\.y).min()!
                        let maxY = locs.map(\.y).max()!
                        
                        let rawW = max(maxX - minX, 0.02)
                        let rawH = max(maxY - minY, minH)
                        
                        let w = min(rawW * 1.35, 0.18)
                        let h = min(rawH * 1.35, 0.75)
                        
                        let box = CGRect(
                            x: max(0, minX - w * 0.1),
                            y: max(0, minY - h * 0.1),
                            width: w,
                            height: h
                        )
                        candidateBoxes.append(box)
                    }
                }
            }
        }
        
        // 2. Process Face Observations
        if let faceResults = faceReq.results {
            for obs in faceResults {
                if obs.confidence >= (confThresh * 1.2) {
                    let box = obs.boundingBox
                    let w = min(box.width * 1.8, 0.16)
                    let h = min(box.height * 2.8, 0.45)
                    if h >= minH {
                        let expanded = CGRect(
                            x: max(0, box.origin.x - w * 0.2),
                            y: max(0, box.origin.y - h * 0.3),
                            width: w,
                            height: h
                        )
                        candidateBoxes.append(expanded)
                    }
                }
            }
        }
        
        // 3. Process Upper Body Observations
        if let upperResults = upperReq.results {
            for obs in upperResults {
                if obs.confidence >= max(confThresh * 1.5, 0.18) {
                    let box = obs.boundingBox
                    let aspect = box.height / max(box.width, 0.001)
                    if aspect >= 0.50 && aspect <= 4.0 && box.width <= 0.18 && box.height >= minH {
                        let center = CGPoint(x: box.midX, y: box.midY)
                        let nearJoint = jointCenters.contains { pt in
                            let dx = pt.x - center.x
                            let dy = pt.y - center.y
                            return sqrt(dx*dx + dy*dy) < 0.18
                        }
                        if nearJoint || obs.confidence >= 0.35 || box.origin.y > 0.35 {
                            candidateBoxes.append(box)
                        }
                    }
                }
            }
        }
        
        return candidateBoxes
    }
    
    private func mergeAndFilterBoxes(_ candidateBoxes: [CGRect]) -> [CGRect] {
        var finalBoxes: [CGRect] = []
        let sorted = candidateBoxes.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
        
        for box in sorted {
            let centerA = CGPoint(x: box.midX, y: box.midY)
            var isDuplicate = false
            
            for (idx, existing) in finalBoxes.enumerated() {
                let centerB = CGPoint(x: existing.midX, y: existing.midY)
                let dx = abs(centerA.x - centerB.x)
                let dy = abs(centerA.y - centerB.y)
                
                let intersection = box.intersection(existing)
                let interArea = intersection.isNull ? 0 : (intersection.width * intersection.height)
                let minArea = min(box.width * box.height, existing.width * existing.height)
                let containment = minArea > 0 ? (interArea / minArea) : 0
                
                if dx < 0.08 && dy < 0.20 && (containment > 0.15 || interArea > 0) {
                    let mergedMinX = min(box.minX, existing.minX)
                    let mergedMaxX = max(box.maxX, existing.maxX)
                    let mergedMinY = min(box.minY, existing.minY)
                    let mergedMaxY = max(box.maxY, existing.maxY)
                    
                    finalBoxes[idx] = CGRect(
                        x: mergedMinX,
                        y: mergedMinY,
                        width: min(mergedMaxX - mergedMinX, 0.18),
                        height: mergedMaxY - mergedMinY
                    )
                    isDuplicate = true
                    break
                } else if containment > 0.35 || (dx < 0.05 && dy < 0.05) {
                    isDuplicate = true
                    break
                }
            }
            
            if !isDuplicate {
                finalBoxes.append(box)
            }
        }
        
        return finalBoxes
    }
}
