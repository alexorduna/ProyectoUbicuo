import Vision
import CoreML

private let CONFIDENCE_THRESHOLD: Float = 0.75
private let DWELL_FRAMES = 10

class GestureEngine {
    private let classifier: gestovoz_rf
    private var predictionBuffer: [Int] = []
    var onGestureConfirmed: ((String, String) -> Void)?
    var onConfidenceUpdate: ((Float) -> Void)?

    init() {
        guard let model = try? gestovoz_rf() else {
            fatalError("No se pudo cargar gestovoz_rf.mlmodel")
        }
        self.classifier = model
    }

    func process(observation: VNHumanHandPoseObservation, gesturePhrases: [Int: String]) {
        guard let inputVector = buildInputVector(from: observation) else {
            predictionBuffer.removeAll()
            return
        }
        guard let prediction = try? classifier.prediction(landmarks_46: inputVector) else {
            predictionBuffer.removeAll()
            return
        }

        let labelIndex = Int(prediction.gesto_predicho)
        let probs = prediction.classProbability
        let sorted = probs.sorted(by: { $0.value > $1.value })
        let topConfidence = Float(sorted[0].value)
        let secondConfidence = Float(sorted[1].value)
        let margin = topConfidence - secondConfidence

        print("[\(indexToGestureName(labelIndex))] top:\(String(format: "%.2f", topConfidence)) margin:\(String(format: "%.2f", margin))")

        guard topConfidence >= CONFIDENCE_THRESHOLD, margin >= 0.15 else {
            predictionBuffer.removeAll()
            return
        }

        predictionBuffer.append(labelIndex)
        if predictionBuffer.count > DWELL_FRAMES {
            predictionBuffer.removeFirst()
        }

        if predictionBuffer.count == DWELL_FRAMES,
           predictionBuffer.allSatisfy({ $0 == labelIndex }) {
            let gestureName = indexToGestureName(labelIndex)
            let phrase = gesturePhrases[labelIndex + 1] ?? gestureName
            predictionBuffer.removeAll()
            DispatchQueue.main.async {
                self.onGestureConfirmed?(gestureName, phrase)
            }
        }
    }

    private func buildInputVector(from obs: VNHumanHandPoseObservation) -> MLMultiArray? {
        // 47 features: 42 coords + 5 ángulos
        guard let input = try? MLMultiArray(shape: [1, 47], dataType: .float32) else { return nil }

        let visionOrder: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        guard let points = try? obs.recognizedPoints(.all) else { return nil }
        guard let wrist = points[.wrist], wrist.confidence > 0.3 else { return nil }

        let wristX = Float(wrist.location.x)
        let wristY = Float(wrist.location.y)

        // Calcular coordenadas centradas
        var cx = [Float](repeating: 0, count: 21)
        var cy = [Float](repeating: 0, count: 21)

        for (i, jointName) in visionOrder.enumerated() {
            let point = points[jointName]
            let confidence = point?.confidence ?? 0
            if confidence > 0.3 {
                cx[i] = Float(point!.location.x) - wristX
                cy[i] = wristY - Float(point!.location.y)
            }
        }

        // Normalizar escala con landmark 9 (base dedo medio) igual que Python
        let scale = sqrt(cx[9] * cx[9] + cy[9] * cy[9])
        let s: Float = scale < 1e-6 ? 1.0 : scale

        // 42 coordenadas normalizadas
        for i in 0..<21 {
            input[i * 2]     = NSNumber(value: cx[i] / s)
            input[i * 2 + 1] = NSNumber(value: cy[i] / s)
        }

        // 5 ángulos entre puntas consecutivas: thumb(4), index(8), middle(12), ring(16), little(20)
        let fingertips = [4, 8, 12, 16, 20]
        for i in 0..<(fingertips.count - 1) {
            let a = fingertips[i]
            let b = fingertips[i + 1]
            let v1 = SIMD2<Float>(cx[a] / s, cy[a] / s)
            let v2 = SIMD2<Float>(cx[b] / s, cy[b] / s)
            let dot = v1.x * v2.x + v1.y * v2.y
            let norm = sqrt(v1.x*v1.x + v1.y*v1.y) * sqrt(v2.x*v2.x + v2.y*v2.y)
            let angle: Float = norm < 1e-6 ? 0.0 : acos(max(-1.0, min(1.0, dot / norm)))
            input[42 + i] = NSNumber(value: angle)
        }

        return input
    }

    private func indexToGestureName(_ index: Int) -> String {
        let order = ["dislike", "fist", "like", "ok", "one", "palm", "peace", "rock"]
        return index < order.count ? order[index] : "unknown"
    }
}
