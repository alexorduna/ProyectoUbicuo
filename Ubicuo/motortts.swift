import AVFoundation

class MotorTTS: NSObject, AVSpeechSynthesizerDelegate {
    
    private let sintetizador = AVSpeechSynthesizer()
    private var listo: Bool = false
    private var pendiente: String? = nil
    
    override init() {
        super.init()
        sintetizador.delegate = self
        configurarAudio()
        precalentar()
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
    
    private func precalentar() {
        // Utterance silencioso para inicializar el sintetizador
        let silencio = AVSpeechUtterance(string: " ")
        silencio.voice = AVSpeechSynthesisVoice(language: "es-MX")
        silencio.volume = 0
        silencio.rate = AVSpeechUtteranceMaximumSpeechRate
        sintetizador.speak(silencio)
    }
    
    func hablar(texto: String) {
        // Si todavía está precalentando, guardar como pendiente
        if sintetizador.isSpeaking {
            pendiente = texto
            sintetizador.stopSpeaking(at: .immediate)
            return
        }
        pronunciar(texto)
    }
    
    private func pronunciar(_ texto: String) {
        let utterance = AVSpeechUtterance(string: texto)
        utterance.voice = AVSpeechSynthesisVoice(language: "es-MX")
        utterance.rate = 0.55
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1
        sintetizador.speak(utterance)
    }
    
    // Delegate: cuando termina un utterance, ver si hay uno pendiente
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if let pendiente = pendiente {
            self.pendiente = nil
            pronunciar(pendiente)
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if let pendiente = pendiente {
            self.pendiente = nil
            pronunciar(pendiente)
        }
    }
}
