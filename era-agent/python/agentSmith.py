# %%
"""
Simple LangChain Agent for discovering and executing skills.
Skills are expected to follow the Claude Skills format with SKILL.md files.
"""

import os
import sys
import re
import subprocess
from pathlib import Path
from typing import List, Dict, Optional
import yaml
from dataclasses import dataclass
from dotenv import load_dotenv

from langchain_anthropic import ChatAnthropic
from langchain_openai import ChatOpenAI


@dataclass
class Skill:
    """Represents a parsed skill from SKILL.md"""
    name: str
    description: str
    instructions: str
    path: Path
    additional_files: Dict[str, str]  # filename -> content mapping
    scripts_available: List[str]  # list of available script paths
    dependencies: List[str] = None  # Python packages required

    def __post_init__(self):
        if self.dependencies is None:
            self.dependencies = []

    def __str__(self):
        return f"{self.name}: {self.description}"

    def get_full_context(self) -> str:
        """Get complete skill context including all resources"""
        context = [f"# Skill: {self.name}\n"]
        context.append(f"## Description\n{self.description}\n")
        context.append(f"## Skill Base Path\n{self.path}\n")
        context.append(f"## Main Instructions\n{self.instructions}\n")
        
        # Add additional documentation files
        if self.additional_files:
            context.append("\n## Additional Documentation Files\n")
            for filename, content in self.additional_files.items():
                context.append(f"\n### File: {filename}\n")
                context.append(f"```markdown\n{content}\n```\n")
        
        # Add available scripts
        if self.scripts_available:
            context.append("\n## Available Scripts\n")
            context.append("The following scripts are available in the skill's scripts/ directory:\n")
            for script in self.scripts_available:
                context.append(f"- {script}\n")
        
        return "\n".join(context)


class SkillDiscovery:
    """Discovers and parses skills from a storage path"""

    def __init__(self, storage_path: str):
        self.storage_path = Path(storage_path)
        self.skills: List[Skill] = []

    def find_skills(self) -> List[Skill]:
        """Find all SKILL.md files in the storage path"""
        self.skills = []

        if not self.storage_path.exists():
            print(f"❌ Warning: Storage path {self.storage_path} does not exist")
            return self.skills

        print(f"\n🔍 Searching for SKILL.md files in: {self.storage_path}")

        # Find all SKILL.md files
        skill_files_found = list(self.storage_path.rglob("SKILL.md"))

        if not skill_files_found:
            print(f"⚠️  No SKILL.md files found in {self.storage_path}")
            return self.skills

        print(f"📄 Found {len(skill_files_found)} SKILL.md file(s)")

        for skill_file in skill_files_found:
            print(f"\n  → Parsing: {skill_file.relative_to(self.storage_path)}")
            try:
                skill = self._parse_skill(skill_file)
                if skill:
                    self.skills.append(skill)
                    print(f"    ✓ Successfully loaded skill: {skill.name}")
                    print(f"      Description: {skill.description[:80]}...")
            except Exception as e:
                print(f"    ✗ Error parsing {skill_file}: {e}")

        return self.skills

    def _extract_dependencies(self, skill_dir: Path, instructions: str, additional_files: Dict[str, str]) -> List[str]:
        """Extract Python dependencies from skill files"""
        dependencies = set()

        # Common import to package name mappings
        import_to_package = {
            'pypdf': 'pypdf',
            'pdfplumber': 'pdfplumber',
            'pandas': 'pandas',
            'reportlab': 'reportlab',
            'pytesseract': 'pytesseract',
            'pdf2image': 'pdf2image',
            'PIL': 'Pillow',
            'cv2': 'opencv-python',
            'numpy': 'numpy',
            'requests': 'requests',
            'bs4': 'beautifulsoup4',
            'sklearn': 'scikit-learn',
            'torch': 'torch',
            'tensorflow': 'tensorflow',
        }

        # Check for requirements.txt in skill directory
        requirements_file = skill_dir / 'requirements.txt'
        if requirements_file.exists():
            try:
                with open(requirements_file, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            # Extract package name (before any version specifiers)
                            pkg = line.split('==')[0].split('>=')[0].split('<=')[0].split('>')[0].split('<')[0].strip()
                            dependencies.add(pkg)
                return list(dependencies)
            except Exception as e:
                print(f"       ⚠️  Error reading requirements.txt: {e}")

        # Otherwise, extract from imports in instructions and additional files
        all_content = instructions
        for content in additional_files.values():
            all_content += "\n" + content

        # Find all import statements
        import_pattern = r'^(?:from|import)\s+([a-zA-Z_][a-zA-Z0-9_]*)'
        matches = re.findall(import_pattern, all_content, re.MULTILINE)

        for module in matches:
            # Map import to package name
            if module in import_to_package:
                dependencies.add(import_to_package[module])

        # Also check scripts directory
        scripts_dir = skill_dir / 'scripts'
        if scripts_dir.exists() and scripts_dir.is_dir():
            for script_file in scripts_dir.rglob('*.py'):
                try:
                    with open(script_file, 'r', encoding='utf-8') as f:
                        script_content = f.read()
                        matches = re.findall(import_pattern, script_content, re.MULTILINE)
                        for module in matches:
                            if module in import_to_package:
                                dependencies.add(import_to_package[module])
                except Exception:
                    pass

        return list(dependencies)

    def _parse_skill(self, skill_file: Path) -> Optional[Skill]:
        """Parse a SKILL.md file with YAML frontmatter and discover all skill resources"""
        with open(skill_file, 'r', encoding='utf-8') as f:
            content = f.read()

        # Split frontmatter and instructions
        if not content.startswith('---'):
            print(f"    ⚠️  Warning: {skill_file} missing YAML frontmatter")
            return None

        parts = content.split('---', 2)
        if len(parts) < 3:
            print(f"    ⚠️  Warning: {skill_file} has malformed frontmatter")
            return None

        # Parse YAML frontmatter
        try:
            metadata = yaml.safe_load(parts[1])
        except yaml.YAMLError as e:
            print(f"    ✗ Error parsing YAML in {skill_file}: {e}")
            return None

        if not metadata or 'name' not in metadata or 'description' not in metadata:
            print(f"    ⚠️  Warning: {skill_file} missing required name or description")
            return None

        instructions = parts[2].strip()
        skill_dir = skill_file.parent

        # Discover additional documentation files
        additional_files = {}
        common_doc_files = ['reference.md', 'forms.md', 'README.md', 'LICENSE.txt']
        print(f"    📚 Scanning for additional documentation files...")
        for doc_file in common_doc_files:
            doc_path = skill_dir / doc_file
            if doc_path.exists() and doc_path.is_file():
                try:
                    with open(doc_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                        additional_files[doc_file] = content
                        size_kb = len(content) / 1024
                        print(f"       • Found: {doc_file} ({size_kb:.1f} KB)")
                except Exception as e:
                    print(f"       ⚠️  Could not read {doc_path}: {e}")

        if not additional_files:
            print(f"       (No additional documentation files found)")

        # Discover available scripts
        scripts_available = []
        scripts_dir = skill_dir / 'scripts'
        print(f"    🔧 Scanning for scripts in scripts/ directory...")
        if scripts_dir.exists() and scripts_dir.is_dir():
            for script_file in scripts_dir.rglob('*'):
                if script_file.is_file() and not script_file.name.startswith('.'):
                    relative_path = script_file.relative_to(skill_dir)
                    scripts_available.append(str(relative_path))
                    print(f"       • Found: {relative_path}")
        else:
            print(f"       (No scripts directory found)")

        # Sort scripts for consistent ordering
        scripts_available.sort()

        # Extract dependencies
        print(f"    📦 Scanning for Python dependencies...")
        dependencies = self._extract_dependencies(skill_dir, instructions, additional_files)
        if dependencies:
            print(f"       • Found: {', '.join(dependencies)}")
        else:
            print(f"       (No dependencies detected)")

        return Skill(
            name=metadata['name'],
            description=metadata['description'],
            instructions=instructions,
            path=skill_dir,
            additional_files=additional_files,
            scripts_available=scripts_available,
            dependencies=dependencies
        )

    def list_skills(self) -> None:
        """Print all discovered skills"""
        if not self.skills:
            print("\n❌ No skills found.")
            return

        print(f"\n{'='*70}")
        print(f"📋 SKILL DISCOVERY SUMMARY")
        print(f"{'='*70}")
        print(f"\n✅ Successfully loaded {len(self.skills)} skill(s):\n")

        for i, skill in enumerate(self.skills, 1):
            print(f"{i}. 🎯 {skill.name}")
            print(f"   📝 Description: {skill.description}")
            print(f"   📂 Path: {skill.path}")
            print(f"   📄 Instructions: {len(skill.instructions)} characters")

            # Show additional resources found
            if skill.additional_files:
                print(f"   📚 Additional files: {', '.join(skill.additional_files.keys())}")
            else:
                print(f"   📚 Additional files: None")

            if skill.scripts_available:
                print(f"   🔧 Scripts available: {len(skill.scripts_available)}")
                for script in skill.scripts_available:
                    print(f"      • {script}")
            else:
                print(f"   🔧 Scripts available: None")

            if skill.dependencies:
                print(f"   📦 Dependencies: {', '.join(skill.dependencies)}")
            else:
                print(f"   📦 Dependencies: None")

            print()


class SkillAgent:
    """LangChain agent that can execute skills"""

    def __init__(self, model_provider: str = "anthropic", model_name: Optional[str] = None, skills: List[Skill] = None):
        self.model_provider = model_provider.lower()
        self.conversation_history = []  # Track conversation history
        self.skills = skills or []  # Available skills
        self.installed_dependencies = set()  # Track which skill dependencies are installed

        # Load environment variables from .env file if it exists
        load_dotenv()

        print(f"\n{'='*70}")
        print(f"🤖 INITIALIZING SKILL AGENT")
        print(f"{'='*70}")

        # Configure LLM based on provider
        if self.model_provider == "anthropic":
            model_name = model_name or "claude-sonnet-4-5-20250929"

            # Check for API key
            api_key = os.getenv("ANTHROPIC_API_KEY")
            if not api_key:
                print("\n❌ ERROR: ANTHROPIC_API_KEY not found!")
                print("Please set your Anthropic API key:")
                print("  export ANTHROPIC_API_KEY='your-api-key-here'")
                print("  or create a .env file with: ANTHROPIC_API_KEY=your-api-key-here")
                sys.exit(1)

            print(f"✓ API Key found for Anthropic")
            self.llm = ChatAnthropic(model=model_name, temperature=0, api_key=api_key)
        elif self.model_provider == "openai":
            model_name = model_name or "gpt-4"

            # Check for API key
            api_key = os.getenv("OPENAI_API_KEY")
            if not api_key:
                print("\n❌ ERROR: OPENAI_API_KEY not found!")
                print("Please set your OpenAI API key:")
                print("  export OPENAI_API_KEY='your-api-key-here'")
                print("  or create a .env file with: OPENAI_API_KEY=your-api-key-here")
                sys.exit(1)

            print(f"✓ API Key found for OpenAI")
            self.llm = ChatOpenAI(model=model_name, temperature=0, api_key=api_key)
        else:
            raise ValueError(f"Unsupported model provider: {model_provider}")

        print(f"✓ Initialized agent with {self.model_provider} model: {model_name}")
        print(f"{'='*70}\n")

    def select_skill(self, user_request: str) -> Optional[Skill]:
        """Use LLM to select the most appropriate skill for the user's request"""
        if not self.skills:
            print("❌ No skills available")
            return None

        if len(self.skills) == 1:
            return self.skills[0]

        # Create a prompt for skill selection
        skill_descriptions = []
        for i, skill in enumerate(self.skills, 1):
            skill_descriptions.append(f"{i}. {skill.name}: {skill.description}")

        selection_prompt = f"""Given the following user request and available skills, select the MOST appropriate skill to use.

User Request: {user_request}

Available Skills:
{chr(10).join(skill_descriptions)}

Respond with ONLY the number of the most appropriate skill (1-{len(self.skills)}). Do not include any other text or explanation.
"""

        try:
            messages = [{"role": "user", "content": selection_prompt}]
            response = self.llm.invoke(messages)

            # Extract the skill number from response
            content = response.content.strip()

            # Try to find a number in the response
            import re
            numbers = re.findall(r'\d+', content)
            if numbers:
                skill_num = int(numbers[0])
                if 1 <= skill_num <= len(self.skills):
                    selected_skill = self.skills[skill_num - 1]
                    print(f"\n🎯 Selected skill: {selected_skill.name}")
                    print(f"   Reason: {selected_skill.description[:100]}...")
                    return selected_skill

            # Fallback to first skill if parsing fails
            print(f"\n⚠️  Could not parse skill selection, using first skill: {self.skills[0].name}")
            return self.skills[0]

        except Exception as e:
            print(f"\n⚠️  Error selecting skill: {e}")
            print(f"   Using first skill: {self.skills[0].name}")
            return self.skills[0]

    def install_dependencies(self, skill: Skill) -> bool:
        """Install Python dependencies for a skill"""
        # Check if already installed for this skill
        if skill.name in self.installed_dependencies:
            return True

        if not skill.dependencies:
            print(f"✓ No dependencies to install for skill: {skill.name}")
            self.installed_dependencies.add(skill.name)
            return True

        print(f"\n{'='*70}")
        print(f"📦 INSTALLING DEPENDENCIES FOR SKILL: {skill.name}")
        print(f"{'='*70}\n")

        print(f"Dependencies to install: {', '.join(skill.dependencies)}")
        print(f"\nThis will run: pip install {' '.join(skill.dependencies)}\n")

        # Check which packages are already installed
        already_installed = []
        to_install = []

        for package in skill.dependencies:
            try:
                result = subprocess.run(
                    [sys.executable, "-m", "pip", "show", package],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    already_installed.append(package)
                else:
                    to_install.append(package)
            except Exception:
                to_install.append(package)

        if already_installed:
            print(f"✓ Already installed: {', '.join(already_installed)}")

        if not to_install:
            print(f"\n✅ All dependencies already installed!")
            print(f"{'='*70}\n")
            return True

        print(f"\n📥 Installing: {', '.join(to_install)}\n")

        try:
            # Install missing packages
            result = subprocess.run(
                [sys.executable, "-m", "pip", "install"] + to_install,
                capture_output=True,
                text=True,
                timeout=300  # 5 minute timeout for installation
            )

            if result.returncode == 0:
                print(f"✅ Successfully installed: {', '.join(to_install)}")
                print(f"\n{'='*70}\n")
                self.installed_dependencies.add(skill.name)
                return True
            else:
                print(f"❌ Failed to install dependencies")
                print(f"\nError output:")
                print(result.stderr)
                print(f"\n{'='*70}\n")
                return False

        except subprocess.TimeoutExpired:
            print(f"❌ Installation timed out after 5 minutes")
            print(f"{'='*70}\n")
            return False
        except Exception as e:
            print(f"❌ Error installing dependencies: {e}")
            print(f"{'='*70}\n")
            return False

    def extract_python_code(self, text: str) -> List[str]:
        """Extract Python code blocks from markdown-formatted text"""
        # Pattern to match ```python ... ``` code blocks
        pattern = r'```python\n(.*?)```'
        matches = re.findall(pattern, text, re.DOTALL)
        return matches

    def execute_python_code(self, code: str) -> tuple[bool, str]:
        """Execute Python code and return success status and output"""
        try:
            print(f"\n{'='*70}")
            print(f"⚙️  EXECUTING PYTHON CODE")
            print(f"{'='*70}\n")

            # Write code to a temporary file
            temp_file = Path("temp_skill_code.py")
            with open(temp_file, 'w') as f:
                f.write(code)

            # Execute the code
            result = subprocess.run(
                [sys.executable, str(temp_file)],
                capture_output=True,
                text=True,
                timeout=30
            )

            # Clean up temp file
            temp_file.unlink()

            # Display output
            if result.stdout:
                print("📤 Output:")
                print(result.stdout)

            if result.stderr:
                print("⚠️  Errors/Warnings:")
                print(result.stderr)

            print(f"\n{'='*70}")
            if result.returncode == 0:
                print(f"✅ CODE EXECUTION COMPLETED SUCCESSFULLY")
            else:
                print(f"❌ CODE EXECUTION FAILED (exit code: {result.returncode})")
            print(f"{'='*70}\n")

            return result.returncode == 0, result.stdout + result.stderr

        except subprocess.TimeoutExpired:
            print(f"\n❌ Code execution timed out after 30 seconds")
            return False, "Execution timed out"
        except Exception as e:
            print(f"\n❌ Error executing code: {e}")
            import traceback
            traceback.print_exc()
            return False, str(e)

    def handle_request(self, user_input: str) -> str:
        """Handle a user request by selecting the appropriate skill and executing it"""
        # Select the best skill for this request
        selected_skill = self.select_skill(user_input)

        if not selected_skill:
            return "❌ No suitable skill found for your request"

        # Install dependencies if needed
        if selected_skill.dependencies and selected_skill.name not in self.installed_dependencies:
            install_success = self.install_dependencies(selected_skill)
            if not install_success:
                print(f"\n⚠️  Warning: Failed to install dependencies for {selected_skill.name}")
                print(f"   The skill may not work correctly.")

        # Execute the skill
        return self.execute_skill(selected_skill, user_input)

    def execute_skill(self, skill: Skill, user_input: str) -> str:
        """Execute a skill based on its instructions and all available resources"""
        print(f"\n{'='*70}")
        print(f"🚀 EXECUTING SKILL: {skill.name}")
        print(f"{'='*70}")

        # Show what resources are being loaded
        print(f"\n📦 Loading skill resources...")
        print(f"   ✓ Main instructions: {len(skill.instructions)} characters")
        if skill.additional_files:
            print(f"   ✓ Additional documentation: {len(skill.additional_files)} file(s)")
            for filename in skill.additional_files.keys():
                print(f"      • {filename}")
        if skill.scripts_available:
            print(f"   ✓ Available scripts: {len(skill.scripts_available)}")
        print(f"   ✓ Skill base path: {skill.path}")

        # Create a comprehensive system prompt that includes ALL skill resources
        system_prompt = f"""
You are executing a skill called "{skill.name}".

=== COMPLETE SKILL CONTEXT ===

{skill.get_full_context()}

=== END SKILL CONTEXT ===

IMPORTANT INSTRUCTIONS:
1. You have access to all the documentation files and scripts listed above
2. The skill's base directory is: {skill.path}
3. When referencing scripts, use their full path: {skill.path}/scripts/<script_name>
4. Follow the instructions in the main SKILL.md and refer to additional documentation as needed
5. If scripts are mentioned in the documentation, you can use them by their full path

Your task is to follow the skill instructions above to fulfill the user's request.
- If the skill requires you to write code, generate the code and explain what it does
- If the skill references scripts to run, provide the exact commands to execute them
- If the skill references additional documentation (like forms.md, reference.md), use that information
- Execute the skill to the best of your ability and provide a clear, actionable result
"""

        print(f"\n💭 User request: {user_input}")
        print(f"\n{'='*70}")
        print(f"🤖 Agent response:")
        print(f"{'='*70}\n")

        try:
            # For simple direct LLM execution without tools, just use the LLM directly
            messages = [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_input}
            ]

            # Use streaming to show progress
            result_parts = []
            for chunk in self.llm.stream(messages):
                if hasattr(chunk, 'content') and chunk.content:
                    print(chunk.content, end='', flush=True)
                    result_parts.append(chunk.content)

            result = "".join(result_parts) if result_parts else "No response generated"

            # Extract and execute any Python code in the response
            code_blocks = self.extract_python_code(result)
            if code_blocks:
                print(f"\n\n📝 Found {len(code_blocks)} Python code block(s) in response")

                for i, code in enumerate(code_blocks, 1):
                    if len(code_blocks) > 1:
                        print(f"\n🔹 Executing code block {i}/{len(code_blocks)}...")

                    success, output = self.execute_python_code(code)

                    if success:
                        # Store execution results in conversation history
                        self.conversation_history.append({
                            "role": "assistant",
                            "content": result
                        })
                        self.conversation_history.append({
                            "role": "user",
                            "content": f"Code executed successfully. Output:\n{output}"
                        })
                    else:
                        print(f"\n⚠️  Code execution failed. You can try to fix the code or ask for help.")

            print(f"\n{'='*70}")
            print(f"✅ SKILL EXECUTION COMPLETED")
            print(f"{'='*70}\n")

            return result

        except Exception as e:
            error_msg = f"❌ Error executing skill: {str(e)}"
            print(f"\n{error_msg}\n")
            import traceback
            print(f"📋 Traceback:")
            traceback.print_exc()
            return error_msg

# %%
def main():
    """Main entry point for the skill agent"""

    print(f"\n{'='*70}")
    print(f"🎯 SKILL AGENT - LangChain-Based Skill Executor")
    print(f"{'='*70}\n")

    # Parse command line arguments
    if len(sys.argv) < 2:
        print("❌ Error: Missing required argument")
        print("\nUsage: python skill_agent.py <skills_storage_path> [model_provider] [model_name]")
        print("\nExamples:")
        print("  python skill_agent.py ./storage/skills")
        print("  python skill_agent.py ./storage/skills anthropic")
        print("  python skill_agent.py ./storage/skills anthropic claude-sonnet-4-5-20250929")
        print("  python skill_agent.py ./storage/skills openai gpt-4")
        sys.exit(1)

    storage_path = sys.argv[1]
    model_provider = sys.argv[2] if len(sys.argv) > 2 else "anthropic"
    model_name = sys.argv[3] if len(sys.argv) > 3 else None

    print(f"📂 Storage path: {storage_path}")
    print(f"🤖 Model provider: {model_provider}")
    if model_name:
        print(f"🎛️  Model name: {model_name}")

    # Discover skills
    discovery = SkillDiscovery(storage_path)
    skills = discovery.find_skills()
    discovery.list_skills()

    if not skills:
        print("\n❌ No skills found. Exiting.")
        sys.exit(0)

    # Initialize agent with all available skills
    agent = SkillAgent(model_provider=model_provider, model_name=model_name, skills=skills)

    print(f"\n{'='*70}")
    print(f"🎯 PERSISTENT CLI MODE")
    print(f"{'='*70}")
    print(f"\n📚 Available skills: {', '.join([s.name for s in skills])}")
    print(f"\n💡 Tips:")
    print(f"   - The agent will automatically select the best skill for your request")
    print(f"   - Type your requests and press Enter")
    print(f"   - Python code in responses will be automatically executed")
    print(f"   - Dependencies will be installed automatically when a skill is used")
    print(f"   - Press Ctrl+C to exit or type 'exit'/'quit'")
    print(f"\n{'='*70}\n")

    # Persistent CLI loop
    try:
        while True:
            try:
                # Prompt for user input
                user_input = input("🤖 You: ").strip()

                if not user_input:
                    continue

                # Check for exit commands
                if user_input.lower() in ['exit', 'quit', 'q']:
                    print("\n👋 Goodbye!")
                    break

                # Handle the request (selects skill and executes)
                result = agent.handle_request(user_input)

            except KeyboardInterrupt:
                print("\n\n👋 Exiting... Goodbye!")
                break
            except EOFError:
                print("\n\n👋 Exiting... Goodbye!")
                break

    except KeyboardInterrupt:
        print("\n\n👋 Exiting... Goodbye!")

    print(f"\n{'='*70}")
    print(f"✅ Session ended.")
    print(f"{'='*70}\n")


# %%
if __name__ == "__main__":
    main()