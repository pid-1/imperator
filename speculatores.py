#!/usr/bin/env python3
# speculatores.py
#
# Scouts out recent updates from archlinux.org/news/
# Presents in an easily readable format before making -Syu decisions

import requests, os
from bs4 import BeautifulSoup

base_url = 'https://www.archlinux.org'

html = requests.get(f'{base_url}/news').text
soup = BeautifulSoup(html, 'html.parser')

linx = {}

rows = soup.tbody.find_all('tr')
for idx,row in enumerate(rows):
   if idx == 5:
      break

   date, title, author = row.find_all('td')

   text = title.text
   link = title.a.get('href')

   # For easier selection syntax
   linx[idx] = link
   print(f'{idx})', date.text, f'{base_url}{link}')


sel = input('Select by # for more info, <CR> or ^C to cancel\n> ')
if sel != '':
   goto = linx.get(int(sel))
   os.system(f'w3m {base_url}{goto}')
