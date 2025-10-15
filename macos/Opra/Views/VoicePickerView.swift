//
//  VoicePickerView.swift
//  Opra
//
//  Created by Francesco Vezzani on 12/10/25.
//

import SwiftUI
import AVFoundation

struct VoicePickerView: View {
    @ObservedObject var ttsManager: TextToSpeechManager
    @Environment(\.dismiss) private var dismiss
    @State private var previewingVoice: AVSpeechSynthesisVoice?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Select Voice")
                .font(.headline)
            
            List(ttsManager.availableVoices, id: \.identifier) { voice in
                HStack {
                    VStack(alignment: .leading) {
                        Text(voice.name)
                            .font(.headline)
                        Text(voice.language)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button("Preview") {
                            previewingVoice = voice
                            ttsManager.previewVoice(voice)
                        }
                        .buttonStyle(.bordered)
                        .disabled(ttsManager.isSpeaking && previewingVoice?.identifier != voice.identifier)
                        
                        if voice.identifier == ttsManager.currentVoice?.identifier {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    ttsManager.setVoice(voice)
                }
            }
            
            HStack {
                if ttsManager.isSpeaking && previewingVoice != nil {
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundColor(.green)
                        Text("Previewing \(previewingVoice?.name ?? "voice")...")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                
                Spacer()
                
                Button("Stop Preview") {
                    ttsManager.stopSpeaking()
                    previewingVoice = nil
                }
                .buttonStyle(.bordered)
                .disabled(!ttsManager.isSpeaking)
                
                Button("Done") {
                    ttsManager.stopSpeaking()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 450, height: 400)
    }
}
