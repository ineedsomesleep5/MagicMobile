#!/usr/bin/env python3
"""Generate checked platform repository copies; never modify the upstream checkout."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from prepare_upstream import git_blob, replace_body

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'Mage/src/main/java/mage/cards/repository/'


def patch_card(text):
    text = replace_body(text, 'CardRepository()',
                        '        // MOBILE_READ_ONLY_CATALOGUE: metadata is loaded lazily from bundled resources.')
    for name in ('getNames', 'getLandNames', 'getNonLandNames', 'getNonbasicLandNames',
                 'getNotBasicLandNames', 'getCreatureNames', 'getArtifactNames',
                 'getNonLandAndNonCreatureNames', 'getNonArtifactAndNonLandNames'):
        text = replace_body(text, 'public synchronized Set<String> ' + name + '()',
                            '        return MobileCardCatalogue.names("' + name + '");')
    methods = {
        'public CardInfo findCard(String setCode, String cardNumber, boolean ignoreNightCards)':
            'return MobileCardCatalogue.printing(setCode, cardNumber, ignoreNightCards);',
        'public List<String> getClassNames()': 'return MobileCardCatalogue.classNames();',
        'public List<CardInfo> getMissingCards(List<String> classNames)':
            'return MobileCardCatalogue.missing(classNames);',
        'public List<CardInfo> findCards(String name, long limitByMaxAmount, boolean returnSplitCardHalf, boolean canCheckDatabaseHealth)':
            'return MobileCardCatalogue.find(name, limitByMaxAmount, returnSplitCardHalf);',
        'public List<CardInfo> findCardsByClass(String canonicalClassName)':
            'return MobileCardCatalogue.byClass(canonicalClassName);',
        'public List<CardInfo> findCards(CardCriteria criteria)':
            'return MobileCardCatalogue.find(criteria);',
    }
    for signature, body in methods.items():
        text = replace_body(text, signature, '        ' + body)
    for signature in (
        'public void saveCards(final List<CardInfo> newCards, long newContentVersion)',
        'public long getContentVersionFromDB()', 'public void setContentVersion(long version)',
        'public void closeDB(boolean writeCompact)', 'public void openDB()',
        'public void printDatabaseStats(String info)', 'public List<List<String>> querySQL(String sql)',
        'public void execSQL(String sql)', 'public static boolean checkDatabaseHealthAndFix()',
    ):
        text = replace_body(text, signature,
            '        throw new UnsupportedOperationException("Desktop database operations are unavailable in the read-only mobile catalogue");')
    return text


def patch_expansion(text):
    text = replace_body(text, 'ExpansionRepository()',
        '        // Read-only metadata comes from the installed, generated XMage set registry.\n'
        '        instanceInitialized = true;')
    methods = {
        'public List<String> getSetCodes()': 'return MobileCardCatalogue.setCodes();',
        'public ExpansionInfo[] getWithBoostersSortedByReleaseDate()': 'return MobileCardCatalogue.boosterSets();',
        'public List<ExpansionInfo> getSetsWithBasicLandsByReleaseDate()': 'return MobileCardCatalogue.basicLandSets();',
        'public List<ExpansionInfo> getSetsFromBlock(String blockName)': 'return MobileCardCatalogue.blockSets(blockName);',
        'public ExpansionInfo getSetByCode(String setCode)': 'return MobileCardCatalogue.set(setCode, false);',
        'public ExpansionInfo getSetByName(String setName)': 'return MobileCardCatalogue.set(setName, true);',
        'public List<ExpansionInfo> getAll()': 'return MobileCardCatalogue.sets();',
    }
    for signature, body in methods.items():
        text = replace_body(text, signature, '        ' + body)
    for signature in (
        'public void saveSets(final List<ExpansionInfo> newSets, final List<ExpansionInfo> updatedSets, long newContentVersion)',
        'public long getContentVersionFromDB()', 'public void setContentVersion(long version)',
    ):
        text = replace_body(text, signature,
            '        throw new UnsupportedOperationException("Desktop database operations are unavailable in the read-only mobile catalogue");')
    return text


def prepare(checkout, output, mode):
    lock = json.loads((ROOT / 'platform/repository-sources.json').read_text())
    head = subprocess.check_output(['git', '-C', str(checkout), 'rev-parse', 'HEAD'], text=True).strip()
    if head != lock['commit']:
        raise ValueError('Unreviewed upstream revision for catalogue adapter')
    sources = {}
    for name, expected in lock['blobs'].items():
        data = (checkout / PACKAGE / name).read_bytes()
        if git_blob(data) != expected:
            raise ValueError('Unreviewed repository source: ' + name)
        sources[name] = data.decode()
    if mode == 'runtime':
        sources = {
            'CardRepository.java': patch_card(sources['CardRepository.java']),
            'ExpansionRepository.java': patch_expansion(sources['ExpansionRepository.java']),
            'CardCriteria.java': sources['CardCriteria.java'].rsplit('}', 1)[0]
                + '    public Boolean getNightCard() { return nightCard; } // MOBILE_QUERY_ACCESSOR\n}\n',
        }
    else:
        # Build-time oracle/export only: original SQL semantics, no file database or server.
        sources.pop('CardInfo.java')
        sources['DatabaseUtils.java'] = replace_body(sources['DatabaseUtils.java'],
            'public static String prepareH2Connection(String dbName, boolean improveCaches)',
            '        return "jdbc:h2:mem:mobile_catalogue_export;DB_CLOSE_DELAY=-1;IGNORECASE=TRUE";')
    output.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for name, source in sources.items():
        destination = output / 'mage/cards/repository' / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(source)
        hashes[name] = hashlib.sha256(source.encode()).hexdigest()
    (output / 'repository-patch-manifest.json').write_text(json.dumps({
        'upstream': head, 'mode': mode, 'sourceBlobs': lock['blobs'], 'outputs': hashes,
    }, indent=2) + '\n')
    print('Prepared checked ' + mode + ' catalogue adapter: ' + str(output))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--checkout', type=Path, default=ROOT / '.upstream/mage')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--mode', choices=('runtime', 'export'), required=True)
    args = parser.parse_args()
    prepare(args.checkout, args.output, args.mode)
