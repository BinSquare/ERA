# Skill Agent

A simple LangChain-based agent that discovers and executes skills in the Claude Skills format.

## Features

- **Comprehensive Skill Discovery**: Automatically scans directories for SKILL.md files
- **Rich Resource Detection**: Finds and loads:
  - YAML frontmatter with skill metadata
  - Main instruction content
  - Additional documentation files (reference.md, forms.md, README.md, LICENSE.txt)
  - Available scripts in the scripts/ directory
- **Verbose Output**: Detailed progress tracking with visual indicators showing:
  - Discovery process and files found
  - Parsed skill information and resources
  - API key validation
  - Skill execution status
- **Multiple LLM Providers**: Supports Anthropic Claude and OpenAI
- **Error Handling**: Comprehensive error messages with traceback information

## Installation

Install dependencies:

```bash
pip install -r requirements.txt
```

Set up your API keys:

```bash
# For Anthropic Claude (default)
export ANTHROPIC_API_KEY="your-api-key"

# For OpenAI (if using)
export OPENAI_API_KEY="your-api-key"
```

## Usage

Basic usage with default settings (Anthropic Claude Sonnet 4.5):

```bash
python skill_agent.py ./skills
```

Specify a different provider:

```bash
python skill_agent.py ./skills openai
```

Specify a custom model:

```bash
python skill_agent.py ./skills anthropic claude-3-5-sonnet-20241022
python skill_agent.py ./skills openai gpt-4o
```

## Skill Format

Skills should follow the Claude Skills format with a `SKILL.md` file and optional additional resources:

```
skills/
└── skill-name/
    ├── SKILL.md              # Required: Main skill definition
    ├── reference.md          # Optional: Additional reference material
    ├── forms.md              # Optional: Forms-related documentation
    ├── README.md             # Optional: Additional readme
    ├── LICENSE.txt           # Optional: License information
    └── scripts/              # Optional: Helper scripts
        ├── script1.py
        └── script2.py
```

Example SKILL.md with YAML frontmatter:

```markdown
---
name: skill-name
description: Description of when this skill should be used
---

# Skill Title

## Instructions

Step-by-step instructions for executing the skill...
```

The agent will automatically discover and load all available resources when executing a skill.

## Example

An example research-papers skill is included in `skills/research-papers/`.

Run it:

```bash
python skill_agent.py ./skills
```

When prompted, enter a research topic like:

```
Find papers about machine learning for climate modeling
```

## How It Works

1. **Discovery Phase**:
   - Recursively scans the storage path for all `SKILL.md` files
   - Reports each file found with visual progress indicators

2. **Parsing Phase**:
   - Extracts YAML frontmatter (name, description, metadata)
   - Loads main instruction content
   - Scans for additional documentation files
   - Discovers available scripts in the scripts/ directory
   - Reports all resources found for each skill

3. **Summary**:
   - Displays comprehensive skill information
   - Lists all loaded resources (docs, scripts, paths)

4. **Agent Initialization**:
   - Validates API keys
   - Configures the specified LLM provider and model

5. **Execution**:
   - Loads the complete skill context (instructions + all resources)
   - Shows what resources are being used
   - Passes everything to the LLM as system context
   - Streams the response in real-time

6. **Result**:
   - The LLM has access to all skill resources
   - Can reference documentation, scripts, and instructions
   - Provides comprehensive, context-aware responses

## Output Features

The refactored agent provides rich, informative output throughout execution:

- 🔍 **Discovery indicators**: Shows search progress and files found
- ✓ **Success markers**: Confirms successful operations
- ⚠️ **Warnings**: Highlights issues that don't stop execution
- ❌ **Errors**: Clear error messages with context
- 📊 **Statistics**: File counts, sizes, and resource summaries
- 🎯 **Status updates**: Current operation and progress

Example output snippet:
```
🔍 Searching for SKILL.md files in: storage/skills
📄 Found 1 SKILL.md file(s)

  → Parsing: pdf/SKILL.md
    📚 Scanning for additional documentation files...
       • Found: reference.md (16.3 KB)
       • Found: forms.md (9.1 KB)
    🔧 Scanning for scripts in scripts/ directory...
       • Found: scripts/fill_fillable_fields.py
       ...
    ✓ Successfully loaded skill: pdf
```

## Notes

- The agent loads ALL available skill resources into the LLM context
- Skills are executed with full access to instructions, docs, and script references
- Make sure your API keys are properly configured before running
- The verbose output helps debug skill structure and resource loading issues
