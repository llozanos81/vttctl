import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

import pytest
import argparse
from vttctl import main

def test_main_no_args(capsys):
    # Test main with no args
    args = argparse.Namespace()
    main(args)
    captured = capsys.readouterr()
    assert captured.out.strip() == "Namespace()"

def test_main_with_download_arg(capsys):
    # Test main with download arg
    args = argparse.Namespace(download='test_url')
    main(args)
    captured = capsys.readouterr()
    assert captured.out.strip() == "Namespace(download='test_url')"