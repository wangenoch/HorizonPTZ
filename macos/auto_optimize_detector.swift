import Foundation
import Vision
import AppKit

let imagePath = "/tmp/crowd_sample.png"
guard let nsImage = NSImage(contentsOfFile: imagePath),
      let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Error: Could not load /tmp/crowd_sample.png")
    exit(1)
}

let w = CGFloat(cgImage.width)
let h = CGFloat(cgImage.height)

print("=== AUTOMATED DETECTOR OPTIMIZER ===")
print("Screen capture size: \(w) x \(h)")

let cam1Rect = CGRect(x: w * 0.04, y: h * 0.22, width: w * 0.43, height: h * 0.38)
let cam2Rect = CGRect(x: w * 0.53, y: h * 0.22, width: w * 0.43, height: h * 0.38)

guard let cam1Cg = cgImage.cropping(to: cam1Rect),
      let cam2Cg = cgImage.cropping(to: cam2Rect) else {
    print("Error cropping viewports")
    exit(1)
}

struct BBox {
    var rect: CGRect
    var confidence: Float
    var label: String
}

func optimizeDetection(cgImage: CGImage, cameraName: String) -> [CGRect] {
    print("\n--- Optimizing \(cameraName) ---")
    var rawBoxes: [BBox] = []
    
    // Pass 1: Full Image Pass (Stage & Standing Presenter Pass, confidence = 0.08)
    let reqFull = VNDetectHumanRectanglesRequest()
    reqFull.upperBodyOnly = false
    let reqUpper = VNDetectHumanRectanglesRequest()
    reqUpper.upperBodyOnly = true
    let reqFace = VNDetectFaceRectanglesRequest()
    
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([reqFull, reqUpper, reqFace])
    
    for r in (reqFull.results ?? []) {
        if r.confidence >= 0.08 {
            rawBoxes.append(BBox(rect: r.boundingBox, confidence: r.confidence, label: "FullBody"))
        }
    }
    for r in (reqUpper.results ?? []) {
        if r.confidence >= 0.08 {
            rawBoxes.append(BBox(rect: r.boundingBox, confidence: r.confidence, label: "UpperBody"))
        }
    }
    for f in (reqFace.results ?? []) {
        if f.confidence >= 0.08 {
            let b = f.boundingBox
            let headBox = CGRect(x: max(0, b.origin.x - b.width*0.2),
                                 y: max(0, b.origin.y - b.height*0.2),
                                 width: min(1.0 - b.origin.x, b.width * 1.4),
                                 height: min(1.0 - b.origin.y, b.height * 1.8))
            rawBoxes.append(BBox(rect: headBox, confidence: f.confidence, label: "FaceHead"))
        }
    }
    
    // Pass 2: Adaptive Regional Confidence Grid Tiling (3x3 Tiles)
    let cols = 3
    let rows = 3
    let tileW = cgImage.width / cols
    let tileH = cgImage.height / rows
    
    for r in 0..<rows {
        for c in 0..<cols {
            let tileRect = CGRect(x: c * tileW, y: r * tileH, width: tileW, height: tileH)
            guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
            
            // In audience seating area (bottom 2 rows in Vision y-up space), use high sensitivity (0.015)
            // In upper stage/wall area, use conservative threshold (0.08) to prevent wall noise
            let isAudienceArea = (r <= 1)
            let tileThresh: Float = isAudienceArea ? 0.015 : 0.08
            
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
                    rawBoxes.append(BBox(rect: CGRect(x: normX, y: normY, width: normW, height: normH), confidence: res.confidence, label: "TileFull"))
                }
            }
            
            for res in (tUpper.results ?? []) {
                if res.confidence >= tileThresh {
                    let b = res.boundingBox
                    let normX = (CGFloat(c * tileW) + b.origin.x * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normY = (CGFloat(r * tileH) + b.origin.y * CGFloat(tileH)) / CGFloat(cgImage.height)
                    let normW = (b.width * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normH = (b.height * CGFloat(tileH)) / CGFloat(cgImage.height)
                    rawBoxes.append(BBox(rect: CGRect(x: normX, y: normY, width: normW, height: normH), confidence: res.confidence, label: "TileUpper"))
                }
            }
            
            for f in (tFace.results ?? []) {
                if f.confidence >= tileThresh {
                    let b = f.boundingBox
                    let normX = (CGFloat(c * tileW) + (b.origin.x - b.width*0.2) * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normY = (CGFloat(r * tileH) + (b.origin.y - b.height*0.2) * CGFloat(tileH)) / CGFloat(cgImage.height)
                    let normW = (b.width * 1.4 * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normH = (b.height * 1.8 * CGFloat(tileH)) / CGFloat(cgImage.height)
                    rawBoxes.append(BBox(rect: CGRect(x: normX, y: normY, width: normW, height: normH), confidence: f.confidence, label: "TileFace"))
                }
            }
        }
    }
    
    print("Raw detections collected: \(rawBoxes.count)")
    
    // Filter out ceiling wall noise (y > 0.82)
    let validBoxes = rawBoxes.filter { b in
        let r = b.rect
        return r.origin.y + r.height < 0.82 && r.width * r.height >= 0.002
    }
    
    // === VERTICAL CONTAINMENT & OVERLAP MERGING (Zero Body Slicing!) ===
    var mergedBoxes: [BBox] = []
    let sortedByArea = validBoxes.sorted { ($0.rect.width * $0.rect.height) > ($1.rect.width * $1.rect.height) }
    
    for b in sortedByArea {
        var isContainedInLarger = false
        for m in mergedBoxes {
            let intersection = b.rect.intersection(m.rect)
            if !intersection.isNull {
                let interArea = intersection.width * intersection.height
                let bArea = b.rect.width * b.rect.height
                let verticalOverlap = intersection.height / b.rect.height
                let horizontalOverlap = intersection.width / b.rect.width
                
                // If smaller box is >40% covered by larger box OR >50% vertically overlapping in same column
                if (interArea / bArea > 0.35) || (verticalOverlap > 0.50 && horizontalOverlap > 0.50) {
                    isContainedInLarger = true
                    break
                }
            }
        }
        if !isContainedInLarger {
            mergedBoxes.append(b)
        }
    }
    
    print("After Vertical Containment Merging: \(mergedBoxes.count) clean single-person boxes!")
    
    return mergedBoxes.map { $0.rect }
}

let res1 = optimizeDetection(cgImage: cam1Cg, cameraName: "CAM 01 (Left)")
let res2 = optimizeDetection(cgImage: cam2Cg, cameraName: "CAM 02 (Right)")

print("\n=== OPTIMIZER SUMMARY RESULTS ===")
print("CAM 01 Final People Count: \(res1.count)")
print("CAM 02 Final People Count: \(res2.count)")
