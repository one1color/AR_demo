//
//  ViewController.swift
//  AR_demo
//
//  Created by koki isshiki on 09.06.20.
//  Copyright © 2020 koki isshiki. All rights reserved.

import UIKit
import RealityKit
import ARKit
import MultipeerSession

class ViewController: UIViewController {
    
    @IBOutlet var arView: ARView!
    @IBOutlet weak var statusMessage: StatusMessage!
    
    var multipeerSession: MultipeerSession?
    var sessionIDObservation: NSKeyValueObservation?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        arView.automaticallyConfigureSession = false //creating and setting up my configuration
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal] //to detect horizontal ebene
        config.environmentTexturing = .automatic //Enable realistic reflection
        config.isCollaborationEnabled = true //Enable a collaborativve session
        arView.session.run(config)
        statusMessage.displayMessage("Hello! Tap your screen to put ball in AR Space.")
        setupMultipeerSession()
        
        arView.session.delegate = self
        
        //Recognize the tap of screen and
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(onTap(recognizer:)))
        arView.addGestureRecognizer(tapGestureRecognizer)
        
    }
    
    
    func setupMultipeerSession() {
        //Set up key-Value to identify the ARSession's User.
        sessionIDObservation = observe(\.arView.session.identifier, options: [.new]) { object, change in
            print("SessionID changed to: \(change.newValue!)")
            guard let multipeerSession = self.multipeerSession else {return}
            self.sendARSessionIDTo(peers: multipeerSession.connectedPeers)
        }
        
        // Start looking for other players via MultiPeerConnectivity.
        multipeerSession = MultipeerSession(serviceName: "multiuser-ar", receivedDataHandler: self.recievedData, peerJoinedHandler: self.peerJoined, peerLeftHandler: self.peerLeft, peerDiscoveredHandler: self.peerDiscovered)
    }
    
    //function what will happen when the screen is tapped
    @objc func onTap(recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: arView)
        //try to find a 3D location on a horizontal surface where the user has touch.
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .horizontal)
        
        if let firstResult = results.first{
            //add Anchor calls "objectPlacement" at a location where is touched
            let anchor = ARAnchor(name: "objectPlacement", transform: firstResult.worldTransform)
            arView.session.add(anchor: anchor)
        } else {
            //if the surface is not detected, we can't put the object. -> error status message on display
            statusMessage.displayMessage("Can't place object! Please try to detect surface.")
        }
    }
}


extension ViewController: ARSessionDelegate {
    //session control: if nother user has been participated, add their anchor into the ARView
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            
            if let participantAnchor = anchor as? ARParticipantAnchor {
                print("connected with another User! let's share the AR space")
                statusMessage.displayMessage("Well done! Connected with another User, Let's get started to share AR experience!")
                
                let anchorEntity = AnchorEntity(anchor: participantAnchor)
                
                arView.scene.addAnchor(anchorEntity)
            //in anycase call crateObject to create "hello" into the ARworld as long as the anchor calls "objectPlacement"
            }else if let anchorName = anchor.name, anchorName == "objectPlacement"{
                createObject(named: anchorName, for: anchor)
            }
        }
    }
    
    //create object which will appear in the scene. I made box and text version.
    func createObject(named entityName: String, for anchor: ARAnchor) {
        
        //create box
        /*
         let boxLength: Float = 0.05
         let color = UIColor.orange
         let coloredCube = ModelEntity(mesh: MeshResource.generateBox(size: boxLength),
         materials: [SimpleMaterial(color: color, isMetallic: true)])
         
         let anchorEntity = AnchorEntity(anchor: anchor)
         anchorEntity.addChild(coloredCube)
         */
        
        //create "Hello" text
        let textMesh = MeshResource.generateText(
            "Hello!",
            extrusionDepth: 0.1,
            font: .systemFont(ofSize: 1.5),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail)
        let textMaterial = SimpleMaterial(color: UIColor.white, roughness: 0.0, isMetallic: true)
        let textModel = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textModel.scale = SIMD3<Float>(0.1, 0.1, 0.1) //scaledown because it's too big
        let anchorEntity = AnchorEntity(anchor: anchor)
        
        anchorEntity.addChild(textModel)
        arView.scene.addAnchor(anchorEntity) //add AR scene
        
    }
}

// For MultipeerSession: most of code is referenced to Apple official sample code
extension ViewController {
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        guard let multipeerSession = multipeerSession else { return }
        if !multipeerSession.connectedPeers.isEmpty {
            guard let encodedData = try? NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
                else { fatalError("Unexpectedly failed to encode collaboration data.") }
            // Use reliable mode if the data is critical, and unreliable mode if the data is optional.
            let dataIsCritical = data.priority == .critical
            multipeerSession.sendToAllPeers(encodedData, reliably: dataIsCritical)
        } else {
            print("Deferred sending collaboration to later because there are no peers.")
        }
    }

    private func sendARSessionIDTo(peers: [PeerID]) {
        guard let multipeerSession = multipeerSession else {return}
        let idString = arView.session.identifier.uuidString
        let command = "SessionID:" + idString
        if let commandData = command.data(using: .utf8) {
            multipeerSession.sendToPeers(commandData, reliably: true, peers: peers)
        }
    }
    
    func recievedData(_ data: Data, from peer: PeerID) {
        guard let multipeerSession = multipeerSession else {return}
        
        if let collaborationData = try? NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: data) {
            arView.session.update(with: collaborationData)
            return
        }
        // ...
        let sessionIDCommandString = "SessionID:"
        if let commandString = String(data: data, encoding: .utf8), commandString.starts(with: sessionIDCommandString) {
            let newSessionID = String(commandString[commandString.index(commandString.startIndex, offsetBy: sessionIDCommandString.count)...])
            // If this peer was using a different session ID before, remove all its associated anchors.
            // This will remove the old participant anchor and its geometry from the scene.
            if let oldSessionID = multipeerSession.peerSessionIDs[peer] {
                removeAllAnchorsOriginatingFromARSessionWithID(oldSessionID)
            }
            
            multipeerSession.peerSessionIDs[peer] = newSessionID
        }
    }
    
    
    func peerDiscovered(_ peer: PeerID) -> Bool {
        guard let multipeerSession = multipeerSession else { return false }
        
        if multipeerSession.connectedPeers.count > 3 {
            // Do not accept more than four users in the ecperoence.
            print("A forth player wants to join.\nThe game is currently limited to three players.")
            return false
        } else {
            return true
        }
    }
    
    
    func peerJoined(_ peer: PeerID) {
        print("""
            A player wants to join the game.
            Hold the devices next to each other.
            """)
        // Provide your session ID to the new user so they can keep track of your ancohrs.
        sendARSessionIDTo(peers: [peer])
    }

    func peerLeft(_ peer: PeerID) {
        guard let multipeerSession = multipeerSession else { return }
        
        print("A player has left the game.")
        
        // Remove all ARAnchors associated with the peer that just left the experience.
        if let sessionID = multipeerSession.peerSessionIDs[peer] {
            removeAllAnchorsOriginatingFromARSessionWithID(sessionID)
            multipeerSession.peerSessionIDs.removeValue(forKey: peer)
        }
    }
    
    private func removeAllAnchorsOriginatingFromARSessionWithID(_ identifier: String) {
        guard let frame = arView.session.currentFrame else { return }
        for anchor in frame.anchors {
            guard let anchorSessionID = anchor.sessionIdentifier else { continue }
            if anchorSessionID.uuidString == identifier {
                arView.session.remove(anchor: anchor)
            }
            
        }
    }
}
