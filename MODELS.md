# Model Setup

## Moonshine v2 (Speech Transcription)

The Moonshine model files (~160MB) are not checked into git. Download and set them up before building:

1. Download and extract:
   ```bash
   curl -L -o /tmp/ios-examples.tar.gz \
     https://github.com/moonshine-ai/moonshine/releases/latest/download/ios-examples.tar.gz
   tar -xzf /tmp/ios-examples.tar.gz -C /tmp Transcriber/models/
   cp -r /tmp/Transcriber/models/small-streaming-en ActiveSpeaker/small-streaming-en
   ```

2. In Xcode, the `small-streaming-en` group under the project root should already reference these files. If the files show in red, right-click the group and re-link to the `ActiveSpeaker/small-streaming-en/` directory.

3. Verify the model files appear in **Build Phases → Copy Bundle Resources**:
   `encoder.ort`, `decoder_kv.ort`, `adapter.ort`, `cross_kv.ort`, `frontend.ort`, `tokenizer.bin`, `streaming_config.json`

## Silero VAD

The `silero_vad.onnx` file in `ActiveSpeaker/` is already tracked in git.

## MobileFaceNet

The `MobileFaceNet.mlpackage` in `ActiveSpeaker/` is already tracked in git.
