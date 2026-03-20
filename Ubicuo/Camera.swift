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


final class CamaraController: NSObject, ObservableObject
{
    // Estado pubicado a SwiftUI
    @Published var resultadoVision: String = "" //como es observable object, estos son los datos que se observan para el cambio
    @Published var mostrarAlertaPermisos: Bool = false
    
    
    // AVFoundation
    private let session = AVCaptureSession() //sesion principal de la camara
    nonisolated(unsafe) private var posicionActual: AVCaptureDevice.Position = .back //que camara se usa, frontal o trasera
    // nonisolated(unsafe) permite acceder desde un contexto nonisolated. es unsafe porque nosotros garantizamos manualmente que el acceso es thread-safe (solo se leen en visionQueue, solo se escriben en sessionQueue/configurarSesion)
    
    private let videoOutput = AVCaptureVideoDataOutput() //objeto que etnrega los frames de video
    
    //Un dispatchQueue es un queue pero de hilos
    //lo tenemos separado, para tener un mejor control de los threads y que otros no se bloqueen
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let visionQueue = DispatchQueue(label: "vision.queue")
    
    //Vision
    nonisolated(unsafe) private var solicitudesVision: [VNRequest] = [] //Es un arreglo donde guardas todas las “tareas” que Vision debe ejecutar sobre cada frame.
    // en este caso VNDetectHumanHandPoseRequest para detectar manos, configurado en la funcion.
    
    // Referencia al VC para agregar el preview layer
    weak var previewVC: CamaraPreviewViewController?
    //Significa que no incrementa el contador de referencias. Esto evita ciclos de retención (memory leaks).
    //CamaraPreviewViewController tiene una relacion strong, y CamaraController una weak
    
    
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
                        //aqui ejecutamos un thread en el queue principal (main) a diferencia de los otros
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
        //aseguramos que todo se realice en un hilo seguro sin bloquear la UI ni generar race conditions
        sessionQueue.async
        {
            //solo continua el codigo si self existe
            [weak self] in guard let self else {return}
            
            self.session.beginConfiguration() //modificamos sesion, pero no se aplican los cambios hasta terminar
            
            //limpiar inputs anteriores (por si se cambia la camara frontal o trasera
            self.session.inputs.forEach{self.session.removeInput($0)}
                                        
            // agregar nuevo input
            guard
                // obtenemos camara utilizada
                //creamos el input a partir de la camara
                // verificamos que AVFoundation permita agregarlo
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for:.video, position: posicion),
                let input = try? AVCaptureDeviceInput(device: device),
                    self.session.canAddInput(input)
            else
            {
                self.session.commitConfiguration()
                return
            }
            
            //guarda la posicion actual de la camara
            self.session.addInput(input)
            self.posicionActual = posicion
            
            
            //Configurar outpur de video
            
            if self.session.outputs.isEmpty
            {
                self.videoOutput.setSampleBufferDelegate(self, queue:self.visionQueue) //Cada vez que la cámara genere un frame, envíalo a esta función en el hilo visionQueue
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                if self.session.canAddOutput(self.videoOutput)
                {
                    self.session.addOutput(self.videoOutput)
                }
            }
            
            
            self.session.commitConfiguration() //ahora si mandamos las configuraciones
            
            //Agregar preview layer en hilo principal
            DispatchQueue.main.async
            {
                self.previewVC?.agregarPreviewLayer(session: self.session)
            }
            
            //Iniciar sesion, arrancamos camara si no esta prendida
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


extension CamaraController :  AVCaptureVideoDataOutputSampleBufferDelegate
{
    //procesar frames con vision
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
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
