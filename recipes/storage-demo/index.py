#!/usr/bin/env python3
"""
ERA Storage Demo
Demonstrates KV, D1, and R2 storage operations
"""

import era_storage
import json
from datetime import datetime

def demo_kv():
    """Demonstrate KV storage operations"""
    print("📦 KV Storage Demo")
    print("-" * 50)

    # Store user data
    user_data = {
        "name": "Alice",
        "email": "alice@example.com",
        "preferences": {"theme": "dark", "notifications": True}
    }

    era_storage.kv.set("demo", "user:alice", json.dumps(user_data))
    print("✅ Stored user data")

    # Retrieve user data
    retrieved = era_storage.kv.get("demo", "user:alice")
    user = json.loads(retrieved)
    print(f"👤 Retrieved user: {user['name']} ({user['email']})")

    # Store multiple keys
    for i in range(3):
        era_storage.kv.set("demo", f"item:{i}", f"Item {i}")

    # List keys
    keys = era_storage.kv.list("demo", prefix="item:")
    print(f"📝 Found {len(keys)} items")

    print()

def demo_d1():
    """Demonstrate D1 database operations"""
    print("🗄️  D1 Database Demo")
    print("-" * 50)

    # Create table
    era_storage.d1.exec("demo", """
        CREATE TABLE IF NOT EXISTS todos (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            completed BOOLEAN DEFAULT 0,
            created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
    """)
    print("✅ Created todos table")

    # Insert tasks
    tasks = ["Learn ERA Storage", "Build something cool", "Deploy to production"]
    for task in tasks:
        era_storage.d1.exec("demo",
            "INSERT INTO todos (title) VALUES (?)",
            [task]
        )
    print(f"➕ Added {len(tasks)} tasks")

    # Query tasks
    results = era_storage.d1.query("demo", "SELECT * FROM todos ORDER BY id")
    print(f"📋 Pending tasks:")
    for todo in results:
        status = "✓" if todo['completed'] else "○"
        print(f"  {status} {todo['title']}")

    # Mark first task as complete
    era_storage.d1.exec("demo",
        "UPDATE todos SET completed = 1 WHERE id = ?",
        [results[0]['id']]
    )
    print("✅ Marked first task as complete")

    print()

def demo_r2():
    """Demonstrate R2 object storage"""
    print("📁 R2 Object Storage Demo")
    print("-" * 50)

    # Store a file
    content = f"Hello from ERA Storage!\nGenerated at: {datetime.now().isoformat()}"
    era_storage.r2.put("demo", "hello.txt", content.encode(),
        metadata={"type": "greeting", "version": "1.0"}
    )
    print("✅ Stored hello.txt")

    # Store multiple files
    for i in range(3):
        era_storage.r2.put("demo", f"logs/log-{i}.txt",
            f"Log entry {i}\n".encode()
        )

    # List objects
    objects = era_storage.r2.list("demo", prefix="logs/")
    print(f"📄 Found {len(objects)} log files")

    # Retrieve file
    retrieved = era_storage.r2.get("demo", "hello.txt")
    print(f"📖 File content:\n{retrieved.decode()}")

    print()

def main():
    print("=" * 50)
    print("🚀 ERA Storage Demo")
    print("=" * 50)
    print()

    try:
        demo_kv()
        demo_d1()
        demo_r2()

        print("=" * 50)
        print("✨ Demo completed successfully!")
        print("=" * 50)
    except Exception as e:
        print(f"❌ Error: {e}")
        raise

if __name__ == "__main__":
    main()
