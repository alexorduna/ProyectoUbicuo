//
//  Camera.swift
//  Ubicuo
//
//  Created by Ivan Mijares on 19/03/26.
//

import SwiftUI
import AVFoundation
import Vision
import Combine


final class CamaraController: NSObject, ObservableObject
{
    @Published var resultadoVision: String = ""
    @Published var confidencevalue: Float = 0.0
    @Published var mostrarAlertaPermisos: Bool = false
    @Published var camaraLista: Bool = false

    private let gestureEngine = GestureEngine()
    private var gesturePhrases: [Int:String] = [:]
    private let motorTTS = MotorTTS()
    private var ultimaActivacion: Date = .distantPast
    private var sesionConfigurada: Bool = false
    private var estaPausado: Bool = false

    let session = AVCaptureSession()
    nonisolated(unsafe) private var posicionActual: AVCaptureDevice.Position = .front
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let visionQueue = DispatchQueue(label: "vision.queue")
    nonisolated(unsafe) private var solicitudesVision: [VNRequest] = []
    weak var previewVC: CamaraPreviewViewController?

    func solicitarPermisos()
    {
        guard !sesionConfigurada else {
            reanudar()
            return
        }

        for i in 1...8 {
            let order = ["dislike", "fist", "like", "ok", "one", "palm", "peace", "rock"]
            let frase = UserDefaults.standard.string(forKey: "gesto_\(i)") ?? order[i - 1]
            gesturePhrases[i] = frase
        }

        gestureEngine.onGestureConfirmed = { [weak self] gestureName, phrase in
            guard let self = self else { return }
            let ahora = Date()
            guard ahora.timeIntervalSince(self.ultimaActivacion) > 2.0 else { return }
            self.ultimaActivacion = ahora
            self.resultadoVision = "\(gestureName): \(phrase)"
            self.motorTTS.hablar(texto: phrase)
        }

        switch AVCaptureDevice.authorizationStatus(for: .video)
        {
            case .authorized:
                configurarSesion()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    if granted {
                        self?.configurarSesion()
                    } else {
                        DispatchQueue.main.async {
                            self?.mostrarAlertaPermisos = true
                        }
                    }
                }
            default:
                DispatchQueue.main.async {
                    self.mostrarAlertaPermisos = true
                }
        }
    }

    func configurarSesion(posicion: AVCaptureDevice.Position = .front)
    {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.inputs.forEach { self.session.removeInput($0) }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: posicion),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)
            self.posicionActual = posicion

            if self.session.outputs.isEmpty {
                self.videoOutput.setSampleBufferDelegate(self, queue: self.visionQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                if self.session.canAddOutput(self.videoOutput) {
                    self.session.addOutput(self.videoOutput)
                }
            }

            self.session.commitConfiguration()
            self.configurarVision()

            if !self.session.isRunning {
                self.session.startRunning()
            }

            self.sesionConfigurada = true

            DispatchQueue.main.async {
                self.previewVC?.mostrarPreview()
                self.camaraLista = true
            }
        }
    }

    func pausar()
    {
        estaPausado = true
        sessionQueue.async{ [weak self] in
            self?.session.stopRunning()
        }
        
        DispatchQueue.main.async {
            self.previewVC?.ocultarPreview()
            self.camaraLista = false
        }
    }

    func reanudar()
    {
        for i in 1...8 {
            let order = ["dislike", "fist", "like", "ok", "one", "palm", "peace", "rock"]
            let frase = UserDefaults.standard.string(forKey: "gesto_\(i)") ?? order[i - 1]
            gesturePhrases[i] = frase
        }
        estaPausado = false
        sessionQueue.async { [weak self] in
            guard let self, self.sesionConfigurada else
            {
                DispatchQueue.main.async {self?.solicitarPermisos()}
                return
            }
            
            if !self.session.isRunning
            {
                self.session.startRunning()
            }
            
            DispatchQueue.main.async {
                self.previewVC?.mostrarPreview()
                self.camaraLista = true
            }
        }
    }

    func detener()
    {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            self?.sesionConfigurada = false
        }
        DispatchQueue.main.async {
            self.camaraLista = false
        }
    }

    func configurarVision()
    {
        let handRequest = VNDetectHumanHandPoseRequest { [weak self] request, error in
            self?.procesarResultadosManos(request: request, error: error)
        }
        handRequest.maximumHandCount = 2
        solicitudesVision = [handRequest]
    }

    private func convertir(_ punto: VNRecognizedPoint, en size: CGSize) -> CGPoint {
        return CGPoint(
            x: punto.location.x * size.width,
            y: (1 - punto.location.y) * size.height
        )
    }

    private func dibujarEsqueleto(para mano: VNHumanHandPoseObservation) {
        guard let view = previewVC?.view else { return }
        let size = view.bounds.size
        let path = UIBezierPath()

        guard let puntos = try? mano.recognizedPoints(.all) else { return }

        let conexiones: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
            (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
            (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
            (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
            (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
        ]

        for (a, b) in conexiones {
            if let p1 = puntos[a], p1.confidence > 0.3,
               let p2 = puntos[b], p2.confidence > 0.3 {
                let c1 = convertir(p1, en: size)
                let c2 = convertir(p2, en: size)
                path.move(to: c1)
                path.addLine(to: c2)
            }
        }

        for (_, p) in puntos {
            if p.confidence > 0.3 {
                let c = convertir(p, en: size)
                let circle = UIBezierPath(ovalIn: CGRect(x: c.x-3, y: c.y-3, width: 6, height: 6))
                path.append(circle)
            }
        }

        DispatchQueue.main.async {
            if let existing = view.layer.sublayers?
                .first(where: { $0.name == "handSkeleton" }) as? CAShapeLayer
            {
                existing.path = path.cgPath
            }
            else
            {
                let shapeLayer = CAShapeLayer()
                shapeLayer.strokeColor = UIColor.systemBlue.cgColor
                shapeLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
                shapeLayer.lineWidth = 2
                shapeLayer.name = "handSkeleton"
                shapeLayer.path = path.cgPath
                view.layer.addSublayer(shapeLayer)
            }
        }
    }

    private func procesarResultadosManos(request: VNRequest, error: Error?)
    {
        guard let observaciones = request.results as? [VNHumanHandPoseObservation], !observaciones.isEmpty
        else {
            DispatchQueue.main.async { self.resultadoVision = "" }
            return
        }

        for mano in observaciones {
            gestureEngine.process(observation: mano, gesturePhrases: gesturePhrases)
            dibujarEsqueleto(para: mano)
        }
    }
}


nonisolated extension CamaraController: AVCaptureVideoDataOutputSampleBufferDelegate
{
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        guard !estaPausado else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientacion: CGImagePropertyOrientation = posicionActual == .front ? .leftMirrored : .right
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientacion, options: [:])
        do {
            try handler.perform(solicitudesVision)
        } catch {
            print("Error Vision: \(error)")
        }
    }
}


class CamaraPreviewViewController: UIViewController
{
    var camaraController: CamaraController?
    var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = .black
        camaraController?.previewVC = self
        camaraController?.solicitarPermisos()
    }

    func mostrarPreview()
    {
        if let existing = previewLayer {
            existing.isHidden = false
            existing.frame = view.bounds
            return
        }
        guard let session = camaraController?.session else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        view.layer.insertSublayer(layer, at: 0)
        self.previewLayer = layer
    }

    func ocultarPreview()
    {
        previewLayer?.isHidden = true
    }

    override func viewDidLayoutSubviews()
    {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}


struct Camara: View
{
    @ObservedObject var controller: CamaraController

    var body: some View
    {
        ZStack
        {
            CamaraPreviewRepresentable(controller: controller).ignoresSafeArea()

            if !controller.camaraLista
            {
                ZStack
                {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 16)
                    {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Iniciando cámara...")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .transition(.opacity)
                .animation(.easeOut(duration: 0.4), value: controller.camaraLista)
            }

            VStack
            {
                if !controller.resultadoVision.isEmpty
                {
                    Text(controller.resultadoVision)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .padding(.top, 60)
                        .transition(.opacity)
                        .animation(.easeInOut, value: controller.resultadoVision)
                }
            }
        }
        .navigationTitle("Camara")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            controller.reanudar()
        }
        .onDisappear {
            controller.pausar()
        }
        .alert("Sin permiso de camara", isPresented: $controller.mostrarAlertaPermisos)
        {
            Button("Ir a Ajustes")
            {
                if let url = URL(string: UIApplication.openSettingsURLString)
                {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Activa el permiso de camara en ajustes para usar esta funcion")
        }
    }
}


struct CamaraPreviewRepresentable: UIViewControllerRepresentable
{
    let controller: CamaraController

    func makeUIViewController(context: Context) -> CamaraPreviewViewController
    {
        let vc = CamaraPreviewViewController()
        vc.camaraController = controller
        controller.previewVC = vc
        return vc
    }

    func updateUIViewController(_ uiViewController: CamaraPreviewViewController, context: Context)
    {
        controller.previewVC = uiViewController
    }
}


#Preview
{
    NavigationStack {
        Camara(controller: CamaraController())
    }
}
