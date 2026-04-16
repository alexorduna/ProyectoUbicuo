
import AVFoundation

class MotorTTS: NSObject, AVSpeechSynthesizerDelegate {
    
    private let sintetizador = AVSpeechSynthesizer()
    
    override init() {
        super.init()
        sintetizador.delegate = self
        configurarAudio()
    }
    
    private func configurarAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Error configurando audio: \(error)")
        }
    }
    
    func hablar(texto: String) {
        if sintetizador.isSpeaking {
            sintetizador.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: texto)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-MX")
        utterance.rate = 0.55
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        sintetizador.speak(utterance)
    }
}
