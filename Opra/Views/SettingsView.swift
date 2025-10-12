//
//  SettingsView.swift
//  Opra
//
//  Created by Francesco Vezzani on 12/10/25.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var ttsProviderManager: TTSProviderManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingVoicePicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                // TTS Provider Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text-to-Speech Provider")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Picker("TTS Provider", selection: $ttsProviderManager.currentProvider) {
                        ForEach(TTSProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: ttsProviderManager.currentProvider) { _, newProvider in
                        ttsProviderManager.setProvider(newProvider)
                    }
                    
                    Text(ttsProviderManager.currentProvider.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Speech Rate
                VStack(alignment: .leading, spacing: 12) {
                    Text("Speech Rate")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Slow")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Slider(value: $settingsManager.speechRate, in: 0.1...1.0, step: 0.05)
                            .onChange(of: settingsManager.speechRate) { _, newValue in
                                settingsManager.setSpeechRate(newValue)
                                ttsProviderManager.setSpeechRate(newValue)
                            }
                        
                        Text("Fast")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Button("Preview Speed") {
                            ttsProviderManager.previewSpeed(settingsManager.speechRate)
                        }
                        .buttonStyle(.bordered)
                        .disabled(ttsProviderManager.isSpeaking)
                        
                        if ttsProviderManager.isSpeaking {
                            HStack {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundColor(.green)
                                Text("Previewing speed...")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    Text("\(Int(settingsManager.speechRate * 100))%")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Divider()
                
                // Voice Selection (only for System TTS)
                if ttsProviderManager.currentProvider == .system {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Voice")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ttsProviderManager.currentVoice?.name ?? "Default Voice")
                                    .font(.subheadline)
                                Text(ttsProviderManager.currentVoice?.language ?? "en-US")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("Change Voice") {
                                showingVoicePicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                } else {
                    // Ollama Model Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ollama Model")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text(ttsProviderManager.ollamaTTSManager.selectedModel.isEmpty ? "No model selected" : ttsProviderManager.ollamaTTSManager.selectedModel)
                                    .font(.subheadline)
                                Text(ttsProviderManager.ollamaTTSManager.isAvailable ? "Ollama connected" : "Ollama not available")
                                    .font(.caption)
                                    .foregroundColor(ttsProviderManager.ollamaTTSManager.isAvailable ? .green : .red)
                            }
                            
                            Spacer()
                            
                            Button("Setup Ollama") {
                                // This will be handled by the main view
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }
                }
                
                Divider()
                
                // Preferences
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preferences")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Toggle("Auto-start reading after page selection", isOn: $settingsManager.autoStartReading)
                        .onChange(of: settingsManager.autoStartReading) { _, newValue in
                            settingsManager.setAutoStartReading(newValue)
                        }
                }
                }
            }
        }
        .padding(30)
        .sheet(isPresented: $showingVoicePicker) {
            VoicePickerView(ttsManager: ttsProviderManager.systemTTSManager)
        }
    }
}
