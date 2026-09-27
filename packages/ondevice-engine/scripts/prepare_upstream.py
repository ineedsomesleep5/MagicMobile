#!/usr/bin/env python3
"""Narrow, checked source transformations. Never translates or reimplements MTG rules."""
from __future__ import annotations
import argparse, hashlib, json, re, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def java_mask(text: str) -> str:
    """Preserve positions, masking comments and string/char literals for brace matching."""
    chars=list(text);i=0
    while i<len(text):
        if text.startswith('//',i):
            end=text.find('\n',i);end=len(text) if end<0 else end
        elif text.startswith('/*',i):
            close=text.find('*/',i+2)
            if close<0: raise ValueError('Unclosed comment')
            end=close+2
        elif text[i] in ('"',"'"):
            quote=text[i];end=i+1
            while end<len(text):
                if text[end]=='\\':end+=2;continue
                if text[end]==quote:end+=1;break
                end+=1
            else:raise ValueError('Unclosed Java literal')
        else:i+=1;continue
        for j in range(i,min(end,len(chars))):
            if chars[j]!='\n':chars[j]=' '
        i=end
    return ''.join(chars)

def replace_body(text: str, signature: str, body: str) -> str:
    masked=java_mask(text)
    matches=list(re.finditer(re.escape(signature),masked))
    if len(matches)!=1:raise ValueError(f'Expected exactly one method: {signature}')
    start=masked.find('{',matches[0].end())
    if start<0:raise ValueError('Missing body')
    depth=1;end=start+1
    while end<len(masked) and depth:
        depth += (masked[end]=='{')-(masked[end]=='}');end+=1
    if depth:raise ValueError('Unbalanced braces')
    return text[:start+1]+'\n'+body+'\n    '+text[end-1:]

def patch_card(text: str) -> str:
    text=replace_body(text,'public static Card createCard(String name, CardSetInfo setInfo)',
        '        return MobileCardFactories.create(name, setInfo); // MOBILE_NATIVE_FACTORY')
    text=replace_body(text,'public static Card createCard(Class<?> clazz, CardSetInfo setInfo, List<String> errorList)',
        '        try {\n            return MobileCardFactories.create(clazz.getName(), setInfo);\n'
        '        } catch (RuntimeException e) {\n            if (errorList != null) errorList.add("Mobile card construction failed: " + clazz.getName());\n'
        '            throw e;\n        }')
    return text

def patch_human(text: str) -> str:
    old='private final transient PlayerResponse response;'
    if text.count(old)!=1:raise ValueError('HumanPlayer response field changed')
    return text.replace(old,'protected final transient PlayerResponse response; // MOBILE_RESPONSE_HOOK')

def patch_sets(text: str) -> str:
    return replace_body(text,'private Sets()',
        '        // MOBILE_STATIC_SETS: populated by GeneratedSetRegistry, with direct getInstance calls.\n'
        '        // No classpath/plugin scanning in the phone runtime.')

FACTORY="""package mage.cards;
/** Installed by the mobile adapter before constructing any card. */
public final class MobileCardFactories {
    public interface Factory { Card create(String name, CardSetInfo info); }
    private static volatile Factory factory;
    private MobileCardFactories() {}
    public static synchronized void install(Factory f) { factory=java.util.Objects.requireNonNull(f); }
    public static Card create(String name,CardSetInfo info) {
        Factory f=factory;
        if(f==null) throw new IllegalStateException("Mobile card factory was not installed");
        return f.create(name,info);
    }
}
"""

def git_blob(data: bytes) -> str:
    return hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()

def main() -> None:
    p=argparse.ArgumentParser();p.add_argument('checkout',type=Path);args=p.parse_args()
    checkout=args.checkout.resolve();lock=json.loads((ROOT/'upstream.lock.json').read_text())
    head=subprocess.check_output(['git','-C',str(checkout),'rev-parse','HEAD'],text=True).strip()
    if head!=lock['commit']:raise SystemExit('Wrong upstream revision; refusing to patch')
    stamp=checkout/'.mobile-patch.json'
    if stamp.exists():
        for path,digest in json.loads(stamp.read_text())['outputs'].items():
            if hashlib.sha256((checkout/path).read_bytes()).hexdigest()!=digest:raise SystemExit('Patched files changed; review before proceeding: '+path)
        print('Checked mobile patches already applied');return
    functions={'CardImpl.java':patch_card,'Sets.java':patch_sets,'HumanPlayer.java':patch_human}
    transformed={}
    for path,expected in lock['sourceBlobs'].items():
        data=(checkout/path).read_bytes()
        if git_blob(data)!=expected:raise SystemExit('Upstream source differs from reviewed blob: '+path)
        transformed[path]=functions[Path(path).name](data.decode()).encode()
    transformed['Mage/src/main/java/mage/cards/MobileCardFactories.java']=FACTORY.encode()
    for path,data in transformed.items():(checkout/path).write_bytes(data)
    stamp.write_text(json.dumps({'commit':head,'outputs':{p:hashlib.sha256(b).hexdigest() for p,b in transformed.items()}},indent=2)+'\n')
    print('Applied checked mobile patches: card factory, set registry, human response hook')
if __name__=='__main__':main()
