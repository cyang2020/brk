#!/usr/bin/env python3
"""The stand-in for the local `claude` / `codex` command while the station captures the AI scenes (P45-P50).

capture-brk-scenes.py launches Brk with BRK_AI_FIXTURE_EXECUTABLE pointing here; a Brk started with a control socket
runs this file instead of looking for claude or codex on PATH (Sources/BrkApp/AIProvider.swift). Every answer is
fixed, so the captures do not depend on a model, an account or the network. Brk calls it as `fake-ai.py -p <prompt>
<claude options>`. The answers follow what Arc showed in the references:

  link preview (BRK_PREVIEW)       Arc's P45 card as Brk's answer-card JSON (title and four details)
  tidy title (pinning a tab)       "Sidebar Ellipsis", Arc's rename of the long-title tab in P47
  organize Today                   two folders, Design (design, interaction, interface, visual pages) and Reading
  instant link (BRK_INSTANT_LINK)  no answer for 60 s, so the loading state stays on screen (P48); the scene cancels
  translate (BRK_TRANSLATE)        Bonjour -> Hello, Monde -> World (the fixture's French heading, as in P50)
  anything else                    one fixed sentence

BRK_AI_FIXTURE_LOG, when set, gets one JSON line per call with the prompt.
"""
import json, os, re, sys, time

prompt = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == '-p' else sys.argv[-1]
if '--json-schema' in sys.argv: prompt = ''
if os.environ.get('BRK_AI_FIXTURE_LOG'):
    with open(os.environ['BRK_AI_FIXTURE_LOG'], 'a') as f: f.write(json.dumps({'pid': os.getpid(), 'prompt': prompt[:2000]}) + '\n')

# Arc's answer card (P45-a) in the JSON Brk asks for: the title and four details with their SF Symbols.
PREVIEW = json.dumps({'blocked': False, 'quickSummary': 'Synthetic page for browser comparison', 'details': [
    {'label': 'Purpose:', 'icon': 'eye', 'info': 'Compare browser chrome performance.'},
    {'label': 'Features:', 'icon': 'slider.horizontal.3', 'info': 'Usable controls for text and layout.'},
    {'label': 'Visuals:', 'icon': 'rectangle.fill', 'info': 'Colored block indicates screenshot boundaries.'},
    {'label': 'Navigation:', 'icon': 'folder', 'info': 'Links for preview and inspection.'},
]})


# The basic layer (docs/design/ai-native.md) runs Claude Code with `--json-schema` and the stream-json protocol: the
# task's input JSON arrives as a user message on stdin and the answer goes back as `structured_output`. The answers
# are the same fixed ones as the plain branch below, told apart by the schema's fields.
def structured(data, props):
    keys = set(props)
    if keys == {'blocked', 'quickSummary', 'details'}: return json.loads(PREVIEW)
    if keys == {'title'}: return {'title': 'Sidebar Ellipsis'}
    if keys == {'name'}: return {'name': 'Design'}
    if keys == {'groups'}:
        groups = {'Design': [], 'Reading': []}
        for tab in data.get('tabs', []):
            groups['Design' if re.search(r'design|interaction|interface|visual', tab.get('title', ''), re.I) else 'Reading'].append(tab['id'])
        return {'groups': [{'name': name, 'tabs': tabs} for name, tabs in groups.items() if tabs]}
    if keys == {'names'}:
        if 'id' in props['names']['items']['properties']:
            return {'names': [{'id': t['id'], 'name': t['title']} for t in data.get('tabs', [])]}
        return {'names': [{'group': g['group'], 'name': 'Group ' + str(g['group'] + 1)} for g in data.get('groups', [])]}
    if keys == {'nodes'}:
        return {'nodes': [{'id': n['id'], 'text': n['text'].replace('Bonjour', 'Hello').replace('Monde', 'World')} for n in data.get('nodes', [])]}
    if keys == {'filename'}: return {'filename': 'Download.' + data.get('filename', 'file.bin').split('.')[-1]}
    if keys == {'urls'}:
        time.sleep(60)
        return {'urls': ['http://127.0.0.1:8764/docs.html']}
    if keys == {'translation'}: return {'translation': data.get('text', '').replace('Bonjour', 'Hello').replace('Monde', 'World')}
    out = {}
    for key, value in props.items():
        if value.get('type') == 'string': out[key] = (value.get('enum') or [''])[0]
        elif value.get('type') == 'integer': out[key] = 0
        elif value.get('type') == 'boolean': out[key] = False
    return out

def structured_session():
    schema = json.loads(sys.argv[sys.argv.index('--json-schema') + 1])
    session = 'fake-ai-' + str(os.getpid())
    put = lambda obj: (sys.stdout.write(json.dumps(obj) + '\n'), sys.stdout.flush())
    for line in sys.stdin:
        try: message = json.loads(line)
        except ValueError: continue
        if message.get('type') == 'control_request':
            put({'type': 'control_response', 'response': {'subtype': 'success', 'request_id': message['request_id'], 'response': {}}})
        elif message.get('type') == 'user':
            text = message['message']['content'][0]['text']
            if os.environ.get('BRK_AI_FIXTURE_LOG'):
                with open(os.environ['BRK_AI_FIXTURE_LOG'], 'a') as f: f.write(json.dumps({'pid': os.getpid(), 'prompt': text[:2000]}) + '\n')
            try: data = json.loads(text)
            except ValueError: data = {}
            obj = structured(data, schema.get('properties') or {})
            put({'type': 'system', 'subtype': 'init', 'session_id': session, 'model': 'claude-fake'})
            put({'type': 'assistant', 'parent_tool_use_id': None, 'message': {'content': [{'type': 'tool_use', 'id': 'toolu_so', 'name': 'StructuredOutput', 'input': obj}]}})
            put({'type': 'result', 'subtype': 'success', 'is_error': False, 'result': json.dumps(obj), 'structured_output': obj, 'session_id': session,
                 'usage': {'input_tokens': 2, 'output_tokens': 20}})

if '--json-schema' in sys.argv:
    structured_session()
    sys.exit(0)
elif prompt.startswith('BRK_PREVIEW'):
    print(PREVIEW)
elif prompt.startswith('Give a short, tidy title'):
    print('Sidebar Ellipsis')
elif prompt.startswith('Group these browser tabs'):
    groups = {'Design': [], 'Reading': []}
    for tab, title in re.findall(r'^- ([^:]+): (.*) <', prompt, re.M):
        groups['Design' if re.search(r'design|interaction|interface|visual', title, re.I) else 'Reading'].append(tab)
    print(json.dumps([{'folder': name, 'tabs': tabs} for name, tabs in groups.items() if tabs]))
elif prompt.startswith('BRK_INSTANT_LINK'):
    time.sleep(60)
    print('http://127.0.0.1:8764/docs.html')
elif prompt.startswith('BRK_TRANSLATE'):
    nodes = json.loads(prompt.splitlines()[-1])
    for node in nodes: node['text'] = node['text'].replace('Bonjour', 'Hello').replace('Monde', 'World')
    print(json.dumps(nodes))
elif prompt.startswith('BRK_DOWNLOAD_NAME'):
    print('Download.' + prompt.splitlines()[-1].split('.')[-1])
elif prompt.startswith('BRK_PAGE_QUESTION') or prompt.startswith('BRK_BROWSE'):
    print('Browsers shape text with the platform font stack, then rasterize the glyphs on the GPU. [1]')
else:
    print('Browsers shape text with the platform font stack, then rasterize the glyphs on the GPU.')
