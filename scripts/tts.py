"""
Text-to-Speech file generator using macOS say command.

Usage:
  python tts.py "your text here"
  python tts.py "your text here" --voice Samantha
  python tts.py "your text here" --output myfile.aiff
"""

import subprocess
import sys
import os

DEFAULT_VOICE = "Samantha"  # Change to any installed voice
OUTPUT_DIR = os.path.expanduser("~/Desktop")


def generate_tts(text, voice=DEFAULT_VOICE, output=None):
    if not output:
        safe_name = "".join(c if c.isalnum() or c == " " else "" for c in text)[:40].strip()
        safe_name = safe_name.replace(" ", "_")
        output = os.path.join(OUTPUT_DIR, f"{safe_name}.mp3")

    # Generate AIFF first, then convert to MP3 if needed
    if output.endswith(".mp3"):
        aiff_temp = output.replace(".mp3", "_temp.aiff")
        subprocess.run(["say", "-v", voice, "-o", aiff_temp, text], check=True)
        subprocess.run(["afconvert", "-f", "mp4f", "-d", "aac", aiff_temp, output], check=True)
        os.remove(aiff_temp)
    else:
        subprocess.run(["say", "-v", voice, "-o", output, text], check=True)

    print(f"Generating: \"{text}\"")
    print(f"Voice: {voice}")
    print(f"Output: {output}")
    print(f"✓ Saved to {output}")
    return output


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python tts.py \"your text here\" [--voice Voice] [--output file.aiff]")
        sys.exit(1)

    text = sys.argv[1]
    voice = DEFAULT_VOICE
    output = None

    args = sys.argv[2:]
    for i, arg in enumerate(args):
        if arg == "--voice" and i + 1 < len(args):
            voice = args[i + 1]
        elif arg == "--output" and i + 1 < len(args):
            output = args[i + 1]

    generate_tts(text, voice, output)
