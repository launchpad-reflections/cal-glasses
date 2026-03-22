#!/usr/bin/env python3
"""
Convert a pretrained MobileFaceNet (ArcFace-trained) model to Core ML.

Usage:
    pip install onnx onnx2torch coremltools torch numpy
    python convert_mobilefacenet.py

Outputs MobileFaceNet.mlpackage in the current directory (~4 MB).
"""

import argparse
import os
import zipfile
import urllib.request

import numpy as np
import onnx


def download_insightface_model(model_name: str = "buffalo_sc") -> str:
    """Download the insightface model pack and return the recognition ONNX path."""
    model_dir = os.path.join(
        os.path.expanduser("~"), ".insightface", "models", model_name
    )
    zip_path = model_dir + ".zip"

    if not os.path.isdir(model_dir):
        url = f"https://github.com/deepinsight/insightface/releases/download/v0.7/{model_name}.zip"
        print(f"Downloading {url} ...")
        os.makedirs(os.path.dirname(model_dir), exist_ok=True)
        urllib.request.urlretrieve(url, zip_path)
        with zipfile.ZipFile(zip_path, "r") as zf:
            zf.extractall(os.path.dirname(model_dir))
        os.remove(zip_path)

    for f in os.listdir(model_dir):
        if f.endswith(".onnx") and ("mbf" in f.lower() or "w600k" in f.lower()):
            return os.path.join(model_dir, f)

    for f in os.listdir(model_dir):
        if f.endswith(".onnx") and "det" not in f.lower():
            return os.path.join(model_dir, f)

    raise FileNotFoundError(
        f"No recognition ONNX model found in {model_dir}. "
        f"Contents: {os.listdir(model_dir)}"
    )


def inspect_onnx(onnx_path: str) -> None:
    """Print ONNX model input/output info."""
    model = onnx.load(onnx_path)
    print("ONNX model inputs:")
    for inp in model.graph.input:
        shape = [d.dim_value or d.dim_param for d in inp.type.tensor_type.shape.dim]
        print(f"  {inp.name}: {shape}")
    print("ONNX model outputs:")
    for out in model.graph.output:
        shape = [d.dim_value or d.dim_param for d in out.type.tensor_type.shape.dim]
        print(f"  {out.name}: {shape}")


def convert_onnx_to_coreml(onnx_path: str, output_path: str) -> None:
    """Convert ONNX → PyTorch → Core ML."""
    import torch
    from onnx2torch import convert as onnx2torch_convert
    import coremltools as ct

    print(f"Converting {onnx_path} to Core ML...")
    inspect_onnx(onnx_path)

    # Step 1: ONNX → PyTorch
    print("\nStep 1: Converting ONNX to PyTorch...")
    pytorch_model = onnx2torch_convert(onnx_path)
    pytorch_model.eval()

    # Verify PyTorch model works
    dummy_input = torch.randn(1, 3, 112, 112)
    with torch.no_grad():
        pt_output = pytorch_model(dummy_input)
    print(f"PyTorch output shape: {pt_output.shape}")

    # Step 2: Trace the PyTorch model
    print("Step 2: Tracing PyTorch model...")
    traced_model = torch.jit.trace(pytorch_model, dummy_input)

    # Step 3: PyTorch → Core ML
    print("Step 3: Converting PyTorch to Core ML...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[ct.TensorType(shape=(1, 3, 112, 112), name="input")],
        minimum_deployment_target=ct.target.iOS17,
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT16,
        convert_to="mlprogram",
    )

    mlmodel.author = "insightface / ArcFace"
    mlmodel.short_description = (
        "MobileFaceNet (ArcFace-trained) for 512-d face embeddings. "
        "Input: 112x112 RGB, normalized to [-1, 1]."
    )

    mlmodel.save(output_path)
    print(f"Saved {output_path}")

    size_mb = sum(
        os.path.getsize(os.path.join(dp, f))
        for dp, _, filenames in os.walk(output_path)
        for f in filenames
    ) / (1024 * 1024)
    print(f"Model size: {size_mb:.1f} MB")


def verify_model(mlpackage_path: str) -> None:
    """Quick sanity check: run a dummy input and print embedding shape."""
    import coremltools as ct

    model = ct.models.MLModel(mlpackage_path)

    spec = model.get_spec()
    input_name = spec.description.input[0].name
    output_name = spec.description.output[0].name
    print(f"CoreML input name: '{input_name}'")
    print(f"CoreML output name: '{output_name}'")

    dummy = np.random.randn(1, 3, 112, 112).astype(np.float32)
    out = model.predict({input_name: dummy})

    for key, value in out.items():
        arr = np.array(value)
        print(f"Output '{key}': shape={arr.shape}, dtype={arr.dtype}")
        print(f"  L2 norm: {np.linalg.norm(arr):.4f}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--onnx", type=str, default=None,
        help="Path to an existing MobileFaceNet ONNX file.",
    )
    parser.add_argument(
        "--output", type=str, default="MobileFaceNet.mlpackage",
        help="Output path for the .mlpackage",
    )
    parser.add_argument(
        "--no-verify", action="store_true",
        help="Skip verification step.",
    )
    args = parser.parse_args()

    if args.onnx:
        onnx_path = args.onnx
    else:
        print("Downloading MobileFaceNet from insightface...")
        onnx_path = download_insightface_model()

    print(f"Using ONNX model: {onnx_path}")
    convert_onnx_to_coreml(onnx_path, args.output)

    if not args.no_verify:
        print("\nVerifying converted model...")
        verify_model(args.output)

    print("\nDone! Add the .mlpackage to your Xcode project's bundle resources.")


if __name__ == "__main__":
    main()
