//
//  ContentView.swift
//  Ubicuo
//
//  Created by Ivan Mijares on 13/03/26.
//

import SwiftUI

//reusable
struct MenuCard<Icon:View>:View
{
    let icon: ()-> Icon
    let label: String
    
    var body: some View {
            VStack(spacing: 14) {
                icon().foregroundColor(.primary)
                Text(label)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1.5)
            )
            .cornerRadius(16)
            // Opcional: asegura que todo el card sea “tappable”
            .contentShape(Rectangle())
        }

}


struct ContentView: View
{
    var body: some View
    {
        NavigationStack
        {
            VStack
            {
                
                VStack(spacing:20)
                {
                    Spacer()
                    
                    //card1
                    NavigationLink(destination:PerfilView())
                    {
                        MenuCard(
                            icon:
                                {
                                    AnyView(
                                        ZStack(alignment: .bottomTrailing)
                                        {
                                            Image(systemName:"hand.raised")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width:53,height:52)
                                            Image(systemName:"gearshape.fill")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width:22,height:22)
                                                .offset(x:8, y:8)
                                        }
                                    )
                                },
                            label:"Gestionar tus gestos"
                        )
                    }
                    
                    
                    //activar camara
                    NavigationLink(destination:Camara())
                    {
                        MenuCard(
                            icon:
                                {
                                    AnyView(
                                        Image(systemName:"camera")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width:53,height:52)
                                    )
                                },
                            label:"Activar cámara"
                        )
                    }
                    
                    
                    Spacer()
                }.padding(.horizontal,24)
            }.navigationTitle("Hand Tracking")
                .navigationBarTitleDisplayMode(.large)
                .toolbar
                {
                    ToolbarItem(placement: .navigationBarLeading)
                    {
                        Button(action: {})
                        {
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.primary)
                        }
                    }
                }
        }
    }
}



struct PerfilView: View
{
    var body: some View
    {
        Text("Gestionr Gestos")
    }
}

struct Camara: View
{
    var body: some View
    {
        Text("Camara")
    }
}





#Preview {
    ContentView()
}
