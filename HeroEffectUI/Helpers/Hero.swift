//
//  Hero.swift
//  HeroEffectUI
//
//  Created by EstrHuP on 2/2/24.
//

import SwiftUI

struct HeroWrapper<Content: View>: View {
    
    @ViewBuilder var content: Content
    
    @Environment(\.scenePhase) private var scene
    @State private var overlayWindow: PasstroughWindow?
    @StateObject private var heroModel: HeroModel = .init()
    
    var body: some View {
        content.customOnChange(value: scene) { newValue in
            if newValue == .active { addOverlayWindow() }
        }
        .environmentObject(heroModel)
    }
    
    func addOverlayWindow() {
        UIApplication.shared.connectedScenes.forEach { scene in
            if let windowScene = scene as? UIWindowScene, scene.activationState == .foregroundActive, overlayWindow == nil {
                let window = PasstroughWindow(windowScene: windowScene)
                window.backgroundColor = .clear
                window.isUserInteractionEnabled = true
                window.isHidden = false
                
                let rootController = UIHostingController(rootView: HeroLayerView().environmentObject(heroModel))
                rootController.view.frame = windowScene.screen.bounds
                rootController.view.backgroundColor = .clear
                
                window.rootViewController = rootController
                
                self.overlayWindow = window
            }
        }
        
        if overlayWindow == nil {
            print("No window scene found")
        }
    }
}

struct SourceView<Content: View>: View {
    
    let id: String
    
    @EnvironmentObject private var heroModel: HeroModel
    @ViewBuilder var content: Content
    
    var index: Int? {
        if let index = heroModel.info.firstIndex(where: { $0.infoID == id }) {
            return index
        }
        return nil
    }
    
    var opacity: CGFloat {
        if let index {
            return heroModel.info[index].isActive ? 0 : 1
        }
        return 1
    }
    
    var body: some View {
        content
            .opacity(opacity)
            .anchorPreference(key: AnchorKey.self, value: .bounds) { anchor in
                ///ID is active, we will be returning its anchor value for handling the animation
                if let index, heroModel.info[index].isActive {
                    return [id: anchor]
                }
                return [:]
            }
        .onPreferenceChange(AnchorKey.self) { value in
            if let index, heroModel.info[index].isActive, heroModel.info[index].sourceAnchor == nil {
                heroModel.info[index].sourceAnchor = value[id]
            }
        }
    }
}

fileprivate struct HeroLayerView: View {
    
    @EnvironmentObject private var heroModel: HeroModel
    
    var body: some View {
        GeometryReader { proxy in
            ForEach($heroModel.info) { $info in
                ZStack {
                    if let sourceAnchor = info.sourceAnchor,
                       let destinationAnchor = info.destinationAnchor,
                       let layerView = info.layerView,
                       !info.hideView {
                        /// Retreving Bounds data from the anchor values
                        let sRect = proxy[sourceAnchor]
                        let dRect = proxy[destinationAnchor]
                        let animateView = info.animateView
                        
                        let size = CGSize(
                            width: animateView ? dRect.size.width : sRect.size.width,
                            height: animateView ? dRect.size.height : sRect.size.height
                        )
                        
                        //Position
                        let offset = CGSize(
                            width: animateView ? dRect.minX : sRect.minX,
                            height: animateView ? dRect.minY : sRect.minY
                        )
                        
                        layerView
                            .frame(width: size.width, height: size.height)
                            .clipShape(.rect(cornerRadius: animateView ? info.dCornerRadius : info.sCornerRadius))
                            .offset(offset)
                            .transition(.identity)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .customOnChange(value: info.hideView) { newValue in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        if !newValue {
                            /// Reseting all data once the view goes back to it's source state
                            info.isActive = false
                            info.layerView = nil
                            info.sourceAnchor = nil
                            info.destinationAnchor = nil
                            info.sCornerRadius = .zero
                            info.dCornerRadius = .zero
                            info.completion(false)
                        } else {
                            info.hideView = true
                            info.completion(true)
                        }
                    }
                }
            }
        }
    }
}

// Environment object
fileprivate class HeroModel: ObservableObject {
    @Published var info: [HeroInfo] = []
}

// Individual Hero Animation View Info
/// This will contain all the necessary information about each hero effect
fileprivate struct HeroInfo: Identifiable {
    private(set) var id: UUID = .init()
    private(set) var infoID: String
    var isActive: Bool = false
    var layerView: AnyView?
    var animateView: Bool = false
    var hideView: Bool = false
    var sourceAnchor: Anchor<CGRect>?
    var destinationAnchor: Anchor<CGRect>?
    var sCornerRadius: CGFloat = 0
    var dCornerRadius: CGFloat = 0
    var completion: (Bool) -> () = { _ in }
    
    init(id: String) {
        self.infoID = id
    }
}

fileprivate struct AnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String : Anchor<CGRect>], nextValue: () -> [String : Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}


struct DestinationView<Content: View>: View {
    
    var id: String
    
    @EnvironmentObject private var heroModel: HeroModel
    @ViewBuilder var content: Content
    
    var index: Int? {
        if let index = heroModel.info.firstIndex(where: { $0.infoID == id }) {
            return index
        }
        return nil
    }
    
    var opacity: CGFloat {
        if let index {
            /// The destination view will be available once the animation layer view is hidden.
            /// Update: Replace the 0 at the end of the ternary operator with 1
            return heroModel.info[index].isActive ? (heroModel.info[index].hideView ? 1 : 0) : 1
        }
        return 1
    }
    
    var body: some View {
        content
            .opacity(opacity)
            .anchorPreference(key: AnchorKey.self, value: .bounds) { anchor in
            ///ID is active, we will be returning its anchor value for handling the animation
            if let index, heroModel.info[index].isActive {
                return ["\(id)DESTINATION": anchor]
            }
            return [:]
        }
        .onPreferenceChange(AnchorKey.self) { value in
            if let index, heroModel.info[index].isActive {
                heroModel.info[index].destinationAnchor = value[id]
            }
        }
    }
}

extension View {
    
    @ViewBuilder
    func customOnChange<Value: Equatable>(value: Value, completion: @escaping (Value) -> ()) -> some View {
        if #available(iOS 17, *) {
            self.onChange(of: value) { oldValue, newValue in
                completion(newValue)
            }
        } else {
            self.onChange(of: value, perform: { value in
                completion(value)
            })
        }
    }
    
    @ViewBuilder
    func heroLayer<Content: View>(id: String,
                                  animate: Binding<Bool>,
                                  sourceCornerRadius: CGFloat = 0,
                                  destinationCornerRadius: CGFloat = 0,
                                  @ViewBuilder content: @escaping () -> Content,
                                  completion: @escaping (Bool) -> ())
    -> some View {
        self
            .modifier(HeroLayerViewModifier(id: id,
                                            animate: animate,
                                            sourceCornerRadius: sourceCornerRadius,
                                            destinationCornerRadius: destinationCornerRadius,
                                            layer: content,
                                            completion: completion))
    }
}

fileprivate struct HeroLayerViewModifier<Layer: View>: ViewModifier {
    let id: String
    @Binding var animate: Bool
    var sourceCornerRadius: CGFloat
    var destinationCornerRadius: CGFloat
    @ViewBuilder var layer: Layer
    var completion: (Bool) -> ()
    
    ///Hero Model
    @EnvironmentObject private var heroModel: HeroModel
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                if !heroModel.info.contains(where: { $0.infoID == id }) {
                    heroModel.info.append(.init(id: id))
                }
            }
            .customOnChange(value: animate) { newValue in
                if let index = heroModel.info.firstIndex(where: { $0.infoID == id }) {
                    /// Setting up all the necessary properties for the animation
                    heroModel.info[index].isActive = true
                    heroModel.info[index].layerView = AnyView(layer)
                    heroModel.info[index].sCornerRadius = sourceCornerRadius
                    heroModel.info[index].dCornerRadius = destinationCornerRadius
                    heroModel.info[index].completion = completion
                    
                    if newValue {
                        /// The reason for the delay is for the destination view to get loaded into the scfreen for reading its anchor values
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                            withAnimation(.snappy(duration: 0.35, extraBounce: .zero)) {
                                heroModel.info[index].animateView = true
                            }
                        }
                    } else {
                        heroModel.info[index].hideView = false
                        withAnimation(.snappy(duration: 0.45, extraBounce: .zero)) {
                            heroModel.info[index].animateView = false
                        }
                    }
                }
            }
    }
}


fileprivate class PasstroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let view = super.hitTest(point, with: event) else  { return nil }
        return rootViewController?.view == view ? nil : view
    }
}
