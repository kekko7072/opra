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
                
                // Text Processing
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text Processing")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Chunk Size (words)")
                                .font(.subheadline)
                            
                            Spacer()
                            
                            TextField("Chunk Size", value: $settingsManager.chunkSize, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .onChange(of: settingsManager.chunkSize) { _, newValue in
                                    settingsManager.setChunkSize(newValue)
                                }
                        }
                        
                        Text("Large texts will be split into chunks to prevent crashes. Default: 10,000 words")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                
                Divider()
                
                // Personal Voice & SSML Features
                VStack(alignment: .leading, spacing: 12) {
                    Text("Advanced Speech Features")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        // Personal Voice Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Personal Voice")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                
                                Spacer()
                                
                                if ttsProviderManager.isPersonalVoiceAuthorized {
                                    Text("✓ Authorized")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        .fontWeight(.medium)
                                } else {
                                    Button("Request Access") {
                                        ttsProviderManager.requestPersonalVoiceAuthorization()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            Text("Status: \(ttsProviderManager.personalVoiceStatus)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Personal Voice allows you to use your own voice for text-to-speech. Requires microphone access permission.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // SSML Section
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("SSML Markup (Advanced)", isOn: $settingsManager.enableSSML)
                                .onChange(of: settingsManager.enableSSML) { _, newValue in
                                    settingsManager.setSSMLEnabled(newValue)
                                    ttsProviderManager.setSSMLEnabled(newValue)
                                }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("SSML (Speech Synthesis Markup Language) provides advanced control over speech synthesis")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("When enabled, speech rate, pitch, and voice settings are controlled via SSML markup instead of AVSpeechUtterance properties.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 20)
                        }
                    }
                }
                
                Divider()
                
                // Experimental Features
                VStack(alignment: .leading, spacing: 12) {
                    Text("Experimental Features")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Follow Text (Experimental)", isOn: $settingsManager.enableFollowText)
                            .onChange(of: settingsManager.enableFollowText) { _, newValue in
                                settingsManager.setEnableFollowText(newValue)
                            }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("⚠️ This feature is experimental and may be buggy")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fontWeight(.medium)
                            
                            Text("Highlights the currently spoken word in the text. May cause performance issues or incorrect highlighting.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
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
