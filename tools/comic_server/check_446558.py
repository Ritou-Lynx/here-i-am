import urllib.request, re

url = 'https://manwa.me/book/446558'
req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36'})
resp = urllib.request.urlopen(req, timeout=30)
html = resp.read().decode('utf-8', 'replace')

chapters = re.findall(r'href="[^"]*chapter[^"]*"', html)
print('chapter links found:', len(chapters))
for c in chapters[:5]:
    print(' ', c)

title = re.search(r'<title>(.*?)</title>', html)
if title:
    print('title:', title.group(1)[:100])

# Also look for /book/ links
book_links = re.findall(r'href="[^"]*/book/[^"]*"', html)
print('book links:', len(book_links))
for b in book_links[:5]:
    print(' ', b)