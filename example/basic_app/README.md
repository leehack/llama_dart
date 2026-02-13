# llamadart CLI Chat Example

A clean, organized CLI application demonstrating the capabilities of the `llamadart` package. It supports both interactive conversation mode and single-response mode.

## Features

- **Interactive Mode**: Have a back-and-forth conversation with an LLM in your terminal.
- **Single Response Mode**: Pass a prompt as an argument for quick tasks.
- **Automatic Model Management**: Automatically downloads models from Hugging Face if a URL is provided.
- **Backend Optimization**: Defaults to GPU acceleration (Metal/Vulkan) when available.
- **LoRA Adapters**: Load one or more LoRA adapters with repeated `--lora` flags.
- **Structured Output**: Pass `--grammar` for GBNF-constrained generation.
- **Tool Calling Test Mode**: Enable `--tool-test` to exercise function-calling flow.
- **Sampling Controls**: Tune `--temp`, `--top-k`, `--top-p`, and `--penalty`.

## Usage

First, ensure you have the Dart SDK installed.

### 1. Install Dependencies

```bash
dart pub get
```

### 2. Run Interactive Mode (Default)

This will download a small default model (Qwen 2.5 0.5B) if not already present and start a chat session.

```bash
dart run
```

### 3. Run with a Specific Model

You can provide a local path or a Hugging Face GGUF URL.

```bash
dart run -- -m "path/to/model.gguf"
```

### 4. Single Response Mode

Useful for scripting or quick queries.

```bash
dart run -- -p "What is the capital of France?"
```

## Options

- `-m, --model`: Path or URL to the GGUF model file.
- `-l, --lora`: Path to LoRA adapter(s). Can be set multiple times.
- `-p, --prompt`: Prompt for single response mode.
- `-i, --interactive`: Start in interactive mode (default if no prompt provided).
- `-g, --log`: Enable native engine logging output (defaults to off).
- `-G, --grammar`: GBNF grammar string for constrained output.
- `-t, --tool-test`: Enables sample `get_weather` tool-calling flow.
- `--temp`: Temperature (default `0.8`).
- `--top-k`: Top-k sampling (default `40`).
- `--top-p`: Top-p sampling (default `0.95`).
- `--penalty`: Repeat penalty (default `1.1`).
- `-h, --help`: Show help message.

## Tests

Run the basic app test suite with:

```bash
dart test
```

## Project Structure

- **`bin/llamadart_basic_example.dart`**: The CLI entry point and user interface logic.
- **`lib/services/llama_service.dart`**: High-level wrapper for the `llamadart` engine.
- **`lib/services/model_service.dart`**: Handles model downloading and path verification.
- **`lib/models.dart`**: Data structures for the application.
