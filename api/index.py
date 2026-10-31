import sys
import os

# Add parent directory and backend directory to python path
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
sys.path.insert(0, parent_dir)
sys.path.insert(0, os.path.join(parent_dir, "backend"))

from backend.app import app

# Vercel WSGI entry point
handler = app
