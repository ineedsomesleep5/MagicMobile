"""The lessons: a staged board, then a fixed line for every seat, with Maren's coaching on the learner's moves.

Coach entries are text, or {text, spot, gesture}: `spot` names what the coach points at (a card by name,
or a control: primary (the corner button), medallion), `gesture` is drag, tap or hold.
"""
from recorder import Step

YOU, ROOK, BRYN, TAM = 'you', 'rook', 'bryn', 'tam'


def you(kind, coach=None, **args): return Step(YOU, kind, coach, **args)
def rook(kind, **args): return Step(ROOK, kind, None, **args)
def note(text, at=None, **extra): return Step(YOU, 'note', {'text': text, **extra}, step=at)
def end(text, at=None): return Step(YOU, 'end', {'text': text}, step=at)


def two_seats(you_commander='Ghalta, Primal Hunger', you_basic='Forest', rook_commander='Krenko, Mob Boss', rook_basic='Mountain'):
    return [{'seatId': YOU, 'name': 'You', 'commander': you_commander, 'basic': you_basic},
            {'seatId': ROOK, 'name': 'Rook', 'commander': rook_commander, 'basic': rook_basic}]


def first_spells(r):
    r.start(two_seats(), first=YOU, stage={
        YOU: {'hand': ['Forest', 'Grizzly Bears'], 'battlefield': ['Forest'], 'library': ['Forest', 'Forest']},
        ROOK: {'life': 2, 'hand': [], 'battlefield': ['Mountain'], 'library': ['Mountain', 'Mountain']}})
    r.play([
        note("I'm Maren, and this is my tavern. Let's learn by playing. Rook is down to 2 life: bring him to 0 and you win.",
             title='Welcome'),
        you('play', {'title': 'Play a land', 'text': 'Lands make mana, the energy you cast spells with. Drag the Forest from your hand onto the table.',
                     'spot': 'Forest', 'gesture': 'drag'}, card='Forest'),
        you('cast', {'title': 'Cast a creature', 'text': 'Grizzly Bears costs two mana, shown in its top corner. Drag it onto the table to cast it.',
                     'spot': 'Grizzly Bears', 'gesture': 'drag'}, card='Grizzly Bears',
            then=[{'title': 'Pay the cost', 'text': 'Tap a Forest to pay. Auto Pay in the corner can do it for you.', 'spot': 'Forest', 'gesture': 'tap'},
                  {'title': 'Pay the cost', 'text': 'One more Forest.', 'spot': 'Forest', 'gesture': 'tap'}]),
        note('Press and hold any card to read it. A creature can’t attack the turn it arrives, so your Bears wait until next turn.',
             title='Read a card', spot='Grizzly Bears', gesture='hold'),
        you('pass', {'title': 'End your turn', 'text': 'Nothing left to do this turn. Tap Next to move on.', 'spot': 'primary', 'gesture': 'tap'},
            step='PRECOMBAT_MAIN'),
        you('pass', {'title': 'Your turn again', 'text': 'Rook did nothing on his turn. Tap Next to go to combat.', 'spot': 'primary', 'gesture': 'tap'},
            step='PRECOMBAT_MAIN'),
        you('attack', {'title': 'Attack', 'text': 'Tap your Bears to send them at Rook.', 'spot': 'Grizzly Bears', 'gesture': 'tap'},
            cards=['Grizzly Bears'], then=[{'title': 'Attack', 'text': 'Tap 1 Attacker to confirm.', 'spot': 'primary', 'gesture': 'tap'}]),
    ])


LESSONS = [
    {'id': 'first-spells', 'title': 'Lands and spells', 'record': first_spells},
]


def combat(r):
    r.start(two_seats('Avacyn, Angel of Hope', 'Plains'), first=ROOK, stage={
        YOU: {'battlefield': ['Serra Angel', 'Grizzly Bears', 'Plains', 'Plains'], 'library': ['Plains', 'Plains']},
        ROOK: {'life': 4, 'battlefield': ['Hill Giant', 'Mountain', 'Mountain'], 'library': ['Mountain', 'Mountain']}})
    r.play([
        note('Creatures fight in combat. The attacker chooses who to attack, and the defender chooses how to block. Rook goes first this time.',
             title='Combat'),
        rook('attack', cards=['Hill Giant']),
        you('block', {'title': 'Block', 'text': 'Rook attacks with Hill Giant, a 3/3. Tap Serra Angel to block it: she deals 4 damage and can take 3.',
                      'spot': 'Serra Angel', 'gesture': 'tap'}, blocker='Serra Angel', attacker='Hill Giant',
            then=[{'title': 'Block', 'text': 'Tap 1 Blocker to confirm.', 'spot': 'primary', 'gesture': 'tap'}]),
        note('The first number is power, the damage a creature deals; the second is toughness, the damage it can take. Hill Giant took 4, so it died.',
             title='Power and toughness', at='POSTCOMBAT_MAIN'),
        you('pass', {'title': 'To combat', 'text': 'Your turn. Tap Next to go to combat.', 'spot': 'primary', 'gesture': 'tap'},
            step='PRECOMBAT_MAIN'),
        you('attack', {'title': 'Fly over', 'text': 'Serra Angel has flying: only creatures with flying or reach can block her. Tap her to attack.',
                       'spot': 'Serra Angel', 'gesture': 'tap'}, cards=['Serra Angel'],
            then=[{'title': 'Fly over', 'text': 'Tap 1 Attacker to confirm.', 'spot': 'primary', 'gesture': 'tap'}]),
    ])


def stack(r):
    r.start(two_seats(), first=YOU, stage={
        YOU: {'hand': ['Giant Growth'], 'battlefield': ['Grizzly Bears', 'Forest', 'Forest'], 'library': ['Forest', 'Forest']},
        ROOK: {'life': 5, 'hand': ['Shock'], 'battlefield': ['Mountain'], 'library': ['Mountain', 'Mountain']}})
    r.play([
        note('Instants can be cast at any time, even in the middle of combat. Rook is at 5 life and has a trick ready. So do you.',
             title='Instants'),
        you('pass', {'title': 'To combat', 'text': 'Tap Next to go to combat.', 'spot': 'primary', 'gesture': 'tap'},
            step='PRECOMBAT_MAIN'),
        you('attack', {'title': 'Attack', 'text': 'Tap your Bears to attack.', 'spot': 'Grizzly Bears', 'gesture': 'tap'},
            cards=['Grizzly Bears'], then=[{'title': 'Attack', 'text': 'Tap 1 Attacker to confirm.', 'spot': 'primary', 'gesture': 'tap'}]),
        Step(ROOK, 'cast', None, card='Shock', targets=['Grizzly Bears'], step='DECLARE_ATTACKERS'),
        you('cast', {'title': 'Answer it', 'text': 'Rook cast Shock at your Bears. It waits on the stack until both of you pass. '
                                                   'Drag Giant Growth onto the table to answer.', 'spot': 'Giant Growth', 'gesture': 'drag'},
            card='Giant Growth', targets=['Grizzly Bears'],
            then=[{'title': 'Pay the cost', 'text': 'Tap a Forest to pay.', 'spot': 'Forest', 'gesture': 'tap'}]),
        note('The last spell cast resolves first. Giant Growth makes your Bears 5/5, so the Shock that follows can’t kill them.',
             title='The stack'),
    ])


def commander(r):
    r.start(two_seats('Isamaru, Hound of Konda', 'Plains', 'Sheoldred, the Apocalypse', 'Swamp'), first=YOU, stage={
        YOU: {'battlefield': ['Plains', 'Plains', 'Plains'], 'library': ['Plains', 'Plains']},
        ROOK: {'hand': ['Murder'], 'battlefield': ['Swamp', 'Swamp', 'Swamp'], 'library': ['Swamp', 'Swamp']}})
    r.play([
        note('In Commander, a legendary creature leads your deck: your commander. It waits in the command zone, on the medallion by your portrait.',
             title='Your commander', spot='medallion'),
        you('cast', {'title': 'Cast your commander', 'text': 'Isamaru costs one white mana. Tap your portrait, then Command, then Cast.',
                     'spot': 'medallion', 'gesture': 'tap'}, card='Isamaru, Hound of Konda',
            then=[{'title': 'Pay the cost', 'text': 'Tap a Plains to pay.', 'spot': 'Plains', 'gesture': 'tap'}]),
        you('pass', {'title': 'Summoning sickness', 'text': 'Isamaru can\u2019t attack the turn he arrives. Tap Next to move on.', 'spot': 'primary', 'gesture': 'tap'},
            step='PRECOMBAT_MAIN'),
        Step(ROOK, 'cast', None, card='Murder', targets=['Isamaru, Hound of Konda'], step='PRECOMBAT_MAIN'),
        you('yes', {'title': 'Back to the command zone', 'text': 'Rook destroyed Isamaru. A commander that dies can go back to the command zone instead of the graveyard. Choose Move to command.',
                    'spot': 'yes', 'gesture': 'tap'}),
        you('cast', {'title': 'Commander tax', 'text': 'Each time you cast your commander again it costs two more. Isamaru now costs three. Tap your portrait, then Command, then Cast.',
                     'spot': 'medallion', 'gesture': 'tap'}, card='Isamaru, Hound of Konda',
            then=[{'title': 'Pay the cost', 'text': 'Tap a Plains.', 'spot': 'Plains', 'gesture': 'tap'},
                  {'title': 'Pay the cost', 'text': 'Another Plains.', 'spot': 'Plains', 'gesture': 'tap'},
                  {'title': 'Pay the cost', 'text': 'And the last one.', 'spot': 'Plains', 'gesture': 'tap'}]),
        end('Commander games start at 40 life, and 21 combat damage from one commander knocks a player out. Decks are 100 cards, '
            'one of each except basic lands, in your commander’s colours.'),
    ])


def table(r):
    r.start([{'seatId': YOU, 'name': 'You', 'commander': 'Avacyn, Angel of Hope', 'basic': 'Plains'},
             {'seatId': ROOK, 'name': 'Rook', 'commander': 'Krenko, Mob Boss', 'basic': 'Mountain'},
             {'seatId': BRYN, 'name': 'Bryn', 'commander': 'Ghalta, Primal Hunger', 'basic': 'Forest'},
             {'seatId': TAM, 'name': 'Tam', 'commander': 'Sheoldred, the Apocalypse', 'basic': 'Swamp'}], first=YOU, stage={
        YOU: {'battlefield': ['Serra Angel', 'Plains', 'Plains'], 'library': ['Plains', 'Plains']},
        ROOK: {'life': 3, 'battlefield': ['Mountain'], 'library': ['Mountain', 'Mountain']},
        BRYN: {'life': 31, 'battlefield': ['Colossal Dreadmaw', 'Forest', 'Forest'], 'library': ['Forest', 'Forest']},
        TAM: {'life': 22, 'battlefield': ['Swamp', 'Swamp'], 'library': ['Swamp', 'Swamp']}})
    r.play([
        note('Commander is usually played by four. Turns go around the table, and each time you attack you choose which player to attack.',
             title='Around the table'),
        Step(YOU, 'swap', {'title': 'Look around', 'spot': 'Rook', 'gesture': 'tap',
                           'text': 'The top of the table shows one opponent at a time. Tap Rook\u2019s portrait, then Bryn, to see her side.',
                           'desktop': 'Everyone sits across the top. Bryn, at 31 life, has a Colossal Dreadmaw. Rook is down to 3.'},
             player='Bryn'),
        Step(YOU, 'swap', {'title': 'The biggest threat', 'spot': 'Bryn', 'gesture': 'tap',
                           'text': 'That\u2019s Bryn\u2019s side. Tap the table to close her card and see her Colossal Dreadmaw, the biggest threat here. '
                                   'Then swap back: tap Bryn\u2019s portrait, then Rook.',
                           'desktop': 'Bryn\u2019s Dreadmaw is the biggest threat at the table, but Rook is the one you can knock out today.'},
             player='Rook'),
        you('pass', {'title': 'To combat', 'text': 'Tap Next to go to combat.', 'spot': 'primary', 'gesture': 'tap'},
            step='PRECOMBAT_MAIN'),
        you('attack', {'title': 'Pick a player', 'text': 'Rook is down to 3. Tap Serra Angel to attack.', 'spot': 'Serra Angel', 'gesture': 'tap'},
            cards=['Serra Angel'], defender='Rook',
            then=[{'title': 'Pick a player', 'text': 'Choose Rook.', 'spot': 'Rook', 'gesture': 'tap'},
                  {'title': 'Pick a player', 'text': 'Tap 1 Attacker to confirm.', 'spot': 'primary', 'gesture': 'tap'}]),
        end('Rook is out, and the game goes on with three. In a full game, keep an eye on the biggest threat at the table, like '
            'Bryn\u2019s Dreadmaw. Friends today can be rivals tomorrow.', at='POSTCOMBAT_MAIN'),
    ])


LESSONS += [
    {'id': 'combat', 'title': 'Combat', 'record': combat},
    {'id': 'stack', 'title': 'Instants and the stack', 'record': stack},
    {'id': 'commander', 'title': 'Your commander', 'record': commander},
    {'id': 'table', 'title': 'Around the table', 'record': table, 'focus': 'Rook'},
]
