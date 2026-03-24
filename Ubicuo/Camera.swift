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
        //VNDetectHumanHandPoseRequest detecta manos, suspuntos clave y la postura de los dedos
        // {[weak self] request, error in self?.procesarResultadosManos(request:request,error:error)}: Cuando Vision termine de analizar un frame y detecte manos, ejecuta este bloque.
        handRequest.maximumHandCount = 2
        
        solicitudesVision = [handRequest]
        
//        Vision analiza el frame
//        Vision detecta manos
//        Vision llama tu closure
//        Tú procesas el resultado en tu función procesarResultadosManos
    }
    
    
    //Convertir puntos normalizados a coordenadas de pantalla
    //Vision entrega puntos en coordenadas normalizadas (0–1)
    private func convertir(_ punto: VNRecognizedPoint, en size: CGSize) -> CGPoint {
        return CGPoint(
            x: punto.location.x * size.width,
            y: (1 - punto.location.y) * size.height // invertir Y para UIKit
        )
    }

    //Función para dibujar el esqueleto completo de la mano
    private func dibujarEsqueleto(para mano: VNHumanHandPoseObservation) {
        guard let view = previewVC?.view else { return }
        let size = view.bounds.size
        let shapeLayer = CAShapeLayer()
        let path = UIBezierPath()

        // Intentar obtener todos los puntos posibles
        guard let puntos = try? mano.recognizedPoints(.all) else { return }

        // Conexiones entre articulaciones (esqueleto)
        let conexiones: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
            (.wrist, .thumbCMC), (.thumbCMC, .thumbMP), (.thumbMP, .thumbIP), (.thumbIP, .thumbTip),
            (.wrist, .indexMCP), (.indexMCP, .indexPIP), (.indexPIP, .indexDIP), (.indexDIP, .indexTip),
            (.wrist, .middleMCP), (.middleMCP, .middlePIP), (.middlePIP, .middleDIP), (.middleDIP, .middleTip),
            (.wrist, .ringMCP), (.ringMCP, .ringPIP), (.ringPIP, .ringDIP), (.ringDIP, .ringTip),
            (.wrist, .littleMCP), (.littleMCP, .littlePIP), (.littlePIP, .littleDIP), (.littleDIP, .littleTip),
        ]

        // 🟦 Dibujar lineas del esqueleto
        for (a, b) in conexiones {
            if let p1 = puntos[a], p1.confidence > 0.3,
               let p2 = puntos[b], p2.confidence > 0.3 {

                let c1 = convertir(p1, en: size)
                let c2 = convertir(p2, en: size)

                path.move(to: c1)
                path.addLine(to: c2)
            }
        }

        // 🔵 También puedes dibujar nodos individuales (opcional)
        for (_, p) in puntos {
            if p.confidence > 0.3 {
                let c = convertir(p, en: size)
                let circle = UIBezierPath(ovalIn: CGRect(x: c.x-3, y: c.y-3, width: 6, height: 6))
                path.append(circle)
            }
        }

        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = UIColor.systemBlue.cgColor
        shapeLayer.fillColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        shapeLayer.lineWidth = 2
        shapeLayer.name = "handSkeleton"

        DispatchQueue.main.async {
            // Eliminar skeleton anterior para evitar capas acumuladas
            view.layer.sublayers?.removeAll(where: { $0.name == "handSkeleton" })
            view.layer.addSublayer(shapeLayer)
        }
    }

    
    // Procesar resultados de manos
    // Chris Alex modificar esta funcion para que haga uso del modelo
    private func procesarResultadosManos(request: VNRequest, error: Error?)
    {
        //request.results contiene el resultado del análisis de Vision.
        // VNHumanHandPoseObservation que es la lista de manos detectadas.
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
            dibujarEsqueleto(para: mano)
        }
        DispatchQueue.main.async
        {
            self.resultadoVision = textos.joined(separator: " | ")
        }
            
//        Recibe el resultado de Vision
//        Verifica si hay manos
//        Saca el pulgar e índice de cada mano
//        Calcula qué tan cerca están
//        Decide si es "👌 OK" o "🤚 Palma Abierta"
//        Actualiza la UI con el resultado
        
    }
}


nonisolated extension  CamaraController :  AVCaptureVideoDataOutputSampleBufferDelegate
{
    //procesar frames con vision
    //uando AVFoundation captura un frame, llama a esta función
     func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
    {
        
//        sampleBuffer = el frame crudo que da AVFoundation
//        Lo conviertes a pixelBuffer, que es el formato que Vision usa para procesar imágenes
//        Si no se puede convertir → simplemente saltas ese frame
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {return}
        
        //Calcular la orientación correcta del frame
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
        
//      Esta función recibe cada frame de la cámara, lo prepara para Vision y luego ejecuta la detección de manos usando las solicitudes configuradas. Es el puente entre AVFoundation y Vision.
    }
}




class CamaraPreviewViewController: UIViewController
{
    //es digamos el controlador de la vista a diferencia del del otro, su funcion es mostrar en pantalla el preview de la cámara usando un AVCaptureVideoPreviewLayer.
    var camaraController: CamaraController?
    var previewLayer: AVCaptureVideoPreviewLayer? //Es la capa que renderiza el video en vivo directamente desde AVCaptureSession.

    override func viewDidLoad()
    {
        super.viewDidLoad()
        view.backgroundColor = .black
//        Este método se llama cuando la vista se crea.
//        Solo pones el fondo negro (por si la cámara tarda en cargar).
        
            camaraController = CamaraController()
            camaraController?.previewVC = self 
            camaraController?.solicitarPermisos()

    }
    
    func agregarPreviewLayer(session: AVCaptureSession)
    {
//        “Rellena toda la pantalla con el video, aunque se recorte un poco”.
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
//        Este método se llama:
//        cuando rota el dispositivo
//        cuando cambia el tamaño de la vista
//        en cambios de layout en general
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
