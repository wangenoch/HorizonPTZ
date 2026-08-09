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

print("=== INDUSTRY BEST-PRACTICE DENSE CROWD & SINGLE SPEAKER OPTIMIZER ===")
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

func runIndustryOptimizedDetection(cgImage: CGImage, cameraName: String) -> [CGRect] {
    print("\n--- Processing \(cameraName) ---")
    var rawBoxes: [BBox] = []
    
    // 1. Pass 1: Global Full Body & Upper Body Pass
    let reqFull = VNDetectHumanRectanglesRequest()
    reqFull.upperBodyOnly = false
    let reqUpper = VNDetectHumanRectanglesRequest()
    reqUpper.upperBodyOnly = true
    let reqFace = VNDetectFaceRectanglesRequest()
    
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler.perform([reqFull, reqUpper, reqFace])
    
    for r in (reqFull.results ?? []) {
        if r.confidence >= 0.03 {
            rawBoxes.append(BBox(rect: r.boundingBox, confidence: r.confidence, label: "FullBody"))
        }
    }
    for r in (reqUpper.results ?? []) {
        if r.confidence >= 0.03 {
            rawBoxes.append(BBox(rect: r.boundingBox, confidence: r.confidence, label: "UpperBody"))
        }
    }
    for f in (reqFace.results ?? []) {
        if f.confidence >= 0.03 {
            let b = f.boundingBox
            let headBox = CGRect(x: max(0, b.origin.x - b.width*0.3),
                                 y: max(0, b.origin.y - b.height*0.3),
                                 width: min(1.0 - b.origin.x, b.width * 1.6),
                                 height: min(1.0 - b.origin.y, b.height * 2.0))
            rawBoxes.append(BBox(rect: headBox, confidence: f.confidence, label: "FaceHead"))
        }
    }
    
    // 2. Pass 2: 4x3 Multi-scale Dense Grid Tiling (Extremely High Sensitivity for Audience Seating)
    let cols = 4
    let rows = 3
    let tileW = cgImage.width / cols
    let tileH = cgImage.height / rows
    
    for r in 0..<rows {
        for c in 0..<cols {
            let tileRect = CGRect(x: c * tileW, y: r * tileH, width: tileW, height: tileH)
            guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
            
            // Audience seating is bottom 2 rows (r <= 1) in Vision y-up coordinates
            let isAudienceArea = (r <= 1)
            let tileThresh: Float = isAudienceArea ? 0.01 : 0.06
            
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
                    let normX = (CGFloat(c * tileW) + (b.origin.x - b.width*0.3) * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normY = (CGFloat(r * tileH) + (b.origin.y - b.height*0.3) * CGFloat(tileH)) / CGFloat(cgImage.height)
                    let normW = (b.width * 1.6 * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normH = (b.height * 2.0 * CGFloat(tileH)) / CGFloat(cgImage.height)
                    rawBoxes.append(BBox(rect: CGRect(x: normX, y: normY, width: normW, height: normH), confidence: f.confidence, label: "TileFace"))
                }
            }
        }
    }
    
    print("Raw detections collected: \(rawBoxes.count)")
    
    // Filter ceiling noise (y > 0.82)
    let validBoxes = rawBoxes.filter { b in
        let r = b.rect
        return r.origin.y + r.height < 0.82 && r.width * r.height >= 0.0015
    }
    
    // 3. Dominant Vertical Human Column Fusion (Fixes 1 person sliced into 2-3 parts!)
    // If Box A and Box B belong to the exact same vertical column (centerX distance < 35% of width)
    // AND they overlap vertically, MERGE THEM INTO A SINGLE ENCLOSING BODY BOX!
    var finalBoxes: [CGRect] = []
    let sortedByArea = validBoxes.sorted { ($0.rect.width * $0.rect.height) > ($1.rect.width * $1.rect.height) }
    
    for b in sortedByArea {
        var mergedIdx: Int? = nil
        for (idx, existing) in finalBoxes.enumerated() {
            let intersection = b.rect.intersection(existing)
            if !intersection.isNull {
                let centerDx = abs(b.rect.midX - existing.midX)
                let maxW = max(b.rect.width, existing.width)
                let vertOverlap = intersection.height / min(b.rect.height, existing.height)
                
                // Same vertical human column test (center distance < 0.45 maxW & vertOverlap > 0.35)
                if centerDx < maxW * 0.45 && vertOverlap > 0.35 {
                    mergedIdx = idx
                    break
                }
            }
        }
        
        if let idx = mergedIdx {
            // Expand existing box to enclose both upper and lower body parts!
            let e = finalBoxes[idx]
            let u = b.rect
            let newMinX = min(e.minX, u.minX)
            let newMinY = min(e.minY, u.minY)
            let newMaxX = max(e.maxX, u.maxX)
            let newMaxY = max(e.maxY, u.maxY)
            finalBoxes[idx] = CGRect(x: newMinX, y: newMinY, width: newMaxX - newMinX, height: newMaxY - newMinY)
        } else {
            finalBoxes.append(b.rect)
        }
    }
    
    print("After Dominant Column Fusion: \(finalBoxes.count) clean human boxes!")
    return finalBoxes
}

let res1 = runIndustryOptimizedDetection(cgImage: cam1Cg, cameraName: "CAM 01 (Left)")
let res2 = runIndustryOptimizedDetection(cgImage: cam2Cg, cameraName: "CAM 02 (Right)")

print("\n=== FINAL TEST RESULTS ===")
print("CAM 01 Final People Count: \(res1.count)")
print("CAM 02 Final People Count: \(res2.count)")
