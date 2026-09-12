#!/usr/bin/env python3
"""Transcribe audio file using faster-whisper, printing plain text to stdout."""
import sys, os, subprocess, tempfile
from faster_whisper import WhisperModel

if len(sys.argv) < 2:
    sys.exit("Usage: whisper-transcribe.py <audio-file>")

MODEL_DIR = os.path.expanduser("~/.openclaw/whisper-models")
os.makedirs(MODEL_DIR, exist_ok=True)
HALLUCINATIONS = {"you", "thank you.", "thank you", "thanks.", "thanks", "bye.", "bye"}

def denoise(input_path):
    """Run ffmpeg afftdn denoising filter, return path to cleaned file."""
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()
    result = subprocess.run(
        ["ffmpeg", "-y", "-i", input_path, "-af", "afftdn=nf=-25", tmp.name],
        capture_output=True,
    )
    if result.returncode != 0:
        os.unlink(tmp.name)
        return input_path  # fall back to original if ffmpeg fails
    return tmp.name

audio_file = sys.argv[1]
denoised = denoise(audio_file)

try:
    model = WhisperModel("small", device="cpu", compute_type="int8", download_root=MODEL_DIR)
    segments, _ = model.transcribe(
        denoised,
        language="en",
        vad_filter=True,
        vad_parameters={"min_speech_duration_ms": 250},
    )
    for segment in segments:
        text = segment.text.strip()
        if text.lower() not in HALLUCINATIONS:
            print(text)
finally:
    if denoised != audio_file and os.path.exists(denoised):
        os.unlink(denoised)
