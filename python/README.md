# 🧠 ERA Python Skill Agent

## TL;DR

**What it is:** A LangChain-based agent that discovers and executes skills from SKILL.md files  
**How to run:** `python agentSmith.py ./storage` (after setting `ANTHROPIC_API_KEY`)  
**What it does:** Automatically finds skills, loads their instructions, and executes them via LLM

---

## 🚀 Quick Start

1. **Install dependencies:**

   ```bash
   pip install -r requirements.txt
   ```

2. **Set API key:**

   ```bash
   export ANTHROPIC_API_KEY="your-api-key"
   # or create .env file with: ANTHROPIC_API_KEY=your-api-key
   ```

3. **Run the agent:**

   ```bash
   python agentSmith.py ./storage
   ```

4. **Use it:** Type requests like "Find papers about RAG" and press Enter

---

## 📁 Folder Structure

```
python/
├── agentSmith.py          # Main agent script
├── requirements.txt       # Dependencies
├── README.md              # This file
└── storage/               # Skills directory
    └── skills/
        └── skill-name/
            ├── SKILL.md     # Required: Skill definition
            ├── reference.md # Optional: Additional docs
            ├── forms.md     # Optional: Forms docs
            ├── README.md    # Optional: Extra readme
            ├── LICENSE.txt  # Optional: License
            └── scripts/     # Optional: Helper scripts
                └── script.py
```

---

## 🎯 How It Works

1. **Discovery:** Scans directories for `SKILL.md` files
2. **Parsing:** Extracts YAML frontmatter (name, description) + instructions
3. **Loading:** Finds additional resources (docs, scripts) for each skill
4. **Execution:** Creates LangChain agent with skill context as system prompt
5. **Streaming:** Real-time response with automatic code execution

---

## 📝 Skill Format

Skills use the Claude Skills format with YAML frontmatter:

```markdown
---
name: skill-name
description: When to use this skill
---

# Skill Title

## Instructions

Step-by-step instructions for executing the skill...
```

**Required:** `SKILL.md` with YAML frontmatter  
**Optional:** `reference.md`, `forms.md`, `README.md`, `LICENSE.txt`, `scripts/` folder

---

## 🔧 Usage Options

**Basic (default Anthropic Claude):**

```bash
python agentSmith.py ./storage
```

**With different provider:**

```bash
python agentSmith.py ./storage openai
python agentSmith.py ./storage anthropic claude-sonnet-4-5-20250929
```

**Persistent CLI mode:**

- Runs continuously until Ctrl+C or 'exit'
- Maintains conversation context
- Automatically executes Python code from responses

---

## 🛠️ Adding Skills

1. **Create skill directory:**

   ```bash
   mkdir storage/skills/my-skill
   ```

2. **Add SKILL.md:**

   ```markdown
   ---
   name: my-skill
   description: What this skill does
   ---

   # My Skill

   ## Instructions

   Detailed instructions for the skill...
   ```

3. **Add optional resources:**

   - `reference.md` - Additional documentation
   - `scripts/` - Helper Python scripts
   - `forms.md` - Form-related docs

4. **Test it:**
   ```bash
   python agentSmith.py ./storage
   ```

---

## 🎨 Features

- **Auto-discovery:** Finds all skills recursively
- **Rich context:** Loads all skill resources into LLM context
- **Multiple providers:** Anthropic Claude, OpenAI
- **Code execution:** Automatically runs Python code from responses
- **Streaming:** Real-time responses
- **Error handling:** Clear error messages with helpful hints

---

## 🔍 Example Session

```bash
$ python agentSmith.py ./storage

🔍 Discovering skills in: ./storage
Found 1 skill(s):
1. research-papers: Find academic papers on topics

🤖 You: Find papers about machine learning
[Agent executes skill and returns formatted results]

🤖 You: exit
👋 Goodbye!
```

---

## 🚨 Troubleshooting

**"ANTHROPIC_API_KEY not found":**

- Set environment variable: `export ANTHROPIC_API_KEY='your-key'`
- Or create `.env` file with the key

**"No skills found":**

- Ensure `SKILL.md` files exist in subdirectories
- Check YAML frontmatter format

**Import errors:**

- Run `pip install -r requirements.txt`
- Install missing packages as needed

---

## 🏗️ Framework Choice

This agent uses **LangChain** because it provides:

- ✅ Huge community and documentation
- ✅ Built-in LLM integrations
- ✅ Tool chaining and memory
- ✅ Streaming and async support

**Alternative frameworks** for different needs:

- **SmolAgents:** Ultra-lightweight for simple agents
- **AutoGen:** Multi-agent collaboration
- **CrewAI:** Role-based agent teams
- **Haystack:** RAG/document-based agents

---

## 📚 Resources

- [LangChain Agents Documentation](https://docs.langchain.com/oss/python/langchain/overview)
- [Claude Skills Format](https://docs.claude.com/en/docs/agents-and-tools/agent-skills/overview)
- [Anthropic API Keys](https://console.anthropic.com/)

---

© 2025 — ERA Python Skill Agent (KISS Edition)
