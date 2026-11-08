# Third-party notices

Typist includes or depends on the following third-party software. Each entry lists its license, which must be compatible with GPL-3.0.

| Component | Version | License | Used for | Source |
|---|---|---|---|---|
| WhisperKit (argmax-oss-swift) | 1.1.1 | MIT | On-device speech recognition with CoreML Whisper models | https://github.com/argmaxinc/WhisperKit |

## Models downloaded at runtime

Typist does not bundle model weights. It downloads them from Hugging Face on first use.

| Model | License | Used for | Source |
|---|---|---|---|
| OpenAI Whisper large-v3-turbo, CoreML conversion by Argmax (`openai_whisper-large-v3-v20240930_626MB`) | MIT (weights: OpenAI; conversion: Argmax) | Speech recognition | https://huggingface.co/argmaxinc/whisperkit-coreml, original weights https://huggingface.co/openai/whisper-large-v3-turbo |
