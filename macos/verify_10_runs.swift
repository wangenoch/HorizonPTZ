import Foundation
import Vision
import AppKit

print("=== DEEP 10-RUN AUTOMATED APPLICATION VERIFICATION ===")

func runDetectionOnImage(cgImage: CGImage) -> (cam1Boxes: [CGRect], cam2Boxes: [CGRect]) {
    let w = CGFloat(cgImage.width)
    let h = CGFloat(cgImage.height)
    
    let cam1Rect = CGRect(x: w * 0.04, y: h * 0.15, width: w * 0.43, height: h * 0.80)
    let cam2Rect = CGRect(x: w * 0.53, y: h * 0.15, width: w * 0.43, height: h * 0.80)
    
    guard let cam1Cg = cgImage.cropping(to: cam1Rect),
          let cam2Cg = cgImage.cropping(to: cam2Rect) else {
        return ([], [])
    }
    
    func getCleanBoxes(cg: CGImage) -> [CGRect] {
        var rawBoxes: [CGRect] = []
        let poseReq = VNDetectHumanBodyPoseRequest()
        let faceReq = VNDetectFaceRectanglesRequest()
        let h1 = VNImageRequestHandler(cgImage: cg, options: [:])
        try? h1.perform([poseReq, faceReq])
        
        for obs in (poseReq.results ?? []) {
            if let points = try? obs.recognizedPoints(forGroupKey: .all) {
                let valid = points.values.filter { $0.confidence > 0.02 }
                if valid.count >= 2 {
                    let xs = valid.map { CGFloat($0.location.x) }
                    let ys = valid.map { CGFloat($0.location.y) }
                    let minX = xs.min()!
                    let maxX = xs.max()!
                    let minY = ys.min()!
                    let maxY = ys.max()!
                    rawBoxes.append(CGRect(x: max(0, minX - 0.04), y: max(0, minY - 0.06), width: min(0.65, (maxX - minX) + 0.08), height: min(0.85, (maxY - minY) + 0.12)))
                }
            }
        }
        
        for f in (faceReq.results ?? []) {
            if f.confidence >= 0.01 {
                let b = f.boundingBox
                rawBoxes.append(CGRect(x: max(0, b.origin.x - b.width*0.20), y: max(0, b.origin.y - b.height*0.20), width: min(0.25, b.width * 1.4), height: min(0.35, b.height * 1.8)))
            }
        }
        
        let valid = rawBoxes.filter { b in
            let area = b.width * b.height
            let isDoorFrame = (b.origin.x < 0.08 && b.origin.y > 0.40)
            let isCeiling = (b.origin.y + b.height >= 0.88)
            let isTripod = (b.midX > 0.44 && b.midX < 0.54 && b.midY > 0.20 && b.midY < 0.55 && b.width < 0.20)
            let isGiantCluster = (b.width > 0.45)
            
            return area >= 0.0008 && !isCeiling && !isDoorFrame && !isTripod && !isGiantCluster
        }
        
        var fused: [CGRect] = []
        for b in valid.sorted(by: { ($0.width * $0.height) > ($1.width * $1.height) }) {
            var absorbed: Int? = nil
            for (idx, existing) in fused.enumerated() {
                let intersection = b.intersection(existing)
                let centerDx = abs(b.midX - existing.midX)
                let centerDy = abs(b.midY - existing.midY)
                let maxW = max(b.width, existing.width)
                let maxH = max(b.height, existing.height)
                let isSamePersonColumn = (centerDx < maxW * 0.55 && centerDy < maxH * 0.85)
                let isOverlapping = !intersection.isNull && (intersection.width * intersection.height / min(b.width * b.height, existing.width * existing.height) > 0.25)
                if isSamePersonColumn || isOverlapping {
                    absorbed = idx
                    break
                }
            }
            if let idx = absorbed {
                let e = fused[idx]
                let nx = min(e.minX, b.minX)
                let ny = min(e.minY, b.minY)
                let mx = max(e.maxX, b.maxX)
                let my = max(e.maxY, b.maxY)
                if (mx - nx) <= 0.65 {
                    fused[idx] = CGRect(x: nx, y: ny, width: mx - nx, height: my - ny)
                } else {
                    fused.append(b)
                }
            } else {
                fused.append(b)
            }
        }
        
        var kept: [CGRect] = []
        for b in fused.sorted(by: { ($0.width * $0.height) > ($1.width * $1.height) }) {
            var isContained = false
            for k in kept {
                let intersection = b.intersection(k)
                if !intersection.isNull {
                    let bCenterInsideK = k.contains(CGPoint(x: b.midX, y: b.midY))
                    let isOverlapContained = (intersection.width * intersection.height / (b.width * b.height)) > 0.25
                    if bCenterInsideK || isOverlapContained {
                        isContained = true
                        break
                    }
                }
            }
            if !isContained {
                kept.append(b)
            }
        }
        return kept
    }
    
    return (getCleanBoxes(cg: cam1Cg), getCleanBoxes(cg: cam2Cg))
}

var allPassed = true

for i in 1...10 {
    let tmpFile = "/tmp/run_\(i).png"
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = ["-x", tmpFile]
    try? proc.run()
    proc.waitUntilExit()
    
    guard let nsImg = NSImage(contentsOfFile: tmpFile),
          let cgImg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("Run \(i): Screencapture failed")
        allPassed = false
        continue
    }
    
    let res = runDetectionOnImage(cgImage: cgImg)
    let cam2Pass = (res.cam2Boxes.count == 1)
    
    print("Run \(i)/10: CAM 02 Speaker Box Count = \(res.cam2Boxes.count) | Status: \(cam2Pass ? "✅ PASS" : "❌ FAIL")")
    if !cam2Pass {
        allPassed = false
    }
    Thread.sleep(forTimeInterval: 0.8)
}

print("\n==========================================")
print(allPassed ? "🎉 10/10 CONSECUTIVE RUNS PASSED PERFECTLY!" : "⚠️ SOME RUNS FAILED - TUNING REQUIRED")
print("==========================================")
