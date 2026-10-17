//
//  ContentView.swift
//  LiveSub
//
import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var speechRecognizer: SpeechRecognizer
    @ObservedObject var pipManager = PiPManager.shared
    @State private var isConnectedToBroadcast = false
    @State private var selectedLanguage = "en-US"
    @AppStorage("fontSize") private var fontSize: Double = 16.0

    private let supportedLocales = [
        ("English", "en-US"),
        ("Français", "fr-FR"),
        ("Español", "es-ES"),
        ("Deutsch", "de-DE"),
        ("日本語", "ja-JP")
    ]

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.12).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header Status Card
                        statusCard

                        // Subtitle Live Box
                        captionPreviewBox

                        // Action Controls
                        controlsGrid

                        // Settings & Customization
                        settingsSection

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }
            .navigationTitle("LiveSub")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Audio Capture")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(speechRecognizer.isRecognizing ? "Transcribing in real time" : "Ready to broadcast")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()

            // Native Broadcast Trigger
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 50, height: 50)
                    .shadow(color: .blue.opacity(0.4), radius: 8, x: 0, y: 4)

                BroadcastPickerRepresentable()
                    .frame(width: 48, height: 48)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var captionPreviewBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Live Captions Preview", systemImage: "text.bubble.fill")
                    .font(.subheadline.bold())
                    .foregroundColor(.gray)
                Spacer()
                Button(action: { speechRecognizer.clear() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.gray)
                }
            }

            Text(speechRecognizer.transcript.isEmpty ? "Tap the blue button to begin broadcasting audio from any app (YouTube, TikTok, Netflix, Podcasts)..." : speechRecognizer.transcript)
                .font(.system(size: CGFloat(fontSize), weight: .medium, design: .rounded))
                .foregroundColor(speechRecognizer.transcript.isEmpty ? .gray.opacity(0.7) : .white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 90)
                .padding(14)
                .background(Color.black.opacity(0.35))
                .cornerRadius(14)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var controlsGrid: some View {
        Button(action: { pipManager.togglePiP() }) {
            HStack {
                Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                    .font(.headline)
                Text(pipManager.isPiPActive ? "Exit Floating Subtitles" : "Open Floating Subtitles (PiP)")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.purple],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: .purple.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .foregroundColor(.white)

            // Language Selector
            HStack {
                Text("Transcription Language")
                    .foregroundColor(.white)
                Spacer()
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(supportedLocales, id: \.1) { name, code in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedLanguage) { newCode in
                    speechRecognizer.updateLocale(Locale(identifier: newCode))
                }
            }

            Divider().background(Color.white.opacity(0.1))

            // Subtitle Font Size Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Subtitle Text Size")
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(fontSize)) pt")
                        .foregroundColor(.gray)
                }
                Slider(value: $fontSize, in: 12...24, step: 1)
                    .tint(.blue)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
}
