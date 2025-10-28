#!/usr/bin/env python3
"""
Web Scraper Recipe
Fetches and parses web content using requests and BeautifulSoup
"""

import requests
from bs4 import BeautifulSoup
import json
import os

def scrape_url(url):
    """Scrape content from a URL"""
    print(f"🌐 Fetching: {url}")

    headers = {
        'User-Agent': 'Mozilla/5.0 (compatible; ERA-Agent-Scraper/1.0)'
    }

    response = requests.get(url, headers=headers, timeout=10)
    response.raise_for_status()

    soup = BeautifulSoup(response.content, 'html.parser')

    # Extract title
    title = soup.title.string if soup.title else "No title"

    # Extract all links
    links = []
    for a in soup.find_all('a', href=True):
        href = a['href']
        text = a.get_text(strip=True)
        if href.startswith('http') and text:
            links.append({'text': text, 'url': href})

    # Extract all headings
    headings = []
    for tag in ['h1', 'h2', 'h3']:
        for heading in soup.find_all(tag):
            headings.append({
                'level': tag,
                'text': heading.get_text(strip=True)
            })

    # Extract meta description
    meta_desc = soup.find('meta', attrs={'name': 'description'})
    description = meta_desc['content'] if meta_desc else None

    return {
        'url': url,
        'title': title,
        'description': description,
        'headings': headings[:10],  # First 10 headings
        'links': links[:20],  # First 20 links
        'word_count': len(soup.get_text().split())
    }

def main():
    url = os.getenv('URL', 'https://example.com')

    print("=" * 60)
    print("🕷️  Web Scraper Recipe")
    print("=" * 60)
    print()

    try:
        data = scrape_url(url)

        print(f"\n📄 Title: {data['title']}")
        if data['description']:
            print(f"📝 Description: {data['description'][:100]}...")

        print(f"\n📊 Statistics:")
        print(f"  - Word count: {data['word_count']}")
        print(f"  - Headings found: {len(data['headings'])}")
        print(f"  - Links found: {len(data['links'])}")

        if data['headings']:
            print(f"\n📋 Headings:")
            for h in data['headings'][:5]:
                print(f"  {h['level'].upper()}: {h['text'][:60]}")

        if data['links']:
            print(f"\n🔗 Sample Links:")
            for link in data['links'][:5]:
                print(f"  - {link['text'][:50]}")
                print(f"    {link['url'][:70]}")

        # Output JSON for programmatic use
        print(f"\n📦 Full data (JSON):")
        print(json.dumps(data, indent=2))

    except requests.RequestException as e:
        print(f"❌ Error fetching URL: {e}")
        return 1
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1

    print("\n✨ Scraping completed successfully!")
    return 0

if __name__ == "__main__":
    exit(main())
