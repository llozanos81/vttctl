#!/usr/bin/env python3
import os
import argparse


VTTCTL_PATH = os.path.join(os.getenv('HOME'), '.vttctl')

def main(args):
    print(args)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='VTT Control Utility')
    # Add your arguments here. For example:
    parser.add_argument('-d', '--download', type=str, help='download Foundry VTT ZIP file using TIMED URL')
    # parser.add_argument('--input', type=str, help='Input file')
    # parser.add_argument('--output', type=str, help='Output file')

    args = parser.parse_args()
    main(args)