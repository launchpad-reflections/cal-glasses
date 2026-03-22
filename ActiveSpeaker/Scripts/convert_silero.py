"""
Download Silero VAD ONNX model for use with ONNX Runtime on iOS.

Usage:
    python convert_silero.py

The script will download silero_vad.onnx if not already present.
Copy the resulting silero_vad.onnx into your Xcode project's bundle resources.
"""

import os
import urllib.request

MODEL_URL = "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx"
ONNX_PATH = "silero_vad.onnx"


def download_model():
    if os.path.exists(ONNX_PATH):
        print(f"Found existing {ONNX_PATH}")
        return
    print("Downloading Silero VAD ONNX model...")
    urllib.request.urlretrieve(MODEL_URL, ONNX_PATH)
    print(f"Download complete: {ONNX_PATH}")
    print(f"Add {ONNX_PATH} to your Xcode project's bundle resources.")


if __name__ == "__main__":
    download_model()
