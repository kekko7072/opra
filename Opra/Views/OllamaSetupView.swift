//
//  OllamaSetupView.swift
//  Opra
//
//  Created by Francesco Vezzani on 12/10/25.
//

import SwiftUI

struct OllamaSetupView: View {
    @ObservedObject var ollamaTTSManager: OllamaTTSManager
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalling = false
    @State private var installationProgress = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with close button
            HStack {
                Text("Ollama TTS Setup")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 20)
            
            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    // Status
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Status")
                            .font(.headline)
                        
                        HStack {
                            Image(systemName: ollamaTTSManager.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(ollamaTTSManager.isAvailable ? .green : .red)
                            
                            Text(ollamaTTSManager.isAvailable ? "Ollama is running" : "Ollama is not available")
                                .font(.subheadline)
                            
                            Spacer()
                            
                            if !ollamaTTSManager.isAvailable {
                                Button("Retry") {
                                    ollamaTTSManager.retryConnection()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(ollamaTTSManager.isRetrying)
                            }
                        }
                        
                        if let error = ollamaTTSManager.errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(8)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(4)
                                
                                if error.contains("not running") || error.contains("CannotConnectToHost") {
                                    Text("💡 Tip: Make sure Ollama is installed and running. Try running 'ollama serve' in Terminal.")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Installation Instructions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Installation Instructions")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("1. Install Ollama:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("Visit ollama.ai and download Ollama for macOS")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Open Documentation") {
                                    if let url = URL(string: "https://ollama.ai") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text("2. Start Ollama:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("Run 'ollama serve' in Terminal or start the Ollama app")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Open Terminal") {
                                    let script = "tell application \"Terminal\" to activate"
                                    let appleScript = NSAppleScript(source: script)
                                    appleScript?.executeAndReturnError(nil)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            Text("3. Install Orpheus Model:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("Run this command in Terminal:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Button("Copy Command") {
                                    let command = "ollama pull sematre/orpheus:en"
                                    let pasteboard = NSPasteboard.general
                                    pasteboard.clearContents()
                                    pasteboard.setString(command, forType: .string)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ollama pull sematre/orpheus:en")
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .cornerRadius(4)
                            }
                            
                            Text("Note: sematre/orpheus:en is the only supported TTS model for Ollama integration.")
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                    
                    Divider()
                    
                    // Available Models
                    if !ollamaTTSManager.availableModels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Available Models")
                                .font(.headline)
                            
                            List(ollamaTTSManager.availableModels, id: \.self) { model in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model)
                                            .font(.subheadline)
                                        
                                        // Show model type
                                        let isOrpheusModel = model.contains("sematre/orpheus")
                                        
                                        Text(isOrpheusModel ? "Supported TTS Model" : "Unsupported Model")
                                            .font(.caption2)
                                            .foregroundColor(isOrpheusModel ? .green : .red)
                                    }
                                    
                                    Spacer()
                                    
                                    if model == ollamaTTSManager.selectedModel {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    ollamaTTSManager.setModel(model)
                                }
                            }
                            .frame(height: 150)
                        }
                    }
                    
                    // Install Model
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Install Orpheus Model")
                            .font(.headline)
                        
                        HStack {
                            TextField("Model name", text: .constant("sematre/orpheus:en"))
                                .textFieldStyle(.roundedBorder)
                                .disabled(true)
                            
                            Button("Install") {
                                installModel("sematre/orpheus:en")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isInstalling)
                        }
                        
                        if isInstalling {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(installationProgress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                }
                
                // Footer with refresh button
                HStack {
                    Button("Refresh") {
                        ollamaTTSManager.checkOllamaAvailability()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
        }
    }
    
    func installModel(_ modelName: String) {
        isInstalling = true
        installationProgress = "Installing \(modelName)..."
        
        ollamaTTSManager.installModel(modelName) { success in
            DispatchQueue.main.async {
                isInstalling = false
                if success {
                    installationProgress = "\(modelName) installed successfully!"
                } else {
                    installationProgress = "Failed to install \(modelName)"
                }
            }
        }
    }
}
