//
//  GestureEngine.swift
//  Ubicuo
//

import Vision
import CoreML

private let CONFIDENCE_THRESHOLD: Float = 0.75
private let DWELL_FRAMES = 15

class GestureEngine {

    private let classifier: gestovoz_rf
    private var predictionBuffer: [Int] = []
    var onGestureConfirmed: ((String, String) -> Void)?

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

        guard let prediction = try? classifier.prediction(landmarks_42: inputVector) else {
            predictionBuffer.removeAll()
            return
        }

        let labelIndex = Int(prediction.gesto_predicho)
        let confidence = Float(prediction.classProbability[Int64(labelIndex)] ?? 0)

        guard confidence >= CONFIDENCE_THRESHOLD else {
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
        guard let input = try? MLMultiArray(shape: [1, 42], dataType: .float32) else { return nil }

        let visionOrder: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]

        guard let points = try? obs.recognizedPoints(.all) else { return nil }

        // Normalizar relativo a la muñeca como lo hace MediaPipe
        guard let wrist = points[.wrist], wrist.confidence > 0.3 else { return nil }
        let wristX = Float(wrist.location.x)
        let wristY = Float(wrist.location.y)

        for (i, jointName) in visionOrder.enumerated() {
            let point = points[jointName]
            let confidence = point?.confidence ?? 0
            if confidence > 0.3 {
                input[i * 2]     = NSNumber(value: Float(point!.location.x) - wristX)
                input[i * 2 + 1] = NSNumber(value: wristY - Float(point!.location.y))
            } else {
                input[i * 2]     = NSNumber(value: 0)
                input[i * 2 + 1] = NSNumber(value: 0)
            }
        }
        return input
    }

    private func indexToGestureName(_ index: Int) -> String {
        let order = ["call", "dislike", "fist", "like", "ok", "one", "palm", "peace", "rock"]
        return index < order.count ? order[index] : "unknown"
    }
}
