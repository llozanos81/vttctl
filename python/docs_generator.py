#!/usr/bin/env python3
"""
Docs generator for vttctl using Jinja2.
Generates command reference docs.
"""

import os
from jinja2 import Environment, FileSystemLoader

def generate_docs():
    # Define commands data
    commands = [
        {
            "name": "start",
            "description": "Start FoundryVTT services (production and optionally dev)",
            "usage": "./vttctl.sh start",
            "options": [],
            "examples": ["./vttctl.sh start"]
        },
        {
            "name": "stop",
            "description": "Stop FoundryVTT services",
            "usage": "./vttctl.sh stop [--all]",
            "options": [{"flag": "--all", "description": "Stop all services including dev"}],
            "examples": ["./vttctl.sh stop", "./vttctl.sh stop --all"]
        },
        {
            "name": "build",
            "description": "Build Docker images for FoundryVTT (interactive version selection)",
            "usage": "./vttctl.sh build [--force]",
            "options": [{"flag": "--force", "description": "Force rebuild of running version"}],
            "examples": ["./vttctl.sh build"]
        },
        {
            "name": "backup",
            "description": "Create a backup of FoundryVTT user data",
            "usage": "./vttctl.sh backup [--cleanup]",
            "options": [{"flag": "--cleanup", "description": "Interactive cleanup of old backups"}],
            "examples": ["./vttctl.sh backup", "./vttctl.sh backup --cleanup"]
        },
        {
            "name": "restore",
            "description": "Restore FoundryVTT user data from backup (interactive)",
            "usage": "./vttctl.sh restore",
            "options": [],
            "examples": ["./vttctl.sh restore"]
        },
        {
            "name": "logs",
            "description": "Show logs",
            "usage": "./vttctl.sh logs [--live]",
            "options": [{"flag": "--live", "description": "Live log tailing"}],
            "examples": ["./vttctl.sh logs", "./vttctl.sh logs --live"]
        },
        {
            "name": "clean",
            "description": "Remove containers",
            "usage": "./vttctl.sh clean [--all]",
            "options": [{"flag": "--all", "description": "Remove all user data and volumes"}],
            "examples": ["./vttctl.sh clean", "./vttctl.sh clean --all"]
        },
        {
            "name": "validate",
            "description": "Check dependencies and generate .env if missing",
            "usage": "./vttctl.sh validate",
            "options": [],
            "examples": ["./vttctl.sh validate"]
        },
        {
            "name": "wizard",
            "description": "Interactive configuration wizard for .env file setup",
            "usage": "./vttctl.sh wizard",
            "options": [],
            "examples": ["./vttctl.sh wizard"]
        },
        {
            "name": "download",
            "description": "Download FoundryVTT zip from timed URL",
            "usage": "./vttctl.sh download \"<TIMED_URL>\"",
            "options": [],
            "examples": ["./vttctl.sh download \"https://foundryvtt.com/...\""]
        },
        {
            "name": "info",
            "description": "Show FoundryVTT and system info",
            "usage": "./vttctl.sh info",
            "options": [],
            "examples": ["./vttctl.sh info"]
        },
        {
            "name": "help",
            "description": "Show help and usage information",
            "usage": "./vttctl.sh help",
            "options": [],
            "examples": ["./vttctl.sh help"]
        }
        # Add more commands as needed
    ]

    # Get template directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    template_dir = os.path.join(script_dir, '..', 'templates', 'docs')
    output_dir = os.path.join(script_dir, '..', 'docs')

    # Create output dir if not exists
    os.makedirs(output_dir, exist_ok=True)

    # Set up Jinja2
    env = Environment(loader=FileSystemLoader(template_dir))
    template = env.get_template('commands.md.j2')

    # Render
    rendered = template.render(commands=commands)

    # Write output
    output_path = os.path.join(output_dir, 'commands.md')
    with open(output_path, 'w') as f:
        f.write(rendered)

    print(f"Docs generated: {output_path}")

if __name__ == '__main__':
    generate_docs()