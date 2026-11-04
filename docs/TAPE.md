# Tape images

Several titles support tape, including Money Minder, Information Manager, and APL/S. Each cartridge has its own tape commands and procedures; see its manual for the operations it supports. The core's tape menu mounts and rewinds images; use the cartridge's commands to perform the transfer.

The VideoBrain and Expander 1 automatically control tape playback, recording, and stopping in response to the software's commands. Once an image is mounted, rewind is the only transport control you need to operate manually.

Load Expander 1 firmware. Copy `examples/blank-tape.vbt` to the SD card with a new name, then choose **Mount Record Tape** on the main menu. Issue the cartridge's SAVE command to record. The first SAVE after mounting, rewinding the record tape or resetting replaces the recording from the beginning. Subsequent SAVE requests append, including the separate records in one workspace save. Mounting and playback do not write the image. Read-only images reject recording. **Tape busy** is a popup refreshed during activity; **Tape idle** reports that activity has ended. Notices wait until the OSD closes. Wait for the user LED to clear before unmounting or switching cores. Idle does not verify cartridge data. **Tape error** reports a controller failure, even if the cartridge reports TAPE OK.

Choose **Mount Playback Tape** for LOAD or VERIFY. To load a core recording, wait for Tape idle, then mount that saved file in the playback slot. Playback resumes from its current position across remote stops. Use **Rewind Playback Tape** before repeating LOAD or VERIFY. **Rewind Record Tape** starts the next SAVE from the beginning of its image. Playback does not reset the record deck's append position. Use different files in the two slots, especially for EDIT, which reads the source while writing a new database. Both remotes enabled is a setup state and does not start a transfer. Reset rewinds and cancels tape activity. An interrupted recording is invalid; a new SAVE can replace it. If the record remote switches to playback without a signal transition, the image and playback position are preserved. Actual recordings retain the initial constant signal interval before the first transition.

With VideoBrain image-creation support in Main_MiSTer, **New Record Tape** creates and mounts an 8 MiB blank in the `saves` subdirectory of the core's games directory. Files are named `Tape_1.vbt`, `Tape_2.vbt`, and so on without replacing existing files. Close the OSD to see the result. Older Main versions require the blank-file procedure above.

Both mount entries and **New Record Tape** are disabled while either deck is busy. Wait for both decks to finish before switching cores.

At the end of a playback image, the deck releases busy and reports **End of tape**, even if the cartridge leaves its playback remote enabled. The tape stays at the end; use **Rewind Playback Tape** to play it again. This notice does not indicate whether LOAD or VERIFY succeeded.

## Examples and tutorials

Follow [Make, save and reload](../examples/saves/README.md) to create a Money Minder account, the Information Manager APPLE database, or an original APL/S countdown, then verify your recording by reloading it.

## Tape tools

Use the [tape tools](../tools/README.md#tape-images) to create an 8 MiB blank, trim unused capacity, or convert between WAV and VBT. Imports and trimmed images have little spare recording capacity; use a separate blank for SAVE.

WAV conversion preserves waveform timing without decoding records. Cassette playback also depends on analog levels, polarity and the receiving interface. Keep the original WAV when importing a recording.

## VBT1 format

VBT1 uses 512-byte sectors. Sector 0 contains `VBT1`, a little-endian 32-bit clock rate (14318180 Hz), and a little-endian 32-bit interval count; remaining header bytes are zero. Count FFFFFFFF marks an incomplete recording. Sector 1 onward holds little-endian 32-bit intervals: bit 31 is the digital level, bits 30:0 are its duration in clock ticks (minimum 2). Padding is ignored. Timing and record gaps are retained while record remote is active. SD buffering uses 4 KiB; overflow or playback underrun raises Tape error.
