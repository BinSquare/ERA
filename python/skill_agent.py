# %%
"""
Simple LangChain Agent for discovering and executing skills.
Skills are expected to follow the Claude Skills format with SKILL.md files.
"""

import os
import sys
from pathlib import Path
from typing import List, Dict, Optional
import yaml
from dataclasses import dataclass
from dotenv import load_dotenv

from langchain_anthropic import ChatAnthropic
from langchain_openai import ChatOpenAI
from langchain.agents import create_agent
from langchain_core.tools import Tool
from langchain_core.messages import HumanMessage


@dataclass
class Skill:
    """Represents a parsed skill from SKILL.md"""
    name: str
    description: str
    instructions: str
    path: Path

    def __str__(self):
        return f"{self.name}: {self.description}"


class SkillDiscovery:
    """Discovers and parses skills from a storage path"""

    def __init__(self, storage_path: str):
        self.storage_path = Path(storage_path)
        self.skills: List[Skill] = []

    def find_skills(self) -> List[Skill]:
        """Find all SKILL.md files in the storage path"""
        self.skills = []

        if not self.storage_path.exists():
            print(f"Warning: Storage path {self.storage_path} does not exist")
            return self.skills

        # Find all SKILL.md files
        for skill_file in self.storage_path.rglob("SKILL.md"):
            try:
                skill = self._parse_skill(skill_file)
                if skill:
                    self.skills.append(skill)
            except Exception as e:
                print(f"Error parsing {skill_file}: {e}")

        return self.skills

    def _parse_skill(self, skill_file: Path) -> Optional[Skill]:
        """Parse a SKILL.md file with YAML frontmatter"""
        with open(skill_file, 'r', encoding='utf-8') as f:
            content = f.read()

        # Split frontmatter and instructions
        if not content.startswith('---'):
            print(f"Warning: {skill_file} missing YAML frontmatter")
            return None

        parts = content.split('---', 2)
        if len(parts) < 3:
            print(f"Warning: {skill_file} has malformed frontmatter")
            return None

        # Parse YAML frontmatter
        try:
            metadata = yaml.safe_load(parts[1])
        except yaml.YAMLError as e:
            print(f"Error parsing YAML in {skill_file}: {e}")
            return None

        if not metadata or 'name' not in metadata or 'description' not in metadata:
            print(f"Warning: {skill_file} missing required name or description")
            return None

        instructions = parts[2].strip()

        return Skill(
            name=metadata['name'],
            description=metadata['description'],
            instructions=instructions,
            path=skill_file.parent
        )

    def list_skills(self) -> None:
        """Print all discovered skills"""
        if not self.skills:
            print("No skills found.")
            return

        print(f"\nFound {len(self.skills)} skill(s):\n")
        for i, skill in enumerate(self.skills, 1):
            print(f"{i}. {skill}")
            print(f"   Path: {skill.path}")
            print()


class SkillAgent:
    """LangChain agent that can execute skills"""

    def __init__(self, model_provider: str = "anthropic", model_name: Optional[str] = None):
        self.model_provider = model_provider.lower()

        # Load environment variables from .env file if it exists
        load_dotenv()

        # Configure LLM based on provider
        if self.model_provider == "anthropic":
            model_name = model_name or "claude-sonnet-4-5-20250929"
            
            # Check for API key
            api_key = os.getenv("ANTHROPIC_API_KEY")
            if not api_key:
                print("ERROR: ANTHROPIC_API_KEY not found!")
                print("Please set your Anthropic API key:")
                print("  export ANTHROPIC_API_KEY='your-api-key-here'")
                print("  or create a .env file with: ANTHROPIC_API_KEY=your-api-key-here")
                sys.exit(1)
                
            self.llm = ChatAnthropic(model=model_name, temperature=0, api_key=api_key)
        elif self.model_provider == "openai":
            model_name = model_name or "gpt-4"
            
            # Check for API key
            api_key = os.getenv("OPENAI_API_KEY")
            if not api_key:
                print("ERROR: OPENAI_API_KEY not found!")
                print("Please set your OpenAI API key:")
                print("  export OPENAI_API_KEY='your-api-key-here'")
                print("  or create a .env file with: OPENAI_API_KEY=your-api-key-here")
                sys.exit(1)
                
            self.llm = ChatOpenAI(model=model_name, temperature=0, api_key=api_key)
        else:
            raise ValueError(f"Unsupported model provider: {model_provider}")

        print(f"Initialized agent with {self.model_provider} model: {model_name}")

    def execute_skill(self, skill: Skill, user_input: str) -> str:
        """Execute a skill based on its instructions"""
        print(f"\n{'='*60}")
        print(f"Executing skill: {skill.name}")
        print(f"{'='*60}\n")

        # Create a comprehensive system prompt that includes skill instructions
        system_prompt = f"""
        You are executing a skill called "{skill.name}".

        Skill Description: {skill.description}

        Skill Instructions:
        {skill.instructions}

        Your task is to follow the skill instructions above to fulfill the user's request.
        If the skill requires you to write code, generate the code and explain what it does.
        If the skill requires you to search for information, describe how you would do it.
        Execute the skill to the best of your ability and provide a clear result.
        """

        try:
            # Create agent using the new API
            agent = create_agent(
                model=self.llm,
                tools=[],  # No tools for now, just direct LLM execution
                system_prompt=system_prompt
            )

            # Execute the agent with user input
            inputs = {"messages": [{"role": "user", "content": user_input}]}
            
            # Stream the response
            result_parts = []
            for chunk in agent.stream(inputs, stream_mode="updates"):
                if "messages" in chunk:
                    for message in chunk["messages"]:
                        if hasattr(message, 'content') and message.content:
                            result_parts.append(message.content)

            result = "\n".join(result_parts) if result_parts else "No response generated"

            print("\n" + "="*60)
            print("SKILL EXECUTION RESULT")
            print("="*60)
            print(result)
            print("="*60 + "\n")

            return result

        except Exception as e:
            error_msg = f"Error executing skill: {str(e)}"
            print(f"\n{error_msg}\n")
            return error_msg

# %%
def main():
    """Main entry point for the skill agent"""

    # Parse command line arguments
    if len(sys.argv) < 2:
        print("Usage: python skill_agent.py <skills_storage_path> [model_provider] [model_name]")
        print("\nExamples:")
        print("  python skill_agent.py ./skills")
        print("  python skill_agent.py ./skills anthropic")
        print("  python skill_agent.py ./skills openai gpt-4")
        sys.exit(1)

    storage_path = sys.argv[1]
    model_provider = sys.argv[2] if len(sys.argv) > 2 else "anthropic"
    model_name = sys.argv[3] if len(sys.argv) > 3 else None

    # Discover skills
    print(f"Discovering skills in: {storage_path}")
    discovery = SkillDiscovery(storage_path)
    skills = discovery.find_skills()
    discovery.list_skills()

    if not skills:
        print("No skills found. Exiting.")
        sys.exit(0)

    # Initialize agent
    agent = SkillAgent(model_provider=model_provider, model_name=model_name)

    # Execute first skill
    first_skill = skills[0]
    print(f"\nAttempting to implement first skill: {first_skill.name}")

    # Get user input for the skill
    print("\nWhat would you like this skill to do?")
    user_input = input("> ").strip()

    if not user_input:
        user_input = "Execute this skill with default behavior"

    # Execute the skill
    result = agent.execute_skill(first_skill, user_input)

    print("\nSkill execution completed!")


# %%
if __name__ == "__main__":
    main()