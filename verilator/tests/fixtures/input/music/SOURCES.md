# Music sources and arrangements

These files reduce the cited scores to one melodic line for Music Teacher 1.
The matching `.mml` files are the editable sources; `.vbk` files use score
timing, with acknowledged score timing for Flight of the Bumblebee.
See [playback and regeneration](README.md).

## Bach: Cello Suite No. 1, Prelude (BWV 1007)

`bach-cello-suite-1-prelude` contains all 42 measures, with 656 notes in the
original cello register. The tied D in measure 22 is held continuously.
Fermatas use fixed timing; the final chord is rolled G2, B3, G4.

Source: [Mutopia edition by Andreas Scherer](https://www.mutopiaproject.org/ftp/BachJS/BWV1007/bwv1007/bwv1007-lys/),
public domain. Pitches and durations were checked against the edition's MIDI;
the ending is adapted for monophonic playback.

## Bach: The Well-Tempered Clavier, Book I, Prelude No. 1 (BWV 846)

`bach-wtc-1-prelude-1` contains all 35 measures, with 549 notes. Sustained
bass notes end at the next attack; the final chord is rolled C2, C3, E4, G4,
then C5. The final fermata uses fixed timing. Each MML line is one measure.

Source: [Mutopia edition by Tobias Erbsland](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=5),
public domain. Pitches were checked against the LilyPond source.

## Chopin: Minute Waltz, Op. 64 No. 1

`chopin-minute-waltz` contains the repeated form, reduced to the uppermost
right-hand line, with 688 notes. The melody is lowered one octave; the final
high F and descending flourish are lowered a further octave. Accompaniment
and chord doublings are omitted. Explicit MIDI grace notes are retained;
trills and mordents retain the MIDI's plain held notes.

Source: [Mutopia's Edition Peters transcription](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=483),
typeset by Magnus Lewis-Smith, revision January 17, 2015, public domain.
The melody was extracted from the right-hand MIDI track and checked against
its LilyPond notation.

## Joplin: The Entertainer

`joplin-the-entertainer` contains the repeated form, with 754 notes. The
uppermost right-hand line is retained, including the introduction's
cross-staff phrase. Chords, octave doublings and accompaniment are omitted.
The arrangement is lowered one octave; the second B strain follows the
score's Repeat 8va instruction, returning down for the A pickup.

Source: [Mutopia's reproduction of the 1902 edition](https://www.mutopiaproject.org/ftp/JoplinS/entertainer/),
typeset by Chris Sawer and revised by Simon Albrecht, public domain.
Pitches and durations were checked against its LilyPond source and MIDI.

## Rimsky-Korsakov: Flight of the Bumblebee

`rimsky-korsakov-flight-of-the-bumblebee` follows the running sixteenth-note
line between hands, omitting accompaniment and chord doublings. It contains
872 notes across 113 performed measures, including the repeat at measures
75-85 and its first and second endings. The melody is lowered 15 semitones,
from A minor to F# minor. The first-ending flourish at measure 85a is lowered
one further octave; the opening bass note of measure 92 is raised one octave.
The resulting range is C2-F#5. C2 occurs eight times and G#2 fourteen times.

Source: [Noctave's CC0 piano reduction](https://noctavepiano.com/en/sheet-music/rimski-vol-du-bourdon/),
based on the [2017 MuseScore transcription](https://musescore.com/user/23708136/scores/4413561).
Pitches, durations, hand changes and repeats were checked against the MusicXML.
The arrangement retains quarter note = 144; dynamics and articulation are
omitted. This MML arrangement and its VBK are dedicated to the public domain
under [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

## Strauss: The Blue Danube Waltz, Op. 314, main theme

`strauss-blue-danube` contains the pickup and 33 bars of the main theme,
with 72 notes. The melody is transposed from C major to D major and lowered
an octave. Melody calls alternate with the highest notes of response chords;
responses sound for an eighth note, with rests suggesting pizzicato.
Accompaniment is omitted and ties are merged into held notes.

Source: [Mutopia's main-theme piano reduction](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=519),
arranged and typeset by Nikos Kouremenos, from Christian Mondrup's four-hand
piano reduction at the Werner Icking Music Archive.

The source arrangement and the adapted `strauss-blue-danube.mml` and
`strauss-blue-danube.vbk` are licensed under
[Creative Commons Attribution-ShareAlike 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
Retain this attribution and license when redistributing these files.
