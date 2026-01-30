# llamadart Chat Example

A Flutter chat application demonstrating real-world usage of llamadart with UI.

## Features

- 🦙 Real-time chat with local LLM
- 📱 Material Design 3 UI
- ⚙️ Model configuration (path, backend selection)
- 💾 Settings persistence
- 🔄 Streaming generation
- 🎨 User and AI message bubbles

## Setup

### 1. Download a Model
```bash
# For macOS/Linux
mkdir -p /tmp/models
curl -L https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf \
  -o /tmp/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf

# For Android
# Download and place in /storage/emulated/0/Download/
```

### 2. Run the App
```bash
cd chat_app
flutter pub get
flutter run
```

### 3. Configure
1. Tap the settings icon (⚙️) in the app bar
2. Set your model path
3. Select Preferred Backend (Auto/Metal/Vulkan/CPU)
4. Tap "Load Model"
5. Start chatting!

## Testing Scenarios

### Scenario 1: Fresh Install
1. Install the app
2. Model not loaded -> Show welcome screen
3. Configure and load model
4. Verify it works

### Scenario 2: App Restart
1. Load model and chat
2. Close and reopen app
3. Verify settings persist
4. Verify model reloads automatically

### Scenario 3: Offline Mode
1. Use app once (downloads libraries)
2. Disconnect internet
3. Restart app
4. Verify it works offline

### Scenario 4: Multiple Messages
1. Load model
2. Send multiple messages
3. Verify responses
4. Check context is maintained

## Architecture

The app follows a clean architecture with state management:

```
lib/
├── main.dart              # App entry point
├── chat_screen.dart       # Main chat UI
├── models/
│   └── chat_model.dart    # State management (Provider)
├── screens/
│   └── model_selection_screen.dart # Model downloader & selector
└── stub/
    └── io_stub.dart       # Platform stubs for web compatibility
```

### ChatProvider
State management provider using `ChangeNotifier`:
- Manages model lifecycle (load/unload)
- Handles chat messages
- Persists settings to SharedPreferences
- Provides reactive UI updates

### ChatScreen
Flutter UI with Material Design 3:
- Message list with scroll-to-bottom
- Input field with send button
- Settings modal for model configuration
- Loading and error states

## Code Examples

### Loading a Model
```dart
final service = LlamaService();
await service.init(
  modelPath,
  modelParams: ModelParams(
    gpuLayers: 99, // Offload all layers for best performance on GPU
    contextSize: 2048,
    preferredBackend: GpuBackend.auto,
  ),
);
```

### Sending a Message
```dart
final stream = service.generate(
  userMessage,
  params: GenerationParams(
    maxTokens: 128,
    temp: 0.7,
  ),
);

await for (final token in stream) {
  print(token);
}
```

### Persisting Settings
```dart
final prefs = await SharedPreferences.getInstance();
await prefs.setString('model_path', modelPath);
await prefs.setString('model_path', modelPath);
await prefs.setInt('preferred_backend', backendIndex);
```

## Screenshots

_(Add screenshots here when complete)_

## Troubleshooting

**"Failed to load library" on first run:**
- Check console for download messages
- Ensure GitHub releases are accessible
- Check internet connection

**"Model file not found" error:**
- Verify model path in settings
- Ensure model is downloaded
- Check file permissions

**Slow generation:**
- Ensure hardware acceleration is enabled in settings
- Use smaller quantization model (Q4_K_M)

**App crashes on startup:**
- Check console output for error messages
- Verify llamadart dependency is correctly configured
- Ensure Flutter version >= 3.10.0

## Tech Stack

- **llamadart** - LLM inference
- **Provider** - State management
- **shared_preferences** - Settings persistence
- **Material Design 3** - UI components

## Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| macOS    | ✅ Tested | Full support |
| Linux    | ✅ Tested | Full support |
| Windows  | 🟡 Expected | Should work |
| Android  | ✅ Verified | Full Vulkan acceleration |
| iOS      | ✅ Verified | Full Metal acceleration |

## Future Enhancements

- [ ] Conversation history
- [ ] Multiple model support
- [ ] Export/import conversations
- [ ] Streaming token display in UI
- [ ] Custom system prompts
- [ ] Temperature/top_p controls in UI
- [ ] Dark mode theme
