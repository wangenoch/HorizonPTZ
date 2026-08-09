import Foundation
import Vision
import AppKit

let imagePath = "/tmp/crowd_sample.png"
guard let nsImage = NSImage(contentsOfFile: imagePath),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Error loading image")
    exit(1)
}

let w = CGFloat(cgImage.width)
let h = CGFloat(cgImage.height)

print("=== PERFECT SINGLE SPEAKER FUSION & 30-PERSON CROWD COUNTING OPTIMIZER ===")
print("Screen size: \(w) x \(h)")

let cam1Rect = CGRect(x: w * 0.04, y: h * 0.15, width: w * 0.43, height: h * 0.80)
let cam2Rect = CGRect(x: w * 0.53, y: h * 0.15, width: w * 0.43, height: h * 0.80)

guard let cam1Cg = cgImage.cropping(to: cam1Rect),
      let cam2Cg = cgImage.cropping(to: cam2Rect) else {
    print("Error cropping viewports")
    exit(1)
}

struct RawDetection {
    var rect: CGRect
    var type: String
    var confidence: Float
}

func processViewport(cgImage: CGImage, cameraName: String) -> [CGRect] {
    print("\n--- Optimizing \(cameraName) ---")
    var rawList: [RawDetection] = []
    
    // 1. Pass 1: Global Pose Keypoints
    let poseReq = VNDetectHumanBodyPoseRequest()
    let h1 = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? h1.perform([poseReq])
    
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
                
                let b = CGRect(x: max(0, minX - 0.04),
                               y: max(0, minY - 0.06),
                               width: min(0.35, (maxX - minX) + 0.08),
                               height: min(0.65, (maxY - minY) + 0.12))
                rawList.append(RawDetection(rect: b, type: "pose", confidence: obs.confidence))
            }
        }
    }
    
    // 2. Pass 2: Global Face Request
    let faceReq = VNDetectFaceRectanglesRequest()
    let h2 = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? h2.perform([faceReq])
    
    for f in (faceReq.results ?? []) {
        if f.confidence >= 0.03 {
            let b = f.boundingBox
            let head = CGRect(x: max(0, b.origin.x - b.width*0.25),
                              y: max(0, b.origin.y - b.height*0.25),
                              width: min(0.20, b.width * 1.5),
                              height: min(0.25, b.height * 1.9))
            rawList.append(RawDetection(rect: head, type: "face", confidence: f.confidence))
        }
    }
    
    // 3. Pass 3: 4x4 Grid Seated Head Tiling (For 30 Audience Members)
    let cols = 4
    let rows = 4
    let tileW = cgImage.width / cols
    let tileH = cgImage.height / rows
    
    for r in 0..<rows {
        for c in 0..<cols {
            let tileRect = CGRect(x: c * tileW, y: r * tileH, width: tileW, height: tileH)
            guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
            
            let tFace = VNDetectFaceRectanglesRequest()
            let th = VNImageRequestHandler(cgImage: tileCg, options: [:])
            try? th.perform([tFace])
            
            for f in (tFace.results ?? []) {
                if f.confidence >= 0.015 {
                    let b = f.boundingBox
                    let normX = (CGFloat(c * tileW) + (b.origin.x - b.width*0.25) * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normY = (CGFloat(r * tileH) + (b.origin.y - b.height*0.25) * CGFloat(tileH)) / CGFloat(cgImage.height)
                    let normW = (b.width * 1.5 * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normH = (b.height * 1.9 * CGFloat(tileH)) / CGFloat(cgImage.height)
                    
                    let headBox = CGRect(x: normX, y: normY, width: min(0.18, normW), height: min(0.25, normH))
                    rawList.append(RawDetection(rect: headBox, type: "tileFace", confidence: f.confidence))
                }
            }
        }
    }
    
    print("Raw detections collected: \(rawList.count)")
    
    // === SINGLE SPEAKER ANATOMICAL FUSION ENGINE ===
    var fusedBoxes: [CGRect] = []
    let sortedByArea = rawList.map { $0.rect }.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
    
    for b in sortedByArea {
        var mergedIdx: Int? = nil
        for (idx, existing) in fusedBoxes.enumerated() {
            let centerDx = abs(b.midX - existing.midX)
            let centerDy = abs(b.midY - existing.midY)
            let maxW = max(b.width, existing.width)
            let maxH = max(b.height, existing.height)
            
            let isSamePersonColumn = (centerDx < maxW * 0.40 && centerDy < maxH * 0.85)
            let isOverlapping = !b.intersection(existing).isNull && (b.intersection(existing).width * b.intersection(existing).height / (b.width * b.height) > 0.25)
            
            if isSamePersonColumn || isOverlapping {
                mergedIdx = idx
                break
            }
        }
        
        if let idx = mergedIdx {
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
    
    let cleanBoxes = fusedBoxes.filter { b in
        return b.width <= 0.35 && b.height <= 0.70
    }
    
    print("After Anatomical Fusion & Wall Filter: \(cleanBoxes.count) clean human boxes!")
    return cleanBoxes
}

let res1 = processViewport(cgImage: cam1Cg, cameraName: "CAM 01 (Left)")
let res2 = processViewport(cgImage: cam2Cg, cameraName: "CAM 02 (Right)")

print("\n=== OPTIMIZER FINAL SUMMARY ===")
print("CAM 01 Final People Count: \(res1.count)")
print("CAM 02 Final People Count: \(res2.count)")
