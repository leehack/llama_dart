import 'dart:typed_data';

/// Base class for all content types in a message.
///
/// Multi-modality allows a single message to contain different types of data,
/// such as text, images, or audio.
sealed class LlamaContentPart {
  /// Base constructor for content parts.
  const LlamaContentPart();
}

/// A part of a message containing plain text.
class LlamaTextContent extends LlamaContentPart {
  /// The raw text string.
  final String text;

  /// Creates a text content part.
  const LlamaTextContent(this.text);
}

/// A part of a message containing image data for vision models.
///
/// The model must be loaded with a compatible multimodal projector (mmproj).
class LlamaImageContent extends LlamaContentPart {
  /// Raw RGB pixel data.
  ///
  /// For best performance, provide pre-processed RGB bytes.
  final Uint8List? bytes; // RGB format

  /// Width of the image in pixels.
  final int? width;

  /// Height of the image in pixels.
  final int? height;

  /// Local filesystem path to the image (e.g., JPEG, PNG).
  ///
  /// If provided, the native engine will load and decode the image automatically.
  final String? path; // Alternative: file path

  /// URL to a remote image (not yet supported).
  final String? url; // Future: remote images

  /// Creates an image content part.
  ///
  /// Either [path] or [bytes] should be provided.
  const LlamaImageContent({
    this.bytes,
    this.width,
    this.height,
    this.path,
    this.url,
  });
}

/// A part of a message containing audio data for speech-to-text models.
class LlamaAudioContent extends LlamaContentPart {
  /// Raw PCM Float32 audio samples.
  final Float32List? samples; // PCM F32

  /// Local filesystem path to the audio file (e.g., WAV, MP3).
  ///
  /// If provided, the native engine will decode the audio automatically.
  final String? path; // Alternative: file path

  /// Creates an audio content part.
  const LlamaAudioContent({this.samples, this.path});
}
