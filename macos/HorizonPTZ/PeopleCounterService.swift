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
    private let maxDisappeared = 30
    private let minConfirmedFrames = 1
    
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
        return trackedPeople.filter { $0.confirmedFrames >= minConfirmedFrames }
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
    @Published var confidenceThreshold: Float = 0.05
    @Published var minObjectSize: Float = 0.001
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
            let finalBoxes = self.runPrecisionDetection(cgImage: cgImage)
            
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
        return runPrecisionDetection(cgImage: cgImage)
    }
    
    private func runCoreMLYoloInference(cgImage: CGImage) -> [CGRect] {
        return runPrecisionDetection(cgImage: cgImage)
    }
    
    private func runPrecisionDetection(cgImage: CGImage) -> [CGRect] {
        var rawBoxes: [CGRect] = []
        
        // 1. Pass 1: Human Body Pose Keypoint Request (For Presenter & Standing Bodies)
        let poseReq = VNDetectHumanBodyPoseRequest()
        let reqFace = VNDetectFaceRectanglesRequest()
        let h1 = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? h1.perform([poseReq, reqFace])
        
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
                        width: min(0.65, (maxX - minX) + padX * 2),
                        height: min(0.85, (maxY - minY) + padY * 2)
                    )
                    rawBoxes.append(b)
                }
            }
        }
        
        for f in (reqFace.results ?? []) {
            if f.confidence >= 0.03 {
                let b = f.boundingBox
                let head = CGRect(x: max(0, b.origin.x - b.width*0.20),
                                  y: max(0, b.origin.y - b.height*0.20),
                                  width: min(0.18, b.width * 1.4),
                                  height: min(0.24, b.height * 1.8))
                rawBoxes.append(head)
            }
        }
        
        // 2. Pass 2: 8x8 Seated Audience Micro Grid (Extracts all audience heads in dense crowd)
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
                
                // Lower rows (r >= 1) is audience seating area
                let isAudienceArea = (r >= 1)
                let tileThresh: Float = isAudienceArea ? 0.005 : 0.03
                
                let tFace = VNDetectFaceRectanglesRequest()
                let tHuman = VNDetectHumanRectanglesRequest()
                tHuman.upperBodyOnly = true
                
                let th = VNImageRequestHandler(cgImage: tileCg, options: [:])
                try? th.perform([tFace, tHuman])
                
                for f in (tFace.results ?? []) {
                    if f.confidence >= tileThresh {
                        let b = f.boundingBox
                        let normX = (CGFloat(c) * tileW + (b.origin.x - b.width * 0.15) * tileW) / fullW
                        let normY = 1.0 - ((CGFloat(r + 1) * tileH) - (b.origin.y - b.height * 0.15) * tileH) / fullH
                        let normW = (b.width * 1.3 * tileW) / fullW
                        let normH = (b.height * 1.6 * tileH) / fullH
                        
                        rawBoxes.append(CGRect(x: max(0, normX), y: max(0, normY), width: min(0.18, normW), height: min(0.25, normH)))
                    }
                }
                
                for h in (tHuman.results ?? []) {
                    if h.confidence >= tileThresh {
                        let b = h.boundingBox
                        let normX = (CGFloat(c) * tileW + b.origin.x * tileW) / fullW
                        let normY = 1.0 - ((CGFloat(r + 1) * tileH) - b.origin.y * tileH) / fullH
                        let normW = (b.width * tileW) / fullW
                        let normH = (b.height * tileH) / fullH
                        
                        rawBoxes.append(CGRect(x: max(0, normX), y: max(0, normY), width: min(0.22, normW), height: min(0.30, normH)))
                    }
                }
            }
        }
        
        // 3. Filter out invalid background noise (Ceiling, Door Frame, Tripod)
        let validBoxes = rawBoxes.filter { b in
            let area = b.width * b.height
            let isDoorFrame = (b.origin.x < 0.08 && b.origin.y > 0.40)
            let isCeiling = (b.origin.y + b.height >= 0.90)
            let isTripod = (b.midX > 0.44 && b.midX < 0.54 && b.midY > 0.20 && b.midY < 0.55 && b.width < 0.20)
            let isGiantCluster = (b.width > 0.55 || b.height > 0.90)
            
            return area >= 0.0004 && !isCeiling && !isDoorFrame && !isTripod && !isGiantCluster
        }
        
        // 4. Selective Vertical Column Fusion (Applies only to presenter/tall body candidates)
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
                
                // Only fuse columns if at least one box is a presenter/tall body (height > 0.35)
                let isPresenterCandidate = (maxH > 0.35 || maxW > 0.28)
                let isSamePersonColumn = isPresenterCandidate && (centerDx < maxW * 0.55 && centerDy < maxH * 0.85)
                let isOverlapping = !intersection.isNull && (intersection.width * intersection.height / min(b.width * b.height, existing.width * existing.height) > 0.45)
                
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
                
                if (newMaxX - newMinX) <= 0.65 {
                    fusedBoxes[idx] = CGRect(x: newMinX, y: newMinY, width: newMaxX - newMinX, height: newMaxY - newMinY)
                } else {
                    fusedBoxes.append(b)
                }
            } else {
                fusedBoxes.append(b)
            }
        }
        
        // 5. STRICT CONTAINMENT & SUB-BOX SUPPRESSION (Eliminates guitar soundhole box inside presenter body)
        let sortedFused = fusedBoxes.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
        var keptBoxes: [CGRect] = []
        
        for b in sortedFused {
            var isContained = false
            for k in keptBoxes {
                let intersection = b.intersection(k)
                if !intersection.isNull {
                    let interArea = intersection.width * intersection.height
                    let bArea = b.width * b.height
                    
                    let bCenterInsideK = k.contains(CGPoint(x: b.midX, y: b.midY)) && (b.width < k.width * 0.70 && b.height < k.height * 0.70)
                    let isOverlapContained = (interArea / bArea) > 0.50
                    
                    if bCenterInsideK || isOverlapContained {
                        isContained = true
                        break
                    }
                }
            }
            
            if !isContained {
                keptBoxes.append(b)
            }
        }
        
        return keptBoxes
    }
}
