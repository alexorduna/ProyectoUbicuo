//
//  PerfilView.swift
//  Ubicuo
//
//  Created by Ivan Mijares on 19/03/26.
//

import SwiftUI
import Combine

struct Gesto : Identifiable
{
    let id: Int
    var frase: String
    var icono: String
}

class GestorViewModel: ObservableObject
{
    @Published var gestos: [Gesto] = []
    
    private let totalGestos = 8
    
    private let iconos = [
        "👎",  // 0 dislike
        "✊",  // 1 fist
        "👍",  // 2 like
        "👌",  // 3 ok
        "☝️",  // 4 one
        "✋",  // 5 palm
        "✌️",  // 6 peace
        "🤘"   // 7 rock
    ]
    
    init()
    {
        cargarGestos()
    }
    
    func cargarGestos()
    {
        gestos = (1...totalGestos).map
        {
            i in let fraseGuardada = UserDefaults.standard.string(forKey: "gesto_\(i)")
            return Gesto(id: i, frase: fraseGuardada ?? "Frase de gesto \(i)", icono: iconos[i-1])
        }
    }
    
    func guardarCambios()
    {
        for gesto in gestos
        {
            UserDefaults.standard.set(gesto.frase, forKey: "gesto_\(gesto.id)")
        }
    }
    
    func actualizarFrase(id: Int, nuevaFrase: String)
    {
        if let index = gestos.firstIndex(where: { $0.id == id })
        {
            gestos[index].frase = nuevaFrase
        }
    }
}

struct GestionDeGestosView: View
{
    @StateObject private var viewModel = GestorViewModel()
    @State private var mostrarConfirmacion = false
    
    var body: some View
    {
        VStack(spacing: 0)
        {
            ScrollView
            {
                VStack(spacing: 12)
                {
                    ForEach($viewModel.gestos)
                    {
                        $gesto in GestoRow(gesto: $gesto)
                    }
                }
            }
            
            VStack()
            {
                Button(action: {
                    viewModel.guardarCambios()
                    mostrarConfirmacion = true
                })
                {
                    Text("Guardar cambios")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary, lineWidth: 1.5))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Color(.systemBackground).shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: -2))
        }
        .navigationTitle("Gestión de gestos")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Guardado!", isPresented: $mostrarConfirmacion) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Tus frases han sido guardadas correctamente.")
        }
        .padding(15)
    }
}

struct GestoRow: View
{
    @Binding var gesto: Gesto
    @State private var editando = false
    @FocusState private var campoActivo: Bool
    
    var body: some View
    {
        HStack(spacing: 12)
        {
            Text("\(gesto.id)")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 20, alignment: .trailing)
                .foregroundColor(.secondary)
            
            Text(gesto.icono)
                .scaledToFit()
                .frame(width: 28, height: 28)
            
            TextField("Frase para Gesto \(gesto.id)", text: $gesto.frase)
                .font(.system(size: 15))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .focused($campoActivo)
                .submitLabel(.done)
                .onSubmit {
                    editando = false
                    campoActivo = false
                }
            
            Button(action: {
                editando = true
                campoActivo = true
            }) {
                Image(systemName: editando && campoActivo ? "checkmark.circle.fill" : "pencil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundColor(editando && campoActivo ? .green : .primary)
                    .animation(.easeInOut(duration: 0.2), value: campoActivo)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview
{
    NavigationStack {
        GestionDeGestosView()
    }
}
