//
//  Camera.swift
//  Ubicuo
//
//  Created by Ivan Mijares on 19/03/26.
//

import SwiftUI
import AVFoundation //frameworks más importantes de Apple para trabajar con audio, video y captura
import Vision
import Combine


class CamaraController: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate
{
    // Estado pubicado a SwiftUI
    @Published var resultadoVision: String = ""
    @Published var mostrarAlertaPermisos: Bool = false
    
    
    // AVFoundation
    private let session = AVCaptureSession( )
    private var posicionActual: AVCaptureDevice.Position = .back
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let visionQueue = DispatchQueue(label: "vision.queue")
    
    //Vision
    private var solicitudesVision: [VNRequest] = []
    
    // Referencia al VC para agregar el preview layer
    weak var previewVC: CamaraPreviewViewController?
    
    
    func solicitarPermisos()
    {
        switch AVCaptureDevice.authorizationStatus(for: .video)
        {
            case .authorized:
                configurarSesion()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for:.video){[weak self] granted in
                    if granted
                    {
                        self?.configurarSesion()
                    }
                    else
                    {
                        DispatchQueue.main.async
                        {
                            self?.mostrarAlertaPermisos = true
                        }
                    }
                }
            default:
                DispatchQueue.main.async
                {
                    self.mostrarAlertaPermisos = true
                }
        }
    }
    
    
    func configurarSesion(posicion: AVCaptureDevice.Position = .back)
    {
        sessionQueue.async
        {
            [weak self] in guard let self else {return}
            
            self.session.beginConfiguration()
            
            //limpiar inputs anteriores
            self.session.inputs.forEach{self.session.removeInput($0)}
                                        
            // agregar nuevo input
            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for:.video, position: posicion),
                let input = try? AVCaptureDeviceInput(device: device),
                    self.session.canAddInput(input)
            else
            {
                self.session.commitConfiguration()
                return
            }
            
            self.session.addInput(input)
            self.posicionActual = posicion
            
            
            //Configurar outpur de video
            
            if self.session.outputs.isEmpty
            {
                self.videoOutput.setSampleBufferDelegate(self,queue:self.visionQueue)
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                if self.session.canAddOutput(self.videoOutput)
                {
                    self.session.addOutput(self.videoOutput)
                }
            }
            
            
            self.session.commitConfiguration()
            
            //Agregar preview layer en hilo principal
            DispatchQueue.main.async
            {
                self.previewVC?.agregarPreviewLayer(session: self.session)
            }
            
            //Iniciar sesion
            if !self.session.isRunning
            {
                self.session.startRunning()
            }
            
            //configurar vision
            self.configurarVision()
            
        }
    
    }
    
    
    func cambiarCamara()
    {
        let nuevaPosicion: AVCaptureDevice.Position = posicionActual == .back ? .front: .back
        configurarSesion(posicion: nuevaPosicion)
    }
    
    func detener()
    {
        sessionQueue.async
        {
            [weak self] in self?.session.stopRunning()
        }
    }
    
    func configurarVision()
    {
        //Deteccion de manos (VNDetectHumanandPoseRequest)
        let handRequest = VNDetectHumanHandPoseRequest {[weak self] request, error in self?.procesarResultadosManos(request:request,error:error)}
        
        handRequest.maximumHandCount = 2
        
        solicitudesVision = [handRequest]
    }
    
    //procesar frames con vision
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {return}
        
        let orientacion: CGImagePropertyOrientation = posicionActual == .front ? .leftMirrored : .right
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientacion, options:[:])
        
        do
        {
            try handler.perform(solicitudesVision)
        }
        catch
        {
            print("Error VIsion: \(error)")
        }
    }
    
    
    
    // Procesar resultados de manos
    private func procesarResultadosManos(request: VNRequest, error: Error?)
    {
        guard let observaciones = request.results as? [VNHumanHandPoseObservation], !observaciones.isEmpty
        else
        {
            DispatchQueue.main.async
            {
                self.resultadoVision = ""
            }
            return
        }
        
        //por cada mano detectada extramenos los puntos clave
        
        var textos: [String] = []
        
        for (i,mano) in observaciones.enumerated()
        {
            if let pulgar = try? mano.recognizedPoint(.thumbTip),
               let indice = try? mano.recognizedPoint(.indexTip),
               pulgar.confidence > 0.5 && indice.confidence > 0.5
            {
                //Distancia entre pulgar e indice (normalizdo 0/1)
                
                let dx = pulgar.location.x - indice.location.x
                let dy = pulgar.location.y - indice.location.y
                let distancia = sqrt(dx*dx+dy*dy)
                
                
                let gesto = distancia < 0.05 ? "👌 OK" : " 🤚 Palma Abierta"
                textos.append("Mano \(i+1): \(gesto)")
            }
            
        }
        DispatchQueue.main.async
        {
            self.resultadoVision = textos.joined(separator: " | ")
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
    }
    
    func agregarPreviewLayer(session: AVCaptureSession)
    {
        previewLayer?.removeFromSuperlayer( )
        let layer = AVCaptureVideoPreviewLayer(session:session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at:0)
        self.previewLayer = layer
    }
    
    override func viewDidLayoutSubviews( )
    {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}



struct Camara: View
{
    @StateObject private var controller = CamaraController() //solo se crea una instancia del objecto
    @State private var mostraraAlerta = false
    
    var body: some View
    {
        ZStack
        {
            CamaraPreviewRepresentable(controller: controller).ignoresSafeArea()
            
            VStack
            {
                if !controller.resultadoVision.isEmpty
                {
                    Text(controller.resultadoVision)
                        .font(.system(size:18,weight:.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal,16)
                        .padding(.vertical,10)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        .padding(.top,60)
                        .transition(.opacity)
                        .animation(.easeInOut, value:controller.resultadoVision)
                }
                
                Spacer()
                
                HStack(spacing:48)
                {
                    Spacer()
                    Button(action:{
                        controller.cambiarCamara()
                    }){
                        Image(systemName:"arrow.triangle.2.circlepath.camera")
                            .resizable()
                            .scaledToFit()
                            .frame(width:32,height:32)
                            .foregroundColor(.white)
                            .padding(16)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                }
                .padding(.bottom,48)
            }
            
        }
        .navigationTitle("Camara")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear{
            controller.solicitarPermisos()
        }
        .onDisappear{
            controller.detener()
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
            Button("Cancelar", role:.cancel){}
        }message:{
            Text("Activa el permiso de camara en ajsutes para usar esta funcion")
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
    
    func updateUIViewController(_ uiViewController: CamaraPreviewViewController, context: Context) {
        
    }
}



#Preview
{
    NavigationStack{
        Camara()
    }
}
