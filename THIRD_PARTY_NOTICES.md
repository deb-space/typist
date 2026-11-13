# Third-party notices

Typist includes or depends on the following third-party software. Each entry lists its license, which must be compatible with GPL-3.0.

| Component | Version | License | Used for | Source |
|---|---|---|---|---|
| WhisperKit (argmax-oss-swift) | 1.1.1 | MIT | On-device speech recognition with CoreML Whisper models | https://github.com/argmaxinc/WhisperKit |
| MLX Swift | 0.32.3 | MIT | Running language models on the GPU | https://github.com/ml-explore/mlx-swift |
| MLX Swift LM | 3.32.3 | MIT | Language model architectures and text generation | https://github.com/ml-explore/mlx-swift-lm |
| swift-transformers | 1.4.0 | Apache-2.0 | Tokenizers and chat templates | https://github.com/huggingface/swift-transformers |
| FluidAudio | 0.18.3 | Apache-2.0 | Telling meeting speakers apart (speaker diarization) | https://github.com/FluidInference/FluidAudio |

Packages these depend on, resolved in `Package.resolved`: swift-jinja, swift-huggingface, swift-collections, swift-crypto, swift-asn1, swift-numerics, swift-syntax and swift-argument-parser (Apache-2.0), yyjson and EventSource (MIT).

## Models downloaded at runtime

Typist does not bundle model weights. It downloads them from Hugging Face on first use.

| Model | License | Used for | Source |
|---|---|---|---|
| OpenAI Whisper large-v3-turbo, CoreML conversion by Argmax (`openai_whisper-large-v3-v20240930_626MB`) | MIT (weights: OpenAI; conversion: Argmax) | Speech recognition | https://huggingface.co/argmaxinc/whisperkit-coreml, original weights https://huggingface.co/openai/whisper-large-v3-turbo |
| Google Gemma 4 E4B, 4-bit MLX conversion (`mlx-community/gemma-4-e4b-it-4bit`) | Apache-2.0 | AI cleanup, the default | https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit, original weights https://huggingface.co/google/gemma-4-E4B-it |
| Qwen3.5 4B, 4-bit MLX conversion (`mlx-community/Qwen3.5-4B-MLX-4bit`) | Apache-2.0 | AI cleanup, optional | https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit, original weights https://huggingface.co/Qwen/Qwen3.5-4B |
| Qwen3.5 9B, 4-bit MLX conversion (`mlx-community/Qwen3.5-9B-MLX-4bit`) | Apache-2.0 | AI cleanup, optional | https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit, original weights https://huggingface.co/Qwen/Qwen3.5-9B |
| pyannote speaker-diarization-community-1, CoreML conversion by FluidInference (`FluidInference/speaker-diarization-coreml`) | Segmentation (pyannote segmentation-3.0): MIT. Speaker embeddings (WeSpeaker ResNet34) and the community-1 pipeline: CC-BY-4.0 | Telling meeting speakers apart | https://huggingface.co/FluidInference/speaker-diarization-coreml, original https://huggingface.co/pyannote/speaker-diarization-community-1 |

Attribution for CC-BY-4.0: the speaker diarization pipeline is pyannote.audio's speaker-diarization-community-1 by pyannoteAI (Hervé Bredin et al.), with speaker embeddings from WeSpeaker (Wang et al., "WeSpeaker: A Research and Production Oriented Speaker Embedding Learning Toolkit", ICASSP 2023), converted to CoreML by FluidInference. Typist runs them unchanged.

Language models are pinned to a reviewed commit of their repository and downloaded only when AI cleanup is on.
