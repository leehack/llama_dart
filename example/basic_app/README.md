# llamadart Basic Example

A simple console application demonstrating how to use `llamadart` with:
- Automatic model downloading (TinyLlama)
- Inference testing
- Clean architecture

## Run the Example

```bash
cd basic_app
dart pub get
dart run
```

This will:
1.  Download `TinyLlama-1.1B` to `tmp/` (if not already present).
2.  Initialize the `LlamaService`.
3.  Run a test inference prompt.

## Code Structure

- **`bin/llamadart_basic_example.dart`**: Entry point.
- **`lib/model_downloader.dart`**: Handles automatic model downloading.
- **`lib/inference_test.dart`**: Encapsulates the inference logic and validation.

## Running with Docker (Linux Verification)

You can verify the application on Linux using the centralized Docker environment:

```bash
# Run from the project root
./docker/build-docker.sh basic-run
```

This ensures a consistent environment with all necessary Linux dependencies.

## Troubleshooting

**"Failed to load library"**:
Ensure you have built the project or are running in an environment where the native library is available.
