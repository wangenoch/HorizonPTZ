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

print("=== DEEP NEURAL BODY ABSORPTION & CROWD DETECTOR OPTIMIZER ===")
print("Screen size: \(w) x \(h)")

// Crop CAM 01 (Left) and CAM 02 (Right) viewports in CGImage top-left coordinates
let cam1Rect = CGRect(x: w * 0.04, y: h * 0.20, width: w * 0.43, height: h * 0.45)
let cam2Rect = CGRect(x: w * 0.53, y: h * 0.20, width: w * 0.43, height: h * 0.45)

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

func processViewport(cgImage: CGImage, name: String) -> [CGRect] {
    print("\n--- Processing \(name) ---")
    var raw: [BBox] = []
    
    // Pass 1: Global Requests
    let reqFull = VNDetectHumanRectanglesRequest()
    reqFull.upperBodyOnly = false
    let reqUpper = VNDetectHumanRectanglesRequest()
    reqUpper.upperBodyOnly = true
    let reqFace = VNDetectFaceRectanglesRequest()
    
    let h1 = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? h1.perform([reqFull, reqUpper, reqFace])
    
    for r in (reqFull.results ?? []) {
        if r.confidence >= 0.03 { raw.append(BBox(rect: r.boundingBox, confidence: r.confidence, label: "Full")) }
    }
    for r in (reqUpper.results ?? []) {
        if r.confidence >= 0.03 { raw.append(BBox(rect: r.boundingBox, confidence: r.confidence, label: "Upper")) }
    }
    for f in (reqFace.results ?? []) {
        if f.confidence >= 0.05 {
            let b = f.boundingBox
            let head = CGRect(x: max(0, b.origin.x - b.width*0.2),
                              y: max(0, b.origin.y - b.height*0.2),
                              width: min(1.0 - b.origin.x, b.width * 1.4),
                              height: min(1.0 - b.origin.y, b.height * 1.8))
            raw.append(BBox(rect: head, confidence: f.confidence, label: "Face"))
        }
    }
    
    // Pass 2: 4x4 Multi-scale Grid Tiling (For Seated Audience)
    let cols = 4
    let rows = 4
    let tileW = cgImage.width / cols
    let tileH = cgImage.height / rows
    
    for r in 0..<rows {
        for c in 0..<cols {
            let tileRect = CGRect(x: c * tileW, y: r * tileH, width: tileW, height: tileH)
            guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
            
            // Audience seating is bottom 3 rows (r <= 2) in Vision y-up space
            let isSeatingArea = (r <= 2)
            let tileThresh: Float = isSeatingArea ? 0.01 : 0.06
            
            let tFull = VNDetectHumanRectanglesRequest()
            tFull.upperBodyOnly = false
            let tUpper = VNDetectHumanRectanglesRequest()
            tUpper.upperBodyOnly = true
            let tFace = VNDetectFaceRectanglesRequest()
            
            let th = VNImageRequestHandler(cgImage: tileCg, options: [:])
            try? th.perform([tFull, tUpper, tFace])
            
            for res in (tFull.results ?? []) + (tUpper.results ?? []) {
                if res.confidence >= tileThresh {
                    let b = res.boundingBox
                    let normX = (CGFloat(c * tileW) + b.origin.x * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normY = (CGFloat(r * tileH) + b.origin.y * CGFloat(tileH)) / CGFloat(cgImage.height)
                    let normW = (b.width * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normH = (b.height * CGFloat(tileH)) / CGFloat(cgImage.height)
                    raw.append(BBox(rect: CGRect(x: normX, y: normY, width: normW, height: normH), confidence: res.confidence, label: "TileBody"))
                }
            }
            for f in (tFace.results ?? []) {
                if f.confidence >= tileThresh {
                    let b = f.boundingBox
                    let normX = (CGFloat(c * tileW) + (b.origin.x - b.width*0.2) * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normY = (CGFloat(r * tileH) + (b.origin.y - b.height*0.2) * CGFloat(tileH)) / CGFloat(cgImage.height)
                    let normW = (b.width * 1.4 * CGFloat(tileW)) / CGFloat(cgImage.width)
                    let normH = (b.height * 1.8 * CGFloat(tileH)) / CGFloat(cgImage.height)
                    raw.append(BBox(rect: CGRect(x: normX, y: normY, width: normW, height: normH), confidence: f.confidence, label: "TileFace"))
                }
            }
        }
    }
    
    print("Raw detections collected: \(raw.count)")
    
    // Filter out ceiling wall noise (y > 0.85) and tiny noise (< 0.0015 area)
    let valid = raw.filter { b in
        let r = b.rect
        return r.origin.y + r.height < 0.85 && r.width * r.height >= 0.0015
    }
    
    // === AGGRESSIVE HUMAN BODY & MICROPHONE ABSORPTION ENGINE ===
    // Sort boxes by area descending
    var merged: [CGRect] = []
    let sortedByArea = valid.map { $0.rect }.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
    
    for b in sortedByArea {
        var absorbedIdx: Int? = nil
        for (idx, existing) in merged.enumerated() {
            let intersection = b.intersection(existing)
            let bArea = b.width * b.height
            let eArea = existing.width * existing.height
            
            let centerDx = abs(b.midX - existing.midX)
            let centerDy = abs(b.midY - existing.midY)
            let maxW = max(b.width, existing.width)
            let maxH = max(b.height, existing.height)
            
            // Check 1: Box B center is INSIDE Box A (Microphone/chest/belt inside speaker body)
            let isCenterInside = existing.contains(CGPoint(x: b.midX, y: b.midY)) || b.contains(CGPoint(x: existing.midX, y: existing.midY))
            
            // Check 2: Same vertical human column (center X dx < 50% maxW AND center Y dy < 85% maxH)
            let isSameColumn = (centerDx < maxW * 0.50 && centerDy < maxH * 0.85)
            
            // Check 3: Overlap ratio
            let isOverlapping = !intersection.isNull && (intersection.width * intersection.height / bArea > 0.30)
            
            if isCenterInside || isSameColumn || isOverlapping {
                absorbedIdx = idx
                break
            }
        }
        
        if let idx = absorbedIdx {
            // Expand parent box to enclose the absorbed part (mic, chest, belt)
            let e = merged[idx]
            let newMinX = min(e.minX, b.minX)
            let newMinY = min(e.minY, b.minY)
            let newMaxX = max(e.maxX, b.maxX)
            let newMaxY = max(e.maxY, b.maxY)
            merged[idx] = CGRect(x: newMinX, y: newMinY, width: newMaxX - newMinX, height: newMaxY - newMinY)
        } else {
            merged.append(b)
        }
    }
    
    print("After Aggressive Neural Body & Mic Absorption: \(merged.count) clean human boxes!")
    return merged
}

let res1 = processViewport(cgImage: cam1Cg, name: "CAM 01 (Left)")
let res2 = processViewport(cgImage: cam2Cg, name: "CAM 02 (Right)")

print("\n=== OPTIMIZER FINAL SUMMARY ===")
print("CAM 01 Final People Count: \(res1.count)")
print("CAM 02 Final People Count: \(res2.count)")
