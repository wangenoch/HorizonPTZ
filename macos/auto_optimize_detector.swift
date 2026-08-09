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

print("=== AUTOMATED REPEATED TESTING & OPTIMIZATION ENGINE ===")
print("Screen size: \(w) x \(h)")

// Crop exact player viewports
let cam1Rect = CGRect(x: w * 0.04, y: h * 0.25, width: w * 0.43, height: h * 0.65)
let cam2Rect = CGRect(x: w * 0.53, y: h * 0.25, width: w * 0.43, height: h * 0.65)

guard let cam1Cg = cgImage.cropping(to: cam1Rect),
      let cam2Cg = cgImage.cropping(to: cam2Rect) else {
    print("Error cropping viewports")
    exit(1)
}

func runOptimizedDetection(cgImage: CGImage, cameraName: String) -> [CGRect] {
    print("\n--- Iterative Optimizer Testing \(cameraName) ---")
    
    var validHumanBoxes: [CGRect] = []
    
    // Pass 1: Pose Keypoint Detection (Highest Confidence Human Detector)
    let poseReq = VNDetectHumanBodyPoseRequest()
    let handler1 = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler1.perform([poseReq])
    
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
                
                let padX: CGFloat = 0.05
                let padY: CGFloat = 0.08
                
                let b = CGRect(
                    x: max(0, minX - padX),
                    y: max(0, minY - padY),
                    width: min(0.35, (maxX - minX) + padX * 2), // Max width 0.35 to prevent giant wall boxes!
                    height: min(0.65, (maxY - minY) + padY * 2)
                )
                validHumanBoxes.append(b)
            }
        }
    }
    
    // Pass 2: Face & Head Detection
    let faceReq = VNDetectFaceRectanglesRequest()
    let handler2 = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try? handler2.perform([faceReq])
    
    for f in (faceReq.results ?? []) {
        if f.confidence >= 0.05 {
            let b = f.boundingBox
            let head = CGRect(x: max(0, b.origin.x - b.width*0.25),
                              y: max(0, b.origin.y - b.height*0.25),
                              width: min(0.20, b.width * 1.5),
                              height: min(0.25, b.height * 1.9))
            
            var isInsidePose = false
            for poseBox in validHumanBoxes {
                if poseBox.contains(CGPoint(x: head.midX, y: head.midY)) {
                    isInsidePose = true
                    break
                }
            }
            if !isInsidePose {
                validHumanBoxes.append(head)
            }
        }
    }
    
    // Pass 3: 4x4 Grid Seated Audience Head Tiling
    let cols = 4
    let rows = 4
    let tileW = cgImage.width / cols
    let tileH = cgImage.height / rows
    
    for r in 0..<rows {
        for c in 0..<cols {
            let tileRect = CGRect(x: c * tileW, y: r * tileH, width: tileW, height: tileH)
            guard let tileCg = cgImage.cropping(to: tileRect) else { continue }
            
            // Seating area is bottom 3 rows (r <= 2 in Vision y-up space)
            if r <= 2 {
                let tFace = VNDetectFaceRectanglesRequest()
                let tPose = VNDetectHumanBodyPoseRequest()
                let th = VNImageRequestHandler(cgImage: tileCg, options: [:])
                try? th.perform([tFace, tPose])
                
                for f in (tFace.results ?? []) {
                    if f.confidence >= 0.05 {
                        let b = f.boundingBox
                        let normX = (CGFloat(c * tileW) + (b.origin.x - b.width*0.25) * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normY = (CGFloat(r * tileH) + (b.origin.y - b.height*0.25) * CGFloat(tileH)) / CGFloat(cgImage.height)
                        let normW = (b.width * 1.5 * CGFloat(tileW)) / CGFloat(cgImage.width)
                        let normH = (b.height * 1.9 * CGFloat(tileH)) / CGFloat(cgImage.height)
                        
                        let tileHeadBox = CGRect(x: normX, y: normY, width: normW, height: normH)
                        
                        var isDup = false
                        for k in validHumanBoxes {
                            if k.contains(CGPoint(x: tileHeadBox.midX, y: tileHeadBox.midY)) {
                                isDup = true
                                break
                            }
                        }
                        if !isDup {
                            validHumanBoxes.append(tileHeadBox)
                        }
                    }
                }
            }
        }
    }
    
    // Filter out architectural door frames (x < 0.08 & y > 0.40) & ceiling wall areas (y + height > 0.85)
    let cleanBoxes = validHumanBoxes.filter { b in
        let isDoorFrame = (b.origin.x < 0.08 && b.origin.y > 0.40)
        let isCeiling = (b.origin.y + b.height > 0.85)
        let isTooWide = (b.width > 0.38) // Reject giant wall boxes!
        return !isDoorFrame && !isCeiling && !isTooWide
    }
    
    // Clean NMS (Max 1 box per person)
    var finalKept: [CGRect] = []
    let sorted = cleanBoxes.sorted { ($0.width * $0.height) > ($1.width * $1.height) }
    
    for box in sorted {
        var isOverlap = false
        for k in finalKept {
            let intersection = box.intersection(k)
            if !intersection.isNull {
                let interArea = intersection.width * intersection.height
                let boxArea = box.width * box.height
                if interArea / boxArea > 0.40 {
                    isOverlap = true
                    break
                }
            }
        }
        if !isOverlap {
            finalKept.append(box)
        }
    }
    
    print("Final Clean Human Count: \(finalKept.count) people")
    return finalKept
}

let res1 = runOptimizedDetection(cgImage: cam1Cg, cameraName: "CAM 01 (Left)")
let res2 = runOptimizedDetection(cgImage: cam2Cg, cameraName: "CAM 02 (Right)")

print("\n=== ITERATIVE OPTIMIZER FINAL TEST SUMMARY ===")
print("CAM 01 People Count: \(res1.count)")
print("CAM 02 People Count: \(res2.count)")
