#!/usr/bin/env python3
"""Runtime classpath: each built reactor module's classes first, then its runtime jars.

A reactor module's own installed jar (~/.m2/.../org/mage/<artifact>/<version>) holds the same
classes as the target/classes directory ahead of it, so it is left out: a duplicate adds nothing
at runtime and doubles what a native image build scans.
"""
import os,sys
import xml.etree.ElementTree as ET
from pathlib import Path

POM='{http://maven.apache.org/POM/4.0.0}'


def coordinates(module):
    """(groupId, artifactId, version) from a module's pom.xml, inheriting group and version."""
    project=ET.parse(module/'pom.xml').getroot()
    parent=project.find(POM+'parent')
    def value(tag):
        node=project.find(POM+tag)
        if node is None and parent is not None: node=parent.find(POM+tag)
        return node.text.strip() if node is not None and node.text else None
    return value('groupId'),value('artifactId'),value('version')


def own_jar(entry,group,artifact,version):
    """True for <repo>/<group path>/<artifact>/<version>/<artifact>-<version>.jar."""
    parts=Path(entry).parts
    tail=(*group.split('.'),artifact,version,f'{artifact}-{version}.jar')
    return len(parts)>len(tail) and parts[-len(tail):]==tail


def main(upstream,output):
    entries=[];built=[]
    for p in sorted(Path(upstream).rglob('target/mobile-classpath.txt')):
        for e in p.read_text().strip().split(os.pathsep):
            if e and e not in entries:entries.append(e)
        classes=p.parent/'classes'
        if classes.is_dir():
            if str(classes) not in entries:entries.insert(0,str(classes))
            group,artifact,version=coordinates(p.parent.parent)
            if group and artifact and version:built.append((group,artifact,version))
    if not entries:raise SystemExit('No Maven classpaths generated')
    dropped=[e for e in entries if any(own_jar(e,*c) for c in built)]
    entries=[e for e in entries if e not in dropped]
    for e in dropped:print('classpath: '+Path(e).name+' duplicates its module classes; left out',file=sys.stderr)
    Path(output).write_text(os.pathsep.join(entries))


if __name__=='__main__':main(*sys.argv[1:])
