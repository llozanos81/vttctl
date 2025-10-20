#!/usr/bin/env python3
"""
Template renderer for vttctl using Jinja2.
Renders templates with provided variables.
"""

import os
import argparse
from jinja2 import Environment, FileSystemLoader

def render_template(template_path, output_path, variables):
    """
    Render a Jinja2 template with given variables.
    
    Args:
        template_path (str): Path to the template file
        output_path (str): Path to the output file
        variables (dict): Dictionary of variables to pass to the template
    """
    try:
        # Get the directory and filename of the template
        template_dir, template_file = os.path.split(template_path)
        
        # Set up Jinja2 environment
        env = Environment(loader=FileSystemLoader(template_dir), cache_size=0)
        
        # Load the template
        template = env.get_template(template_file)
        
        # Render with variables
        rendered = template.render(**variables)
        with open(output_path, 'w') as f:
            f.write(rendered)
        
        print(f"Template rendered: {template_path} -> {output_path}")
    except Exception as e:
        print(f"Error rendering template: {e}")
        raise

def main():
    parser = argparse.ArgumentParser(description='Render Jinja2 templates for vttctl')
    parser.add_argument('--template', required=True, help='Path to template file')
    parser.add_argument('--output', required=True, help='Path to output file')
    parser.add_argument('--var', action='append', help='Variable in key=value format')
    
    args = parser.parse_args()
    
    # Parse variables
    variables = {}
    if args.var:
        for var in args.var:
            if '=' in var:
                key, value = var.split('=', 1)
                variables[key] = value
            else:
                print(f"Warning: Invalid variable format: {var}")
    
    render_template(args.template, args.output, variables)

if __name__ == '__main__':
    main()