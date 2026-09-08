"""Shared release entry point: established V2 transforms, then Premium integration."""
from pathlib import Path
import runpy
from premium_experiences import apply_premium

ROOT = Path(__file__).resolve().parents[1]
runpy.run_path(str(ROOT / 'scripts/apply_v2_final_base.py'), run_name='__main__')
apply_premium(ROOT)
