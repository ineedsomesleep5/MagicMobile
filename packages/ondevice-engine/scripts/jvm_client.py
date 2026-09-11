"""Bounded JSON-lines client for real engine integration tests, never an app backend."""
from __future__ import annotations
import json, queue, subprocess, threading
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class EngineProcess:
    def __init__(self,timeout=30,diagnostics=None,command=None,heap='768m'):
        self.timeout=timeout
        self.log=Path(diagnostics).open('w') if diagnostics else None
        if command is None:
            cp=(ROOT/'build/runtime-classpath.txt').read_text().strip()
            command=['java',f'-Xmx{heap}','-Djava.awt.headless=true']
            if self.log:command.append('-Dmagicmobile.debug=true')
            command+=['-cp',cp,'io.magicmobile.xmage.EngineCli']
        self.process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,
            stderr=self.log or subprocess.DEVNULL,text=True,bufsize=1)
        self.replies=queue.Queue()
        self.reader=threading.Thread(target=self._read,daemon=True);self.reader.start()
    def _read(self):
        for line in self.process.stdout:
            try:reply=json.loads(line)
            except ValueError:continue
            if isinstance(reply,dict) and reply.get('protocol')==1 and 'ok' in reply:
                self.replies.put(reply)
        self.replies.put(None)
    def request(self,op,**fields):
        self.process.stdin.write(json.dumps({'protocol':1,'op':op,**fields})+'\n')
        self.process.stdin.flush()
        try:reply=self.replies.get(timeout=self.timeout)
        except queue.Empty:raise RuntimeError('Real engine response timed out')
        if reply is None:raise RuntimeError('Real engine process exited')
        return reply
    def call(self,op,**fields):
        reply=self.request(op,**fields)
        if not reply['ok']:raise RuntimeError(reply['error'])
        return reply['result']
    def __enter__(self):return self
    def __exit__(self,*exc):
        self.process.stdin.close()
        try:self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:self.process.kill();self.process.wait()
        self.reader.join(timeout=1)
        self.process.stdout.close()
        if self.log:self.log.close()
