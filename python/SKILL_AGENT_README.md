# Skill Agent

A simple LangChain-based agent that discovers and executes skills in the Claude Skills format.

## Features

- Discovers skills from a storage directory
- Parses SKILL.md files with YAML frontmatter
- Lists all available skills
- Executes the first skill with user input
- Configurable LLM provider (Anthropic Claude or OpenAI)

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

Skills should follow the Claude Skills format with a `SKILL.md` file:

```
skills/
└── skill-name/
    └── SKILL.md
```

Example SKILL.md:

```markdown
---
name: skill-name
description: Description of when this skill should be used
---

# Skill Title

## Instructions

Step-by-step instructions for executing the skill...
```

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

1. **Discovery**: Scans the storage path for all `SKILL.md` files
2. **Parsing**: Extracts name, description, and instructions from each skill
3. **Listing**: Displays all discovered skills
4. **Execution**: Takes the first skill and passes its instructions to the LLM
5. **Result**: The LLM interprets the skill instructions and fulfills the user's request

## Notes

- The agent uses a simple prompt-based approach for skill execution
- Skills are executed by the LLM following the instructions in SKILL.md
- Make sure your API keys are properly configured before running
