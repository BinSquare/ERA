"""
ERA Storage SDK for Python
Provides easy access to KV, D1, R2 storage from sandboxed code
"""

import os
import json
import base64
from typing import Any, Dict, List, Optional
from urllib.request import Request, urlopen
from urllib.error import HTTPError

# Get storage URL from environment
STORAGE_URL = os.getenv('ERA_STORAGE_URL', 'http://localhost')

class KVStorage:
    """Key-Value storage interface"""

    @staticmethod
    def set(namespace: str, key: str, value: str, metadata: Optional[Dict] = None) -> bool:
        """Set a key-value pair"""
        url = f"{STORAGE_URL}/api/storage/kv/{namespace}/{key}"
        data = json.dumps({"value": value, "metadata": metadata}).encode('utf-8')

        req = Request(url, data=data, method='PUT')
        req.add_header('Content-Type', 'application/json')

        try:
            with urlopen(req) as response:
                result = json.loads(response.read())
                return result.get('success', False)
        except HTTPError as e:
            error_data = json.loads(e.read())
            raise Exception(f"KV set failed: {error_data.get('error', str(e))}")

    @staticmethod
    def get(namespace: str, key: str) -> Optional[str]:
        """Get a value by key"""
        url = f"{STORAGE_URL}/api/storage/kv/{namespace}/{key}"

        try:
            with urlopen(url) as response:
                result = json.loads(response.read())
                return result.get('value')
        except HTTPError as e:
            if e.code == 404:
                return None
            error_data = json.loads(e.read())
            raise Exception(f"KV get failed: {error_data.get('error', str(e))}")

    @staticmethod
    def delete(namespace: str, key: str) -> bool:
        """Delete a key"""
        url = f"{STORAGE_URL}/api/storage/kv/{namespace}/{key}"
        req = Request(url, method='DELETE')

        try:
            with urlopen(req) as response:
                result = json.loads(response.read())
                return result.get('success', False)
        except HTTPError as e:
            error_data = json.loads(e.read())
            raise Exception(f"KV delete failed: {error_data.get('error', str(e))}")

    @staticmethod
    def list(namespace: str, prefix: str = "", limit: int = 100) -> List[Dict]:
        """List keys in a namespace"""
        url = f"{STORAGE_URL}/api/storage/kv/{namespace}?prefix={prefix}&limit={limit}"

        try:
            with urlopen(url) as response:
                result = json.loads(response.read())
                return result.get('keys', [])
        except HTTPError as e:
            error_data = json.loads(e.read())
            raise Exception(f"KV list failed: {error_data.get('error', str(e))}")


class D1Storage:
    """D1 SQL database interface"""

    @staticmethod
    def query(namespace: str, sql: str, params: Optional[List] = None) -> List[Dict]:
        """Execute a SELECT query and return results"""
        url = f"{STORAGE_URL}/api/storage/d1/{namespace}/query"
        data = json.dumps({"sql": sql, "params": params or []}).encode('utf-8')

        req = Request(url, data=data, method='POST')
        req.add_header('Content-Type', 'application/json')

        try:
            with urlopen(req) as response:
                result = json.loads(response.read())
                return result.get('results', [])
        except HTTPError as e:
            error_data = json.loads(e.read())
            raise Exception(f"D1 query failed: {error_data.get('error', str(e))}")

    @staticmethod
    def exec(namespace: str, sql: str, params: Optional[List] = None) -> Dict:
        """Execute a statement (INSERT, UPDATE, DELETE, CREATE TABLE, etc.)"""
        url = f"{STORAGE_URL}/api/storage/d1/{namespace}/exec"
        data = json.dumps({"sql": sql, "params": params or []}).encode('utf-8')

        req = Request(url, data=data, method='POST')
        req.add_header('Content-Type', 'application/json')

        try:
            with urlopen(req) as response:
                return json.loads(response.read())
        except HTTPError as e:
            error_data = json.loads(e.read())
            raise Exception(f"D1 exec failed: {error_data.get('error', str(e))}")


class R2Storage:
    """R2 Object storage interface"""

    @staticmethod
    def put(namespace: str, key: str, content: bytes, metadata: Optional[Dict[str, str]] = None) -> bool:
        """Store an object"""
        url = f"{STORAGE_URL}/api/storage/r2/{namespace}/{key}"

        # Encode content as base64 for JSON transport
        content_b64 = base64.b64encode(content).decode('ascii')
        data = json.dumps({"content": content_b64, "metadata": metadata}).encode('utf-8')

        req = Request(url, data=data, method='PUT')
        req.add_header('Content-Type', 'application/json')

        try:
            with urlopen(req) as response:
                result = json.loads(response.read())
                return result.get('success', False)
        except HTTPError as e:
            error_data = json.loads(e.read())
            raise Exception(f"R2 put failed: {error_data.get('error', str(e))}")

    @staticmethod
    def get(namespace: str, key: str) -> Optional[bytes]:
        """Retrieve an object"""
        url = f"{STORAGE_URL}/api/storage/r2/{namespace}/{key}"

        try:
            with urlopen(url) as response:
                result = json.loads(response.read())
                content_b64 = result.get('content')
                if content_b64:
                    return base64.b64decode(content_b64)
                return None
        except HTTPError as e:
            if e.code == 404:
                return None
            error_data = json.loads(e.read())
            raise Exception(f"R2 get failed: {error_data.get('error', str(e))}")

    @staticmethod
    def delete(namespace: str, key: str) -> bool:
        """Delete an object"""
        url = f"{STORAGE_URL}/api/storage/r2/{namespace}/{key}"
        req = Request(url, method='DELETE')

        try:
            with urlopen(req) as response:
                result = json.loads(response.read())
                return result.get('success', False)
        except HTTPError as e:
            error_data = json.loads(e.read())
            raise Exception(f"R2 delete failed: {error_data.get('error', str(e))}")

    @staticmethod
    def list(namespace: str, prefix: str = "", limit: int = 100) -> List[Dict]:
        """List objects in a namespace"""
        url = f"{STORAGE_URL}/api/storage/r2/{namespace}?prefix={prefix}&limit={limit}"

        try:
            with urlopen(url) as response:
                result = json.loads(response.read())
                return result.get('objects', [])
        except HTTPError as e:
            error_data = json.loads(e.read())
            raise Exception(f"R2 list failed: {error_data.get('error', str(e))}")


# Convenience instances
kv = KVStorage()
d1 = D1Storage()
r2 = R2Storage()


# Example usage:
if __name__ == "__main__":
    # KV example
    kv.set("app1", "user:123", json.dumps({"name": "Alice", "age": 30}))
    user_data = json.loads(kv.get("app1", "user:123"))
    print(f"User: {user_data}")

    # D1 example
    d1.exec("app1", "CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, name TEXT)")
    d1.exec("app1", "INSERT INTO users (name) VALUES (?)", ["Bob"])
    users = d1.query("app1", "SELECT * FROM users")
    print(f"Users: {users}")

    # R2 example
    r2.put("app1", "file.txt", b"Hello World!")
    content = r2.get("app1", "file.txt")
    print(f"File content: {content.decode()}")
