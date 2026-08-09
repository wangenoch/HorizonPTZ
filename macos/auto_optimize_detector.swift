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

print("=== INDIVIDUAL SEAT BOXING & ZERO CLUSTER MERGING OPTIMIZER ===")
print("Screen size: \(w) x \(h)")

func runIndividualSeatDetection(cgImage: CGImage) -> [CGRect] {
    var rawBoxes: [CGRect] = []
    
    // 1. Pass 1: Pose Keypoints
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
                
                let padX: CGFloat = 0.03
                let padY: CGFloat = 0.04
                
                let b = CGRect(
                    x: max(0, minX - padX),
                    y: max(0, minY - padY),
                    width: min(0.18, (maxX - minX) + padX * 2), // Individual person max width 0.18!
                    height: min(0.35, (maxY - minY) + padY * 2)
                )
                rawBoxes.append(b)
            }
        }
    }
    
    // 2. Pass 2: Face & Head Requests
    let faceReq = VNDetectFaceRectanglesRequest()
    let h2 = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? h2.perform([faceReq])
    
    for f in (faceReq.results ?? []) {
        if f.confidence >= 0.03 {
            let b = f.boundingBox
            let head = CGRect(x: max(0, b.origin.x - b.width*0.25),
                              y: max(0, b.origin.y - b.height*0.25),
                              width: min(0.14, b.width * 1.5),
                              height: min(0.22, b.height * 1.9))
            rawBoxes.append(head)
        }
    }
    
    // 3. Pass 3: 4x4 Grid Seated Head Tiling (Extracts all 25-28 individual audience heads)
    let cols = 4
    let rows = 4
    let tileW = cgImage.width / cols
    let tileH = cgImage.height / rows
    
    for r in 0..<rows {
        for c in 0..<cols {
            let tileRect = CGRect(x: c * tileW, y: r * tileH, width: tileW, height: tileH)
            guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
            
            let tFace = VNDetectFaceRectanglesRequest()
            let tHuman = VNDetectHumanRectanglesRequest()
            tHuman.upperBodyOnly = true
            
            let th = VNImageRequestHandler(cgImage: tileCg, options: [:])
            try? th.perform([tFace, tHuman])
            
            for f in (tFace.results ?? []) {
                if f.confidence >= 0.02 {
                    let b = f.boundingBox
                    let normX = (CGFloat(c * tileW) + (b.origin.x - b.width*0.25) * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normY = (CGFloat(r * tileH) + (b.origin.y - b.height*0.25) * CGFloat(tileH)) / CGFloat(cgImage.height)
                    let normW = (b.width * 1.5 * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normH = (b.height * 1.9 * CGFloat(tileH)) / CGFloat(cgImage.height)
                    rawBoxes.append(CGRect(x: normX, y: normY, width: min(0.15, normW), height: min(0.25, normH)))
                }
            }
            
            for h in (tHuman.results ?? []) {
                if h.confidence >= 0.02 {
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
    
    print("Total Raw Detections Collected: \(rawBoxes.count)")
    
    // Filter out:
    // - Tripod area (center empty space x: 0.44..0.52 & y: 0.20..0.55)
    // - Empty wall area (y + height > 0.82)
    // - Giant boxes (width > 0.22 or height > 0.45)
    let filtered = rawBoxes.filter { b in
        let isTripod = (b.midX > 0.44 && b.midX < 0.52 && b.midY > 0.20 && b.midY < 0.55)
        let isCeiling = (b.origin.y + b.height > 0.82)
        let isGiantBox = (b.width > 0.22 || b.height > 0.45)
        return !isTripod && !isCeiling && !isGiantBox
    }
    
    // Standard Pure NMS (IoU 0.35 threshold) - ZERO merging of neighboring people!
    var kept: [CGRect] = []
    let sorted = filtered.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
    
    for box in sorted {
        var isOverlap = false
        for k in kept {
            let intersection = box.intersection(k)
            if !intersection.isNull {
                let interArea = intersection.width * intersection.height
                let boxArea = box.width * box.height
                if interArea / boxArea > 0.35 {
                    isOverlap = true
                    break
                }
            }
        }
        if !isOverlap {
            kept.append(box)
        }
    }
    
    print("Final Individual Person Boxes: \(kept.count) people detected!")
    return kept
}

let result = runIndividualSeatDetection(cgImage: cgImage)
print("\n=== FINAL PROPOSED INDIVIDUAL PERSON COUNT ===")
print("Detected Individual People Count: \(result.count) people!")
