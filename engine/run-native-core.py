#!/usr/bin/env python3
"""Compatibility entry point: every native run now uses BrkCore in dist/Brk.app."""
import os
from pathlib import Path
import sys
runner = Path(__file__).resolve().parents[1] / 'scripts/run-native.py'
os.execv(sys.executable, [sys.executable, str(runner), *sys.argv[1:]])
