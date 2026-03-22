# Model Setup

## Moonshine v2 (Speech Transcription)

The Moonshine model files (~160MB) are not checked into git. Download and set them up before building:

1. Download the iOS examples archive:
   ```bash
   curl -L -o /tmp/ios-examples.tar.gz \
     https://github.com/moonshine-ai/moonshine/releases/latest/download/ios-examples.tar.gz
   ```

2. Extract the model files into the project:
   ```bash
   tar -xzf /tmp/ios-examples.tar.gz -C /tmp Transcriber/models/
   cp -r /tmp/Transcriber/models ActiveSpeaker/
   ```

3. In Xcode, drag the `ActiveSpeaker/models/` folder into the project navigator:
   - Select **"Create folder references"** (blue folder icon)
   - Ensure **"Add to targets: ActiveSpeaker"** is checked

The model files (`encoder.ort`, `decoder_kv.ort`, `adapter.ort`, `cross_kv.ort`, `frontend.ort`, `tokenizer.bin`, `streaming_config.json`) should appear in **Build Phases → Copy Bundle Resources**.

## Silero VAD

The `silero_vad.onnx` file in `ActiveSpeaker/` is already tracked in git.
